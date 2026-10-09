-- ../pokegold/maps/PlayersHouse1F.asm:21
local U = require("tests.drivers.util")
local ChoiceBox = require("src.ui.ChoiceBox")
local InitClock = require("src.ui.gen2.InitClock")

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/gold-mom"
  local fails = 0
  local function ok(cond, line)
    if not cond then fails = fails + 1 end
    print("[driver] " .. (cond and "PASS " or "FAIL ") .. line)
    return cond
  end
  local function finish()
    print("[driver] " .. (fails == 0 and "PASS gold mom scene" or ("FAIL " .. fails .. " claims failed")))
    love.event.quit(fails == 0 and 0 or 1)
    while true do U.wait(60) end
  end

  local function press(button)
    table.insert(game.input.pressQueue, button)
    game.input.state[button] = true
    U.wait(1)
    game.input.state[button] = false
  end
  local function boxText(box)
    if not (box and box.isTextBox and box.pages) then return "" end
    local lines = {}
    for _, page in ipairs(box.pages) do
      for _, line in ipairs(page) do lines[#lines + 1] = tostring(line) end
    end
    return table.concat(lines, "\n")
  end
  local function under(state)
    local states = game.stack.states
    for i = #states, 2, -1 do
      if states[i] == state then return states[i - 1] end
    end
    return nil
  end

  U.wait(45)
  local world = game.world
  if not ok(world and world.map, "gold world booted") then finish() end
  U.still(game, out .. "/00-bedroom.png")

  world:warpToMapId("PLAYERS_HOUSE_1F", 9, 0, "down")
  local deadline = love.timer.getTime() + 5
  while not world:busy() and love.timer.getTime() < deadline do U.wait(1) end
  if not ok(world:busy(), "MeetMomScript started on the stairs") then finish() end

  local MOMENTS = {
    { id = "01-here-you-go", match = function(top) return top.isTextBox and top.done and boxText(top):find("neighbor", 1, true) end },
    { id = "02-received-pokegear", match = function(top) return top.isTextBox and top.done and boxText(top):find("received", 1, true) and boxText(top):find("GEAR", 1, true) end },
    { id = "03-day-not-set", match = function(top) return top.isTextBox and top.done and boxText(top):find("just ", 1, true) end },
    { id = "04-day-of-week", match = function(top) return getmetatable(top) == InitClock and top.mode == "day" end },
    { id = "05-dst-yes-no", match = function(top) return getmetatable(top) == ChoiceBox and boxText(under(top)):find("Saving Time now?", 1, true) end },
    { id = "06-come-home-yes-no", match = function(top) return getmetatable(top) == ChoiceBox and boxText(under(top)):find("PHONE?", 1, true) end },
    { id = "07-phone-numbers", match = function(top) return top.isTextBox and top.done and boxText(top):find("Phone numbers", 1, true) end },
  }
  local reached, nextPress = {}, 0
  deadline = love.timer.getTime() + 22
  while love.timer.getTime() < deadline and not (reached["07-phone-numbers"] and not world:busy()) do
    local top = game.stack:top()
    if top then
      for _, m in ipairs(MOMENTS) do
        if not reached[m.id] and m.match(top) then
          reached[m.id] = true
          U.still(game, ("%s/%s.png"):format(out, m.id))
        end
      end
    end
    if top and love.timer.getTime() >= nextPress then
      nextPress = love.timer.getTime() + 0.2
      press("a")
    else
      U.wait(1)
    end
  end
  for _ = 1, 30 do U.wait(1) end
  ok(not world:busy(), "MeetMomScript ran to its end")
  U.still(game, out .. "/08-scene-end.png")
  for _, m in ipairs(MOMENTS) do
    ok(reached[m.id] == true, "reached " .. m.id)
  end

  local greyed, pooled = 0, 0
  for _, npc in pairs(world.npcPool or {}) do
    pooled = pooled + 1
    if npc.sprite and npc.spriteDef and not npc.sprite.objColors then greyed = greyed + 1 end
  end
  ok(greyed == 0, ("every pooled NPC has a baked palette (%d pooled, %d grey)"):format(pooled, greyed))
  finish()
end
