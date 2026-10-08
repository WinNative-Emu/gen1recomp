local U = require("tests.drivers.util")
local GameVersion = require("src.core.GameVersion")
local Presence = require("src.world.gen2.UnionRoomPresence")
local RoomMap = require("src.world.gen2.UnionRoomMap")

return function(game)
  local fails = 0
  local role = os.getenv("POKEPORT_UNION_ROLE") or "host"
  local address = os.getenv("POKEPORT_UNION_RELAY")
  local function ok(cond, line)
    if not cond then fails = fails + 1 end
    print((cond and "PASS " or "FAIL ") .. role .. " " .. line)
    return cond
  end
  local function done()
    print(fails == 0 and "ALL PASS" or (fails .. " FAILURES"))
    love.event.quit(fails == 0 and 0 or 1)
    coroutine.yield()
  end
  U.wait(60)
  local world = game.world
  if not ok(world and world.map ~= nil and address ~= nil, "world booted with a relay address") then return done() end
  local v = GameVersion.current
  local dir = (os.getenv("POKEPORT_SHOT_DIR") or "/tmp/union-w5b") .. "/relay"
  local Client = require("src.online.Client")
  Client.configure({ relayAddress = address })

  local function waitReal(cond, seconds)
    local stop = love.timer.getTime() + seconds
    while love.timer.getTime() < stop do
      if cond() then return true end
      coroutine.yield()
    end
    return cond()
  end
  local function tap(btn)
    table.insert(game.input.pressQueue, btn)
    coroutine.yield()
    game.input.state[btn] = false
    U.wait(2)
  end
  local function mashReal(btn, cond, seconds)
    local stop = love.timer.getTime() + seconds
    while love.timer.getTime() < stop do
      if cond() then return true end
      tap(btn)
    end
    return cond()
  end
  local function shot(name)
    U.still(game, ("%s/%s_%s_%s.png"):format(dir, role, v, name))
  end

  world:warpToMapId(RoomMap.ID, 12, 22, "up")
  ok(waitReal(function()
    local s = Presence.active()
    return s and s.state == "joined" and #s:entities() >= 1
  end, 20), "the live room shows the other game")
  local s = Presence.active()
  if not s then return done() end
  waitReal(function() return game.stack:top() == nil and s.ui == nil end, 3)
  local other = s:entities()[1]
  ok(other and other.participant.gen == 2, "the other trainer reads gen 2")
  print(("%s sees %s on %s slot %d"):format(role, tostring(other and other.participant.name),
    tostring(other and other.participant.game), other and other.unionSlot or -1))
  local p = world.player
  p.cellX, p.cellY = other.cellX, other.cellY + 1
  p.px, p.py = p.cellX * 16, p.cellY * 16
  p.facing = "up"
  U.wait(10)
  shot("01_room")

  if role == "host" then
    waitReal(function() return false end, 2)
    tap("a")
    ok(waitReal(function() return s.ui == "talk" end, 3), "talking opens the menu flow")
    ok(mashReal("a", function()
      local top = game.stack:top()
      return top and top.items ~= nil
    end, 5), "the menu is up")
    tap("a")
    ok(waitReal(function() return s.activity ~= nil end, 20), "the guest accepts over the live relay")
  else
    ok(waitReal(function() return s.ui == "prompt" end, 25), "the live request arrives")
    ok(mashReal("a", function()
      local top = game.stack:top()
      return top and getmetatable(top) == require("src.ui.ChoiceBox")
    end, 5), "YES / NO is up")
    shot("02_prompt")
    tap("a")
    ok(waitReal(function() return s.activity ~= nil end, 20), "accepting opens the activity")
  end
  ok(waitReal(function() return s.activity and s.activity.waiter and s.activity.waiter:shown() end, 10),
    "the getting-ready line is up")
  local prep = s.activity and s.activity.prep
  ok(waitReal(function() prep = s.activity and s.activity.prep return prep and prep.rules ~= nil end, 10),
    "live rules arrive")
  print(("%s rules %s"):format(role, tostring(prep and prep.rules and prep.rules.ruleset)))
  shot("03_getting_ready")
  if role == "host" then
    U.wait(60)
    tap("b")
    ok(waitReal(function() return s.activity and s.activity.state == "done" end, 5), "the host cancels")
    U.wait(20)
    shot("04_cancelled")
  else
    ok(waitReal(function() return s.activity and s.activity.why == "peer" end, 20), "the guest sees the host cancel")
    U.wait(20)
    shot("04_peer_cancelled")
  end
  mashReal("a", function() return s.activity == nil and game.stack:top() == nil end, 5)
  ok(s.activity == nil, "the activity closes")
  U.wait(30)
  Client.disconnect()
  done()
end
