local U = require("tests.drivers.util")
local X = require("tests.drivers.em_xa_util")

local d = X.new("s2_rs_field_yesno", "/tmp/s2_rs_field_yesno")

return function(game)
  local version = os.getenv("POKEPORT_VERSION") or "sapphire"
  local rs = version == "ruby" or version == "sapphire"
  local sess = X.newGame(d, game, 0)
  if not sess then return d.finish() end
  X.settle(game)
  U.wait(30)

  local Window = require("src.ui.game3.window")
  local MenuCursor = require("src.ui.game3.rs.menu_cursor")
  local Chrome = require("src.ui.game3.chrome")
  local Choice = require("src.ui.game3.choice")
  local Message = require("src.ui.game3.message")
  local arrows, bars, frames = {}, {}, {}
  local origArrow, origBar, origStd = Window.cursorPx, MenuCursor.draw, Chrome.stdFrame
  Window.cursorPx = function(x, y, ...)
    arrows[#arrows + 1] = { x, y }
    return origArrow(x, y, ...)
  end
  MenuCursor.draw = function(x, y, w, ...)
    bars[#bars + 1] = { x, y, w }
    return origBar(x, y, w, ...)
  end
  Chrome.stdFrame = function(l, t, w, h, ...)
    frames[#frames + 1] = { l, t, w, h }
    return origStd(l, t, w, h, ...)
  end

  local emerald = version == "emerald"
  -- pokeruby/src/scrcmd.c:1277 yesnobox 19, 7
  Message.showStay("Would you like to save\nthe game?")
  U.wait(10)
  local answered
  Choice.yesNo(function(yes) answered = yes end, { left = 19, top = 7 })
  d.check(Choice.fieldLayout() == (rs and "rs" or "frlg"), "field yes/no layout is " .. tostring(Choice.fieldLayout()))
  arrows, bars, frames = {}, {}, {}
  X.waitFor(function() return #frames > 0 end, 600)
  U.wait(10)
  local yn
  for _, f in ipairs(frames) do if f[4] == 4 then yn = f end end
  d.check(yn ~= nil, "script yes/no drew a std frame")
  if yn then
    d.note(string.format("yes/no interior %d,%d %dx%d", yn[1], yn[2], yn[3], yn[4]))
    if rs then
      -- pokeruby/src/script_menu.c:765
      d.check(yn[1] == 20 and yn[2] == 8, string.format("RS yesnobox 19,7 interior at tile %d,%d", yn[1], yn[2]))
      d.check(yn[3] == 5, "RS yesnobox interior width " .. yn[3])
    else
      -- pokeemerald/src/script_menu.c:198, pokefirered/src/script_menu.c:864
      d.check(yn[1] == 21 and yn[2] == 9, string.format("yesnobox 19,7 ignored: interior at tile %d,%d", yn[1], yn[2]))
      d.check(yn[3] == (emerald and 5 or 6), "yesnobox interior width " .. yn[3])
    end
  end
  if rs then
    local bar = bars[#bars]
    d.check(#arrows == 0, "RS script yes/no draws no FRLG arrow glyph")
    d.check(bar ~= nil and bar[1] == 160 and bar[2] == 64 and bar[3] == 40,
      "RS script yes/no highlight bar at (160, 64) width 40 on YES")
  else
    d.check(#bars == 0 and #arrows > 0, "FRLG/Emerald script yes/no keeps the arrow glyph")
  end
  d.still(game, rs and "S2_05_rs_script_yesno_bar_on_yes.png" or "S2_07_em_script_yesno.png")
  U.tap(game, "down")
  U.wait(10)
  d.check(Choice.cursor == 2, "cursor moved to NO")
  if rs then
    X.waitFor(function() return bars[#bars] and bars[#bars][2] == 80 end, 600)
    local bar = bars[#bars]
    d.check(bar ~= nil and bar[2] == 80, "RS script yes/no highlight bar at y 80 on NO")
  end
  d.still(game, rs and "S2_06_rs_script_yesno_bar_on_no.png" or "S2_08_em_script_yesno_no.png")
  U.tap(game, "a")
  U.wait(10)
  d.check(answered == false, "NO answered false")
  if Message.isOpen() then Message.close() end
  U.wait(10)

  local StartMenu = require("src.ui.game3.screens").get("start_menu", sess)
  StartMenu.show({ session = sess, game = game })
  U.wait(10)
  StartMenu._confirmExit = true
  StartMenu._confirmCursor = 2
  arrows, bars, frames = {}, {}, {}
  X.waitFor(function() return #frames > 1 end, 600)
  U.wait(10)
  local ex
  for _, f in ipairs(frames) do if f[2] == 9 and f[4] == 4 then ex = f end end
  d.check(ex ~= nil, "exit confirm drew a yes/no frame")
  if ex then d.check(ex[1] == 21 and ex[3] == (rs and 5 or 6), string.format("exit confirm interior %d,%d %dx%d", ex[1], ex[2], ex[3], ex[4])) end
  if rs then
    local bar = bars[#bars]
    d.check(bar ~= nil and bar[1] == 168 and bar[2] == 88 and bar[3] == 40,
      "RS exit confirm highlight bar at (168, 88) width 40 on NO")
    local arrowInBox = false
    for _, a in ipairs(arrows) do if a[2] >= 72 and a[2] <= 104 then arrowInBox = true end end
    d.check(not arrowInBox, "RS exit confirm draws no FRLG arrow glyph")
  else
    d.check(#bars == 0, "Emerald exit confirm draws no RS bar")
  end
  d.still(game, rs and "S2_09_rs_exit_confirm_bar_on_no.png" or "S2_10_em_exit_confirm.png")

  Window.cursorPx, MenuCursor.draw, Chrome.stdFrame = origArrow, origBar, origStd
  StartMenu.close(true)
  d.finish()
end
