local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/rs_bike_pc_items"

local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  print((failures == 0 and "PASS" or "FAIL") .. " rs_bike_pc_items failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
  U.wait(10)
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "BRENDAN", gender = 0 })
  U.wait(240)
  local Runtime = require("src.core.game3.runtime")
  local session = Runtime.getSession()
  if not check(session ~= nil, "session") then return finish() end
  local C = require("src.core.game3.constants").active(session)
  local ItemUse = require("src.core.game3.item_use")
  local Bag = require("src.core.game3.bag")

  local bike = C:id("items", "ITEM_MACH_BIKE")
  Bag.add(session.bag, bike, 1)
  local ok, res, a, b, c = pcall(ItemUse.useField, session, session.bag, bike)
  check(ok, "bike use indoors does not error (" .. tostring(ok and "" or res) .. ")")
  check(ok and res == false and type(b) == "string" and b:find("DAD") ~= nil,
    "bike indoors gives DAD's advice: " .. tostring(b))

  local Storage = require("src.core.game3.storage")
  local list = Storage.ensure(session).items
  for i = #list, 1, -1 do list[i] = nil end
  list[1] = { id = C:id("items", "ITEM_POTION"), qty = 5 }
  list[2] = { id = C:id("items", "ITEM_SUPER_POTION"), qty = 12 }
  list[3] = { id = C:id("items", "ITEM_HM01_CUT"), qty = 1 }
  list[4] = { id = C:id("items", "ITEM_ACRO_BIKE"), qty = 1 }
  local ItemStorage = require("src.ui.game3.rse.item_storage")
  ItemStorage.show({ session = session })
  U.wait(10)
  check(U.still(game, DIR .. "/01_withdraw.png"), "withdraw shot")
  U.tap(game, "down")
  U.wait(6)
  U.tap(game, "select")
  U.wait(6)
  check(U.still(game, DIR .. "/02_swap.png"), "swap shot")
  U.tap(game, "b")
  U.wait(6)
  U.tap(game, "a")
  U.wait(6)
  check(U.still(game, DIR .. "/03_quantity.png"), "quantity shot")
  U.tap(game, "b")
  U.wait(4)
  ItemStorage.close()
  U.wait(4)
  finish()
end
