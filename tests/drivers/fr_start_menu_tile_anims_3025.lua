local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/fr_start_menu_tile_anims_3025"

local MAP, PX, PY = "FR_PALLET_TOWN", 9, 15

local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  print((failures == 0 and "PASS" or "FAIL") .. " fr_start_menu_tile_anims_3025 failures=" .. failures)
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

local function animCounter(TilesetAnim)
  if TilesetAnim._rse then return TilesetAnim._rse.primary end
  return TilesetAnim.counter
end

local function diffCount(a, b)
  local n = 0
  for y = 0, 159 do
    for x = 0, 239 do
      local r1, g1, b1 = a:getPixel(x, y)
      local r2, g2, b2 = b:getPixel(x, y)
      if math.abs(r1 - r2) + math.abs(g1 - g2) + math.abs(b1 - b2) > 0.01 then n = n + 1 end
    end
  end
  return n
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
  local StartMenu = require("src.ui.game3.start_menu")
  local TilesetAnim = require("src.core.game3.tileset_anim")
  local GameVersion = require("src.core.GameVersion")
  if GameVersion.get() == "emerald" then MAP, PX, PY = "EM_PETALBURG_CITY", 10, 20 end
  if not check(Runtime.getSession() ~= nil, "new game reached the field") then return finish() end

  local okLoad = pcall(Map.load, Runtime._mod, game, MAP, { x = PX, y = PY, facing = "down" })
  check(okLoad and Map.current == MAP, MAP .. " loads")
  local s = Runtime.getSession()
  s.x, s.y, s.facing = PX, PY, "down"
  Player.reset(PX, PY, "down")
  U.wait(60)
  local Space = require("src.core.game3.scripting.space")
  if Space.vm and Space.vm:isRunning() then Space.vm:halt(true) end
  require("src.core.game3.field").unlock()
  U.wait(30)

  local c0 = animCounter(TilesetAnim)
  local f0 = renderField(game)
  U.wait(40)
  local f1 = renderField(game)
  check(animCounter(TilesetAnim) ~= c0, "tile animation runs in the field")
  check(diffCount(f0, f1) > 0, "water tiles change in the field")

  U.tap(game, "start")
  U.wait(20)
  if not check(StartMenu.isOpen(), "start menu open") then return finish() end
  U.still(game, DIR .. "/3025_01_menu_open_a.png")
  local m0 = animCounter(TilesetAnim)
  local w0 = renderField(game)
  U.wait(40)
  local w1 = renderField(game)
  U.still(game, DIR .. "/3025_02_menu_open_b.png")
  check(StartMenu.isOpen(), "start menu still open")
  check(animCounter(TilesetAnim) ~= m0,
    "tile animation counter advances under the start menu (" .. tostring(m0) .. " -> " .. tostring(animCounter(TilesetAnim)) .. ")")
  local d = diffCount(w0, w1)
  check(d > 0, "water tiles change with the start menu open (" .. d .. " px)")

  U.tap(game, "b")
  U.wait(20)
  check(not StartMenu.isOpen(), "start menu closed")
  return finish()
end
