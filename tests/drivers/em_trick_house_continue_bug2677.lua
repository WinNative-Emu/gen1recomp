local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_trick_house_continue_bug2677"
local END = "EM_ROUTE110_TRICK_HOUSE_END"
local CORRIDOR = "EM_ROUTE110_TRICK_HOUSE_CORRIDOR"

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  print((failures == 0 and "PASS" or "FAIL") .. " em_trick_house_continue_bug2677 failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
  U.wait(10)
end

return function(game)
  io.stdout:setvbuf("line")
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "BRENDAN", gender = 0 })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Objects = require("src.core.game3.objects")
  local Space = require("src.core.game3.scripting.space")
  local Rse = require("src.core.game3.rse.init")
  local Field = require("src.core.game3.field")
  local Message = require("src.ui.game3.message")
  local Choice = require("src.ui.game3.choice")
  local Encounters = require("src.core.game3.encounters")
  local Player = require("src.core.game3.player")
  Encounters.onStep = function() return nil end
  if not result(Runtime.getSession() ~= nil, "new game reached the field") then return finish() end

  local function idle()
    return not (Space.vm and Space.vm:isRunning()) and not Field.locked
      and not (Message.isOpen and Message.isOpen())
  end
  local function settle(limit)
    for _ = 1, limit or 600 do
      if idle() then return true end
      if Choice.isOpen and Choice.isOpen() then
        U.wait(4)
        U.tap(game, "a")
      elseif Message.isOpen and Message.isOpen() then
        U.tap(game, "a")
      end
      U.wait(2)
    end
    return idle()
  end
  local function master()
    local eo = Objects.find(1)
    return eo ~= nil and eo.visible == true and eo.hidden ~= true and eo.cellX == 4 and eo.cellY == 5
      and eo.facing == "right", eo
  end
  local function walk(dir, n)
    for _ = 1, n do
      local sx, sy, sm = Player.cellX, Player.cellY, Map.current
      for _ = 1, 120 do
        game.input.state[dir] = true
        table.insert(game.input.pressQueue, dir)
        U.wait(1)
        if Player.moving or Player.cellX ~= sx or Player.cellY ~= sy or Map.current ~= sm then break end
      end
      game.input.state[dir] = false
      for _ = 1, 240 do
        if not Player.moving and idle() then break end
        U.wait(1)
      end
      if Map.current ~= sm then return true end
      U.wait(4)
    end
    return true
  end

  Rse.setVar("VAR_TRICK_HOUSE_LEVEL", 4)
  Rse.setFlag("FLAG_HIDE_TRICK_HOUSE_END_MAN", true)
  local ok, err = pcall(function()
    Map.load(nil, game, END, { x = 4, y = 6, facing = "up" })
  end)
  if not result(ok and Map.current == END, "warped into the Trick House end room " .. tostring(err or "")) then
    return finish()
  end
  U.wait(60)
  settle(300)
  result(Rse.flag("FLAG_HIDE_TRICK_HOUSE_END_MAN"), "hide flag is set (a later puzzle)")
  result(master(), "warp in: the Trick Master waits at (4,5) facing east")
  U.still(game, DIR .. "/01_master_waiting_before_save.png")

  result(game:saveGame() == true, "saved in the end room before the prize")
  game:returnToTitle()
  for _ = 1, 600 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  result(game.phase == "boot", "back at the title")
  game:_handleBootAction({ action = "continue" })
  U.wait(120)
  settle(300)
  result(Map.current == END and Player.cellX == 4 and Player.cellY == 6, "Continue resumes in the end room at (4,6)")
  local okMaster, eo = master()
  result(okMaster, "after Continue: the Trick Master is still visible at (4,5) facing east (visible="
    .. tostring(eo and eo.visible) .. " at " .. tostring(eo and eo.cellX) .. "," .. tostring(eo and eo.cellY)
    .. " " .. tostring(eo and eo.facing) .. ")")
  U.still(game, DIR .. "/02_master_waiting_after_continue.png")

  Player.facing = "up"
  U.tap(game, "a")
  U.wait(10)
  local talked = false
  for _ = 1, 3000 do
    if Rse.var("VAR_TEMP_2") == 1 then talked = true end
    if talked and idle() then break end
    if Choice.isOpen and Choice.isOpen() then
      U.wait(4)
      U.tap(game, "a")
    elseif Message.isOpen and Message.isOpen() then
      U.tap(game, "a")
    end
    U.wait(2)
  end
  result(talked, "talking to him sets VAR_TEMP_2 (the prize scene ran)")
  settle(600)

  walk("up", 3)
  walk("left", 2)
  walk("up", 2)
  for _ = 1, 600 do
    if Map.current == CORRIDOR and idle() then break end
    U.wait(1)
  end
  result(Map.current == CORRIDOR, "the exit at (2,1) is not blocked: walked out into the corridor (map="
    .. tostring(Map.current) .. " at " .. tostring(Player.cellX) .. "," .. tostring(Player.cellY) .. ")")
  if Map.current == CORRIDOR then
    U.wait(60)
    U.still(game, DIR .. "/03_walked_out_into_corridor.png")
  end
  return finish()
end
