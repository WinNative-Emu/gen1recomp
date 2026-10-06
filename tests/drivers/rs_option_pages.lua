local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/rs_option_pages"
local PHASE = os.getenv("RS_OPTION_PHASE") or "1"

local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  print((failures == 0 and "PASS" or "FAIL") .. " rs_option_pages phase=" .. PHASE .. " failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
end

local function settle(game)
  local Warp = require("src.core.game3.warp")
  local Message = require("src.ui.game3.message")
  for _ = 1, 600 do
    local busy = Warp.isBusy() or (Message.isOpen and Message.isOpen())
    if not busy then break end
    if Message.isOpen and Message.isOpen() then U.tap(game, "b") end
    U.wait(1)
  end
end

local function enterWorld(game)
  local MapIds = require("src.core.game3.map_ids")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Runtime = require("src.core.game3.runtime")
  pcall(function() game:_handleBootAction({ action = "new_game", name = "RUBY", gender = 0 }) end)
  U.wait(60)
  settle(game)
  pcall(function()
    Map.load(nil, game, MapIds.forConst("MAP_LITTLEROOT_TOWN"), { x = 10, y = 10, facing = "down" })
  end)
  local s = Runtime.getSession()
  if s then s.x, s.y, s.facing = 10, 10, "down" end
  Player.cellX, Player.cellY, Player.px, Player.py = 10, 10, 160, 160
  Player.targetX, Player.targetY, Player.facing = 10, 10, "down"
  U.wait(60)
  settle(game)
  return s
end

local function moveTo(game, page, target)
  for _ = 1, 64 do
    if page.index == target then return true end
    U.tap(game, page.index < target and "down" or "up")
    U.wait(1)
  end
  return page.index == target
end

local function shot(game, name)
  U.wait(3)
  U.shot(game, DIR .. "/" .. name .. ".png")
  U.wait(2)
end

local function phase1(game, ShaderFX, ShaderFXMenu)
  local Menu = require("src.ui.game3.rs.option_menu")
  local Screens = require("src.ui.game3.screens")
  local session = enterWorld(game)
  local Option = Screens.get("option", session)
  check(Option == Menu, "ruby resolves OPTION to the RS menu")
  Option.show({ session = session, game = game })
  for _ = 1, 120 do
    if Menu._state == "input" then break end
    U.wait(1)
  end
  shot(game, "01-native-first-page")
  local top = Menu._pages[1]
  check(top.rows[1].id == "group.speed", "page 1 opens on Emerald's SPEED group")

  U.tap(game, "select")
  U.wait(4)
  check(not ShaderFXMenu.isOpen(), "SELECT no longer opens a hidden SHADER FX menu")

  moveTo(game, top, 8)
  shot(game, "02-scrolled-port-rows")
  moveTo(game, top, #top.rows + 1)
  shot(game, "03-port-rows-bottom")

  local groups = {}
  for i, row in ipairs(top.rows) do
    if row.group then groups[#groups + 1] = { i = i, id = row.id } end
  end
  check(#groups >= 4, "RS OPTION shows " .. #groups .. " port pages")
  local n = 3
  for _, g in ipairs(groups) do
    moveTo(game, top, g.i)
    U.tap(game, "a")
    U.wait(4)
    local page = Menu._pages[#Menu._pages]
    check(#Menu._pages == 2, g.id .. " opens a page")
    n = n + 1
    shot(game, ("%02d-page-%s"):format(n, g.id:gsub("^group%.", "")))
    if g.id == "group.graphics" then
      local si
      for i, r in ipairs(page.rows) do if r.id == "shaderfx" then si = i end end
      if check(si ~= nil, "GRAPHICS lists SHADER FX") then
        moveTo(game, page, si)
        shot(game, "20-graphics-shaderfx-row")
        U.tap(game, "a")
        U.wait(6)
        check(ShaderFXMenu.isOpen(), "A on the visible SHADER FX row opens the picker")
        shot(game, "21-shaderfx-picker")
        ShaderFXMenu.handleInput({ wasPressed = function(_, k) return k == "down" end })
        U.wait(2)
        ShaderFXMenu.handleInput({ wasPressed = function(_, k) return k == "a" end })
        for _ = 1, 600 do
          if ShaderFX.activeEntry("main") then break end
          U.wait(1)
        end
        local e = ShaderFX.activeEntry("main")
        check(e ~= nil, "picking a preset activates SHADER FX")
        check(e and game.options.shaderfx == e.name, "the preset persists as options.shaderfx")
        print("[driver] chose " .. tostring(e and e.name))
        for _ = 1, 4 do
          if not ShaderFXMenu.isOpen() then break end
          ShaderFXMenu.handleInput({ wasPressed = function(_, k) return k == "b" end })
          U.wait(2)
        end
        shot(game, "22-graphics-shader-applied")
      end
    end
    U.tap(game, "b")
    U.wait(4)
    check(#Menu._pages == 1, g.id .. " B returns to the native list")
  end
  U.tap(game, "b")
  for _ = 1, 120 do
    if not Menu.isOpen() then break end
    U.wait(1)
  end
  check(not Menu.isOpen(), "B saves and closes")
  U.wait(10)
  shot(game, "23-overworld-shader-applied")
  local f = love.filesystem.read("options.lua") or ""
  check(f:find("shaderfx", 1, true) ~= nil, "options.lua on disk carries the shader choice")
end

local function phase2(game, ShaderFX)
  local e = ShaderFX.activeEntry("main")
  check(e ~= nil and e.name == game.options.shaderfx, "SHADER FX restored after restart: " .. tostring(e and e.name))
  enterWorld(game)
  shot(game, "30-after-restart")
  ShaderFX.deactivate()
  game.options.shaderfx, game.options.shaderfxSecondary = nil, nil
  game:writeOptions()
  U.wait(4)
end

return function(game)
  local ShaderFX = require("src.render.ShaderFX")
  local ShaderFXMenu = require("src.ui.game3.shaderfx_menu")
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  if not check(game.boot ~= nil, "boot reached") then return finish() end
  check(#ShaderFX.list() > 0, "presets on disk")
  local ok, err = xpcall(function()
    if PHASE == "2" then phase2(game, ShaderFX) else phase1(game, ShaderFX, ShaderFXMenu) end
  end, debug.traceback)
  if not ok then check(false, "driver error: " .. tostring(err)) end
  finish()
end
