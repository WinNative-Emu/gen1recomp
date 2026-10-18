local U = require("tests.drivers.util")

local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_quit_prompt_2992"

local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  print((failures == 0 and "PASS" or "FAIL") .. " game3_quit_prompt_2992 failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
  U.wait(10)
end

local function body(game)
  local Runtime = require("src.core.game3.runtime")
  local StartMenu = require("src.ui.game3.start_menu")
  local Options = require("src.core.game3.options")
  local session = Runtime.getSession()
  local version = session and session.version or "game3"
  if not check(session ~= nil, "session up (" .. version .. ")") then return end
  Options.ensure(session).textSpeed = 1
  U.wait(60)

  for _ = 1, 40 do
    if StartMenu.isOpen() then break end
    U.tap(game, "start")
    U.wait(8)
  end
  if not check(StartMenu.isOpen(), "start menu open") then return end
  for _ = 1, 20 do
    local e = StartMenu.ENTRIES[StartMenu.cursor]
    if e and e.id == "exit" then break end
    U.tap(game, "down")
    U.wait(4)
  end
  local e = StartMenu.ENTRIES[StartMenu.cursor]
  if not check(e and e.id == "exit", "cursor on EXIT") then return end
  U.tap(game, "a")
  U.wait(6)

  check(StartMenu._confirmExit == true, "EXIT opened the confirmation")
  local p = StartMenu._prompt
  check(p ~= nil and p.revealed > 0 and p.revealed < p.total,
    ("a few frames in only part of the question is printed (%s/%s)")
      :format(tostring(p and p.revealed), tostring(p and p.total)))
  check(StartMenu.promptTyping(), "the YES/NO box waits for the text")
  check(U.still(game, DIR .. "/2992_" .. version .. "_01_exit_midprint.png"), "mid-print shot written")

  U.tap(game, "down")
  U.wait(2)
  check(StartMenu._confirmCursor == 2, "down while it prints leaves NO selected")

  for _ = 1, 400 do
    if not StartMenu.promptTyping() then break end
    U.wait(1)
  end
  check(not StartMenu.promptTyping() and p.revealed == p.total, "the question finishes printing")
  check(U.still(game, DIR .. "/2992_" .. version .. "_02_exit_printed.png"), "printed shot written")

  U.tap(game, "b")
  U.wait(4)
  check(StartMenu.isOpen() and not StartMenu._confirmExit, "B backs out to the menu")
  U.tap(game, "b")
  U.wait(10)
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  check(game.boot ~= nil, "boot reached")
  local ok, err = xpcall(function()
    game:_handleBootAction({ action = "new_game", name = "BRENDAN", gender = 0 })
  end, debug.traceback)
  if not ok then check(false, "new_game: " .. tostring(err)) return finish() end
  U.wait(60)
  ok, err = xpcall(function() body(game) end, debug.traceback)
  if not ok then check(false, "body: " .. tostring(err)) end
  return finish()
end
