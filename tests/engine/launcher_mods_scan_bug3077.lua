package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local S = require("tests.harness").suite("launcher mods inbox scan budget")
local eq = S.eq
local check = S.check

local files, dirs, arch = {}, {}, {}
local ARCHIVES = {}
local counts = {}
local now = 0
local WRITE_COST = 0.001

local function bump(name) counts[name] = (counts[name] or 0) + 1 end
local function resetCounts() for k in pairs(counts) do counts[k] = nil end end
local function count(name) return counts[name] or 0 end

local function dirChild(key, name)
  if name == nil or name == "" then return key:match("^[^/]+") end
  local prefix = name .. "/"
  if key:sub(1, #prefix) ~= prefix then return nil end
  return key:sub(#prefix + 1):match("^[^/]+")
end

local function mapInfo(map, name, kind)
  if map[name] ~= nil then
    local body = map[name]
    return { type = kind or "file", size = type(body) == "string" and #body or 0, modtime = 1700000000 }
  end
  for key in pairs(map) do
    if dirChild(key, name) then return { type = "directory" } end
  end
  return nil
end

local vfs = {}

local throwOn

function vfs.write(name, data)
  now = now + WRITE_COST
  bump("write")
  if throwOn and name:find(throwOn, 1, true) then
    throwOn = nil
    error("simulated sd fault")
  end
  files[name] = data
  return true
end

function vfs.read(name)
  if name:lower():match("%.zip$") then bump("zipRead") end
  if arch[name] ~= nil then return arch[name] end
  return files[name]
end

function vfs.remove(name)
  files[name] = nil
  dirs[name] = nil
  return true
end

function vfs.createDirectory(name)
  dirs[name] = true
  return true
end

function vfs.getInfo(name, kind)
  local info = mapInfo(arch, name) or mapInfo(files, name) or mapInfo(dirs, name, "directory")
  if info and kind and info.type ~= kind then return nil end
  return info
end

function vfs.getDirectoryItems(name)
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

local mountedAt = {}

function vfs.mount(archive, point)
  bump("mount")
  local data = type(archive) == "table" and archive.data or files[archive]
  local contents = ARCHIVES[data]
  if not contents then return false end
  mountedAt[archive] = point
  for rel, body in pairs(contents) do arch[point .. "/" .. rel] = body end
  return true
end

function vfs.unmount(archive)
  local point = mountedAt[archive]
  mountedAt[archive] = nil
  if not point then return true end
  for k in pairs(arch) do
    if k:sub(1, #point + 1) == point .. "/" then arch[k] = nil end
  end
  return true
end

function vfs.newFileData(data, name)
  bump("newFileData")
  return { __filedata = true, data = data, name = name }
end

function vfs.newFile(name)
  if name:lower():match("%.zip$") then bump("zipOpen") end
  local f = { pos = 1 }
  function f:open(mode)
    if mode == "r" and files[name] == nil then return false, "missing" end
    return true
  end
  function f:read(n)
    local out = (files[name] or ""):sub(self.pos, self.pos + n - 1)
    self.pos = self.pos + #out
    return out, #out
  end
  function f:close() return true end
  return f
end

function vfs.getSaveDirectory() return "sdmc:/switch/gen1recomp/pokemon-love2d" end
function vfs.getSource() return nil end

local function manifestFor(id)
  return ('{"id":"%s","name":"%s","version":"1.0.0","entry":"main.lua"}'):format(id, id)
end

local function makeArchive(id, nFiles)
  local contents = { [id .. "/manifest.json"] = manifestFor(id), [id .. "/main.lua"] = "return {}\n" }
  for i = 1, nFiles do
    contents[("%s/assets/%02d/f%04d.bin"):format(id, i % 40, i)] = ("x"):rep(16)
  end
  local bytes = "PK\3\4" .. id .. ("z"):rep(nFiles)
  ARCHIVES[bytes] = contents
  return bytes
end

local saved = {
  fs = love.filesystem,
  timer = love.timer,
  getOS = love.system and love.system.getOS,
}
local SaveData = require("src.core.SaveData")
local savedPortable = SaveData.portableBaseDir
SaveData.portableBaseDir = function() return nil end
love.filesystem = vfs
love.timer = { getTime = function() return now end }
love.system = love.system or {}
love.system.getOS = function() return "NX" end
package.loaded["src.core.Platform"] = nil
package.loaded["src.import.CacheFs"] = nil
package.loaded["src.mods.LauncherMods"] = nil
package.loaded["src.import.RomImporter"] = nil
local CacheFs = require("src.import.CacheFs")
local LauncherMods = require("src.mods.LauncherMods")
local RomImporter = require("src.import.RomImporter")

local function importer()
  return setmetatable({
    isNX = true, android = false, launcher = true,
    tab = "mods", mods = {},
    ready = { red = false, blue = false, yellow = false },
    _refreshMods = function(self) self._refreshed = (self._refreshed or 0) + 1 end,
  }, RomImporter)
end

local BUDGET = LauncherMods.STEP_BUDGET or 0.008

local function press(ri)
  local t0 = now
  ri:chooseMod()
  return now - t0
end

local function pumpAll(ri, limit)
  local frames, worst = 0, 0
  while ri._modScanJob and frames < (limit or 100000) do
    local t0 = now
    if ri._pumpModScanJob then ri:_pumpModScanJob() else break end
    worst = math.max(worst, now - t0)
    frames = frames + 1
  end
  return frames, worst
end

files["imports/mods/small_mod.zip"] = makeArchive("small_mod", 3)
local ri = importer()
press(ri)
pumpAll(ri)
check(files["mods/small_mod/manifest.json"] ~= nil, "first scan installs the inbox zip")
check(ri.modNotice and ri.modNotice.ok and tostring(ri.modNotice.text):find("small_mod", 1, true),
  "first scan reports the install")

resetCounts()
ri = importer()
press(ri)
pumpAll(ri)
eq(count("zipRead") + count("zipOpen"), 0, "second scan reads no archive bytes")
eq(count("newFileData"), 0, "second scan builds no FileData")
eq(count("mount"), 0, "second scan mounts nothing")
check(ri.modNotice and ri.modNotice.ok and not tostring(ri.modNotice.text):find("already installed'", 1, true),
  "second scan notice is not an install error")

files["mods/small_mod/manifest.json"] = nil
resetCounts()
ri = importer()
press(ri)
pumpAll(ri)
check(count("newFileData") >= 1, "a tree without manifest.json counts as not installed")
check(files["mods/small_mod/manifest.json"] ~= nil, "manifest-less tree is reinstalled")

files["imports/mods/a_bad.zip"] = "not a zip at all"
files["imports/mods/big_mod.zip"] = makeArchive("big_mod", 2000)
CacheFs.prefix = "red/"
resetCounts()
ri = importer()
local pressCost = press(ri)
check(pressCost <= 2 * BUDGET, ("the press costs at most 2x budget (%.3fs)"):format(pressCost))
check(ri._modScanJob ~= nil, "a big zip leaves a scan job running after the press")
check(files["mods/big_mod/manifest.json"] == nil, "manifest is not written during the press")
eq(CacheFs.prefix, "red/", "CacheFs.prefix is the caller's between frames")
eq(ri.modScanBusy and ri:modScanBusy(), true, "modScanBusy reports the job")
eq(ri.modScanBusy and ri:_modsImportButtonLabel(), "Installing...", "import button reads Installing... while busy")

local job = ri._modScanJob
local reads = count("zipRead") + count("zipOpen")
local idx = job and job.index
ri:chooseMod()
check(ri._modScanJob == job and (job == nil or job.index == idx), "second press while scanning keeps the same job")
eq(count("zipRead") + count("zipOpen"), reads, "second press while scanning reads nothing")

local prefixOk = true
local frames, worst = 0, 0
while ri._modScanJob and frames < 100000 do
  local t0 = now
  ri:_pumpModScanJob()
  worst = math.max(worst, now - t0)
  frames = frames + 1
  if CacheFs.prefix ~= "red/" then prefixOk = false end
end
check(frames > 10, ("the install spans many frames (%d)"):format(frames))
check(worst <= 2 * BUDGET, ("no frame exceeds 2x budget (%.4fs)"):format(worst))
check(prefixOk, "CacheFs.prefix is restored at every frame boundary")
CacheFs.prefix = ""
check(files["mods/big_mod/manifest.json"] ~= nil, "big zip installs once pumped")
check(files["mods/big_mod/assets/00/f2000.bin"] ~= nil, "every file of the big zip is copied")
check(ri.modNotice and ri.modNotice.ok, "mixed scan keeps overall success")
check(tostring(ri.modNotice.text):find("big_mod", 1, true), "notice names the installed mod")
check(tostring(ri.modNotice.text):find("not a zip file", 1, true), "bad zip still reported beside success")
check((ri._refreshed or 0) == 1, "mods list refreshed once per scan")

resetCounts()
ri = importer()
press(ri)
pumpAll(ri)
eq(count("zipRead") + count("zipOpen"), 1, "next scan re-reads only the bad zip")
eq(count("newFileData"), 0, "next scan mounts no installed zip")

files["imports/mods/dup.zip"] = makeArchive("small_mod", 1)
resetCounts()
ri = importer()
press(ri)
pumpAll(ri)
check(ri.modNotice and tostring(ri.modNotice.text):find("already installed", 1, true),
  "a zip for an installed id reports the conflict once")
resetCounts()
ri = importer()
press(ri)
pumpAll(ri)
eq(count("newFileData"), 0, "conflicting zip is not read again")
eq(count("zipRead") + count("zipOpen"), 1, "only the bad zip is read again")

files["imports/mods/a_bad.zip"] = nil
ri = importer()
press(ri)
pumpAll(ri)
check(ri.modNotice and ri.modNotice.ok == false
    and tostring(ri.modNotice.text):find("a mod named 'small_mod' is already installed", 1, true),
  "a skipped conflicting zip still reports the conflict", ri.modNotice and ri.modNotice.text)
files["imports/mods/dup.zip"] = makeArchive("small_mod", 2)
resetCounts()
ri = importer()
press(ri)
pumpAll(ri)
eq(count("newFileData"), 1, "a changed conflicting zip is read again")
files["imports/mods/dup.zip"] = nil

local function liveMounts()
  local n = 0
  for _ in pairs(mountedAt) do n = n + 1 end
  return n
end

local function freshBig(id, n)
  for k in pairs(files) do
    if k:sub(1, #("mods/" .. id .. "/")) == "mods/" .. id .. "/" then files[k] = nil end
  end
  files["imports/mods/" .. id .. ".zip"] = makeArchive(id, n)
end

freshBig("play_mod", 400)
CacheFs.prefix = "red/"
ri = importer()
ri.ready.red = true
local launched = 0
ri.onComplete = function() launched = launched + 1 end
press(ri)
check(ri._modScanJob ~= nil, "play test: scan is running")
ri.tab = "red"
pcall(ri.play, ri, "red")
check(ri._handedOff ~= true and launched == 0, "play is blocked while a mod scan runs")
eq(ri.tab, "mods", "a blocked play shows the mods tab")
check(ri._modScanJob ~= nil, "a blocked play keeps the scan running")
pumpAll(ri)
check(files["mods/play_mod/manifest.json"] ~= nil, "the scan finishes after a blocked play")

freshBig("arena_mod", 400)
ri = importer()
ri.onComplete = function() launched = launched + 1 end
press(ri)
check(ri._modScanJob ~= nil and liveMounts() == 1, "arena test: scan is running with one mount")
pcall(ri.playArena, ri, "red", nil, { arena = true })
check(ri._modScanJob == nil, "an arena start cancels the scan")
eq(liveMounts(), 0, "a cancelled scan unmounts its archive")
eq(CacheFs.prefix, "red/", "a cancelled scan leaves the caller's CacheFs.prefix")
check(files["mods/arena_mod/manifest.json"] == nil, "a cancelled scan writes no manifest")

local dropped = importer()
press(dropped)
check(dropped._modScanJob ~= nil and liveMounts() == 1, "a scan is running when its launcher is dropped")
dropped = nil
collectgarbage("collect")
files["imports/mods/arena_mod.zip"] = nil
files["imports/mods/late_mod.zip"] = makeArchive("late_mod", 2)
ri = importer()
press(ri)
pumpAll(ri)
check(files["mods/late_mod/manifest.json"] ~= nil,
  "the next scan installs after an abandoned one", ri.modNotice and ri.modNotice.text)
eq(liveMounts(), 0, "the abandoned scan's archive is released")

freshBig("fault_mod", 400)
files["imports/mods/zz_after.zip"] = makeArchive("zz_after", 2)
throwOn = "fault_mod/assets/00/f0200.bin"
ri = importer()
press(ri)
local faultPrefixOk = true
local guard = 0
while ri._modScanJob and guard < 100000 do
  ri:_pumpModScanJob()
  if CacheFs.prefix ~= "red/" then faultPrefixOk = false end
  guard = guard + 1
end
check(throwOn == nil, "the fault fired mid-copy")
check(faultPrefixOk, "an error mid-job restores CacheFs.prefix")
eq(liveMounts(), 0, "an error mid-job unmounts the archive")
check(ri.modNotice and tostring(ri.modNotice.text):find("simulated sd fault", 1, true),
  "an error mid-job is reported", ri.modNotice and ri.modNotice.text)
check(files["mods/zz_after/manifest.json"] ~= nil, "the scan continues after an error mid-job")
CacheFs.prefix = ""

local direct = LauncherMods.beginInstallZip and LauncherMods.beginInstallZip("imports/mods/big_mod.zip",
  { replace = true, expectId = "big_mod" })
if direct then
  local steps, state, ok, id = 0, nil, nil, nil
  repeat
    local t0 = now
    state, ok, id = LauncherMods.stepInstall(direct, BUDGET)
    worst = math.max(worst, now - t0)
    steps = steps + 1
  until state == "done" or steps > 100000
  check(steps > 1 and ok == true and id == "big_mod", "stepInstall replaces in several steps")
  local syncOk, syncId = LauncherMods.installZip("imports/mods/big_mod.zip", { replace = true })
  check(syncOk == true and syncId == "big_mod", "blocking installZip still works")
else
  check(false, "LauncherMods.beginInstallZip exists")
end

love.filesystem = saved.fs
love.timer = saved.timer
love.system.getOS = saved.getOS
SaveData.portableBaseDir = savedPortable
package.loaded["src.core.Platform"] = nil
package.loaded["src.import.CacheFs"] = nil
package.loaded["src.mods.LauncherMods"] = nil
package.loaded["src.import.RomImporter"] = nil

S.finish()
