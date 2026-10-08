local U = require("tests.drivers.util")
local GameVersion = require("src.core.GameVersion")
local Presence = require("src.world.gen1.UnionRoomPresence")
local UnionRoomMap = require("src.world.gen1.UnionRoomMap")

return function(game)
  local fails = 0
  local function ok(cond, line)
    if not cond then fails = fails + 1 end
    print((cond and "PASS " or "FAIL ") .. line)
    return cond
  end
  local function done()
    print(fails == 0 and "all claims passed" or (fails .. " claims failed"))
    love.event.quit(fails == 0 and 0 or 1)
    coroutine.yield()
  end
  local role = os.getenv("UR_ROLE") or "host"
  local v = GameVersion.get()
  local dir = (os.getenv("POKEPORT_SHOT_DIR") or "/tmp/union-w5b-gen1") .. "/relay"
  local function shot(name) U.still(game, ("%s/%s_%s_%s.png"):format(dir, role, v, name)) end
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
    U.wait(1)
    game.input.state[btn] = false
    U.wait(2)
  end
  local function top() return game.stack:top() end
  U.wait(10)
  game.save.flags.EVENT_GOT_POKEDEX = true
  game.save.player.name = role == "host" and "HOST" or "GUEST"
  local cx, cy = UnionRoomMap.cellFor(role == "host" and 20 or 21)
  U.teleport(game, UnionRoomMap.MAP_ID, cx, cy + 1, "up")
  local s
  ok(waitReal(function()
    s = Presence.active()
    return s and s.state == "joined"
  end, 20), role .. " joins the live relay's Union Room")
  if not s then return done() end
  ok(waitReal(function() return #s:entities() >= 1 end, 30), role .. " sees the other process")
  local other = s:entities()[1]
  print(("%s sees %s gen %s slot %s"):format(role, tostring(other and other.p.name), tostring(other and other.p.gen),
    tostring(other and other.p.slot)))
  shot("01_room")

  if role == "host" then
    require("src.ui.union.gen1.Talk").invite(game, s, other.p, "xg_battle", function() end)
    ok(waitReal(function() return s.activity ~= nil end, 30), "the guest accepts over the live relay")
    ok(waitReal(function() return s.activity and (s.activity.state == "ready" or s.activity.state == "done") end, 20),
      "the prep resolves")
    local prep = s.activity and s.activity.prep
    print(("host prep state %s rules %s blocked %s"):format(tostring(prep and prep.state),
      tostring(prep and prep.rules and prep.rules.ruleset), tostring(prep and prep.blocked)))
    ok(s.activity and s.activity.state == "ready", "the host reaches the getting-ready line")
    waitReal(function() return top() and top().tick ~= nil end, 10)
    shot("02_ready")
    waitReal(function() return false end, 2)
    tap("b")
    ok(waitReal(function() return top() and top().pages ~= nil end, 10), "cancel shows a line")
    shot("03_cancelled")
  else
    ok(waitReal(function() return s.busy end, 40), "the host's invite reaches the guest")
    for _ = 1, 400 do
      if top() and getmetatable(top()) == require("src.ui.ChoiceBox") then break end
      tap("a")
    end
    shot("02_prompt")
    tap("a")
    ok(waitReal(function() return s.activity and s.activity.state == "ready" end, 30),
      "the guest reaches the getting-ready line")
    ok(waitReal(function() return s.activity == nil or s.activity.state == "done" end, 40),
      "the host's cancel reaches the guest")
    waitReal(function() return top() and top().pages ~= nil end, 10)
    shot("03_peer_cancelled")
  end
  waitReal(function() return false end, 3)
  done()
end
