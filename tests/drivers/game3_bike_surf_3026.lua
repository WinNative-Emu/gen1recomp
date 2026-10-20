local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_bike_surf_3026"

-- pokefirered/include/constants/items.h:432
local ITEM_BICYCLE = 360

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS bike_surf_3026")
    love.event.quit(0)
  else
    print("FAIL bike_surf_3026 failures=" .. failures)
    love.event.quit(1)
  end
end

return function(game)
  print("PASS driver_started")
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Collision = require("src.core.game3.collision")
  local Bag = require("src.core.game3.bag")
  local Audio = require("src.core.game3.audio")
  local Message = require("src.ui.game3.message")
  local StartMenu = require("src.ui.game3.start_menu")
  local BagMenu = require("src.ui.game3.bag_menu")
  local Space = require("src.core.game3.scripting.space")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the field") then return finish() end
  session.repelSteps = 250
  session.bag = session.bag or Bag.new()
  Bag.add(session.bag, ITEM_BICYCLE, 1)
  session.registeredItem = ITEM_BICYCLE

  local function waitFor(fn, budget)
    for _ = 1, (budget or 600) do
      if fn() then return true end
      U.wait(1)
    end
    return fn() and true or false
  end

  local function settle()
    for _ = 1, 240 do
      local busy = (Space.vm and Space.vm:isRunning()) or Message.isOpen()
      if not busy then return true end
      if Message.isOpen() then U.tap(game, "a") end
      U.wait(4)
    end
    return false
  end

  Map.load(nil, game, "FR_PALLET_TOWN", { x = 10, y = 10, facing = "down" })
  U.wait(60)
  settle()

  local sx, sy
  for y = 0, 40 do
    for x = 0, 40 do
      if not sx and Collision.isWater(x, y) and Collision.isWater(x, y + 1)
          and Collision.isWater(x, y + 2) then
        sx, sy = x, y
      end
    end
  end
  if not result(sx ~= nil, "found open water in Pallet Town at " .. tostring(sx) .. "," .. tostring(sy)) then
    return finish()
  end

  local function place(x, y, facing)
    Player.moving = false
    Player.progress = 0
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing
    Player.surfing = true
    Player.biking = false
    Player.dismounting = false
    session.x, session.y, session.facing = x, y, facing
  end
  place(sx, sy, "down")
  Audio.changeMusicTo(Audio.MUS_SURF)
  U.wait(30)

  local function stepFrames(dir)
    local fromX, fromY = Player.cellX, Player.cellY
    local n = 0
    table.insert(game.input.pressQueue, dir)
    game.input.state[dir] = true
    while n < 120 do
      U.wait(1)
      n = n + 1
      if n == 2 then game.input.state[dir] = false end
      if not Player.moving and (Player.cellX ~= fromX or Player.cellY ~= fromY) then break end
    end
    game.input.state[dir] = false
    U.wait(10)
    return n, Player.cellX ~= fromX or Player.cellY ~= fromY
  end

  local baseFrames, moved = stepFrames("down")
  result(moved, "a surf step moves the player, frames=" .. tostring(baseFrames))
  stepFrames("up")
  place(sx, sy, "down")
  U.wait(10)

  print("[driver] SELECT on the registered BICYCLE while surfing")
  U.tap(game, "select")
  U.wait(10)
  result(waitFor(function() return Message.isOpen() end, 120), "SELECT opened a message box")
  waitFor(function() return Message.isWaiting() end, 300)
  local selectText = Message.currentPage()
  print("[driver] SELECT text: " .. tostring(selectText):gsub("\n", " / "))
  result(tostring(selectText):find("time to use that", 1, true) ~= nil,
    "SELECT shows Oak's refusal")
  U.still(game, DIR .. "/3026_01_select_oak_refusal.png")
  result(Player.surfing == true and Player.biking == false,
    "after SELECT the player is still surfing, not biking")
  result(Audio.currentMapMusic() ~= Audio.MUS_CYCLING,
    "no cycling music after SELECT, song=" .. tostring(Audio.currentMapMusic()))
  settle()

  print("[driver] bag USE on the BICYCLE while surfing")
  U.tap(game, "start")
  U.wait(30)
  for _ = 1, 12 do
    local e = StartMenu.ENTRIES and StartMenu.ENTRIES[StartMenu.cursor]
    if e and e.id == "bag" then break end
    U.tap(game, "down")
    U.wait(8)
  end
  U.tap(game, "a")
  U.wait(60)
  if not result(BagMenu.isOpen(), "bag opened") then return finish() end
  for _ = 1, 4 do
    if BagMenu.currentPocket() == "KEY_ITEMS" then break end
    U.tap(game, "right")
    U.wait(15)
  end
  result(BagMenu.currentPocket() == "KEY_ITEMS", "on KEY ITEMS")
  local idx
  for i, row in ipairs(BagMenu.list()) do
    if require("src.core.game3.items_data").toNumericId(row.id) == ITEM_BICYCLE then idx = i end
  end
  if not result(idx ~= nil, "the BICYCLE is in KEY ITEMS at row " .. tostring(idx)) then return finish() end
  for _ = 1, 20 do
    if BagMenu.cursor == idx then break end
    U.tap(game, BagMenu.cursor < idx and "down" or "up")
    U.wait(8)
  end
  U.tap(game, "a")
  U.wait(20)
  result(BagMenu.mode == "action", "the item menu opened, mode=" .. tostring(BagMenu.mode))
  result(BagMenu.ACTIONS[BagMenu.actionCursor] == "USE", "cursor on USE")
  U.tap(game, "a")
  U.wait(10)
  result(waitFor(function() return BagMenu.mode == "message" end, 120),
    "USE printed a message in the bag, mode=" .. tostring(BagMenu.mode))
  U.wait(90)
  local bagText = BagMenu.messageText
  print("[driver] bag text: " .. tostring(bagText):gsub("\n", " / "))
  result(tostring(bagText):find("time to use that", 1, true) ~= nil, "bag USE shows Oak's refusal")
  U.still(game, DIR .. "/3026_02_bag_oak_refusal.png")
  result(BagMenu.isOpen(), "the bag stays open for the message")
  result(Player.surfing == true and Player.biking == false,
    "after bag USE the player is still surfing, not biking")
  result(Audio.currentMapMusic() ~= Audio.MUS_CYCLING,
    "no cycling music after bag USE, song=" .. tostring(Audio.currentMapMusic()))

  for _ = 1, 6 do
    if not BagMenu.isOpen() then break end
    U.tap(game, BagMenu.mode == "message" and "a" or "b")
    U.wait(40)
  end
  for _ = 1, 4 do
    if not (StartMenu.isOpen and StartMenu.isOpen()) then break end
    U.tap(game, "b")
    U.wait(30)
  end
  result(not BagMenu.isOpen(), "bag closed")
  settle()

  place(sx, sy, "down")
  U.wait(10)
  local afterFrames, moved2 = stepFrames("down")
  result(moved2 and afterFrames == baseFrames,
    string.format("surf step speed unchanged, before=%d after=%d", baseFrames, afterFrames))
  result(Player.surfing == true and Player.biking == false, "still surfing after the step")
  U.still(game, DIR .. "/3026_03_still_surfing.png")

  finish()
end
