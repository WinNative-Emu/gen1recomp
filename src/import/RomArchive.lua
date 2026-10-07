local RomArchive = {}

RomArchive.MAX_ARCHIVE_BYTES = 64 * 1024 * 1024

local capsCache = {}

function RomArchive._resetForTests()
  capsCache = {}
end

function RomArchive.kind(data)
  if type(data) ~= "string" or #data < 8 then return nil end
  local head = data:sub(1, 4)
  if head == "PK\3\4" or head == "PK\5\6" then return "zip" end
  if data:sub(1, 6) == "7z\188\175\39\28" then return "7z" end
  return nil
end

local function u16(n)
  return string.char(n % 256, math.floor(n / 256) % 256)
end

local function u32(n)
  return string.char(n % 256, math.floor(n / 256) % 256,
    math.floor(n / 65536) % 256, math.floor(n / 16777216) % 256)
end

function RomArchive._zipProbeBytes()
  local name, body = "probe", "ok"
  local localHeader = "PK\3\4" .. u16(20) .. u16(0) .. u16(0) .. u16(0)
    .. u16(0) .. u32(2044517703) .. u32(#body) .. u32(#body) .. u16(#name)
    .. u16(0) .. name .. body
  local central = "PK\1\2" .. u16(20) .. u16(20) .. u16(0) .. u16(0)
    .. u16(0) .. u16(0) .. u32(2044517703) .. u32(#body) .. u32(#body)
    .. u16(#name) .. u16(0) .. u16(0) .. u16(0) .. u16(0) .. u32(0)
    .. u32(0) .. name
  local eocd = "PK\5\6" .. u16(0) .. u16(0) .. u16(1) .. u16(1)
    .. u32(#central) .. u32(#localHeader) .. u16(0)
  return localHeader .. central .. eocd
end

local SEVENZ_PROBE_HEX =
  "377abcaf271c00044e999ef910000000000000005200000000000000f427ec00"
  .. "67656e317265636f6d702d70726f62650104060001091000070b0100010100"
  .. "0c1000080a01451423990000050111170070002e0072006f006d0070007200"
  .. "6f00620065000000190400000000140a0100332a3077cb55dd011506010020"
  .. "80a4810000"

local function sevenZProbeBytes()
  return (SEVENZ_PROBE_HEX:gsub("%x%x", function(h)
    return string.char(tonumber(h, 16))
  end))
end

local function probeFormat(fs, ext, bytes)
  local okFd, fd = pcall(fs.newFileData, bytes, "rom_probe." .. ext)
  if not okFd or not fd then return false end
  local point = "_rom_probe_" .. ext
  local okMount, mounted = pcall(fs.mount, fd, point)
  local found = false
  if okMount and mounted then
    local okList, items = pcall(fs.getDirectoryItems, point)
    found = okList and type(items) == "table" and #items > 0
  end
  pcall(fs.unmount, fd)
  return found and true or false
end

function RomArchive.capabilities(fs)
  fs = fs or (love and love.filesystem)
  if type(fs) ~= "table" or not (fs.newFileData and fs.mount
      and fs.getDirectoryItems and fs.unmount) then
    return { zip = false, z7 = false }
  end
  local cached = capsCache[fs]
  if cached then return cached end
  local caps = {
    zip = probeFormat(fs, "zip", RomArchive._zipProbeBytes()),
    z7 = probeFormat(fs, "7z", sevenZProbeBytes()),
  }
  capsCache[fs] = caps
  return caps
end

function RomArchive.unwrap(data, displayName, opts)
  opts = opts or {}
  local fs = opts.fs or (love and love.filesystem)
  local kind = RomArchive.kind(data)
  if not kind then return nil, "not a .zip or .7z file" end
  local caps = RomArchive.capabilities(fs)
  if (kind == "zip" and not caps.zip) or (kind == "7z" and not caps.z7) then
    return nil, ("this platform cannot open .%s files; drop the raw "
      .. ".gb/.gbc/.gba instead"):format(kind)
  end

  local isRomName = opts.isRomName or function(name)
    return type(name) == "string" and name:lower():match("%.gb[ac]?$") ~= nil
  end
  local acceptedSize = opts.acceptedSize or function(n)
    return n == 1048576 or n == 2097152 or n == 16777216
  end

  local mount = "_rom_pick_" .. kind
  local fd, staged
  if fs.newFileData then
    local okFd, made = pcall(fs.newFileData, data, "rom_pick." .. kind)
    if okFd and made and fs.mount(made, mount) then fd = made end
  end
  if not fd then
    staged = "rom_pick_tmp." .. kind
    local wrote = fs.write and fs.write(staged, data)
    if not wrote or not fs.mount(staged, mount) then
      if fs.remove then pcall(fs.remove, staged) end
      return nil, "the archive could not be opened"
    end
  end
  local function cleanup()
    pcall(fs.unmount, fd or staged)
    if staged and fs.remove then pcall(fs.remove, staged) end
  end

  local candidates = {}
  local function scan(dir)
    local okItems, items = pcall(fs.getDirectoryItems, dir)
    if not okItems or type(items) ~= "table" then return end
    for _, item in ipairs(items) do
      if item ~= "." and item ~= ".." then
        local path = dir .. "/" .. item
        local okInfo, info = pcall(fs.getInfo, path)
        if okInfo and info then
          if info.type == "directory" then
            scan(path)
          elseif item:sub(1, 1) ~= "." and not dir:find("__MACOSX", 1, true)
              and isRomName(item) and type(info.size) == "number" then
            candidates[#candidates + 1] =
              { path = path, name = item, size = info.size }
          end
        end
      end
    end
  end
  scan(mount)

  if #candidates == 0 then
    cleanup()
    return nil, ("no .gb/.gbc/.gba file found inside %s")
      :format(tostring(displayName or "the archive"))
  end
  table.sort(candidates, function(a, b) return a.path < b.path end)

  local fallback, chosen
  for _, cand in ipairs(candidates) do
    if acceptedSize(cand.size) then
      local okRead, bytes = pcall(fs.read, cand.path)
      if okRead and type(bytes) == "string" and #bytes == cand.size then
        fallback = fallback or { bytes = bytes, name = cand.name }
        if opts.prefer then
          local okPref, hit = pcall(opts.prefer, bytes)
          if okPref and hit then
            chosen = { bytes = bytes, name = cand.name }
            break
          end
        end
      end
    end
  end
  chosen = chosen or fallback
  cleanup()
  if chosen then return chosen.bytes, chosen.name end

  local sizes = {}
  for _, cand in ipairs(candidates) do
    sizes[#sizes + 1] = string.format("%s (%d bytes)", cand.name, cand.size)
  end
  return nil, ("no 1 MiB / 2 MiB / 16 MiB ROM inside %s: %s")
    :format(tostring(displayName or "the archive"), table.concat(sizes, ", "))
end

return RomArchive
