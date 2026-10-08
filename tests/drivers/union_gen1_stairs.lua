local U = require("tests.drivers.util")
local UnionCenters = require("src.world.gen1.UnionCenters")
local Origin = require("src.online.union.Origin")
local GameVersion = require("src.core.GameVersion")

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
  local function at()
    local p = ow().player
    return ow().map.id, p.cellX, p.cellY
  end
  local v = GameVersion.get()
  U.wait(10)
  local r = UnionCenters.forData(game.data)
  ok(r ~= nil, "union centers registry present")
  if not r then love.event.quit(1) return end
  ok(#r.order == #UnionCenters.EXPECTED, ("%d of %d expected centers planned"):format(#r.order, #UnionCenters.EXPECTED))
  for _, id in ipairs(UnionCenters.EXPECTED) do
    ok(r.plans[id] and r.plans[id].verified, id .. " plan verified at load")
  end

  for _, id in ipairs(r.order) do
    local plan = r.plans[id]
    local town = id == "INDIGO_PLATEAU_LOBBY" and "INDIGO_PLATEAU" or "VIRIDIAN_CITY"
    game.save.lastOutdoor = { id = town, x = 10, y = 10 }
    Origin.clear(game.save)
    U.teleport(game, id, plan.stairs.x, plan.stairs.y + 1, "up")
    ow().lastOutdoor = game.save.lastOutdoor
    local outdoorBefore = ow().lastOutdoor
    if id == "VIRIDIAN_POKECENTER" or id == "MT_MOON_POKECENTER" or id == "INDIGO_PLATEAU_LOBBY" then
      U.still(game, ("%s/%s_stairs_1f_%s.png"):format(SHOT_DIR, v, id:lower()))
    end
    U.hold(game, "up", 20)
    ok(waitFor(function() return ow().map.id == UnionCenters.FLOOR_2F and idle() end, 900),
       id .. ": stairs lead to 2F")
    local m, x, y = at()
    ok(m == UnionCenters.FLOOR_2F and x == UnionCenters.STAIRS_2F.x and y == UnionCenters.STAIRS_2F.y,
       ("%s: arrived on the 2F stairs (%s %d,%d)"):format(id, m, x, y))
    local o = Origin.get(game.save)
    ok(o and o.gen == 1 and o.map == id and o.warp == plan.warp and o.x == plan.stairs.x
       and o.y == plan.stairs.y and o.version == v,
       ("%s: origin recorded (%s #%s)"):format(id, tostring(o and o.map), tostring(o and o.warp)))
    ok(ow().lastOutdoor == outdoorBefore and game.save.lastOutdoor.id == town,
       id .. ": outdoor bookkeeping untouched")
    U.hold(game, "down", 20)
    waitFor(idle, 200)
    U.hold(game, "up", 20)
    ok(waitFor(function() return ow().map.id == id and idle() end, 900),
       id .. ": 2F stairs return to the same center")
    m, x, y = at()
    ok(m == id and x == plan.stairs.x and y == plan.stairs.y,
       ("%s: back on the 1F stairs (%s %d,%d)"):format(id, m, x, y))
    ok(Origin.get(game.save) == nil, id .. ": origin cleared after returning")
    ok(game.save.lastOutdoor.id == town, id .. ": lastOutdoor still the town")
  end

  Origin.clear(game.save)
  U.teleport(game, UnionCenters.FLOOR_2F, 13, 2, "up")
  U.hold(game, "up", 20)
  ok(waitFor(function() return ow().map.id ~= UnionCenters.FLOOR_2F and idle() end, 900),
     "2F stairs without an origin fall back to the heal point")
  local heal = ow():escapeWarpTarget()
  ok(ow().map.id == heal, ("fallback landed on %s (heal %s)"):format(ow().map.id, tostring(heal)))

  print(fails == 0 and "all claims passed" or (fails .. " claims failed"))
  love.event.quit(fails == 0 and 0 or 1)
end
