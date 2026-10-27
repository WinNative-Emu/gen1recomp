-- ../pokegold/engine/rtc/timeset.asm:13-18
-- ../pokegold/engine/menus/intro_menu.asm:494-500
--
--   POKEPORT_BOOT_CINEMA=1 POKEPORT_TOUCH=0 tools/run_driver.sh gold <identity> \
--     tests/drivers/gen2_oak_music_after_clock_3059.lua <shotdir>
local U = require("tests.drivers.util")

local GenderSelect = require("src.ui.gen2.GenderSelect")
local InitClock = require("src.ui.gen2.InitClock")
local MainMenu = require("src.ui.gen2.MainMenu")
local Music = require("src.core.Music")
local OakSpeech = require("src.ui.gen2.OakSpeech")

local ROUTE30 = "Music_Route30"

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/3059-oak-music"
  local failures = 0

  local function say(line) print("[driver] " .. line) end

  local function result(ok, label)
    say((ok and "PASS " or "FAIL ") .. label)
    if not ok then failures = failures + 1 end
  end

  local function bail(reason)
    say("FAIL " .. reason)
    love.event.quit(1)
    error(reason, 0)
  end

  local function top() return game.stack:top() end
  local function isA(class)
    local state = top()
    return state ~= nil and getmetatable(state) == class
  end

  local route30OnClock = false
  local function sample()
    if isA(InitClock) and Music.current() == ROUTE30 then
      route30OnClock = true
    end
  end

  local function wait(n)
    for _ = 1, n do
      U.wait(1)
      sample()
    end
  end

  local function tap(button, frames)
    game.input.pressQueue[#game.input.pressQueue + 1] = button
    game.input.state[button] = true
    wait(2)
    game.input.state[button] = false
    wait(frames or 4)
  end

  local function waitFor(label, predicate, frames)
    for _ = 1, frames or 900 do
      if predicate() then return end
      wait(1)
    end
    bail(("stalled waiting for %s (top is %s)"):format(label, tostring(top())))
  end

  for _ = 1, 900 do
    if isA(MainMenu) then break end
    tap("start", 2)
  end
  waitFor("the intro menu", function() return isA(MainMenu) end)
  local menu = top()
  for i, item in ipairs(menu.list.items) do
    if item.value == "new" then menu.list.index = i end
  end
  for _ = 1, 20 do
    if not isA(MainMenu) then break end
    tap("a", 8)
  end
  wait(4)
  if isA(GenderSelect) then bail("gender select on a Gold boot") end

  waitFor("the clock screen", function() return isA(InitClock) end, 300)
  result(Music.current() ~= ROUTE30,
    "no Route 30 theme as the clock screen opens")
  waitFor("the clock screen to settle",
    function() return isA(InitClock) and top().fade == nil end, 300)
  wait(8 * (0x10 + 1) + 16)
  result(isA(InitClock), "still on the clock screen after the fade")
  result(Music.current() == nil,
    ("InitClock faded the music to MUSIC_NONE (current %s)")
      :format(tostring(Music.current())))
  if not U.still(game, out .. "/3059_01_clock_set_silent.png") then
    bail("no clock shot")
  end

  for _ = 1, 200 do
    if not isA(InitClock) then break end
    tap("a", 3)
  end
  waitFor("the Oak speech", function() return isA(OakSpeech) end, 400)
  local speech = top()
  result(not route30OnClock, "Route 30 never played while InitClock was up")

  waitFor("Route 30 after the clock", function()
    return Music.current() == ROUTE30
  end, 120)
  result(Music.current() == ROUTE30, "Route 30 starts once the time is set")
  waitFor("Oak's first line", function()
    return speech.pic ~= nil and speech.fade == nil
      and speech.picReveal == nil and top() ~= speech
  end, 400)
  wait(30)
  if not U.still(game, out .. "/3059_02_oak_with_route30.png") then
    bail("no Oak shot")
  end

  if failures > 0 then
    say(("FAIL gen2 oak music after clock (%d failures)"):format(failures))
    love.event.quit(1)
    return
  end
  say("PASS gen2 oak music after clock")
  love.event.quit(0)
end
