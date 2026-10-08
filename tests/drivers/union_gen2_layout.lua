local U = require("tests.drivers.util")
local CacheFs = require("src.import.CacheFs")
local GameVersion = require("src.core.GameVersion")
local Setting = require("src.online.union.Setting")
local Center = require("src.world.gen2.UnionCenter2F")
local Room = require("src.world.gen2.UnionRoomMap")

local function deepEq(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for k, v in pairs(a) do
    if not deepEq(v, b[k]) then return false end
  end
  for k in pairs(b) do
    if a[k] == nil then return false end
  end
  return true
end

return function(game)
  local fails = 0
  local function ok(cond, line)
    if not cond then fails = fails + 1 end
    print((cond and "PASS " or "FAIL ") .. line)
  end
  U.wait(60)
  local world = game.world
  if not (world and world.map) then print("FAIL world did not boot") love.event.quit(1) return end
  local v = GameVersion.current
  local dir = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/union-gen2"
  local on = Setting.patchesOn(2)
  local tag = on and "on" or "off"
  local maps, tilesets = world.maps, world.tilesets
  local fresh = CacheFs.loadActive("data/generated/maps.lua")
  local freshTs = CacheFs.loadActive("data/generated/tilesets.lua")
  print(("setting %s for %s"):format(tag, v))
  if on then
    ok(maps[Room.ID] ~= nil, "union room added")
    ok(maps[Center.MAP_ID].width == fresh[Center.MAP_ID].width + 2, "2F widened by two blocks")
    ok(not deepEq(maps[Center.MAP_ID], fresh[Center.MAP_ID]), "2F differs from the cache")
  else
    ok(maps[Room.ID] == nil, "no union room")
    ok(deepEq(maps[Center.MAP_ID], fresh[Center.MAP_ID]), "2F equals the cache table")
    ok(deepEq(tilesets[maps[Center.MAP_ID].tileset], freshTs[maps[Center.MAP_ID].tileset]),
      "2F tileset equals the cache table")
    ok(deepEq(tilesets.TILESET_GATE, freshTs.TILESET_GATE), "gate tileset equals the cache table")
    local scripts = CacheFs.loadActive("data/generated/scripts.lua")
    ok(game.data.gen2Scripts[Center.RECEPTIONIST_KEY] == nil
      and deepEq(game.data.gen2Scripts, scripts), "scripts equal the cache table")
  end
  local spots = { { 4, 4 }, { 11, 4 } }
  if on then spots[#spots + 1] = { 16, 4 } end
  for _, spot in ipairs(spots) do
    world:warpToMapId(Center.MAP_ID, spot[1], spot[2], "up")
    U.wait(40)
    U.still(game, ("%s/%s_%s_2f_x%d.png"):format(dir, v, tag, spot[1]))
  end
  if on then
    world:warpToMapId(Room.ID, 12, 12, "down")
    U.wait(40)
    U.still(game, ("%s/%s_on_room_center.png"):format(dir, v))
    world:warpToMapId(Room.ID, 12, 23, "down")
    U.wait(40)
    U.still(game, ("%s/%s_on_room_exit.png"):format(dir, v))
  end
  print(fails == 0 and "ALL PASS" or (fails .. " FAILURES"))
  love.event.quit(fails == 0 and 0 or 1)
end
