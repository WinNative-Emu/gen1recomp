package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local S = require("tests.harness").suite("launcher mods update keeps baseroms")
local eq = S.eq
local check = S.check

local MOD_ID = "big_rom_mod"
local DEST = "mods/" .. MOD_ID
local CHUNK = 4 * 1024 * 1024
local OLD_MANIFEST =
  ('{"id":"%s","name":"Big Rom","version":"1.0.0","entry":"main.lua"}'):format(MOD_ID)
local NEW_MANIFEST =
  ('{"id":"%s","name":"Big Rom","version":"2.0.0","entry":"main.lua"}'):format(MOD_ID)
local ARCHIVE = {
  [MOD_ID .. "/manifest.json"] = NEW_MANIFEST,
  [MOD_ID .. "/main.lua"] = "return function() return 2 end\n",
  [MOD_ID .. "/data/new.lua"] = "return {}\n",
}

local files, dirs, arch, mtime = {}, {}, {}, {}
local ops = {}
local clock = 0
local trapBaseromReads = true
local failWriteOnce, failOpenWrite
local chunkReads, maxChunk = 0, 0
local caseFold

local function fold(name)
  if not caseFold then return name end
  local key = caseFold:lower()
  local low = name:lower()
  if low == key or low:sub(1, #key + 1) == key .. "/" then
    return caseFold .. name:sub(#key + 1)
  end
  return name
end

local function resetFs()
  for _, t in ipairs({ files, dirs, arch, mtime, ops }) do
    for k in pairs(t) do t[k] = nil end
  end
  trapBaseromReads = true
  failWriteOnce, failOpenWrite = nil, nil
  chunkReads, maxChunk = 0, 0
  caseFold = nil
end

local function log(op, path) ops[#ops + 1] = { op = op, path = path } end

local function store(name, data)
  clock = clock + 1
  files[name] = data
  mtime[name] = clock
end

local function dirChild(key, name)
  if name == nil or name == "" then return key:match("^[^/]+") end
  local prefix = name .. "/"
  if key:sub(1, #prefix) ~= prefix then return nil end
  return key:sub(#prefix + 1):match("^[^/]+")
end

local function mapInfo(map, name, kind)
  if map[name] ~= nil then return { type = kind or "file" } end
  for key in pairs(map) do
    if dirChild(key, name) then return { type = "directory" } end
  end
  return nil
end

local vfs = {}

function vfs.write(name, data)
  name = fold(name)
  log("write", name)
  if failWriteOnce == name then
    failWriteOnce = nil
    return nil, "simulated write failure"
  end
  store(name, data)
  return true
end

function vfs.read(name)
  name = fold(name)
  log("read", name)
  if trapBaseromReads and name:find("/baseroms/", 1, true) then
    error("string length overflow")
  end
  if arch[name] ~= nil then return arch[name] end
  return files[name]
end

function vfs.remove(name)
  name = fold(name)
  log("remove", name)
  files[name] = nil
  dirs[name] = nil
  mtime[name] = nil
  return true
end

function vfs.createDirectory(name)
  name = fold(name)
  dirs[name] = true
  return true
end

function vfs.getInfo(name, kind)
  name = fold(name)
  log("info", name)
  local info = mapInfo(arch, name)
    or mapInfo(files, name)
    or mapInfo(dirs, name, "directory")
  if info and kind and info.type ~= kind then return nil end
  return info
end

function vfs.getDirectoryItems(name)
  name = fold(name)
  log("list", name)
  local seen, items = {}, {}
  local function add(child)
    if child and not seen[child] then
      seen[child] = true
      items[#items + 1] = child
    end
  end
  for key in pairs(arch) do add(dirChild(key, name)) end
  for key in pairs(files) do add(dirChild(key, name)) end
  for key in pairs(dirs) do add(dirChild(key, name)) end
  table.sort(items)
  return items
end

function vfs.newFile(name)
  name = fold(name)
  local f = { mode = nil, pos = 1, buf = {} }
  function f:open(mode)
    log("open:" .. mode, name)
    if mode == "w" and failOpenWrite == name then return false, "simulated open failure" end
    if mode == "r" and files[name] == nil then return false, "missing" end
    self.mode = mode
    return true
  end
  function f:read(n)
    chunkReads = chunkReads + 1
    if n > maxChunk then maxChunk = n end
    local src = files[name] or ""
    local out = src:sub(self.pos, self.pos + n - 1)
    self.pos = self.pos + #out
    return out, #out
  end
  function f:write(data)
    self.buf[#self.buf + 1] = data
    return true
  end
  function f:close()
    if self.mode == "w" then
      log("write", name)
      store(name, table.concat(self.buf))
    end
    self.mode = nil
    return true
  end
  return f
end

function vfs.mount(_, point)
  for rel, body in pairs(ARCHIVE) do arch[point .. "/" .. rel] = body end
  return true
end

function vfs.unmount()
  for k in pairs(arch) do arch[k] = nil end
  return true
end

function vfs.newFileData(data, name)
  return { __filedata = true, data = data, name = name }
end

function vfs.getSaveDirectory() return "/tmp/pokeport-update-baseroms-test" end
function vfs.getSource() return nil end

local savedFs = love.filesystem
local savedCacheFs = package.loaded["src.import.CacheFs"]
local savedLauncherMods = package.loaded["src.mods.LauncherMods"]
local SaveData = require("src.core.SaveData")
local savedPortable = SaveData.portableBaseDir

love.filesystem = vfs
package.loaded["src.import.CacheFs"] = nil
package.loaded["src.mods.LauncherMods"] = nil
SaveData.portableBaseDir = function() return nil end
local LauncherMods = require("src.mods.LauncherMods")

local function touches(prefix)
  local n = 0
  for _, o in ipairs(ops) do
    if o.path == prefix or o.path:sub(1, #prefix + 1) == prefix .. "/" then n = n + 1 end
  end
  return n
end

local function seedOldInstall()
  store(DEST .. "/manifest.json", OLD_MANIFEST)
  store(DEST .. "/main.lua", "return function() return 1 end\n")
  store(DEST .. "/old.lua", "return 'stale'\n")
  store(DEST .. "/gfx/old.bin", "stale")
  store(DEST .. "/baseroms/big.3ds", "user-owned-3ds")
  store(DEST .. "/baseroms/.required-import-rom.validated", "digest 14 1")
end

local function update(name)
  store("imports/mods/" .. name, "PK\3\4" .. name)
  return LauncherMods.installZip("imports/mods/" .. name,
    { replace = true, expectId = MOD_ID })
end

resetFs()
seedOldInstall()
local romTime = mtime[DEST .. "/baseroms/big.3ds"]
local receiptTime = mtime[DEST .. "/baseroms/.required-import-rom.validated"]
local ok, err = update("u1.zip")
check(ok == true, "update with a baserom present succeeds (" .. tostring(err) .. ")")
eq(touches(DEST .. "/baseroms"), 0, "update never lists, reads, writes or removes baseroms/")
eq(files[DEST .. "/baseroms/big.3ds"], "user-owned-3ds", "baserom bytes untouched")
eq(mtime[DEST .. "/baseroms/big.3ds"], romTime, "baserom modtime untouched")
eq(mtime[DEST .. "/baseroms/.required-import-rom.validated"], receiptTime,
  "validated receipt untouched")
eq(files[DEST .. "/manifest.json"], NEW_MANIFEST, "manifest is the new version")
eq(files[DEST .. "/main.lua"], ARCHIVE[MOD_ID .. "/main.lua"], "package file updated")
check(files[DEST .. "/data/new.lua"] ~= nil, "new package file written")
check(files[DEST .. "/old.lua"] == nil, "stale file from the old version removed")
check(files[DEST .. "/gfx/old.bin"] == nil, "stale nested file removed")

local lastWrite
for _, o in ipairs(ops) do
  if o.op == "write" and o.path:sub(1, #DEST + 1) == DEST .. "/" then lastWrite = o.path end
end
eq(lastWrite, DEST .. "/manifest.json", "manifest.json is the last write")

resetFs()
trapBaseromReads = false
seedOldInstall()
failWriteOnce = DEST .. "/main.lua"
ok, err = update("u2.zip")
check(not ok, "write failure fails the update")
eq(files[DEST .. "/manifest.json"], OLD_MANIFEST, "old manifest survives the failure")
eq(files[DEST .. "/baseroms/big.3ds"], "user-owned-3ds", "baserom survives the failure")
eq(touches(DEST .. "/baseroms"), 0, "failed update never touches baseroms/")
ok, err = update("u2-retry.zip")
check(ok == true, "retry after a failure succeeds (" .. tostring(err) .. ")")
eq(files[DEST .. "/manifest.json"], NEW_MANIFEST, "retry lands the new manifest")

resetFs()
failWriteOnce = DEST .. "/manifest.json"
store("imports/mods/fresh.zip", "PK\3\4fresh")
ok, err = LauncherMods.installZip("imports/mods/fresh.zip")
check(not ok, "fresh install manifest failure fails")
local left = 0
for k in pairs(files) do if k:sub(1, #DEST + 1) == DEST .. "/" then left = left + 1 end end
eq(left, 0, "failed fresh install rolls back every written file")

resetFs()
local big = string.rep("A", CHUNK) .. string.rep("B", CHUNK) .. "tail"
store("mods/OldFolder/manifest.json", OLD_MANIFEST)
store("mods/OldFolder/main.lua", "return function() end\n")
store("mods/OldFolder/baseroms/x.z64", big)
store("imports/baseroms-recovery/" .. MOD_ID .. "/y.z64", "recovered")
ok, err = update("u3.zip")
check(ok == true, "update over a shadow copy succeeds (" .. tostring(err) .. ")")
check(files[DEST .. "/baseroms/x.z64"] == big, "shadow baserom drained byte-exact")
eq(files[DEST .. "/baseroms/y.z64"], "recovered", "recovery baserom drained")
check(files["mods/OldFolder/manifest.json"] == nil, "shadow tree removed")
check(files["mods/OldFolder/baseroms/x.z64"] == nil, "shadow baserom removed after drain")
check(files["imports/baseroms-recovery/" .. MOD_ID .. "/y.z64"] == nil,
  "recovery dir cleared")
check(chunkReads >= 3, "drain streams in chunks (" .. chunkReads .. " reads)")
check(maxChunk <= CHUNK, "drain never reads more than one chunk at a time")
eq(files[DEST .. "/manifest.json"], NEW_MANIFEST, "drained install has the new manifest")

resetFs()
seedOldInstall()
store("mods/OldFolder/manifest.json", OLD_MANIFEST)
store("mods/OldFolder/baseroms/big.3ds", "shadow-copy")
ok, err = update("u4.zip")
check(ok == true, "update with both copies succeeds (" .. tostring(err) .. ")")
eq(files[DEST .. "/baseroms/big.3ds"], "user-owned-3ds", "existing baserom kept")

resetFs()
store("mods/OldFolder/manifest.json", OLD_MANIFEST)
store("mods/OldFolder/baseroms/z.z64", "only-copy")
failOpenWrite = DEST .. "/baseroms/z.z64"
ok, err = update("u5.zip")
check(not ok, "drain failure fails the update")
check(files[DEST .. "/manifest.json"] ~= nil, "mods/<id> keeps a manifest after a drain failure")
eq(files["mods/OldFolder/baseroms/z.z64"], "only-copy", "drain source kept on failure")
check(files[DEST .. "/baseroms/z.z64"] == nil, "partial drain copy removed")

resetFs()
store(DEST .. "/baseroms/r.z64", "orphan-rom")
store("imports/mods/heal.zip", "PK\3\4heal")
ok, err = LauncherMods.installZip("imports/mods/heal.zip")
check(ok == true, "re-import over orphan baseroms succeeds (" .. tostring(err) .. ")")
eq(files[DEST .. "/manifest.json"], NEW_MANIFEST, "orphan baseroms gain a manifest")
eq(files[DEST .. "/baseroms/r.z64"], "orphan-rom", "orphan baserom kept")
eq(touches(DEST .. "/baseroms"), 0, "re-import never touches baseroms/")

resetFs()
store("mods/Big_Rom_Mod/manifest.json", OLD_MANIFEST)
store("mods/Big_Rom_Mod/main.lua", "return function() return 1 end\n")
store("mods/Big_Rom_Mod/baseroms/k.z64", "case-shadow-rom")
ok, err = update("u6.zip")
check(ok == true, "update over a case-only shadow succeeds (" .. tostring(err) .. ")")
check(files["mods/Big_Rom_Mod/manifest.json"] == nil,
  "case-only shadow removed on a case-sensitive filesystem")
check(files["mods/Big_Rom_Mod/baseroms/k.z64"] == nil, "case-only shadow baserom drained out")
eq(files[DEST .. "/baseroms/k.z64"], "case-shadow-rom", "case-only shadow baserom lands in mods/<id>")
eq(files[DEST .. "/manifest.json"], NEW_MANIFEST, "mods/<id> has the new manifest")

resetFs()
caseFold = "mods/Big_Rom_Mod"
store("mods/Big_Rom_Mod/manifest.json", OLD_MANIFEST)
store("mods/Big_Rom_Mod/main.lua", "return function() return 1 end\n")
store("mods/Big_Rom_Mod/baseroms/k.z64", "folded-rom")
ok, err = update("u7.zip")
check(ok == true, "update on a case-insensitive filesystem succeeds (" .. tostring(err) .. ")")
eq(files["mods/Big_Rom_Mod/manifest.json"], NEW_MANIFEST,
  "case-folded install dir is updated, not removed")
eq(files["mods/Big_Rom_Mod/baseroms/k.z64"], "folded-rom", "case-folded install keeps its baserom")
eq(touches("mods/Big_Rom_Mod/baseroms"), 0, "case-folded install never touches baseroms/")

do
  local FsIo = require("tests.fs_io")
  local tmpBase = (os.getenv("TMPDIR") or "/tmp"):gsub("[/\\]+$", "")
  local sandbox = ("%s/lm3057_portable_%d_%d"):format(tmpBase, os.time(), math.random(1, 999999))
  local game = sandbox .. "/game"
  os.execute('mkdir -p "' .. game .. '/mods/' .. MOD_ID .. '/baseroms"')
  local zip = sandbox .. "/u.zip"
  local function put(path, data)
    local f = assert(io.open(path, "wb"))
    f:write(data)
    f:close()
  end
  put(zip, "PK\003\004x")
  put(game .. "/" .. DEST .. "/baseroms/g.rom", "game-folder-rom")
  local realFs = FsIo.new(game)
  local save, parch, saveOps = {}, {}, {}
  local function mapInfoP(map, name)
    if map[name] ~= nil then return { type = "file" } end
    for k in pairs(map) do if dirChild(k, name) then return { type = "directory" } end end
  end
  local pvfs = {}
  function pvfs.write(n, d) saveOps[#saveOps + 1] = n save[n] = d return true end
  function pvfs.read(n) return parch[n] or save[n] or realFs.read(n) end
  function pvfs.remove(n) saveOps[#saveOps + 1] = n save[n] = nil return true end
  function pvfs.createDirectory() return true end
  function pvfs.getInfo(n, kind)
    local i = mapInfoP(parch, n) or mapInfoP(save, n) or realFs.getInfo(n)
    if i and kind and i.type ~= kind then return nil end
    return i
  end
  function pvfs.getDirectoryItems(n)
    local seen, out = {}, {}
    local function add(c) if c and not seen[c] then seen[c] = true out[#out + 1] = c end end
    for k in pairs(parch) do add(dirChild(k, n)) end
    for k in pairs(save) do add(dirChild(k, n)) end
    local i = realFs.getInfo(n)
    if i and i.type == "directory" then
      for _, c in ipairs(realFs.getDirectoryItems(n)) do add(c) end
    end
    table.sort(out)
    return out
  end
  function pvfs.mount(_, pt) for r, b in pairs(ARCHIVE) do parch[pt .. "/" .. r] = b end return true end
  function pvfs.unmount() for k in pairs(parch) do parch[k] = nil end return true end
  function pvfs.getSource() return game end
  function pvfs.getSaveDirectory() return sandbox .. "/os-save" end

  love.filesystem = pvfs
  SaveData.portableBaseDir = function() return game end
  package.loaded["src.import.CacheFs"] = nil
  package.loaded["src.mods.LauncherMods"] = nil
  local PortableMods = require("src.mods.LauncherMods")

  save[DEST .. "/manifest.json"] = OLD_MANIFEST
  save[DEST .. "/main.lua"] = "return function() return 1 end\n"
  save[DEST .. "/baseroms/s.rom"] = "save-dir-rom"
  ok, err = PortableMods.installZip(zip, { replace = true, expectId = MOD_ID })
  check(ok == true, "portable update over a save-dir twin succeeds (" .. tostring(err) .. ")")
  eq(pvfs.read(DEST .. "/manifest.json"), NEW_MANIFEST,
    "portable update is visible through the merged read path")
  eq(pvfs.read(DEST .. "/main.lua"), ARCHIVE[MOD_ID .. "/main.lua"],
    "portable package file is visible through the merged read path")
  check(save[DEST .. "/manifest.json"] == nil, "save-dir twin manifest cleared")
  eq(save[DEST .. "/baseroms/s.rom"], "save-dir-rom", "save-dir baserom kept")
  eq(realFs.read(DEST .. "/baseroms/g.rom"), "game-folder-rom", "game-folder baserom kept")
  local baseromOps = 0
  for _, n in ipairs(saveOps) do
    if n:find("/baseroms", 1, true) then baseromOps = baseromOps + 1 end
  end
  eq(baseromOps, 0, "portable update never writes or removes a save-dir baserom")
  os.execute('rm -r "' .. sandbox .. '"')
end

love.filesystem = savedFs
SaveData.portableBaseDir = savedPortable
package.loaded["src.import.CacheFs"] = savedCacheFs
package.loaded["src.mods.LauncherMods"] = savedLauncherMods

S.finish()
