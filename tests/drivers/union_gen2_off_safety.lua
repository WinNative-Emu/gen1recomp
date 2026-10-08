local U = require("tests.drivers.util")
local Mon = require("src.battle.gen2.Mon")
local Setting = require("src.online.union.Setting")
local Origin = require("src.online.union.Origin")
local Center = require("src.world.gen2.UnionCenter2F")
local Room = require("src.world.gen2.UnionRoomMap")
local GameVersion = require("src.core.GameVersion")

local function copy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = copy(x) end
  return out
end

return function(game)
  local fails = 0
  local function ok(cond, line)
    if not cond then fails = fails + 1 end
    print((cond and "PASS " or "FAIL ") .. line)
  end
  U.wait(60)
  if not (game.world and game.world.map) then print("FAIL world did not boot") love.event.quit(1) return end
  local on = Setting.patchesOn(2)
  local v = GameVersion.current
  local tag = on and "on" or "off"
  local dir = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/union-gen2"
  print(("setting %s for %s"):format(tag, v))
  local maps = game.world.maps
  local function nurseFront(id)
    for _, o in ipairs(maps[id].objects) do
      if o.sprite == "SPRITE_NURSE" then return o.x, o.y + 2 end
    end
  end
  local home = "VIOLET_POKECENTER_1F"
  local healCenter = "CHERRYGROVE_POKECENTER_1F"
  local stairs = maps[home].warps[3]
  local template = copy(game.save)
  template.party = { Mon.new(game.data, "CYNDAQUIL", 12) }
  template.spawn = "SPAWN_CHERRYGROVE"

  local function boot(pos, backup, withOrigin)
    local save = copy(template)
    save.position = pos
    save.backupWarp = backup
    save.mapScenes = { [Center.MAP_ID] = 99, [Room.ID] = 1 }
    if withOrigin ~= false then
      Origin.record(save, { gen = 2, version = v, map = home, warp = 3,
        x = stairs.x, y = stairs.y, facing = "left" })
    end
    game:continueGame(save)
    U.wait(40)
    return save, game.world
  end
  local function at(w) return w.map.id, w.player.cellX, w.player.cellY, w.player.facing end
  local function atNurse(w, id, what)
    local m, x, y, f = at(w)
    local nx, ny = nurseFront(id)
    ok(m == id and x == nx and y == ny and f == "up",
      ("%s: %s lands in front of the %s nurse (%s %d,%d %s)"):format(tag, what, id, m, x, y, f))
  end

  local good = { map = home, warp = 3 }
  local save, w = boot({ map = Room.ID, x = 12, y = 23, facing = "down" }, good)
  atNurse(w, home, "room save")
  ok(Origin.get(save) == nil, tag .. ": origin cleared")
  ok(save.mapScenes[Room.ID] == nil, tag .. ": room scene cleared")
  U.still(game, ("%s/%s_%s_safety_room_save.png"):format(dir, v, tag))
  w:warpToMapId(home, stairs.x + 1, stairs.y, "left")
  U.wait(30)
  U.hold(game, "left", 30)
  U.wait(60)
  ok(game.world.map.id == Center.MAP_ID, tag .. ": the 1F stairs climb to the 2F")
  ok(game.world.backupWarp and game.world.backupWarp.map == home, tag .. ": backupWarp banks " .. home)

  save, w = boot({ map = Room.ID, x = 12, y = 23 }, { map = "NOWHERE", warp = 1 }, false)
  atNurse(w, healCenter, "room save with no origin")

  save, w = boot({ map = Center.MAP_ID, x = 17, y = 3, facing = "up" }, good)
  atNurse(w, home, "save at the added desk")
  U.still(game, ("%s/%s_%s_safety_2f_added.png"):format(dir, v, tag))

  for _, id in ipairs({ "INDIGO_PLATEAU_POKECENTER_1F", "GOLDENROD_POKECENTER_1F" }) do
    local idx
    for i, wp in ipairs(maps[id].warps) do
      if wp.destMap == Center.MAP_ID then idx = i end
    end
    local s = copy(template)
    s.position = { map = Room.ID, x = 12, y = 23, facing = "down" }
    s.backupWarp = { map = id, warp = idx }
    Origin.record(s, { gen = 2, version = v, map = id, warp = idx,
      x = maps[id].warps[idx].x, y = maps[id].warps[idx].y })
    game:continueGame(s)
    U.wait(40)
    atNurse(game.world, id, "room save from " .. id)
    U.still(game, ("%s/%s_%s_safety_%s.png"):format(dir, v, tag, id:lower()))
  end

  save, w = boot({ map = Center.MAP_ID, x = 0, y = 7, facing = "right" }, good)
  local m, x, y = at(w)
  ok(m == Center.MAP_ID and x == 0 and y == 7, tag .. ": a save on the 2F stairs is left alone")
  ok(Origin.get(save) ~= nil, tag .. ": and keeps its origin")
  print(fails == 0 and "ALL PASS" or (fails .. " FAILURES"))
  love.event.quit(fails == 0 and 0 or 1)
end
