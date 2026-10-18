local U = require("tests.drivers.util")
local Typer = require("src.ui.gen2.Typer")

local SHOT_DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/pokeport-shots"

return function(game)
  local fails = 0
  local function ok(cond, line)
    if not cond then fails = fails + 1 end
    print((cond and "PASS " or "FAIL ") .. line)
    return cond
  end
  local function finish()
    print((fails == 0 and "PASS" or "FAIL") .. " gen2_quit_prompt_2992 failures=" .. fails)
    love.event.quit(fails == 0 and 0 or 1)
    U.wait(10)
  end

  U.wait(60)
  local world, save = game.world, game.save
  if not ok(world and world.map and save, "the overworld booted") then return finish() end
  local version = save.version or os.getenv("POKEPORT_VERSION") or "gen2"
  save.options = save.options or {}
  save.options.textSpeed = "MID"

  U.tap(game, "start")
  U.wait(20)
  local menu = game.stack and game.stack:top()
  if not ok(menu and menu.items and menu.list, "the START menu opened") then return finish() end
  local quitIndex
  for index, item in ipairs(menu.items) do
    if item.value == "quit" then quitIndex = index end
  end
  if not ok(quitIndex ~= nil, "the QUIT row is on the menu") then return finish() end
  menu.list.index = quitIndex
  U.wait(2)
  U.tap(game, "a")
  U.wait(6)

  ok(menu.phase == "confirm", "QUIT opened the confirmation")
  local typer = menu.typer
  ok(typer ~= nil and typer.shown > 0 and typer.shown < typer.total,
    ("a few frames in only part of the question is printed (%s/%s)")
      :format(tostring(typer and typer.shown), tostring(typer and typer.total)))
  ok(menu:promptTyping(), "the YES/NO box waits for the text")
  local partial = table.concat(Typer.text(menu, menu.promptLines or {}), "|")
  print("partial text: " .. partial)
  ok(U.still(game, SHOT_DIR .. "/2992_" .. version .. "_01_quit_midprint.png"), "mid-print shot written")

  for _ = 1, 400 do
    if not menu:promptTyping() then break end
    U.wait(1)
  end
  ok(not menu:promptTyping() and typer.shown == typer.total, "the question finishes printing")
  ok(U.still(game, SHOT_DIR .. "/2992_" .. version .. "_02_quit_printed.png"), "printed shot written")
  ok(menu.confirmChoice == 2, "NO is still the default")

  U.tap(game, "b")
  U.wait(4)
  ok(menu.phase == nil, "B backs out of the confirmation")
  U.tap(game, "start")
  U.wait(10)
  return finish()
end
