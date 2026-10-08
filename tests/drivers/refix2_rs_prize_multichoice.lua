local U = require("tests.drivers.util")
local X = require("tests.drivers.em_xa_util")

local d = X.new("refix2_rs_prize_multichoice", "/tmp/refix2_rs_prize_multichoice")

return function(game)
  local version = os.getenv("POKEPORT_VERSION") or "sapphire"
  local rs = version == "ruby" or version == "sapphire"
  local sess = X.newGame(d, game, 0)
  if not sess then return d.finish() end
  X.settle(game)
  U.wait(30)

  local C = require("src.core.game3.constants").of(version)
  local Bag = require("src.core.game3.bag")
  local MapIds = require("src.core.game3.map_ids")
  local Window = require("src.ui.game3.window")
  local MenuCursor = require("src.ui.game3.rs.menu_cursor")
  local Chrome = require("src.ui.game3.chrome")
  local Choice = require("src.ui.game3.choice")
  local FrlgFont = require("src.ui.game3.frlg_font")
  Bag.add(sess.bag, C:require("items", "ITEM_COIN_CASE"), 1)
  Bag.Coins.set(sess, 120)

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

  -- pokeruby/data/maps/MauvilleCity_GameCorner/scripts.inc:121 multichoice 12, 0, 48, 0
  local corner = MapIds.forConst("MAP_MAUVILLE_CITY_GAME_CORNER")
  if not d.check(X.goTo(d, game, corner, 14, 3, "up"), "Mauville Game Corner loads") then return d.finish() end
  U.wait(20)
  U.tap(game, "a")
  local opened = X.waitFor(function()
    if Choice.isOpen() and Choice.kind == "multi" then return true end
    local Message = require("src.ui.game3.message")
    if Message.isOpen and Message.isOpen() and U.frame() % 20 == 0 then U.tap(game, "a") end
    return false
  end, 3000)
  if not d.check(opened, "prize clerk script opens multichoice 48") then return d.finish() end
  d.check(Choice.left == 13 and Choice.top == 1, string.format("multichoice 12,0 interior at %s,%s", tostring(Choice.left), tostring(Choice.top)))
  local L, Tp = Choice.left, Choice.top
  arrows, bars, frames = {}, {}, {}
  local n = #(Choice.options or {})
  X.waitFor(function()
    for _, f in ipairs(frames) do if f[4] == 2 * n then return true end end
    return false
  end, 600)
  U.wait(10)

  local w = 0
  for _, lab in ipairs(Choice.options or {}) do
    local tiles = math.floor((FrlgFont.measure(tostring(lab)) + 7) / 8)
    if tiles > w then w = tiles end
  end
  local tx = L + w > 29 and 29 - w or L
  d.note(string.format("%d options, widest %d tiles, frame left %d", n, w, tx))
  local fr
  for _, f in ipairs(frames) do
    d.note(string.format("frame %d,%d %dx%d", f[1], f[2], f[3], f[4]))
    if f[4] == 2 * n then fr = f end
  end
  d.check(fr ~= nil, "multichoice drew a std frame 2*count tall")
  if fr then
    d.check(fr[1] == tx and fr[2] == Tp and fr[3] == w,
      string.format("multichoice frame interior %d,%d %dx%d (pret left+1, top+1, widest label, 2*count)", fr[1], fr[2], fr[3], fr[4]))
  end
  if rs then
    local bar = bars[#bars]
    d.check(#arrows == 0, "RS multichoice draws no FRLG arrow glyph")
    d.check(bar ~= nil and bar[1] == tx * 8 and bar[2] == Tp * 8 and bar[3] == w * 8,
      string.format("RS multichoice highlight bar at (%d, %d) width %d on item 0", tx * 8, Tp * 8, w * 8))
  else
    d.check(#bars == 0 and #arrows > 0, "FRLG/Emerald multichoice keeps the arrow glyph")
  end
  d.still(game, rs and "refix2_01_rs_prize_multichoice_bar_on_item0.png" or "refix2_03_em_prize_multichoice.png")

  U.tap(game, "down")
  U.wait(10)
  d.check(Choice.cursor == 2, "cursor moved to item 1")
  if rs then
    X.waitFor(function() return bars[#bars] and bars[#bars][2] == (Tp + 2) * 8 end, 600)
    local bar = bars[#bars]
    d.check(bar ~= nil and bar[2] == (Tp + 2) * 8, string.format("RS multichoice highlight bar at y %d on item 1", (Tp + 2) * 8))
  end
  d.still(game, rs and "refix2_02_rs_prize_multichoice_bar_on_item1.png" or "refix2_04_em_prize_multichoice_item1.png")

  Window.cursorPx, MenuCursor.draw, Chrome.stdFrame = origArrow, origBar, origStd
  for _ = 1, 60 do
    if not (X.scriptRunning and X.scriptRunning()) then break end
    U.tap(game, "b")
    U.wait(15)
  end
  d.finish()
end
