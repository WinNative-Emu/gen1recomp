local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/fr_ember_spa_hot_springs_3024"

local MAP = "FR_ONE_ISLAND_KINDLE_ROAD_EMBER_SPA"
local PX, PY = 13, 11

local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  print((failures == 0 and "PASS" or "FAIL") .. " fr_ember_spa_hot_springs_3024 failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  if not check(game.boot ~= nil, "boot reached") then return finish() end
  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(180)

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Objects = require("src.core.game3.objects")
  local Collision = require("src.core.game3.collision")
  local FieldEffects = require("src.core.game3.field_effects")
  if not check(Runtime.getSession() ~= nil, "new game reached the field") then return finish() end

  local okLoad = pcall(Map.load, Runtime._mod, game, MAP, { x = PX, y = PY, facing = "up" })
  check(okLoad and Map.current == MAP, "Ember Spa loads")
  local s = Runtime.getSession()
  s.x, s.y, s.facing = PX, PY, "up"
  Player.reset(PX, PY, "up")
  U.wait(60)
  local Space = require("src.core.game3.scripting.space")
  if Space.vm and Space.vm:isRunning() then Space.vm:halt(true) end
  require("src.core.game3.field").unlock()
  U.wait(30)

  local inSpring = {}
  for _, eo in ipairs(Objects.forDraw()) do
    if eo.cellX and Collision.isHotSprings(Collision.behavior(eo.cellX, eo.cellY))
        and not eo.moving then
      inSpring[eo] = true
    end
  end
  local springCount = 0
  for _ in pairs(inSpring) do springCount = springCount + 1 end
  check(springCount >= 2, "NPCs standing in the hot spring: " .. springCount)

  local actors = {}
  FieldEffects.collectActors(actors, 0, 0)
  local covered = {}
  local coveredCount = 0
  for _, a in ipairs(actors) do
    if a.kind == "field_effect_hot_springs" and a.disguiseObject and not covered[a.disguiseObject] then
      covered[a.disguiseObject] = true
      coveredCount = coveredCount + 1
    end
  end
  local allCovered = true
  for eo in pairs(inSpring) do
    if not covered[eo] then allCovered = false end
  end
  check(springCount > 0 and allCovered,
    "every NPC in the spring gets the hot springs water sprite (" .. coveredCount .. "/" .. springCount .. ")")
  local dry = 0
  for eo in pairs(covered) do
    if not Collision.isHotSprings(Collision.behavior(eo.cellX, eo.cellY)) then dry = dry + 1 end
  end
  check(dry == 0, "no water sprite on NPCs outside the spring")

  local playerSpring = Collision.isHotSprings(Collision.behavior(Player.cellX, Player.cellY))
  local playerFx = false
  for _, anim in ipairs(FieldEffects._anims or {}) do
    if anim.kind == "hot_springs" then playerFx = true end
  end
  check(not playerSpring or playerFx, "player in the spring keeps the water sprite")

  U.still(game, DIR .. "/3024_01_ember_spa_npcs_in_water.png")
  return finish()
end
