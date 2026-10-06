return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local PartyMenu = require("src.ui.PartyMenu")
  local DIR = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR") or "/tmp/shots"

  local fails = 0
  local function check(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then fails = fails + 1 end
    return ok
  end
  local function finish()
    love.event.quit(fails == 0 and 0 or 1)
    while true do coroutine.yield() end
  end

  if not U.newGame(game) then
    check(false, "2682 reached the overworld")
    finish()
  end
  game.save.options = game.save.options or {}
  game.save.options.textSpeed = 5
  game.save.inventory.SOULBADGE = true

  local surfer = Pokemon.new(game.data, "SQUIRTLE", 30)
  surfer.moves = { { id = "SURF", pp = 15 } }
  local other = Pokemon.new(game.data, "PIDGEY", 30)
  game.save.party = { surfer, other }
  game.partyMenuSavedIndex = 1

  U.teleport(game, "PALLET_TOWN", 4, 13, "down")
  local ow = game.overworld
  ow.player.surfing = false
  check(ow:useSurfFieldMove() == "ok", "2682 (4,13) faces surfable water")

  U.tap(game, "start")
  U.wait(12)
  local menu = game.stack:top()
  local row
  for i, it in ipairs(menu and menu.items or {}) do
    if tostring(it.label):upper():find("MON", 1, true) then row = i break end
  end
  if not check(row ~= nil, "2682 START menu lists POKEMON") then finish() end
  for _ = 2, row do U.tap(game, "down"); U.wait(2) end
  U.tap(game, "a")
  U.wait(12)
  local pm = game.stack:top()
  if not check(getmetatable(pm) == PartyMenu, "2682 party menu open") then finish() end

  local b0 = pm.blink
  U.wait(20)
  check(pm.blink ~= b0, "2682 cursor icon animates while the list takes input")

  U.tap(game, "a")
  U.wait(8)
  if not check(pm.submenu, "2682 A opens the field-move submenu") then finish() end
  local frozen = pm.blink
  U.wait(40)
  check(pm.blink == frozen, "2682 icon frozen behind the submenu")
  U.still(game, DIR .. "/2682_01_submenu_icon_frozen.png")
  U.wait(10)
  check(pm.blink == frozen, "2682 icon still frozen ten frames later")
  U.still(game, DIR .. "/2682_02_submenu_icon_frozen_later.png")

  U.tap(game, "b")
  U.wait(1)
  check(not pm.submenu and pm.blink <= 1, "2682 B back to the list restarts the icon")
  U.wait(9)
  U.tap(game, "down")
  check(pm.index == 2 and pm.blink <= 1, "2682 cursor move restarts the icon on its rest frame")
  U.wait(4)
  U.tap(game, "up")
  U.wait(4)
  check(pm.index == 1, "2682 cursor back on the surfer")

  U.tap(game, "a")
  U.wait(8)
  local sub
  for i, it in ipairs(pm.subItems or {}) do
    if it.action == "surf" then sub = i break end
  end
  if not check(sub ~= nil, "2682 SURF listed in the submenu") then finish() end
  for _ = 2, sub do U.tap(game, "down"); U.wait(2) end
  U.tap(game, "a")
  U.wait(6)
  local top = game.stack:top()
  check(top ~= pm and top and top.pages ~= nil, "2682 got-on text is up")
  check(game.stack.states[game.stack:visibleBase()] == pm,
        "2682 party list is the backdrop of the got-on text")
  check(not pm.submenu and pm.chosenHollow == true,
        "2682 party cursor stays hollow under the got-on text")
  local textBlink = pm.blink
  local printed = false
  for _ = 1, 600 do
    if top.done or top.waiting then printed = true break end
    U.wait(1)
  end
  check(printed, "2682 got-on text finished printing")
  U.wait(4)
  check(pm.blink == textBlink, "2682 icon frozen under the got-on text")
  U.still(game, DIR .. "/2682_03_surf_text_hollow_cursor.png")

  for _ = 1, 400 do
    local t = game.stack:top()
    if not (t and t.pages) then break end
    U.tap(game, "a")
    U.wait(3)
  end
  U.wait(60)
  check(ow.player.surfing == true, "2682 SURF mounted after the text")

  finish()
end
