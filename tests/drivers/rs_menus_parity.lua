local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/rs_menus_parity"

local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  print((failures == 0 and "PASS" or "FAIL") .. " rs_menus_parity failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
  U.wait(10)
end

local function shot(game, name)
  U.wait(3)
  U.shot(game, DIR .. "/" .. name .. ".png")
  U.wait(2)
end

local function until_(n, fn)
  for _ = 1, n do
    if fn() then return true end
    U.wait(1)
  end
  return fn()
end

local function demoMenus(game)
  local Boot = require("src.ui.game3.boot")
  local Menu = require("src.ui.game3.rs.main_menu")
  local Pal = require("src.core.game3.pal_fade")
  local origDraw = Boot.draw
  local info = { name = "BRENDAN", gender = 0, hours = 12, minutes = 34, badges = 3, dexCount = 27,
    mysteryEvents = true, frameType = 0 }
  local cases = {
    { "00-main-no-save", { hasContinue = false } },
    { "01-main-saved", { hasContinue = true, continueInfo = info, menuType = Menu.TYPE.HAS_SAVED_GAME } },
    { "02-main-mystery-events", { hasContinue = true, continueInfo = info, menuType = Menu.TYPE.HAS_MYSTERY_EVENT } },
  }
  for _, c in ipairs(cases) do
    local demo = Menu.new(c[2])
    demo.pal, demo.state = Pal.new(), "input"
    Boot.draw = function() demo:draw() end
    check(demo.items[#demo.items] == "EXIT", c[1] .. " ends with EXIT")
    for _ = 1, #demo.items - 1 do
      demo:frame({ new = { down = true } })
      demo.state = "input"
    end
    shot(game, c[1] .. "-exit")
    local w = Menu.windowFor(demo.menuType, demo.cursor)
    check((w.top + w.height + 1) * 8 - demo.scroll <= 160, c[1] .. " EXIT window on screen")
  end
  Boot.draw = origDraw
end

local function realMainMenuExit(game)
  local Boot = require("src.ui.game3.boot")
  local BootModules = require("src.ui.game3.boot_modules")
  BootModules.startMenu(Boot, game.boot)
  local menu = game.boot.custom.menu
  check(until_(300, function() return menu.state == "input" end), "real RS main menu reaches input")
  for _ = 1, #menu.items do U.tap(game, "down"); U.wait(2) end
  check(menu.items[menu.cursor] == "EXIT", "cursor on EXIT")
  shot(game, "03-real-main-menu-exit")
  local exited = false
  game.returnToLauncher = function() exited = true end
  U.tap(game, "a")
  check(until_(200, function() return exited end), "A on EXIT returns to the launcher")
  game.returnToLauncher = nil
end

local function enterWorld(game)
  local MapIds = require("src.core.game3.map_ids")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Runtime = require("src.core.game3.runtime")
  local Warp = require("src.core.game3.warp")
  local Message = require("src.ui.game3.message")
  local function settle()
    until_(600, function()
      if Message.isOpen and Message.isOpen() then U.tap(game, "b") end
      return not (Warp.isBusy() or (Message.isOpen and Message.isOpen()))
    end)
  end
  pcall(function() game:_handleBootAction({ action = "new_game", name = "RUBY", gender = 0 }) end)
  U.wait(60)
  settle()
  pcall(function()
    Map.load(nil, game, MapIds.forConst("MAP_LITTLEROOT_TOWN"), { x = 10, y = 10, facing = "down" })
  end)
  local s = Runtime.getSession()
  if s then s.x, s.y, s.facing = 10, 10, "down" end
  Player.cellX, Player.cellY, Player.px, Player.py = 10, 10, 160, 160
  Player.targetX, Player.targetY, Player.facing = 10, 10, "down"
  U.wait(60)
  settle()
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

local function options(game, session)
  local Menu = require("src.ui.game3.rs.option_menu")
  local Option = require("src.ui.game3.screens").get("option", session)
  check(Option == Menu, "ruby OPTION is the RS menu")
  Option.show({ session = session, game = game })
  until_(120, function() return Menu._state == "input" end)
  local top = Menu._pages[1]
  check(top.rows[1].id == "group.speed", "top page starts with SPEED like Emerald")
  shot(game, "10-option-top")
  moveTo(game, top, #top.rows + 1)
  shot(game, "11-option-top-cancel")
  for _, id in ipairs({ "group.battle", "group.graphics", "group.speed", "group.audio" }) do
    local gi
    for i, r in ipairs(top.rows) do if r.id == id then gi = i end end
    if check(gi ~= nil, id .. " on the top page") then
      moveTo(game, top, gi)
      U.tap(game, "a")
      U.wait(4)
      local page = Menu._pages[#Menu._pages]
      local natives = 0
      for _, r in ipairs(page.rows) do if r.native then natives = natives + 1 end end
      check(#Menu._pages == 2 and natives > 0, id .. " page carries native cart rows")
      shot(game, "12-option-" .. id:gsub("^group%.", ""))
      U.tap(game, "b")
      U.wait(4)
    end
  end
  U.tap(game, "b")
  check(until_(120, function() return not Menu.isOpen() end), "B saves and closes OPTION")
end

local function startMenuExit(game, session)
  local StartMenu = require("src.ui.game3.start_menu")
  local Boot = require("src.ui.game3.boot")
  U.wait(10)
  StartMenu.show({ session = session, game = game })
  U.wait(4)
  for i, e in ipairs(StartMenu.ENTRIES) do if e.id == "exit" then StartMenu.cursor = i end end
  shot(game, "20-start-menu-exit")
  U.tap(game, "a")
  U.wait(4)
  check(StartMenu._confirmExit == true, "START EXIT asks to return to the main menu")
  shot(game, "21-start-menu-exit-confirm")
  U.tap(game, "up")
  U.wait(2)
  U.tap(game, "a")
  check(until_(300, function() return game.phase == "boot" and game.boot and game.boot.phase == Boot.PHASE.TITLE end),
    "YES returns to the title screen")
  U.wait(60)
  shot(game, "22-after-exit-title")
end

return function(game)
  until_(900, function() return game.phase == "boot" and game.boot end)
  if not check(game.boot ~= nil, "boot reached") then return finish() end
  local ok, err = xpcall(function()
    demoMenus(game)
    realMainMenuExit(game)
    local session = enterWorld(game)
    options(game, session)
    startMenuExit(game, session)
  end, debug.traceback)
  if not ok then check(false, "driver error: " .. tostring(err)) end
  finish()
end
