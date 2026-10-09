-- ../pokegold/engine/overworld/scripting.asm:441
local U = require("tests.drivers.util")
local Sound = require("src.core.Sound")

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/gold-giveitem"
  local fails = 0
  local function ok(cond, line)
    if not cond then fails = fails + 1 end
    print("[driver] " .. (cond and "PASS " or "FAIL ") .. line)
    return cond
  end
  local function finish()
    print("[driver] " .. (fails == 0 and "PASS gold giveitem single box" or ("FAIL " .. fails .. " claims failed")))
    love.event.quit(fails == 0 and 0 or 1)
    while true do U.wait(60) end
  end

  local function boxText(top)
    if not (top and top.isTextBox and top.pages) then return "" end
    local lines = {}
    for _, page in ipairs(top.pages) do
      for _, line in ipairs(page) do lines[#lines + 1] = tostring(line) end
    end
    return table.concat(lines, "\n")
  end

  U.wait(45)
  local world = game.world
  if not ok(world and world.map, "gold world booted") then finish() end

  local def = game.data.items and game.data.items.POTION
  if not ok(def ~= nil and def.index ~= nil, "the cache names POTION") then finish() end
  game.save.inventory = game.save.inventory or {}
  game.save.inventory.POTION = nil

  game.save.playTime = { hours = 0, minutes = 0, seconds = 0, frames = 0 }
  local function clockFrames()
    local t = game.save.playTime
    return ((t.hours * 60 + t.minutes) * 60 + t.seconds) * 60 + t.frames
  end

  world.vm:start({
    { op = "opentext" },
    { op = "verbosegiveitem", item = def.index, quantity = 1 },
    { op = "closetext" },
    { op = "end" },
  })

  local bare, seenFirst = 0, false
  local clockAtFirstBox, clockAtLastBox
  local function step()
    U.wait(1)
    local top = game.stack:top()
    if top then
      if not seenFirst then
        seenFirst = true
        clockAtFirstBox = clockFrames()
      end
      clockAtLastBox = clockFrames()
    elseif seenFirst and world:busy() then
      bare = bare + 1
    end
    return top
  end
  local function press()
    table.insert(game.input.pressQueue, "a")
    game.input.state.a = true
    step()
    game.input.state.a = false
  end
  local function waitFor(pred, seconds)
    local deadline = love.timer.getTime() + seconds
    while love.timer.getTime() < deadline do
      local top = step()
      if pred(top) then return top end
    end
    return nil
  end

  local received = waitFor(function(top)
    return boxText(top):find("received", 1, true) and top.done
  end, 10)
  local recText = boxText(received)
  ok(received ~= nil and recText:find("received\nPOTION.", 1, true) ~= nil and not recText:find("ITEMPOTION", 1, true),
    ("received page reads \"received / POTION.\" (got %q)"):format(recText))
  U.still(game, out .. "/01-received.png")

  local jingle = false
  waitFor(function()
    jingle = jingle or Sound.sfxBusy()
    return jingle
  end, 2)
  ok(jingle, "Sfx_Item starts under the received page")
  if jingle then press() end
  ok(received ~= nil and game.stack:top() == received, "a press while the jingle rings is swallowed")
  local deadline = love.timer.getTime() + 8
  while Sound.sfxBusy() and love.timer.getTime() < deadline do step() end
  ok(received ~= nil and game.stack:top() == received, "received page stays up through the jingle")
  local pocket
  local frames = 0
  while not pocket and frames < 600 do
    if boxText(game.stack:top()):find("put the", 1, true) then
      pocket = game.stack:top()
    else
      frames = frames + 1
      press()
    end
  end
  ok(pocket ~= nil, "pocket page follows the press")
  ok(pocket ~= nil and frames <= 2,
    ("A pressed every frame after the jingle ends is taken within 2 frames (%d)"):format(frames))
  pocket = pocket and waitFor(function(top)
    return top ~= pocket or top.done
  end, 10)
  local pocketText = boxText(pocket)
  ok(pocketText:find("put the\nPOTION in\nthe ITEM POCKET.", 1, true) ~= nil,
    ("pocket page reads \"put the / POTION in / the ITEM POCKET.\" (got %q)"):format(pocketText))
  U.still(game, out .. "/02-pocket.png")

  local closeDeadline = love.timer.getTime() + 10
  while (world:busy() or game.stack:top() ~= nil) and love.timer.getTime() < closeDeadline do
    press()
    for _ = 1, 5 do step() end
  end
  ok(not world:busy() and game.stack:top() == nil, "closetext took the box down")
  ok((game.save.inventory.POTION or 0) > 0, "POTION reached the pack")
  ok(seenFirst and bare == 0, ("no bare overworld frame between the two pages (%d)"):format(bare))
  local spent = (clockAtLastBox or 0) - (clockAtFirstBox or 0)
  ok(spent == 0, ("play clock paused while the box was up (%d frames)"):format(spent))
  finish()
end
