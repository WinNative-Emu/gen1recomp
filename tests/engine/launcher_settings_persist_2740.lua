package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

love.data = love.data or {}
love.data.hash = function(_, data) return "h" .. #data .. ":" .. data:sub(1, 24) end
love.data.encode = function(_, _, digest) return (digest:gsub(".", function(c)
  return ("%02x"):format(c:byte())
end)) end

local SaveData = require("src.core.SaveData")
local Serializer = require("src.core.SaveSerializer")

local function disk()
  return Serializer.decode(love.filesystem.read("options.lua") or "") or {}
end

local function externalWrite(patch)
  local tree = disk()
  for k, v in pairs(patch) do tree[k] = v end
  love.filesystem.write("options.lua", Serializer.encode(tree))
end

SaveData.saveOptions(SaveData.defaultOptions())
local stale = SaveData.loadOptions()
externalWrite({ autoReimport = true, splashVideo = false, themeVideoBg = false,
  reduceMotion = true })

stale.textSpeed = 1
SaveData.saveLiveOptions({ version = "red", options = stale })
local after = disk()
eq(after.autoReimport, true, "Gen 1 in-game save keeps autoReimport")
eq(after.splashVideo, false, "Gen 1 in-game save keeps Splash Video OFF")
eq(after.themeVideoBg, false, "Gen 1 in-game save keeps Theme Video BG OFF")
eq(after.reduceMotion, true, "Gen 1 in-game save keeps Reduce Motion")
eq(after.textSpeed, 1, "and the in-game change still lands")

local Game3 = require("src.core.Game3")
SaveData.saveOptions(SaveData.defaultOptions())
local stale3 = SaveData.loadOptions()
externalWrite({ autoReimport = true, splashVideo = false, themeVideoBg = false })
stale3.musicVol = 3
Game3.writeOptions({ options = stale3 })
after = disk()
eq(after.autoReimport, true, "Gen 3 writeOptions keeps autoReimport")
eq(after.splashVideo, false, "Gen 3 writeOptions keeps Splash Video OFF")
eq(after.themeVideoBg, false, "Gen 3 writeOptions keeps Theme Video BG OFF")
eq(after.musicVol, 3, "and the Gen 3 change still lands")

local LauncherSettings = require("src.import.LauncherSettings")

local function findRow(model, label)
  for _, section in ipairs(model.sections) do
    for _, row in ipairs(section.rows) do
      if row.label == label then return row end
    end
  end
end

SaveData.saveOptions({ lastVersion = "red", splashVideo = true, reduceMotion = false })
local model = LauncherSettings.open(nil, "red")
externalWrite({ lastVersion = "blue", autoReimport = true })
local splash = findRow(model, "Splash Video")
check(splash.step(), "Splash Video row steps")
model.save()
after = disk()
eq(after.splashVideo, false, "the settings panel writes its own change")
eq(after.lastVersion, "blue", "and keeps a launcher key another writer changed")
eq(after.autoReimport, true, "and keeps autoReimport another writer set")

local realWrite = love.filesystem.write
love.filesystem.write = function(name, ...)
  if tostring(name):match("^options%.lua") then return false, "sharing violation" end
  return realWrite(name, ...)
end
local motion = findRow(model, "Reduce Motion")
eq(motion.value(), "OFF", "Reduce Motion starts OFF")
motion.step()
local saved = model.save()
love.filesystem.write = realWrite
check(saved == false, "a failed options write reports failure")
eq(motion.value(), "OFF", "and the row shows what the file holds, not the lost value")
check(type(model.saveError) == "string", "and the panel carries a visible save error")
eq(disk().reduceMotion, false, "the file still holds OFF")

local RomSources = require("src.import.RomSources")
local RomArchive = require("src.import.RomArchive")

local rom = ("R"):rep(1048576)
local romSha = love.data.encode("string", "hex", love.data.hash("sha1", rom))

local mounts = {}
local fs = love.filesystem
local baseMount, baseUnmount, baseItems, baseInfo, baseRead =
  fs.mount, fs.unmount, fs.getDirectoryItems, fs.getInfo, fs.read
fs.newFileData = function(data, name) return { data = data, name = name } end
fs.mount = function(fd, point)
  if type(point) == "string" and point:match("^_rom_") then
    mounts[point] = fd
    return true
  end
  return baseMount(fd, point)
end
fs.unmount = function(fd)
  for point, m in pairs(mounts) do if m == fd then mounts[point] = nil return true end end
  return baseUnmount(fd)
end
local function inner(path)
  local point, rest = tostring(path):match("^(_rom_[%w_]+)/?(.*)$")
  if not point or not mounts[point] then return nil end
  return point, rest
end
fs.getDirectoryItems = function(path)
  local point, rest = inner(path)
  if point then
    if rest == "" then
      return { point:match("probe") and "probe" or "Pokemon Red.gb" }
    end
    return {}
  end
  return baseItems(path)
end
fs.getInfo = function(path, ...)
  local point, rest = inner(path)
  if point then
    if rest == "" then return { type = "directory" } end
    return { type = "file", size = rest == "probe" and 2 or #rom }
  end
  return baseInfo(path, ...)
end
fs.read = function(path, ...)
  local point, rest = inner(path)
  if point then return rest == "probe" and "ok" or rom end
  return baseRead(path, ...)
end
RomArchive._resetForTests()

local tmp = os.tmpname()
local zipPath = tmp .. "-red.zip"
local f = assert(io.open(zipPath, "wb"))
f:write("PK\3\4" .. ("z"):rep(4096))
f:close()

RomSources.remember("red", { sha1 = romSha, path = zipPath, at = 1 })
local cand = RomSources.candidate("red", false)
check(cand ~= nil and not cand.pick and cand.path == zipPath,
  "a zip source whose inner ROM matches the record is a re-import candidate")

local rawPath = tmp .. "-red.gb"
f = assert(io.open(rawPath, "wb"))
f:write(rom)
f:close()
RomSources.remember("red", { sha1 = romSha, path = rawPath, at = 1 })
cand = RomSources.candidate("red", false)
check(cand ~= nil and not cand.pick and cand.path == rawPath, "a raw source still matches")

os.remove(rawPath)
cand = RomSources.candidate("red", false)
check(cand ~= nil and cand.pick == true, "a moved or deleted source asks for the ROM instead of nothing")
eq(cand and cand.missing, "missing", "and says the file is gone")

f = assert(io.open(rawPath, "wb"))
f:write(("X"):rep(1048576))
f:close()
cand = RomSources.candidate("red", false)
check(cand ~= nil and cand.pick == true and cand.missing == "changed",
  "a source that no longer matches asks for the ROM too")

os.remove(rawPath)
os.remove(zipPath)
os.remove(tmp)

T.finish("launcher_settings_persist_2740")
