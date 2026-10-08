package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local SELF = "tests/engine/union_gen3_save_spot.lua"

local function child(V, ROOT)
  require("src.core.GameVersion").set(V)
  require("src.import.gba.versions").select(V)
  local Dataset = require("src.core.game3.dataset")
  Dataset.cacheRootOverride = ROOT
  Dataset.mountExtractRoots()
  local SaveConvert = require("src.save_convert.SaveConvert")
  SaveConvert.setGen3CacheDir(V, (ROOT:gsub("/data/generated/gba$", "")))
  local Schema = require("src.core.game3.save_schema_firered")
  local Spot = require("src.core.game3.link.union_save_spot")
  local s = Schema.newGame({ version = V, name = "TEST", gender = 0, rngSeed = 5 })
  s.version, s.trainerId, s.secretId = V, 1234, 5678
  local base = Schema.toSaveTable(s)
  local pre = Spot.prefix(V)
  local center = V == "firered" and "VIRIDIAN_CITY" or "OLDALE_TOWN"
  local twoF, oneF = pre .. center .. "_POKEMON_CENTER_2F", pre .. center .. "_POKEMON_CENTER_1F"
  local function at(map, x, y)
    local t = {}
    for k, v in pairs(base) do t[k] = v end
    t.map, t.x, t.y, t.facing = map, x, y, "down"
    t.dynamicWarp = { map = twoF, warpId = -1, x = 5, y = 1 }
    t.specialSaveWarpFlags = 1
    t.continueGameWarp = { map = twoF, warpId = -1, x = 5, y = 1 }
    return t
  end
  local cases = { { "room", at(Spot.roomId(V), 12, 20), oneF } }
  if V == "ruby" then cases[#cases + 1] = { "added door cell", at(twoF, 2, 1), oneF } end
  cases[#cases + 1] = { "vanilla 2F cell", at(twoF, 2, 3), twoF }
  for _, c in ipairs(cases) do
    local label, live, want = V .. " " .. c[1], c[2], c[3]
    local liveMap = live.map
    local bytes, err = SaveConvert.exportSav(live, V, nil)
    check(bytes ~= nil, label .. ": exported -- " .. tostring(err))
    eq(live.map, liveMap, label .. ": the live save is not moved")
    local back = bytes and SaveConvert.importSav(bytes, V, V)
    eq(back and back.map, want, label .. ": the .sav reads back on " .. want)
    if want == oneF then
      eq(back and back.x, 7, label .. ": x in front of the nurse")
      eq(back and back.y, 4, label .. ": y in front of the nurse")
    end
  end
  T.finish("union_gen3_save_spot " .. V)
end

if arg[1] and arg[2] then return child(arg[1], arg[2]) end

do
  local Spot = require("src.core.game3.link.union_save_spot")
  local Rules = require("src.core.game3.profiles.firered_rules")
  local nurse = Spot.nurseGfx("firered")
  local open = function() return 0 end
  local L = { collAt = function(_, x, y) return y == 3 and 1 or 0 end }
  local game = { data = { maps = {
    FR_CERULEAN_CITY_POKEMON_CENTER_1F = {
      midLayout = L, objects = { { graphicsId = nurse, x = 7, y = 2 } },
      warps = { { x = 1, y = 6, destMap = "FR_CERULEAN_CITY_POKEMON_CENTER_2F" } },
    },
    FR_CERULEAN_CITY_POKEMON_CENTER_2F = {
      midLayout = { collAt = open }, objects = {},
      warps = { { x = 1, y = 6, destMap = "FR_CERULEAN_CITY_POKEMON_CENTER_1F" } },
    },
  } } }
  local session = {
    version = "firered", map = "FR_UNION_ROOM_PLAZA", x = 12, y = 20, facing = "down",
    dynamicWarp = { map = "FR_CERULEAN_CITY_POKEMON_CENTER_2F", warpId = 0, x = 5, y = 1 },
    specialSaveWarpFlags = 0,
  }
  check(type(Rules.saveLocation) == "function", "FireRed rules rewrite a plaza save")
  local map, x, y, facing = Rules.saveLocation(session, game)
  eq(map, "FR_CERULEAN_CITY_POKEMON_CENTER_1F", "plaza save lands in the origin center 1F")
  eq(x, 7, "in front of the nurse (x)")
  eq(y, 4, "in front of the nurse (y)")
  eq(facing, "up", "facing the nurse")
  eq(session.map, "FR_UNION_ROOM_PLAZA", "the live player is not moved")
  session.map = "FR_CERULEAN_CITY_POKEMON_CENTER_2F"
  check(Rules.saveLocation(session, game) == nil, "a vanilla 2F save is untouched")
end

local function root(version)
  local home = os.getenv("HOME")
  if not home or home == "" then return nil end
  local ids = {}
  local env = os.getenv("POKEPORT_IDENTITY")
  if env and env ~= "" then ids[#ids + 1] = env end
  ids[#ids + 1] = "g1r-" .. version
  for _, base in ipairs({ home .. "/Library/Application Support/LOVE", home .. "/.local/share/love" }) do
    for _, id in ipairs(ids) do
      local r = base .. "/" .. id .. "/" .. version .. "/data/generated/gba"
      local f = io.open(r .. "/map_tree/census.json", "rb")
      if f then
        f:close()
        return r
      end
    end
  end
  return nil
end

for _, v in ipairs({ "firered", "emerald", "ruby" }) do
  local r = root(v)
  if not r then
    print("[skip] union_gen3_save_spot " .. v .. ": no cache")
  else
    local cmd = ("luajit %s %s '%s' 2>&1"):format(SELF, v, r)
    local p = io.popen(cmd)
    local out = p:read("*a")
    local ok = p:close()
    for line in out:gmatch("[^\n]+") do
      if line:find("FAIL", 1, true) then print(line) end
    end
    check(ok == true or ok == 0, v .. ": cart export of an added-map save round-trips to the nurse front")
  end
end

T.finish("union_gen3_save_spot")
