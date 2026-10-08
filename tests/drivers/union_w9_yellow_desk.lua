local U = require("tests.drivers.util")
local Pokemon = require("src.pokemon.Pokemon")
local GameVersion = require("src.core.GameVersion")
local UnionCenters = require("src.world.gen1.UnionCenters")

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
  end
  local function waitFor(cond, frames)
    for _ = 1, frames do
      if cond() then return true end
      U.wait(1)
    end
    return cond()
  end
  local function flat(t, out)
    out = out or {}
    if type(t) == "string" then out[#out + 1] = t
    elseif type(t) == "table" then for _, v in ipairs(t) do flat(v, out) end end
    return out
  end
  local function boxText()
    local top = game.stack:top()
    if not (top and top.pages) then return nil end
    return table.concat(flat(top.pages), " ")
  end
  local function closeBoxes()
    for _ = 1, 40 do
      if idle() then return true end
      U.tap(game, "a")
      U.wait(6)
    end
    return idle()
  end

  ok(GameVersion.isYellow(), "running as Yellow")
  U.wait(10)
  local f = game.save.flags
  f.EVENT_GOT_STARTER = true
  f.EVENT_BATTLED_RIVAL_IN_OAKS_LAB = true
  f.EVENT_GOT_POKEDEX = true
  game.save.pikachuInBall = false
  game.save.party = { Pokemon.new(game.data, "PIKACHU", 20) }
  game.save.lastOutdoor = { id = "VIRIDIAN_CITY", x = 23, y = 25 }

  U.teleport(game, "VIRIDIAN_POKECENTER", 4, 3, "up")
  waitFor(idle, 120)
  U.tap(game, "a")
  local seen = waitFor(function()
    local t = boxText()
    return t and t:find("CHANSEY", 1, true)
  end, 240)
  U.wait(40)
  U.still(game, SHOT_DIR .. "/w9_01_viridian_chansey_talk.png")
  ok(seen, "Viridian Chansey answers across the counter: " .. tostring(boxText()))
  ok(closeBoxes(), "Chansey box closes")

  U.teleport(game, "PEWTER_POKECENTER", 11, 5, "up")
  waitFor(idle, 120)
  ow().pikachuPewterSleepScene = true
  game.save.lastOutdoor = { id = "PEWTER_CITY", x = 13, y = 26 }
  local plan = UnionCenters.planFor(game.data, "PEWTER_POKECENTER")
  ok(plan ~= nil, "Pewter 1F has the union stairs")
  if plan then
    U.teleport(game, "PEWTER_POKECENTER", plan.stairs.x - 1, plan.stairs.y, "right")
    waitFor(idle, 120)
    ow().pikachuPewterSleepScene = true
    U.hold(game, "right", 20)
    ok(waitFor(function() return ow().map.id == UnionCenters.FLOOR_2F and idle() end, 900), "took the stairs to 2F")
  end
  ok(ow().pikachuPewterSleepScene == nil, "the map load ended the Pewter sleep scene")
  ow():cableClubReceptionist(function() end)
  local text
  waitFor(function() text = boxText() return text ~= nil end, 30)
  U.wait(90)
  U.still(game, SHOT_DIR .. "/w9_02_2f_cable_club_apply.png")
  ok(text and not text:find("content", 1, true), "2F cable club desk does not say looks content: " .. tostring(text))
  ok(game.stack:top() and game.stack:top().choice ~= nil, "2F cable club desk asks to apply")

  print(("W9 YELLOW DESK %s (%d failures)"):format(fails == 0 and "PASS" or "FAIL", fails))
  love.event.quit(fails == 0 and 0 or 1)
end
