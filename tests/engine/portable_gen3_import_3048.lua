package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local S = require("tests.harness").suite("portable gen3 import 3048")
local check, eq = S.check, S.eq

local FsIo = require("tests.fs_io")
local SaveData = require("src.core.SaveData")

local WIN = FsIo.isWindows

local function mkdirp(path)
  if WIN then
    os.execute('mkdir "' .. path:gsub("/", "\\") .. '" 2>nul')
  else
    os.execute('mkdir -p "' .. path .. '" 2>/dev/null')
  end
end

local function rmrf(path)
  if WIN then
    os.execute('rmdir /s /q "' .. path:gsub("/", "\\") .. '" 2>nul')
  else
    os.execute('rm -rf "' .. path .. '" 2>/dev/null')
  end
end

local function slurp(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local body = f:read("*a")
  f:close()
  return body
end

local SANDBOX = ((os.getenv("TMPDIR") or os.getenv("TEMP") or "/tmp")
  :gsub("[/\\]+$", "")) .. ("/pokeport_3048_%d_%d"):format(os.time(), math.random(1, 999999))
local GAME = SANDBOX .. "/game"
local SAVEDIR = SANDBOX .. "/appdata"
mkdirp(GAME)
mkdirp(SAVEDIR)
do
  local f = assert(io.open(GAME .. "/portable.txt", "wb"))
  f:close()
end

local savedFs = love.filesystem
local savedSystem = love.system
local savedCacheFs = package.loaded["src.import.CacheFs"]
local savedExtractor = package.loaded["src.import.RomExtractorGen3"]
local savedLuaWriter = package.loaded["src.import.LuaWriter"]

local SPIED = { "write", "newFile", "createDirectory", "append", "remove" }
local spyCalls = {}

local function stubLove()
  local fs = {}
  for k, v in pairs(savedFs) do fs[k] = v end
  fs.getSource = function() return GAME end
  fs.getSourceBaseDirectory = function() return GAME end
  fs.getSaveDirectory = function() return SAVEDIR end
  for _, name in ipairs(SPIED) do
    local real = fs[name]
    fs[name] = function(path, ...)
      spyCalls[#spyCalls + 1] = name .. "(" .. tostring(path) .. ")"
      if real then return real(path, ...) end
      return false
    end
  end
  love.filesystem = fs
  love.system = { getOS = function() return WIN and "Windows" or "Linux" end }
  SaveData._resetPortableCacheForTests()
end

local function saveDirEntries()
  return #(FsIo.listDir(SAVEDIR) or {})
end

local function spySummary()
  return #spyCalls .. (#spyCalls > 0 and (" (" .. table.concat(spyCalls, ", ") .. ")") or "")
end

local function run()
  stubLove()
  check(SaveData.isPortable(), "sandbox game folder is portable")

  package.loaded["src.import.CacheFs"] = nil
  package.loaded["src.import.LuaWriter"] = nil
  package.loaded["src.import.RomExtractorGen3"] = nil
  local CacheFs = require("src.import.CacheFs")
  CacheFs._resetPortableForTests()
  eq(CacheFs.root(), GAME, "cache root is the portable game folder")

  local RomExtractorGen3 = require("src.import.RomExtractorGen3")
  local GameVersion = require("src.core.GameVersion")
  for _, id in ipairs({ "firered", "leafgreen", "ruby", "sapphire", "emerald" }) do
    local version = GameVersion.VERSIONS[id]
    spyCalls = {}
    CacheFs.prefix = version.cachePrefix
    local ok, err = pcall(RomExtractorGen3.writeRequiredMarkers,
      { plan = { dirs = { "", "/intro", "/rse/pokedex", "/pokemon/storage" } } }, version.sha1)
    CacheFs.prefix = ""
    check(ok, id .. " required markers write" .. (ok and "" or (": " .. tostring(err))))
    eq(#spyCalls, 0, id .. " marker pass makes no save-dir filesystem calls: " .. spySummary())
    local root = GAME .. "/" .. version.cachePrefix .. "data/generated/gba"
    check(FsIo.isDir(root .. "/rse/pokedex"), id .. " plan dirs are created in the game folder")
    check(FsIo.isDir(root .. "/pokemon/storage"), id .. " nested plan dirs are created in the game folder")
    check(not FsIo.isDir(GAME .. "/" .. version.cachePrefix .. version.cachePrefix),
      id .. " plan dirs are not double-prefixed")
    eq(saveDirEntries(), 0, id .. " marker pass leaves the OS save directory empty")
  end

  local Loader = require("src.mods.Loader")
  spyCalls = {}
  local loader = setmetatable({
    fs = love.filesystem,
    mods = { m = { enabled = true, manifest = {} } },
    optionSchemas = { m = { { key = "x" } } },
  }, { __index = Loader })
  local okSchema, schemaErr = pcall(Loader._writeOptionSchemas, loader)
  check(okSchema, "option schema export runs" .. (okSchema and "" or (": " .. tostring(schemaErr))))
  check(slurp(GAME .. "/mod_option_schemas.json") ~= nil, "option schemas land in the game folder")
  eq(#spyCalls, 0, "option schema export makes no save-dir filesystem calls: " .. spySummary())
  eq(saveDirEntries(), 0, "option schema export leaves the OS save directory empty")

  local Check = require("src.update.Check")
  local PatchNotes = require("src.update.PatchNotes")
  spyCalls = {}
  check(type(Check._ingestForTests) == "function", "update state ingest is reachable")
  if type(Check._ingestForTests) == "function" then
    local full = { name = "gen1recomp-9.9.9-windows.zip", url = "fixture:full", size = 3 }
    Check._ingestForTests({ status = "checking" })
    Check._ingestForTests({ status = "needs_full", latest = "9.9.9", reason = "payload_missing",
      notes = "portable notes", full = full })
    local notesDoc = slurp(GAME .. "/updates/notes_cache.json")
    check(notesDoc ~= nil and notesDoc:find("portable notes", 1, true) ~= nil,
      "release notes cache lands in the game folder")
    local record = slurp(GAME .. "/updates/full-update.json")
    check(record ~= nil and record:find("payload_missing", 1, true) ~= nil,
      "full-update record lands in the game folder")
    local body, ver = PatchNotes.fromCache("9.9.9")
    eq(body, "portable notes", "patch notes read the portable notes cache")
    eq(ver, "9.9.9", "patch notes name the cached release")
    Check._ingestForTests({ status = "uptodate", latest = "9.9.9", clearFull = true,
      notes = "portable notes" })
    eq(slurp(GAME .. "/updates/full-update.json"), nil, "an up-to-date check clears the portable record")
  end
  eq(#spyCalls, 0, "update persistence makes no save-dir filesystem calls: " .. spySummary())
  eq(saveDirEntries(), 0, "update persistence leaves the OS save directory empty")
end

local ok, err = pcall(run)

love.filesystem = savedFs
love.system = savedSystem
package.loaded["src.import.CacheFs"] = savedCacheFs
package.loaded["src.import.RomExtractorGen3"] = savedExtractor
package.loaded["src.import.LuaWriter"] = savedLuaWriter
SaveData._resetPortableCacheForTests()
rmrf(SANDBOX)

if not ok then check(false, "suite raised: " .. tostring(err)) end

S.finish()
