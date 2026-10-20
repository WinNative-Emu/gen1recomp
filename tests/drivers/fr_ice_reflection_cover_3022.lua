local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/fr_ice_reflection_cover_3022"

local MAP = "FR_FOUR_ISLAND_ICEFALL_CAVE_B1F"
local PX, PY = 16, 9

local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  print((failures == 0 and "PASS" or "FAIL") .. " fr_ice_reflection_cover_3022 failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
end

local function renderField(game)
  local FieldView = require("src.core.game3.field_view")
  local canvas = love.graphics.newCanvas(240, 160)
  love.graphics.push("all")
  love.graphics.setCanvas(canvas)
  love.graphics.clear(0, 0, 0, 1)
  love.graphics.origin()
  FieldView.draw(game, 240, 160, { skipActors = true })
  love.graphics.setCanvas()
  love.graphics.pop()
  return canvas:newImageData()
end

local function midMask(cx, cy)
  local Map = require("src.core.game3.map")
  local NT = require("src.core.game3.tileset_native")
  local Collision = require("src.core.game3.collision")
  local mid, pair = Map.worldMidAt(cx, cy, Collision._mapDef)
  local ts = pair and NT._pairs[pair]
  if not (ts and ts.midImageData) then return nil end
  local slot = NT.slotFor(ts, mid)
  local sx, sy = (slot % ts.cols) * 16, math.floor(slot / ts.cols) * 16
  return function(x, y)
    local _, _, _, a = ts.midImageData:getPixel(sx + x, sy + y)
    return a > 0
  end
end

local function compareCell(game, cx, cy)
  local P = require("src.core.game3.player")
  P.hideReflection = true
  local bare = renderField(game)
  P.hideReflection = false
  local refl = renderField(game)
  local camX = math.floor(PX * 16 + 8 - 120)
  local camY = math.floor(PY * 16 + 8 - 80)
  local ox, oy = cx * 16 - camX, cy * 16 - camY
  local mask = midMask(cx, cy)
  local covered, coveredDiff, openDiff = 0, 0, 0
  if mask then
    for y = 0, 15 do
      for x = 0, 15 do
        local r1, g1, b1 = bare:getPixel(ox + x, oy + y)
        local r2, g2, b2 = refl:getPixel(ox + x, oy + y)
        local diff = math.abs(r1 - r2) + math.abs(g1 - g2) + math.abs(b1 - b2) > 0.01
        if mask(x, y) then
          covered = covered + 1
          if diff then coveredDiff = coveredDiff + 1 end
        elseif diff then
          openDiff = openDiff + 1
        end
      end
    end
  end
  return mask ~= nil, covered, coveredDiff, openDiff
end

local function settle(P)
  local still = 0
  for _ = 1, 400 do
    U.wait(1)
    if P.moving then still = 0 else still = still + 1 end
    if still >= 20 then break end
  end
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
  local FieldEffects = require("src.core.game3.field_effects")
  if not check(Runtime.getSession() ~= nil, "new game reached the field") then return finish() end

  local okLoad = pcall(Map.load, Runtime._mod, game, MAP, { x = PX, y = PY, facing = "down" })
  check(okLoad and Map.current == MAP, "Icefall Cave B1F loads")
  local s = Runtime.getSession()
  s.x, s.y, s.facing = PX, PY, "down"
  Player.reset(PX, PY, "down")
  U.wait(60)
  local Space = require("src.core.game3.scripting.space")
  if Space.vm and Space.vm:isRunning() then Space.vm:halt(true) end
  require("src.core.game3.field").unlock()
  U.wait(20)

  local function verify(tag)
    check(Player.cellX == PX and Player.cellY == PY,
      tag .. ": player on ice at " .. tostring(Player.cellX) .. "," .. tostring(Player.cellY))
    U.still(game, DIR .. "/3022_" .. tag .. "_player_above_rock.png")
    check((FieldEffects.lastFrlgReflections or 0) >= 1, tag .. ": player reflection drawn on the ice")
    local hasMask, covered, coveredDiff, openDiff = compareCell(game, PX, PY + 1)
    check(hasMask, tag .. ": middle-layer mask for the rock metatile")
    check(covered > 0, tag .. ": rock below the player has BG2 pixels (" .. covered .. ")")
    check(openDiff > 0, tag .. ": reflection shows on the ice around the rock (" .. openDiff .. " px)")
    check(coveredDiff == 0, tag .. ": rock pixels drawn over the reflection (" .. coveredDiff .. " px changed)")
  end

  verify("01_landed")

  U.hold(game, "up", 24)
  game.input.state.up = false
  settle(Player)
  check(Player.cellY ~= nil and Player.cellY < PY, "slid up the ice to y=" .. tostring(Player.cellY))
  U.hold(game, "down", 24)
  game.input.state.down = false
  settle(Player)
  verify("02_up_and_back")

  return finish()
end
