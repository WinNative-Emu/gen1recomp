-- engine/movie/oak_speech/oak_speech2.asm:20
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local NamingScreen = require("src.ui.NamingScreen")
  local DIR = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR")
    or "/tmp/shots"
  local failed = false

  local function check(label, ok)
    if ok then print("PASS " .. label) else print("FAIL " .. label) failed = true end
    return ok
  end

  local function finish()
    print(failed and "FAIL oak_naming_empty_start_bug2687"
                 or "PASS oak_naming_empty_start_bug2687")
    love.event.quit(failed and 1 or 0)
    while true do coroutine.yield() end
  end

  local function namingScreen()
    local states = game.stack.states or {}
    for i = #states, 1, -1 do
      if getmetatable(states[i]) == NamingScreen then return states[i] end
    end
    return nil
  end

  local function topIsGrid(ns)
    return ns ~= nil and game.stack:top() == ns and not ns.choosing
  end

  U.wait(5)
  U.tap(game, "start")
  U.wait(10)
  local title = game.stack:top()
  for _ = 1, 60 do
    U.tap(game, "a")
    U.wait(5)
    if game.stack:top() ~= title then break end
  end
  U.tap(game, "a")
  U.wait(10)

  local ns
  for _ = 1, 3000 do
    ns = namingScreen()
    if ns and ns.choosing then break end
    if game.overworld and game.stack:top() == game.overworld then break end
    U.tap(game, "a")
    U.wait(2)
  end
  if not check("reached_player_name_menu", ns ~= nil and ns.choosing) then finish() end
  U.wait(30)
  U.shot(game, DIR .. "/2687_01_name_menu.png")

  U.tap(game, "a")
  U.wait(30)
  check("new_name_opens_empty_grid", topIsGrid(ns) and #ns.glyphs == 0)
  ns.row, ns.col = 3, 4
  U.shot(game, DIR .. "/2687_02_empty_grid_before_start.png")

  U.tap(game, "start")
  check("empty_start_keeps_grid_up", game.stack:top() == ns)
  check("empty_start_whites_out", (ns.whiteout or 0) > 0)
  U.still(game, DIR .. "/2687_03_white_reentry.png")

  U.wait(60)
  check("whiteout_ends", (ns.whiteout or 0) == 0)
  check("grid_back_with_cursor_on_A", topIsGrid(ns) and ns.row == 1 and ns.col == 1)
  U.shot(game, DIR .. "/2687_04_grid_back_cursor_on_A.png")

  U.tap(game, "start")
  U.wait(60)
  check("second_empty_start_still_on_grid", topIsGrid(ns) and #ns.glyphs == 0)

  ns.row, ns.col = 1, 1
  U.tap(game, "a")
  U.wait(5)
  check("typed_letter_A", #ns.glyphs == 1 and ns.glyphs[1] == "A")
  U.shot(game, DIR .. "/2687_05_typed_A.png")
  U.tap(game, "start")
  U.wait(30)
  check("typed_name_confirms", namingScreen() == nil)
  check("player_named_A", game.save.player.name == "A")
  U.shot(game, DIR .. "/2687_06_your_name_is_A.png")

  finish()
end
