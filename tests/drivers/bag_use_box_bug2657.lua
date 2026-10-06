-- engine/menus/start_sub_menus.asm:298
-- engine/items/item_effects.asm:2172
--   tools/run_driver.sh red <identity> tests/drivers/bag_use_box_bug2657.lua <shot dir>
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR") or "/tmp/shots"
  local Bag = require("src.inventory.Bag")
  local Strings = require("src.core.Strings")
  local TextBox = require("src.render.TextBox")
  local Menu = require("src.ui.Menu")
  local ChoiceBox = require("src.ui.ChoiceBox")

  local ok = true
  local function check(label, pass)
    U.log(pass and "PASS" or "FAIL", label)
    if not pass then ok = false end
    return pass
  end
  local function finish()
    U.log(ok and "PASS bag_use_box_2657" or "FAIL bag_use_box_2657")
    love.event.quit(ok and 0 or 1)
    while true do coroutine.yield() end
  end
  local function onStack(state)
    for _, s in ipairs(game.stack.states) do
      if s == state then return true end
    end
    return false
  end
  local function boxText(box)
    local lines = {}
    for _, page in ipairs(box.pages or {}) do
      for _, line in ipairs(page) do lines[#lines + 1] = line end
    end
    return table.concat(lines, " / ")
  end
  local function waitFor(pred, n)
    for _ = 1, n or 300 do
      if pred(game.stack:top()) then return game.stack:top() end
      U.wait(1)
    end
    return nil
  end
  local function stepTo(state, wants, what, dir)
    for _ = 1, 30 do
      if wants(state) then return true end
      U.tap(game, dir or "down")
      U.wait(6)
    end
    check("found " .. what .. " in the menu", false)
    return false
  end

  U.newGame(game)
  if not check("new game reached the overworld", game.overworld ~= nil) then finish() end
  game.save.inventory = {}
  Bag.add(game.save, "POKE_BALL", 5)
  Bag.add(game.save, "TM_TOXIC", 1)
  U.teleport(game, "REDS_HOUSE_1F", 5, 5, "up")
  U.wait(20)

  U.tap(game, "start")
  U.wait(20)
  local start = game.stack:top()
  local ITEM = Strings("ITEM")
  if not check("START opened a menu", start and start.items ~= nil) then finish() end
  if stepTo(start, function(m) return m.items[m.index].label == ITEM end, "ITEM") then
    U.tap(game, "a")
    U.wait(20)
  end
  local bag = game.stack:top()
  if not check("the bag opened", bag and bag.items and bag.items[1] ~= nil) then finish() end

  local function useOn(id, dir)
    if not stepTo(bag, function(b) return b.items[b.index].value == id end, id, dir) then finish() end
    U.tap(game, "a")
    U.wait(10)
    local sub = game.stack:top()
    if not check(id .. ": USE/TOSS opened", getmetatable(sub) == Menu and #sub.items == 2) then finish() end
    U.tap(game, "a")
    U.wait(2)
    return sub
  end

  local sub = useOn("TM_TOXIC")
  local booted = waitFor(function(t)
    return getmetatable(t) == TextBox and (t.waiting or t.done)
      and boxText(t):find("Booted up", 1, true)
  end)
  if not check("TM: Booted up text printed", booted ~= nil) then
    local t = game.stack:top()
    U.log("top:", tostring(getmetatable(t) == TextBox), t and t.done, t and t.pages and boxText(t))
    finish()
  end
  check("TM: USE/TOSS box left painted on the bag", bag.optionBox == sub and not onStack(sub))
  check("TM: hollow cursor on USE", sub.hollowIndex == 1 and sub.index == 1)
  U.wait(10)
  check("shot 1", U.still(game, DIR .. "/2657_01_booted_up_box_kept.png"))

  local yesno = nil
  for _ = 1, 40 do
    yesno = getmetatable(game.stack:top()) == ChoiceBox and game.stack:top() or nil
    if yesno then break end
    U.tap(game, "a")
    U.wait(8)
  end
  if not check("TM: Teach YES/NO up", yesno ~= nil) then finish() end
  check("TM: box still painted under YES/NO", bag.optionBox == sub)
  U.wait(10)
  check("shot 2", U.still(game, DIR .. "/2657_02_teach_yes_no_over_box.png"))

  U.tap(game, "b")
  waitFor(function(t) return t == bag end, 120)
  U.wait(5)
  check("TM: NO returns to the bag list", game.stack:top() == bag)
  check("TM: the list's redraw erased the box", bag.optionBox == nil)
  check("shot 3", U.still(game, DIR .. "/2657_03_list_redrawn.png"))

  local sub2 = useOn("POKE_BALL", "up")
  local refusal = waitFor(function(t)
    return getmetatable(t) == TextBox and (t.waiting or t.done)
  end)
  if check("BALL: refusal text printed", refusal ~= nil) then
    U.log("the box reads:", boxText(refusal))
  end
  check("BALL: USE/TOSS box left painted on the bag", bag.optionBox == sub2)
  U.wait(10)
  check("shot 4", U.still(game, DIR .. "/2657_04_refusal_box_kept.png"))

  for _ = 1, 20 do
    if game.stack:top() == bag then break end
    U.tap(game, "a")
    U.wait(8)
  end
  U.wait(3)
  check("BALL: back on the list", game.stack:top() == bag)
  check("BALL: box erased", bag.optionBox == nil)

  finish()
end
