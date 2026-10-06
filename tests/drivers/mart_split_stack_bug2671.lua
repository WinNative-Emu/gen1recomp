-- engine/events/pokemart.asm:152
-- engine/items/inventory.asm:59
--   POKEPORT_DRIVER=tests/drivers/mart_split_stack_bug2671.lua POKEPORT_IDENTITY=bsa1005-red-2671 POKEPORT_VERSION=red love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR") or "/tmp/shots"
  local Bag = require("src.inventory.Bag")
  local Menu = require("src.ui.Menu")
  local ListMenu = require("src.ui.ListMenu")
  local QuantityBox = require("src.ui.QuantityBox")
  local ChoiceBox = require("src.ui.ChoiceBox")
  local TextBox = require("src.render.TextBox")

  local failures = 0
  local function check(label, ok)
    if not ok then failures = failures + 1 end
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end
  local function top() return game.stack:top() end
  local function topIs(cls) return getmetatable(top()) == cls end
  local function waitFor(pred, frames)
    for _ = 1, frames or 300 do
      if pred() then return true end
      U.wait(1)
    end
    return pred()
  end
  local function rows()
    local out = {}
    for _, r in ipairs(Bag.rows(game.save, game.data)) do
      out[#out + 1] = r.id .. "x" .. tostring(r.count)
    end
    return table.concat(out, ",")
  end
  local function finish()
    U.log(failures == 0 and "PASS mart_split_stack_bug2671"
          or ("FAIL mart_split_stack_bug2671 (" .. failures .. " failures)"))
    love.event.quit(failures == 0 and 0 or 1)
    U.wait(600)
  end

  local MONEY = 104276
  local ok, err = pcall(function()
    game.save.money = MONEY
    game.save.inventory = { X_ACCURACY = 2, POTION = 3 }
    game.save.bagOrder = { "X_ACCURACY", "POTION" }
    U.teleport(game, "CELADON_MART_5F", 5, 5, "up")
    U.wait(10)

    for _ = 1, 60 do
      if topIs(Menu) then break end
      U.tap(game, "a")
      U.wait(4)
    end
    if not check("the X item clerk's mart menu opens", topIs(Menu)) then return end
    local menu = top()

    U.tap(game, "a")
    if not check("BUY opens the list", waitFor(function() return topIs(ListMenu) end, 300)) then return end
    local list = top()
    check("the cursor is on X ACCURACY", list.items[list.index].value == "X_ACCURACY")
    U.wait(4)
    U.tap(game, "a")
    if not check("the quantity box opens", waitFor(function() return topIs(QuantityBox) end, 30)) then return end
    local qty = top()
    check("the selector max stays 99", qty.max == 99)
    U.wait(4)
    U.tap(game, "down")
    U.wait(4)
    check("DOWN wraps to x99", qty.qty == 99)
    U.still(game, DIR .. "/2671_01_buy_x99.png")

    U.tap(game, "a")
    if not check("YES/NO opens", waitFor(function()
      if topIs(TextBox) and top().waiting then U.tap(game, "a") end
      return topIs(ChoiceBox)
    end, 600)) then return end
    U.wait(4)
    U.tap(game, "a")
    local receipt
    check("the clerk hands the items over", waitFor(function()
      local t = top()
      if getmetatable(t) == TextBox and t.pages then
        local text = table.concat(t.pages[1] or {}, " ")
        if text:find("Here you are", 1, true) then receipt = t return true end
        if text:find("carry", 1, true) then return true end
      end
      return false
    end, 600) and receipt ~= nil)
    check("94050 is paid", game.save.money == MONEY - 94050)
    check("the bag holds 101 X ACCURACY", game.save.inventory.X_ACCURACY == 101)
    check("the overflow sits in a new last slot: " .. rows(),
          rows() == "X_ACCURACYx99,POTIONx3,X_ACCURACYx2")
    waitFor(function() return receipt.done end, 600)
    U.still(game, DIR .. "/2671_02_here_you_are.png")

    for _ = 1, 30 do
      if top() == list then break end
      U.tap(game, "a")
      U.wait(4)
    end
    U.tap(game, "b")
    if not check("B returns to BUY/SELL/QUIT", waitFor(function()
      if topIs(TextBox) and top().waiting then U.tap(game, "a") end
      return top() == menu
    end, 600)) then return end
    U.wait(4)
    U.tap(game, "down")
    U.wait(4)
    U.tap(game, "a")
    if not check("SELL opens the bag list", waitFor(function() return topIs(ListMenu) end, 300)) then return end
    local sellList = top()
    U.wait(30)
    local counts = {}
    for _, it in ipairs(sellList.items) do
      if not it.cancel then counts[#counts + 1] = it.value .. "x" .. tostring(it.count) end
    end
    check("the sell list shows two X ACCURACY rows: " .. table.concat(counts, ","),
          table.concat(counts, ",") == "X_ACCURACYx99,POTIONx3,X_ACCURACYx2")
    U.still(game, DIR .. "/2671_03_sell_list_split_rows.png")
  end)
  if not ok then
    failures = failures + 1
    U.log("FAIL driver error:", tostring(err))
  end
  finish()
end
