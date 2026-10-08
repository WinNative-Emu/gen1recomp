local U = require("tests.drivers.util")
local GameVersion = require("src.core.GameVersion")

local ROLE = os.getenv("G3U_ROLE") or "low"
local NAME = os.getenv("G3U_NAME") or (ROLE == "low" and "LOWBOY" or "HIGHGAL")
local PEER = os.getenv("G3U_PEER") or (ROLE == "low" and "HIGHGAL" or "LOWBOY")
local SHOT_DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/g3u-relay"
local LIMIT = tonumber(os.getenv("G3U_SECONDS") or "") or 240

local SPECS = {
  { n = 25, moves = { 85, 87 } },
  { n = 65, moves = { 94, 85 } },
}

local function now() return love.timer.getTime() end

return function(game)
  local version = GameVersion.get()
  local gen = GameVersion.generation(version)
  local fails = 0
  local function ok(cond, line)
    if not cond then fails = fails + 1 end
    print((cond and "PASS " or "FAIL ") .. "[" .. ROLE .. "/" .. version .. "] " .. line)
    return cond
  end
  local Client = require("src.online.Client")
  local function finish()
    pcall(Client.leaveRoom)
    pcall(Client.disconnect)
    print((fails == 0 and "PASS" or "FAIL") .. " g3u_relay_xgen role=" .. ROLE .. " fails=" .. fails)
    love.event.quit(fails == 0 and 0 or 1)
    coroutine.yield()
  end
  local function waitFor(cond, seconds, onFrame)
    local t0 = now()
    while not cond() do
      if onFrame then onFrame() end
      U.wait(1)
      if now() - t0 > seconds then return false end
    end
    return true
  end
  local function shot(name)
    U.still(game, ("%s/%s_%s_%s.png"):format(SHOT_DIR, ROLE, version, name))
  end

  local playerName, trainerId = NAME, 4321
  if gen == 3 then
    for _ = 1, 900 do
      if game.phase == "boot" and game.boot then break end
      U.wait(1)
    end
    game:_handleBootAction({ action = "new_game", name = NAME })
    U.wait(240)
    local session = require("src.core.game3.runtime").getSession()
    session.name = NAME
  else
    if not ok(U.newGame(game), "reached the overworld") then return finish() end
    game.save.player.name = NAME
  end

  local Datasets = require("src.online.xgen.Datasets")
  local Project = require("src.online.xgen.Project")
  local Policy = require("src.online.xgen.Policy")
  local data = Datasets.get(version)
  if not ok(data ~= nil, "own dataset loaded") then return finish() end
  local records = {}
  for _, spec in ipairs(SPECS) do
    local base = data.species[spec.n].base
    local iv = { hp = 31, atk = 31, def = 31, spe = 31, spa = 31, spd = 31 }
    local ev = { hp = 0, atk = 0, def = 0, spe = 0, spa = 0, spd = 0 }
    local st = Project.stats3(base, 50, iv, ev, 0, spec.n)
    local moves = {}
    for i, id in ipairs(spec.moves) do moves[i] = { id = id, pp = Policy.maxPp(data.moves[id].pp, 0), ppUps = 0 } end
    records[#records + 1] = { species = spec.n, level = 50, hp = st.hp, maxHp = st.hp, atk = st.atk, def = st.def,
      spAtk = st.spa, spDef = st.spd, speed = st.spe, moves = moves, ivs = iv, gender = 2, friendship = 70 }
  end

  Client.connect({ name = NAME })
  if not ok(waitFor(function() return Client.state() == "online" end, 20), "online on the local relay") then
    print("[driver] state=" .. tostring(Client.state()) .. " err=" .. tostring(Client.error()))
    return finish()
  end
  local Room = require("src.online.union.Room")
  local room = Room.new({ client = Client })
  local joined, jerr = room:join({ version = version, game = game, name = playerName, trainerId = trainerId,
    gender = 0, style = gen == 3 and "g3:0" or "player" })
  ok(joined, "plaza join sent " .. tostring(jerr and jerr.error))
  local function pump() Client.update(0) room:poll() end
  if not ok(waitFor(function() pump() return room.state == "joined" end, 20), "joined the union plaza") then
    print("[driver] room err=" .. tostring(room.err and room.err.error) .. " " .. tostring(room.err and room.err.detail))
    return finish()
  end

  local peer
  ok(waitFor(function()
    pump()
    for _, p in ipairs(room:members()) do
      if p.name == PEER then peer = p end
    end
    return peer ~= nil
  end, 60), "peer " .. PEER .. " is in the room")
  if not peer then return finish() end

  Client.on("invite_closed", function(m)
    print("[driver] invite_closed why=" .. tostring(m and m.why) .. " detail=" .. tostring(m and m.detail))
  end)
  if ROLE == "low" then
    local tries, last = 0, -10
    ok(waitFor(function()
      pump()
      if room:xgRoom() then return true end
      local busy = false
      for _, o in ipairs(Client.outgoing() or {}) do
        if o.state == "pending" or o.state == "sent" then busy = true end
      end
      if not busy and now() - last > 3 and tries < 8 then
        tries, last = tries + 1, now()
        local h, w = room:invite(peer, "xg_battle")
        print("[driver] invite try " .. tries .. " -> " .. tostring(h ~= nil) .. " " .. tostring(w))
      end
      return false
    end, 60), "peer accepted the invite")
  else
    local inv
    ok(waitFor(function()
      pump()
      for _, i in ipairs(room:incoming()) do if i.mode == "battle" then inv = i end end
      return inv ~= nil
    end, 60), "xg_battle invite arrived")
    if not inv then return finish() end
    room:reply(inv.id, true)
  end
  if not ok(waitFor(function() pump() return room:xgRoom() ~= nil end, 30), "entered the xg prep room") then
    return finish()
  end
  local prep = room:prep()
  prep:sendCaps(room.caps)
  local digest = (ROLE == "low") and "0123456789abcdef" or "fedcba9876543210"
  local sentRoster, sentReady = false, false
  local go
  ok(waitFor(function()
    pump()
    for _, e in ipairs(prep:poll()) do
      if e.kind == "go" then go = e.go end
      if e.kind == "invalidated" then sentReady = false end
      if e.kind == "nack" then
        print("[driver] nack " .. tostring(e.of) .. " " .. tostring(e.why))
        if e.of == "xg_roster" then sentRoster = false end
        if e.of == "xg_ready" then sentReady = false end
      end
    end
    if prep.state == "prep" and not sentRoster then
      sentRoster = prep:roster(#records, digest)
    end
    if prep:canReady() and not sentReady and not prep.mine.ready then
      sentReady = prep:ready(digest)
    end
    return go ~= nil or prep.state == "closed" or prep.state == "blocked"
  end, 60), "prep reached xg_go")
  print("[driver] prep state=" .. tostring(prep.state) .. " blocked=" .. tostring(prep.blocked)
    .. " ruleset=" .. tostring(go and go.ruleset))
  if not go then return finish() end
  ok(go.ruleset == "g3u", "cross-gen battle resolves to g3u")

  local xg = Client.room() and Client.room().xg or {}
  local gl = xg.gens or {}
  local gens = { [0] = tonumber(gl[1]), [1] = tonumber(gl[2]) }
  local seat = Client.seat()
  local names = { [seat] = NAME, [1 - seat] = PEER }
  local result
  local Launch = require("src.ui.g3u.Launch")
  local handle, why = Launch.start(game, gen, {
    ruleset = "g3u", net = Client.roomSession(), seat = seat, go = go, gens = gens, names = names,
    records = records, client = Client, roomId = Client.room() and Client.room().room,
    onDone = function(r) result = r end,
  })
  if not ok(handle ~= nil, "Launch.start " .. tostring(why)) then return finish() end
  local bs = handle.bs
  local shots = {}
  local t0 = now()
  local k = 0
  while not result and now() - t0 < LIMIT do
    k = k + 1
    Client.update(0)
    if bs.match and not shots.start then shots.start = true U.wait(30) shot("01_start") end
    if bs.match and bs.match.turn >= 2 and not shots.mid then shots.mid = true shot("02_turn2") end
    if bs.phase == "replace" and k % 18 == 6 then
      U.tap(game, gen == 3 and "right" or "down")
    elseif k % 6 == 0 then
      U.tap(game, "a")
    else
      U.wait(1)
    end
    if bs.phase == "replace" and not shots.replace then shots.replace = true U.wait(20) shot("02b_replace") end
  end
  ok(result ~= nil, "battle ended inside " .. LIMIT .. "s")
  local turn = bs.match and bs.match.turn or -1
  print(("[driver] RESULT role=%s seat=%d outcome=%s why=%s turns=%d hash=%s"):format(ROLE, seat,
    tostring(result and result.outcome), tostring(result and result.why), turn,
    tostring(bs.myHashes[turn])))
  ok(result and (result.why == "faint" or result.why == "forfeit"), "battle decided by the game, not the link")
  U.wait(60)
  shot("03_after")
  return finish()
end
