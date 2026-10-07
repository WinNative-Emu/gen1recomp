local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_title_controls_2714"

local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  print((failures == 0 and "PASS" or "FAIL") .. " em_title_controls_2714 failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
  U.wait(10)
end

local function try(label, fn)
  local ok, err = xpcall(fn, debug.traceback)
  if not ok then
    print("[driver] " .. label .. " error: " .. tostring(err))
    failures = failures + 1
  end
  return ok
end

local function topId()
  local top = require("src.ui.game3.stack").top()
  return top and top.id
end

local function keyTap(game, key)
  game:keypressed(key)
  U.wait(2)
  game:keyreleased(key)
  U.wait(4)
end

local function waitFor(pred, n)
  for _ = 1, n or 300 do
    if pred() then return true end
    U.wait(1)
  end
  return pred()
end

local function body(game)
  local Boot = require("src.ui.game3.boot")
  local BootModules = require("src.ui.game3.boot_modules")
  local Screens = require("src.ui.game3.screens")
  local Stack = require("src.ui.game3.stack")
  local Controls = require("src.ui.game3.controls_menu")
  local version = require("src.core.GameVersion").get()

  BootModules.startMenu(Boot, game.boot)
  local menu = game.boot.custom.menu
  check(waitFor(function() return menu.state == "input" end, 400), "title MAIN MENU accepts input")
  for _ = 1, 10 do
    if menu.items[menu.cursor] == "OPTION" then break end
    U.tap(game, "down")
    U.wait(6)
  end
  check(menu.items[menu.cursor] == "OPTION", "cursor on OPTION")
  U.tap(game, "a")
  check(waitFor(function() return menu.state == "options" and topId() == "option" end, 200), "title OPTION open")
  U.wait(40)

  local Opt = Screens.get("option")
  local function curPage()
    if Opt._st then return Opt._st.pages and Opt._st.pages[#Opt._st.pages] end
    return Opt._pages and Opt._pages[#Opt._pages]
  end
  local function moveToRow(id)
    local p = curPage()
    local target
    for i, r in ipairs(p and p.rows or {}) do if r.id == id then target = i end end
    if not target then return false end
    for _ = 1, 40 do
      if p.index == target then break end
      U.tap(game, p.index < target and "down" or "up")
      U.wait(6)
    end
    return p.index == target
  end

  check(moveToRow("controls"), "cursor on CONTROLS")
  U.tap(game, "a")
  U.wait(20)
  check(topId() == "controls", "A on CONTROLS opens the controls screen at the title")
  U.still(game, DIR .. "/2714_01_" .. version .. "_title_controls_screen.png")

  local bm = Controls._bm
  local before = bm and bm.index or 0
  U.tap(game, "down")
  U.wait(6)
  check(bm and bm.index == before + 1, "DOWN moves the controls cursor at the title (" .. before .. "->" .. tostring(bm and bm.index) .. ")")
  local function rowOf(id)
    for i, it in ipairs(bm.items) do if it.button.id == id then return i end end
  end
  for _ = 1, 20 do
    if bm.index == rowOf("a") then break end
    U.tap(game, bm.index < rowOf("a") and "down" or "up")
    U.wait(6)
  end
  U.tap(game, "a")
  U.wait(6)
  check(bm.capture ~= nil, "A row capture armed at the title")
  keyTap(game, "k")
  check(game.options.bindings and game.options.bindings.a and game.options.bindings.a.key == "k",
    "A rebound to K from the title")

  U.tap(game, "b")
  U.wait(20)
  check(topId() == "option", "B returns to the title OPTION")
  check(not Controls.open, "controls closed after B")
  U.still(game, DIR .. "/2714_02_" .. version .. "_title_back_on_option.png")

  game.options.bindings = nil
  game:writeOptions()
  game.input:applyBindings(nil)

  check(moveToRow("mods"), "cursor on MODS")
  U.tap(game, "a")
  U.wait(20)
  check(topId() == "mod_manager", "A on MODS opens the mod manager at the title")
  U.tap(game, "b")
  U.wait(20)
  check(topId() == "option", "B from MODS returns to the title OPTION")

  check(moveToRow("controls"), "cursor back on CONTROLS")
  U.tap(game, "a")
  U.wait(20)
  check(topId() == "controls", "CONTROLS reopens")
  Opt.close()
  check(not Stack.has("controls") and not Controls.open, "closing OPTION closes a CONTROLS child")
  check(waitFor(function() return menu.state ~= "options" end, 200), "title leaves the options state")
  U.wait(60)

  game:_handleBootAction({ action = "new_game", name = "BRENDAN", gender = 0 })
  U.wait(120)
  check(not Stack.has("controls") and not Stack.has("mod_manager"), "no stale controls layer in the field")
  check(topId() ~= "controls", "field Stack top is not controls (" .. tostring(topId()) .. ")")
  U.still(game, DIR .. "/2714_03_" .. version .. "_field_clean.png")
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  check(game.boot ~= nil and game.boot.custom ~= nil, "boot reached")
  if game.boot and game.boot.custom then
    try("body", function() body(game) end)
  end
  return finish()
end
