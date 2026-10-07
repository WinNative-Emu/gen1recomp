-- engine/battle/wild_encounters.asm:38-46
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local check, eq = T.check, T.eq

local FIXTURE = {
  ["mods/meadow/manifest.json"] = [[{
    "id": "meadow",
    "name": "Meadow",
    "version": "1.0.0",
    "entry": "main.lua",
    "api": 2
  }]],
  ["mods/meadow/main.lua"] = [[
    local mod = ...
    local function flat(block)
      local b = {}
      for i = 1, 16 do b[i] = block end
      return b
    end
    mod.content.maps:register("MOD_MEADOW", {
      id = "MOD_MEADOW", label = "ModMeadow", index = 1100,
      tileset = "FIX_OUT", width = 4, height = 4, blocks = flat(1),
      borderBlock = 0, warps = {}, signs = {}, objects = {},
      outdoor = true,
    })
    mod.content.maps:register("MOD_CAVE", {
      id = "MOD_CAVE", label = "ModCave", index = 1101,
      tileset = "FIX_OUT", width = 4, height = 4, blocks = flat(1),
      borderBlock = 0, warps = {}, signs = {}, objects = {},
    })
  ]],
}

local run = T.sdk.loadMods({ "mods/meadow" }, { fs = T.sdk.memfs(FIXTURE) })
eq(#run.errors, 0, "the outdoor-map mod loads cleanly")
local data = run.data
check(data.maps.MOD_MEADOW and data.maps.MOD_MEADOW.outdoor == true,
  "maps:register keeps the outdoor field")
data.field.indoorEncounters = { firstIndoorMap = 37, excludedTileset = "FOREST" }

local OW = require("src.world.OverworldController")
local MapLoader = require("src.world.MapLoader")
local SaveData = require("src.core.SaveData")

local indoor = data.field.indoorEncounters
local rolls = OW.rollsIndoorEncounters
check(type(rolls) == "function", "OverworldState exposes the indoor-encounter rule")
if type(rolls) == "function" then
  check(not rolls({ id = "ROUTE_1", index = 12, tileset = "OVERWORLD" }, indoor),
    "a vanilla route below FIRST_INDOOR_MAP rolls only in grass")
  check(not rolls({ id = "ROUTE_23", index = 34, tileset = "PLATEAU" }, indoor),
    "a non-OVERWORLD vanilla map below FIRST_INDOOR_MAP rolls only in grass")
  check(rolls({ id = "MT_MOON_1F", index = 59, tileset = "CAVERN" }, indoor),
    "a vanilla cave rolls on every tile")
  check(not rolls({ id = "VIRIDIAN_FOREST", index = 51, tileset = "FOREST" }, indoor),
    "the FOREST tileset rolls only in grass")
  check(not rolls({ id = "MOD_FIELD", index = 1000, tileset = "OVERWORLD" }, indoor),
    "a mod map on the OVERWORLD tileset is outdoor without declaring it")
  check(not rolls(data.maps.MOD_MEADOW, indoor),
    "a mod map declaring outdoor = true rolls only in grass")
  check(rolls(data.maps.MOD_CAVE, indoor),
    "a mod map that does not declare outdoor keeps the indoor rule")
  check(rolls({ id = "MOD_TOWER", index = 1000, tileset = "OVERWORLD", outdoor = false },
              indoor), "outdoor = false opts an OVERWORLD map into indoor encounters")
  check(rolls({ id = "MOD_NOINDEX", tileset = "CAVERN" }, indoor),
    "a mod map with no index is not a comparison error")
  check(not rolls(data.maps.MOD_CAVE, nil), "no indoor rule in the dataset rolls nothing")
end

local function bind(fn, name, value)
  local i = 1
  while true do
    local n = debug.getupvalue(fn, i)
    if not n then return false end
    if n == name then debug.setupvalue(fn, i, value) return true end
    i = i + 1
  end
end

local save = SaveData.newGame()
save.party = {}
local game = { data = data, save = save,
               stack = { push = function() end },
               input = { isDown = function() return false end } }
check(bind(OW.onStepComplete, "Game", game), "onStepComplete binds Game")
bind(OW.onStepComplete, "mapScripts", { get = function() return nil end })

local function terrainOn(mapId)
  MapLoader.invalidate(mapId)
  local map = MapLoader.load(data, mapId)
  local seen = {}
  local noop = function() return false end
  local state = setmetatable({
    map = map, player = { cellX = 2, cellY = 2, facing = "down" },
    scriptMoves = {}, wildEncounterGraceSteps = 0,
    syncLastMapRewrite = noop, checkSpinner = noop, checkBadgeGate = noop,
    checkForcedMovement = noop, checkSeafoamCurrent = noop, safariStep = noop,
    applyFieldPoison = noop, refreshStandingOnWarp = noop, dirHeld = noop,
    rollEncounter = function(_, _, terrain) seen[#seen + 1] = terrain end,
  }, { __index = OW })
  local ok, err = pcall(OW.onStepComplete, state)
  check(ok, mapId .. " step completes: " .. tostring(err))
  check(not map:isGrassCell(2, 2), mapId .. " step lands off grass")
  return seen[1]
end

eq(terrainOn("MOD_MEADOW"), nil, "an outdoor mod map does not roll off grass")
eq(terrainOn("MOD_CAVE"), "indoor", "an indoor mod map rolls on every tile")

run.release()
T.finish("mod map outdoor encounters")
