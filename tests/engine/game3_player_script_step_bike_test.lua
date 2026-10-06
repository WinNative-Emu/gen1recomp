package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local eq = T.eq
love = love or require("tests.love_stub")

local Player = require("src.core.game3.player")

-- pokeemerald/data/maps/DewfordTown/scripts.inc:112
local function stepFramesFor(biking, run, slow, fast)
  Player.reset(10, 10, "down")
  Player.biking = biking
  Player.bikeType = biking and "mach" or nil
  Player.scriptStep("down", run, slow, fast)
  local frames, running = Player.stepFrames, Player.running
  Player.reset(10, 10, "down")
  return frames, running
end

for _, case in ipairs({
  { "walk", false, false, false },
  { "run", true, false, false },
  { "run slow", true, true, false },
  { "walk fast", false, false, true },
}) do
  local label, run, slow, fast = case[1], case[2], case[3], case[4]
  local onFoot, footRun = stepFramesFor(false, run, slow, fast)
  local onBike, bikeRun = stepFramesFor(true, run, slow, fast)
  eq(onBike, onFoot, "scripted " .. label .. " step on a bike keeps the on-foot frame count")
  eq(bikeRun, footRun, "scripted " .. label .. " step on a bike keeps the on-foot running pose")
end

T.finish("game3_player_script_step_bike_test")
