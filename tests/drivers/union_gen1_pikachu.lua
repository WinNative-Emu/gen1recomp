local U = require("tests.drivers.util")
local Pokemon = require("src.pokemon.Pokemon")
local GameVersion = require("src.core.GameVersion")
local PF = require("src.world.PikachuFollower")
local UnionCenters = require("src.world.gen1.UnionCenters")
local UnionRoomMap = require("src.world.gen1.UnionRoomMap")

local SHOT_DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/pokeport-shots"

return function(game)
  local fails = 0
  local function ok(cond, line)
    if not cond then fails = fails + 1 end
    print((cond and "PASS " or "FAIL ") .. line)
  end
  local function ow() return game.overworld end
  local function idle()
    local o = ow()
    return o and game.stack:top() == o and not o.transitioning
      and not o.runner:isRunning() and #o.scriptMoves == 0
      and not (o.pendingScripts and o.pendingScripts[1])
      and not o.healAnim and not o.emote
  end
  local function waitFor(cond, frames)
    for _ = 1, frames do
      if cond() then return true end
      U.wait(1)
    end
    return cond()
  end
  local function mash(cond, frames)
    for _ = 1, frames do
      if cond() then return true end
      U.tap(game, "a")
      U.wait(3)
    end
    return cond()
  end
  local function at()
    local p = ow().player
    return ow().map.id, p.cellX, p.cellY
  end
  local function follower() return PF.current(ow()) end

  ok(GameVersion.isYellow(), "running as Yellow")
  U.wait(10)
  local f = game.save.flags
  f.EVENT_GOT_STARTER = true
  f.EVENT_BATTLED_RIVAL_IN_OAKS_LAB = true
  f.EVENT_GOT_POKEDEX = true
  game.save.pikachuInBall = false
  game.save.party = { Pokemon.new(game.data, "PIKACHU", 20), Pokemon.new(game.data, "PIDGEY", 5) }
  game.save.lastOutdoor = { id = "PEWTER_CITY", x = 13, y = 26 }

  local function stepTo(dir, cx, cy)
    for _ = 1, 6 do
      local _, x, y = at()
      if x == cx and y == cy then return true end
      U.hold(game, dir, 12)
      waitFor(idle, 60)
    end
    local _, x, y = at()
    return x == cx and y == cy
  end
  U.teleport(game, "PEWTER_POKECENTER", 11, 5, "up")
  ok(stepTo("up", 11, 4) and stepTo("up", 11, 3) and stepTo("up", 11, 2), "walked up the aisle beside the counter end")
  ok(follower() ~= nil, "Pikachu follows on the Pewter 1F")
  U.still(game, SHOT_DIR .. "/yellow_pika_01_1f_before_stairs.png")
  ok(stepTo("up", 11, 1) and stepTo("right", 12, 1), ("walked into the stairs alcove (%s %d,%d)"):format(at()))
  U.hold(game, "right", 20)
  ok(waitFor(function() return ow().map.id == UnionCenters.FLOOR_2F and idle() end, 900), "stairs up with Pikachu")
  U.wait(30)
  ok(follower() ~= nil, "Pikachu followed to 2F")
  local walked = stepTo("down", 13, 2) and stepTo("down", 13, 3)
  for cx = 12, 7, -1 do walked = walked and stepTo("left", cx, 3) end
  ok(walked, "walked across the 2F to the union desk")
  U.hold(game, "up", 4)
  waitFor(idle, 60)
  local m, x, y = at()
  ok(m == UnionCenters.FLOOR_2F and x == 7 and y == 3, ("in front of the union desk (%s %d,%d)"):format(m, x, y))
  U.still(game, SHOT_DIR .. "/yellow_pika_02_2f_desk.png")
  U.tap(game, "a")
  ok(mash(function() return ow().map.id == UnionCenters.UNION_ROOM end, 900), "walked into the room with Pikachu")
  ok(waitFor(idle, 600), "room idle")
  U.wait(40)
  local ex, ey = UnionRoomMap.entry()
  m, x, y = at()
  ok(x == ex and y == ey, ("on the exit carpet (%d,%d)"):format(x, y))
  U.hold(game, "up", 30)
  waitFor(idle, 200)
  U.still(game, SHOT_DIR .. "/yellow_pika_03_room.png")
  ok(follower() ~= nil, "Pikachu inside the room")
  U.teleport(game, UnionCenters.UNION_ROOM, ex, ey, "down")
  U.hold(game, "down", 30)
  ok(waitFor(function() return ow().map.id == UnionCenters.FLOOR_2F end, 600), "out through the carpet")
  ok(mash(idle, 600), "walk-out finished")
  m, x, y = at()
  ok(x == 6 and y == 4, ("walked out to %d,%d"):format(x, y))
  U.still(game, SHOT_DIR .. "/yellow_pika_04_2f_out.png")
  U.teleport(game, UnionCenters.FLOOR_2F, 13, 2, "up")
  game.save.unionOrigin = nil
  require("src.online.union.Origin").record(game.save, { gen = 1, version = "yellow",
    map = "PEWTER_POKECENTER", warp = UnionCenters.planFor(game.data, "PEWTER_POKECENTER").warp,
    x = 13, y = 1, facing = "down" })
  U.hold(game, "up", 20)
  ok(waitFor(function() return ow().map.id == "PEWTER_POKECENTER" and idle() end, 900), "stairs back down to Pewter")
  U.wait(30)
  ok(follower() ~= nil, "Pikachu followed back down")

  print(fails == 0 and "all claims passed" or (fails .. " claims failed"))
  love.event.quit(fails == 0 and 0 or 1)
end
