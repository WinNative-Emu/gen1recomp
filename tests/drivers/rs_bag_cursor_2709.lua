local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/drv2709"

local function until_(n, fn)
  for _ = 1, n do
    if fn() then return true end
    U.wait(1)
  end
  return fn()
end

return function(game)
  local pass = true
  local function check(cond, label)
    print((cond and "PASS " or "FAIL ") .. label)
    if not cond then pass = false end
  end
  until_(900, function() return game.phase == "boot" and game.boot end)
  local ok, err = xpcall(function()
    local Runtime = require("src.core.game3.runtime")
    local Warp = require("src.core.game3.warp")
    local Message = require("src.ui.game3.message")
    pcall(function() game:_handleBootAction({ action = "new_game", name = "TAI", gender = 0 }) end)
    U.wait(60)
    until_(600, function()
      if Message.isOpen and Message.isOpen() then U.tap(game, "b") end
      return not (Warp.isBusy() or (Message.isOpen and Message.isOpen()))
    end)
    local s = Runtime.getSession()
    local C = require("src.core.game3.constants").active(s)
    local Bag = require("src.core.game3.bag")
    Bag.add(s.bag, C:require("items", "ITEM_POKE_BALL"), 5)
    Bag.add(s.bag, C:require("items", "ITEM_POTION"), 3)
    local BagMenu = require("src.ui.game3.bag_menu")
    local Rs = require("src.ui.game3.rs.bag_menu")

    BagMenu.show(s, { battle = true, session = s, pocket = "POKE_BALLS" })
    until_(120, function() return not BagMenu._open end)
    U.wait(10)
    U.tap(game, "a")
    until_(60, function() return BagMenu.mode == "action" end)
    U.wait(10)
    local row = BagMenu.list()[BagMenu.cursor]
    local g = Rs.grid(BagMenu, row)
    check(BagMenu.mode == "action" and g.cells[1] == "USE", "battle popup shows USE")
    check(Rs.cursorWidth(BagMenu, g, 1) == 40, "battle USE cursor 40px")
    U.still(game, DIR .. "/2709_01_battle_use_cursor.png")
    BagMenu.close()
    U.wait(10)

    BagMenu.show(s, { session = s, pocket = "ITEMS" })
    until_(120, function() return not BagMenu._open end)
    U.wait(10)
    U.tap(game, "a")
    until_(60, function() return BagMenu.mode == "action" end)
    U.wait(10)
    g = Rs.grid(BagMenu, BagMenu.list()[BagMenu.cursor])
    check(BagMenu.mode == "action" and g.cols == 2, "field 2x2 popup open")
    check(Rs.cursorWidth(BagMenu, g, 1) == 47, "field USE cursor 47px")
    U.still(game, DIR .. "/2709_02_field_use_cursor.png")
    U.tap(game, "right")
    U.wait(10)
    check(Rs.cursorWidth(BagMenu, g, 3) == 48, "field GIVE cursor 48px")
    U.still(game, DIR .. "/2709_03_field_give_cursor.png")
    BagMenu.close()
  end, debug.traceback)
  if not ok then print("FAIL driver error: " .. tostring(err)); pass = false end
  love.event.quit(pass and 0 or 1)
  U.wait(10)
end
