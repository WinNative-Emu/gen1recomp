local U = require("tests.drivers.util")
local X = require("tests.drivers.em_xa_util")

local d = X.new("s2_save_window", "/tmp/s2_save_window")

return function(game)
  local version = os.getenv("POKEPORT_VERSION") or "sapphire"
  local rs = version == "ruby" or version == "sapphire"
  local sess = X.newGame(d, game, 0)
  if not sess then return d.finish() end
  X.settle(game)
  U.wait(30)

  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local dexFlag = require("src.ui.game3.screens").flags(sess).IDS.SYS_POKEDEX_GET
  Flags.setFlag(Space.store, nil, dexFlag, true)

  local Chrome = require("src.ui.game3.chrome")
  local Window = require("src.ui.game3.window")
  local MenuCursor = require("src.ui.game3.rs.menu_cursor")
  local SaveMenu = require("src.ui.game3.save_menu")
  local frames, arrows, bars = {}, {}, {}
  local origStd = Chrome.stdFrame
  Chrome.stdFrame = function(l, t, w, h, ...)
    frames[#frames + 1] = { l, t, w, h }
    return origStd(l, t, w, h, ...)
  end
  local origArrow, origBar = Window.cursorPx, MenuCursor.draw
  Window.cursorPx = function(x, y, ...)
    arrows[#arrows + 1] = { x, y }
    return origArrow(x, y, ...)
  end
  MenuCursor.draw = function(x, y, w, ...)
    bars[#bars + 1] = { x, y, w }
    return origBar(x, y, w, ...)
  end

  SaveMenu.show({ session = sess, game = game })
  U.wait(20)
  frames, arrows, bars = {}, {}, {}
  X.waitFor(function() return #frames > 0 end, 2000)
  if rs then
    -- pokeruby/src/start_menu.c:699, pokeruby/src/menu.c:721, :750
    local bar = bars[#bars]
    d.check(#arrows == 0, "RS save Yes/No draws no FRLG arrow glyph")
    d.check(bar ~= nil and bar[1] == 168 and bar[2] == 72 and bar[3] == 40,
      "RS save Yes/No highlight bar at (168, 72) width 40 on YES")
  else
    d.check(#bars == 0 and #arrows > 0, "Emerald save Yes/No keeps the arrow glyph")
  end
  d.check(SaveMenu._layout == (rs and "rs" or "rse"), "save menu layout is " .. tostring(SaveMenu._layout))
  local stats = frames[1]
  d.check(stats ~= nil, "save stats window drew a std frame")
  if stats then
    d.note(string.format("stats frame interior %d,%d %dx%d", stats[1], stats[2], stats[3], stats[4]))
    d.check(stats[1] == 1 and stats[2] == 1, "stats window interior starts at tile 1,1")
    local want = rs and 12 or 14
    d.check(stats[3] == want, string.format("stats window interior is %d tiles wide (frame right tile %d)", want, want + 1))
    d.check(stats[4] == 10, "stats window with the dex is 10 tiles tall")
  end
  d.still(game, (rs and "S2_01_rs_save_stats_window.png" or "S2_03_em_save_stats_window.png"))
  Chrome.stdFrame = origStd
  Window.cursorPx, MenuCursor.draw = origArrow, origBar
  SaveMenu.cancel()
  U.wait(20)
  d.check(not SaveMenu.isOpen(), "save dialog closes on B")
  d.finish()
end
