package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local S = require("tests.harness").suite("rom import from archives")
local check, eq = S.check, S.eq

local RomArchive = require("src.import.RomArchive")
local RomImporter = require("src.import.RomImporter")

local KIND_7Z = "7z\188\175\39\28"
local zipProbe = RomArchive._zipProbeBytes()
local userArchive = "PK\3\4" .. "user-archive-body"
local sevenZFile = KIND_7Z .. "user-7z-body"

local goodBody = string.rep("R", 1048576)
local SUPPORT_Z7 = false
local userEntries = { ["Red.gb"] = goodBody }

local function makeVfs()
  local vfs = {}
  local arch = {}
  local mounted = {}
  local staged = {}

  local function keyOf(archive)
    if type(archive) == "table" then return archive end
    return staged[archive] and archive or nil
  end

  function vfs.newFileData(data, name)
    return { _fileData = true, data = data, name = name }
  end

  function vfs.write(path, data)
    staged[path] = data
    return true
  end

  function vfs.remove(path)
    staged[path] = nil
    return true
  end

  function vfs.mount(archive, point)
    local data
    if type(archive) == "table" then
      data = archive.data
    else
      data = staged[archive]
    end
    if not data then return false end
    local entries
    if data == userArchive then
      entries = userEntries
    elseif data == sevenZFile then
      entries = userEntries
    elseif data == zipProbe then
      entries = { probe = "ok" }
    elseif RomArchive.kind(data) == "7z" then
      if not SUPPORT_Z7 then return false end
      entries = { ["p.romprobe"] = "gen1recomp-probe" }
    else
      return false
    end
    arch[point] = { dir = true }
    for rel, body in pairs(entries) do
      arch[point .. "/" .. rel] = { body = body }
    end
    mounted[keyOf(archive) or data] = point
    return true
  end

  function vfs.unmount(archive)
    local point = mounted[archive] or mounted[archive.data and archive or nil]
    if not point then
      for k, v in pairs(mounted) do
        if k == archive or (type(k) == "table" and k.data == archive) then
          point = v
        end
      end
    end
    if not point then return false end
    for path in pairs(arch) do
      if path == point or path:sub(1, #point + 1) == point .. "/" then
        arch[path] = nil
      end
    end
    mounted[archive] = nil
    for k, v in pairs(mounted) do
      if v == point then mounted[k] = nil end
    end
    return true
  end

  function vfs.getDirectoryItems(dir)
    if not (arch[dir] and arch[dir].dir) then return {} end
    local out = {}
    for path in pairs(arch) do
      if path ~= dir and path:sub(1, #dir + 1) == dir .. "/" then
        local rest = path:sub(#dir + 2)
        if not rest:find("/", 1, true) and not arch[path].dir then
          out[#out + 1] = rest
        end
      end
    end
    table.sort(out)
    return out
  end

  function vfs.getInfo(path)
    local node = arch[path]
    if node then
      if node.dir then return { type = "directory" } end
      return { type = "file", size = #node.body }
    end
    for other in pairs(arch) do
      if other:sub(1, #path + 1) == path .. "/" then
        return { type = "directory" }
      end
    end
    return nil
  end

  function vfs.read(path)
    local node = arch[path]
    if node and node.body then return node.body end
    return nil, "not found"
  end

  return vfs
end

local savedFs = love.filesystem
local vfs = makeVfs()
love.filesystem = vfs
RomArchive._resetForTests()

eq(RomArchive.kind("GBROM" .. string.rep("x", 20)), nil, "raw ROM is not an archive")
eq(RomArchive.kind("PK\3\4rest"), "zip", "PK\\3\\4 is a zip")
eq(RomArchive.kind("PK\5\6rest"), "zip", "empty zip is a zip")
eq(RomArchive.kind(KIND_7Z .. "rest"), "7z", "7z magic recognised")
eq(RomArchive.kind("PK"), nil, "truncated input is not an archive")
eq(RomArchive.kind(nil), nil, "non-string input is not an archive")

local caps = RomArchive.capabilities(vfs)
check(caps.zip == true, "zip probe mounts here")
check(caps.z7 == false, "7z probe refuses while SUPPORT_Z7 is off")

SUPPORT_Z7 = true
RomArchive._resetForTests()
caps = RomArchive.capabilities(vfs)
check(caps.z7 == true, "7z probe mounts once the platform supports it")
SUPPORT_Z7 = false
RomArchive._resetForTests()
check(RomArchive.capabilities(vfs).z7 == false, "caps are re-probed after reset")

userEntries = { ["._Red.gb"] = "APPLEDOUBLE", ["Red.gb"] = goodBody }
local bytes, entry = RomArchive.unwrap(userArchive, "pack.zip", { fs = vfs })
eq(bytes, goodBody, "cart bytes come out")
eq(entry, "Red.gb", "AppleDouble ._Red.gb is skipped, Red.gb wins")
check(RomArchive.unwrap("hello", "x.zip", { fs = vfs }) == nil, "not-an-archive refused")

userEntries = { ["A.gb"] = "AAA", ["Y.gb"] = "YYY" }
bytes, entry = RomArchive.unwrap(userArchive, "pack.zip", {
  fs = vfs,
  acceptedSize = function(n) return n >= 3 end,
  prefer = function(b) return b:sub(1, 1) == "Y" end,
})
eq(entry, "Y.gb", "prefer() picks the known-version cart over sort order")

userEntries = { ["notes.txt"] = "text" }
local noRom, noRomErr = RomArchive.unwrap(userArchive, "pack.zip", { fs = vfs })
eq(noRom, nil, "an archive with no cart refuses")
check(tostring(noRomErr):find("no .gb/.gbc/.gba", 1, true) ~= nil,
  "the no-cart message says so: " .. tostring(noRomErr))

userEntries = { ["Red.gb"] = string.rep("R", 2000) }
local wrongSize, wrongErr = RomArchive.unwrap(userArchive, "pack.zip", { fs = vfs })
eq(wrongSize, nil, "a wrong-size cart is never read (zip bomb guard)")
check(tostring(wrongErr):find("2000 bytes", 1, true) ~= nil,
  "the wrong-size message lists sizes: " .. tostring(wrongErr))

userEntries = { ["Red.gb"] = goodBody }
local z7bytes, z7err = RomArchive.unwrap(sevenZFile, "cart.7z", { fs = vfs })
eq(z7bytes, nil, "7z refused while the platform lacks the archiver")
check(tostring(z7err):find("cannot open .7z", 1, true) ~= nil,
  "the caps refusal names the format: " .. tostring(z7err))

SUPPORT_Z7 = true
RomArchive._resetForTests()
local z7ok, z7entry = RomArchive.unwrap(sevenZFile, "cart.7z", { fs = vfs })
eq(z7ok, goodBody, "7z opens once the platform supports it")
eq(z7entry, "Red.gb", "and yields its cart")
SUPPORT_Z7 = false
RomArchive._resetForTests()

love.data = love.data or {}
local savedData = { hash = love.data.hash, encode = love.data.encode }
love.data.hash = function(_, data)
  return { tag = data:sub(1, 1) }
end
love.data.encode = function(_, _, digest)
  if type(digest) == "table" and digest.tag == "R" then
    return require("src.core.GameVersion").info("red").sha1
  end
  return "0000000000000000000000000000000000000000"
end

local function freshImporter(extra)
  local ri = setmetatable({ tab = "red", workState = nil }, RomImporter)
  for k, v in pairs(extra or {}) do ri[k] = v end
  return ri
end

userEntries = { ["Red.gb"] = string.rep("R", 2000) }
local ri = freshImporter()
ri:startData(userArchive, "pack.zip")
eq(ri.workState, "error", "wrong-size cart in a zip lands in the error state")
check(tostring(ri.detail):find("2000 bytes", 1, true) ~= nil,
  "the size filter runs before any read: " .. tostring(ri.detail))

userEntries = { ["Red.gb"] = string.rep("X", 1048576) }
ri = freshImporter()
ri:startData(userArchive, "pack.zip")
eq(ri.workState, "error", "unknown-sha cart in a zip errors too")
check(tostring(ri.detail):find("Unsupported ROM (SHA-1", 1, true) ~= nil,
  "the SHA-1 gate runs on the unwrapped bytes: " .. tostring(ri.detail))

local realMax = RomArchive.MAX_ARCHIVE_BYTES
RomArchive.MAX_ARCHIVE_BYTES = 10
ri = freshImporter()
ri:startData(userArchive, "pack.zip")
RomArchive.MAX_ARCHIVE_BYTES = realMax
eq(ri.workState, "error", "an oversized archive is refused before mounting")
check(tostring(ri.detail):find(".zip", 1, true) ~= nil,
  "the oversize message names the format: " .. tostring(ri.detail))

ri = freshImporter()
ri:startData(sevenZFile, "cart.7z")
eq(ri.workState, "error", "a 7z drop takes the same startData path")
check(tostring(ri.detail):find("cannot open .7z", 1, true) ~= nil,
  "and is refused by caps: " .. tostring(ri.detail))

userEntries = { ["Red.gb"] = goodBody }

local function fakeFile(path, content)
  return {
    open = function() return true end,
    read = function() return content end,
    close = function() end,
    getSize = function() return #content end,
    getFilename = function() return path end,
  }
end

ri = freshImporter({ tab = "red" })
local started
ri.startData = function(self, data, name, src)
  started = { data = data, name = name, src = src }
end
ri:filedropped(fakeFile("/tmp/packs/cart-pack.zip", userArchive))
check(started ~= nil, "a game-tab zip holding a cart routes to startData")
if started then
  eq(started.data, userArchive, "startData receives the archive payload (it unwraps)")
  eq(started.name, "/tmp/packs/cart-pack.zip", "and the dropped path for display")
end

ri = freshImporter({ tab = "red" })
ri:filedropped(fakeFile("/tmp/cart.7z", sevenZFile))
eq(ri.workState, "error", "a dropped .7z reaches startData via the generic path")
check(tostring(ri.detail):find("cannot open .7z", 1, true) ~= nil,
  "and is refused when the platform lacks 7z: " .. tostring(ri.detail))

love.filesystem = savedFs
love.data.hash = savedData.hash
love.data.encode = savedData.encode
RomArchive._resetForTests()

S.finish()
