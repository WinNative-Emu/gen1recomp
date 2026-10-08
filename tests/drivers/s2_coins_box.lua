local U = require("tests.drivers.util")
local X = require("tests.drivers.em_xa_util")

local d = X.new("s2_coins_box", "/tmp/s2_coins_box")

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
  local CoinsBox = require("src.ui.game3.coins_box")
  local Chrome = require("src.ui.game3.chrome")
  Bag.add(sess.bag, C:require("items", "ITEM_COIN_CASE"), 1)
  Bag.Coins.set(sess, 120)

  local corner = MapIds.forConst("MAP_MAUVILLE_CITY_GAME_CORNER")
  if not d.check(X.goTo(d, game, corner, 14, 3, "up"), "Mauville Game Corner loads") then return d.finish() end
  U.wait(20)
  U.tap(game, "a")
  local shown = X.waitFor(function()
    if CoinsBox.isVisible() then return true end
    local Message = require("src.ui.game3.message")
    if Message.isOpen and Message.isOpen() and U.frame() % 20 == 0 then U.tap(game, "a") end
    return false
  end, 3000)
  if not d.check(shown, "doll prize clerk script runs showcoinsbox") then return d.finish() end
  d.check(CoinsBox.x == (rs and 0 or 1) and CoinsBox.y == (rs and 0 or 1),
    string.format("script origin is %d,%d", CoinsBox.x, CoinsBox.y))

  local frames = {}
  local origStd = Chrome.stdFrame
  Chrome.stdFrame = function(l, t, w, h, ...)
    frames[#frames + 1] = { l, t, w, h }
    return origStd(l, t, w, h, ...)
  end
  local box
  X.waitFor(function()
    for _, f in ipairs(frames) do
      if f[3] == 8 and f[4] == 2 then box = f return true end
    end
    return false
  end, 2000)
  Chrome.stdFrame = origStd
  d.check(box ~= nil, "coins window drew an 8x2 std frame")
  if box then
    d.note(string.format("coins interior %d,%d", box[1], box[2]))
    d.check(box[1] == 1 and box[2] == 1, "coins frame top-left is tile 0,0 (interior at 1,1)")
  end
  U.wait(30)
  d.still(game, rs and "S2_02_rs_coins_box.png" or "S2_04_em_coins_box.png")
  for _ = 1, 60 do
    if not (X.scriptRunning and X.scriptRunning()) then break end
    U.tap(game, "b")
    U.wait(15)
  end
  d.finish()
end
