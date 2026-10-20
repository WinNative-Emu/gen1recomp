package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local SaveData = require("src.core.SaveData")
local SEP = package.config:sub(1, 1)

local tmp = os.tmpname()
os.remove(tmp)
local dir = tmp .. "_portable_src"
assert(SaveData.mkdirNative(dir), "temp source folder")
local parent = dir:match("^(.*)[/\\][^/\\]+$")

local created = {}
local function full(rel) return dir .. SEP .. rel:gsub("/", SEP) end
local function put(rel, bytes)
  local parentRel = rel:match("^(.*)/[^/]+$")
  if parentRel then SaveData.mkdirNative(full(parentRel)) end
  local f = assert(io.open(full(rel), "wb"))
  f:write(bytes or "x")
  f:close()
  created[rel] = true
end
local function drop(rel)
  os.remove(full(rel))
  created[rel] = nil
end

love = {
  system = { getOS = function() return "Linux" end },
  filesystem = {
    getSource = function() return dir end,
    getSourceBaseDirectory = function() return parent end,
    getSaveDirectory = function() return dir .. SEP .. "save-dir-unused" end,
    getInfo = function(rel, kind)
      local st = SaveData.statNative(full(rel))
      if not st or (kind and kind ~= st.type) then return nil end
      return st
    end,
    getRealDirectory = function(rel)
      return SaveData.statNative(full(rel)) and dir or nil
    end,
    read = function(rel)
      local f = io.open(full(rel), "rb")
      if not f then return nil end
      local data = f:read("*a")
      f:close()
      return data
    end,
    load = function(rel)
      return loadfile(full(rel))
    end,
  },
}

local GameVersion = require("src.core.GameVersion")
local CacheFs = require("src.import.CacheFs")
local CacheContract = require("src.import.CacheContract")

put("portable.txt", "")
SaveData._resetPortableCacheForTests()
CacheFs._resetPortableForTests()
eq(CacheFs.root(), dir, "portable.txt in the source folder makes it the cache root")

local GEN1_CHART = "return { types = {}, matchups = { { attacker = 'WATER', defender = 'FIRE', multiplier = 20 } } }"
local GEN2_CHART = "return { generation = 2, types = {}, matchups = {}, battleRules = { accuracyMultipliers = {} } }"

for _, path in ipairs(CacheContract.requiredFiles("gold", true)) do put("gold/" .. path) end
put("gold/data/generated/type_chart.lua", GEN1_CHART)
local sha1 = GameVersion.info("gold").sha1
put("gold/" .. CacheContract.MARKER_PATH, "rom-cache-v15:" .. sha1)

check(not CacheContract.sourceTreeHasData("gold"),
  "an importer-written portable cache is not treated as a marker-free source tree")
check(not CacheContract.isReady("gold", CacheFs),
  "a stale-format Gold cache in the portable source folder is not ready")
local inspected = CacheContract.inspect("gold", {
  getInfo = love.filesystem.getInfo,
  getRealDirectory = love.filesystem.getRealDirectory,
  getSource = love.filesystem.getSource,
  readAt = CacheFs.readAt,
}, { allowSource = true, semantic = true })
eq(inspected, nil, "dataset inspection rejects the stale portable Gold cache")

put("gold/" .. CacheContract.MARKER_PATH, CacheContract.markerFor("gold"))
put("gold/data/generated/type_chart.lua", GEN2_CHART)
check(CacheContract.isReady("gold", CacheFs),
  "a current Gold cache in the portable source folder is ready")

drop("gold/data/generated/type_chart.lua")
check(not CacheContract.isReady("gold", CacheFs),
  "a Gold cache without its type chart is not ready")

put("data/generated/type_chart.lua", GEN1_CHART)
local savedVersion = GameVersion.get()
GameVersion.set("gold")
local chart = CacheFs.loadActive("data/generated/type_chart.lua")
eq(chart, nil, "Gold never loads the un-prefixed root type chart")
eq(CacheFs.readActive("data/generated/type_chart.lua"), nil,
  "Gold never reads the un-prefixed root type chart")
put("gold/data/generated/type_chart.lua", GEN2_CHART)
chart = CacheFs.loadActive("data/generated/type_chart.lua")
check(type(chart) == "table" and chart.battleRules ~= nil,
  "Gold loads its own type chart with battle rules")

GameVersion.set("red")
chart = CacheFs.loadActive("data/generated/type_chart.lua")
check(type(chart) == "table" and chart.matchups and chart.matchups[1] ~= nil,
  "Red still reads its legacy root type chart")
GameVersion.set(savedVersion)

drop("portable.txt")
SaveData._resetPortableCacheForTests()
CacheFs._resetPortableForTests()
eq(CacheFs.root(), nil, "without portable.txt the source folder is not the cache root")
for _, path in ipairs(CacheContract.requiredFilesFor("red")) do put(path) end
check(CacheContract.sourceTreeHasData("red"),
  "a marker-free Red source tree outside portable mode is still recognized")

local dirs = {}
for rel in pairs(created) do
  os.remove(full(rel))
  local d = rel:match("^(.*)/[^/]+$")
  while d do
    dirs[d] = true
    d = d:match("^(.*)/[^/]+$")
  end
end
local ordered = {}
for d in pairs(dirs) do ordered[#ordered + 1] = d end
table.sort(ordered, function(a, b) return #a > #b end)
for _, d in ipairs(ordered) do os.remove(full(d)) end
os.remove(dir)

T.finish()
