package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")
local T = require("tests.harness")
local F = require("tests.engine._g3u_fixture")
local L = require("tests.support.g3u_loopback")
local Table = require("src.battle.g3u.Table")
local BS = require("src.online.union.BattleSession")

local function deep(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for k, v in pairs(a) do if not deep(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

local function copy(v)
  if type(v) ~= "table" then return v end
  local o = {}
  for k, x in pairs(v) do o[k] = copy(x) end
  return o
end

local DATA = { [1] = F.gen1(), [2] = F.gen2() }
local TABLES = { [1] = assert(Table.build(DATA[1], 1)), [2] = assert(Table.build(DATA[2], 2)) }

local function clockFn()
  local c = { t = 0 }
  c.fn = function() return c.t end
  return c
end

local function setup(o)
  o = o or {}
  local gen = o.gen or 1
  local t = TABLES[gen]
  local rnd = L.lcg(o.seed or 1)
  local recs = { [0] = o.p0 or F.randomParty(t, rnd, o.size0 or 3), [1] = o.p1 or F.randomParty(t, rnd, o.size1 or 3) }
  local gens = o.gens or { [0] = gen, [1] = 3 }
  local lower = BS.lowerSeat(gens)
  local na, nb = L.pair()
  local clock = o.clock or clockFn()
  local reports = { [0] = {}, [1] = {} }
  local function client(seat)
    return { report = function(w) reports[seat][#reports[seat] + 1] = w end }
  end
  if o.beforeNew then o.beforeNew(na, nb) end
  local go = { seed = o.goSeed or 4242, size = o.goSize or 6 }
  local a = BS.new({ net = na, seat = 0, go = go, gens = gens, data = lower == 0 and DATA[gen] or nil,
    records = recs[0], names = { [0] = "RED", [1] = "MAY" }, client = client(0), now = clock.fn })
  local b = BS.new({ net = nb, seat = 1, go = go, gens = gens, data = lower == 1 and DATA[gen] or nil,
    records = recs[1], names = { [0] = "RED", [1] = "MAY" }, client = client(1), now = clock.fn })
  return { a = a, b = b, na = na, nb = nb, recs = recs, clock = clock, reports = reports, t = t }
end

local function run(s, o)
  o = o or {}
  local ba = L.bot(s.a, { seed = (o.seed or 1) * 3 + 1, switches = o.switches })
  local bb = L.bot(s.b, { seed = (o.seed or 1) * 5 + 2, switches = o.switches })
  local order = L.lcg((o.seed or 1) + 77)
  for _ = 1, o.steps or 4000 do
    if order(2) == 1 then ba() bb() else bb() ba() end
    if o.each then o.each(s) end
    if s.a.result and s.b.result then return true end
    s.clock.t = s.clock.t + (o.dt or 0.01)
  end
  return false
end

local MIRROR = { win = "lose", lose = "win", draw = "draw" }

do
  local ok, turns = 0, 0
  for seed = 1, 24 do
    local gen = (seed % 3 == 0) and 2 or 1
    local s = setup({ gen = gen, seed = seed, size0 = 1 + seed % 3, size1 = 1 + (seed * 7) % 3 })
    local done = run(s, { seed = seed, switches = seed % 2 == 0 })
    local ra, rb = s.a.result, s.b.result
    local good = done and ra and rb and MIRROR[ra.outcome] == rb.outcome and ra.why == rb.why
      and ra.why == "faint" and s.a.match.turn == s.b.match.turn
    for turn = 0, s.a.match.turn do
      if s.a.myHashes[turn] ~= s.b.myHashes[turn] then good = false end
    end
    good = good and #s.reports[0] == 1 and #s.reports[1] == 1
      and MIRROR[s.reports[0][1]] == s.reports[1][1]
    if good then ok = ok + 1 end
    turns = turns + (s.a.match and s.a.match.turn or 0)
    if not good then
      T.check(false, ("battle seed %d: done=%s a=%s/%s b=%s/%s"):format(seed, tostring(done),
        tostring(ra and ra.outcome), tostring(ra and ra.why), tostring(rb and rb.outcome),
        tostring(rb and rb.why)))
    end
  end
  T.eq(ok, 24, "24 loopback battles end on faint with mirrored results, hashes and reports")
  T.check(turns > 24 * 3, "battles run several turns each (" .. turns .. ")")
end

do
  local s = setup({ gen = 2, seed = 9, gens = { [0] = 3, [1] = 2 } })
  T.check(s.b:isLower() and not s.a:isLower(), "seat with the lower gen builds the table")
  T.eq(#s.nb.sent >= 2 and s.nb.sent[1].type, "g3u_table", "lower seat sends g3u_table first")
  T.check(s.na.sent[1].type == "g3u_party", "higher seat sends only its party")
  T.check(run(s, { seed = 9 }), "battle with the table from seat 1 finishes")
  T.eq(s.a.result.why, "faint", "seat 1 table battle ends on faint")
end

do
  local s = setup({ seed = 3 })
  run(s, { seed = 3 })
  local evs = s.a:events()
  local kinds, firstReady, lastOver = {}, nil, nil
  for i, e in ipairs(evs) do
    kinds[e.kind] = (kinds[e.kind] or 0) + 1
    if e.kind == "ready" and not firstReady then firstReady = i end
    if e.kind == "over" then lastOver = i end
  end
  T.eq(firstReady, 1, "ready is the first event")
  T.eq(lastOver, #evs, "over is the last event")
  T.eq(kinds.over, 1, "exactly one over event")
  for _, k in ipairs({ "sendout", "move", "hp", "msg", "faint", "prompt", "end" }) do
    T.check((kinds[k] or 0) > 0, "event stream carries " .. k)
  end
  T.eq(s.a:side(0), "me", "side(mySeat) is me")
  T.eq(s.a:side(1), "foe", "side(peer) is foe")
  T.eq(#s.a:legal(), 0, "no legal actions once over")
end

do
  local saw = false
  for seed = 1, 10 do
    local s = setup({ seed = seed, size0 = 3, size1 = 3 })
    run(s, { seed = seed, each = function(x)
      for _, side in ipairs({ x.a, x.b }) do
        if side.phase == "replace" then saw = true end
      end
    end })
    if saw then break end
  end
  T.check(saw, "a faint with mons left reaches the replace phase")
end

do
  local s = setup({ seed = 5 })
  for _ = 1, 20 do s.a:update() s.b:update() end
  T.eq(s.a.phase, "choose", "seat 0 reaches choose")
  T.check(s.a:forfeit(), "forfeit in choose is accepted")
  local legal = s.b:legal()
  s.b:choose(legal[1])
  for _ = 1, 20 do s.a:update() s.b:update() s.clock.t = s.clock.t + 1 end
  T.eq(s.a.result and s.a.result.outcome, "lose", "forfeiter loses")
  T.eq(s.b.result and s.b.result.outcome, "win", "opponent wins on forfeit")
  T.eq(s.a.result and s.a.result.why, "forfeit", "why forfeit")
  T.eq(s.reports[0][1], "lose", "forfeiter reports lose")
  T.eq(s.reports[1][1], "win", "opponent reports win")
end

do
  local s = setup({ seed = 6 })
  for _ = 1, 20 do s.a:update() s.b:update() end
  s.a:choose(s.a:legal()[1])
  T.eq(s.a.phase, "wait", "seat 0 waits for the peer")
  T.check(s.a:forfeit(), "forfeit while waiting")
  s.b:update()
  T.eq(s.a.result.outcome, "lose", "waiting forfeiter loses")
  T.eq(s.b.result and s.b.result.outcome, "win", "bye forfeit gives the peer the win")
end

do
  local s = setup({ seed = 7 })
  s.b.tamperHash = function(turn, h)
    if turn == 2 then return (h:sub(1, 7) .. (h:sub(8, 8) == "0" and "1" or "0")) end
    return h
  end
  run(s, { seed = 7 })
  T.eq(s.a.result.why, "desync", "tampered hash ends seat 0 with desync")
  T.eq(s.b.result.why, "desync", "tampered hash ends seat 1 with desync")
  T.eq(s.a.result.outcome, "draw", "desync is a draw")
  T.eq(s.a.result.detail, 2, "desync names the turn")
  T.eq(s.reports[0][1], "draw", "desync reports draw")
end

local function tableTamper(fn)
  return function(na)
    na.tamper = function(m)
      if m.type == "g3u_table" then fn(m.table) end
      return m
    end
  end
end

for label, fn in pairs({
  effect = function(t) t.moves[1][5] = 250 end,
  power = function(t) t.moves[33][1] = 999 end,
  extra = function(t) t.extra = 1 end,
  species_type = function(t) t.species[25][1] = 17 end,
  short = function(t) t.species[151] = nil end,
  version = function(t) t.v = 2 end,
}) do
  local s = setup({ seed = 11, beforeNew = tableTamper(fn) })
  for _ = 1, 10 do s.a:update() s.b:update() end
  T.eq(s.b.result and s.b.result.why, "bad_table", "receiver rejects table (" .. label .. ")")
  T.eq(s.a.result and s.a.result.why, "bad_table", "sender learns the table was rejected (" .. label .. ")")
  T.check(s.b.match == nil, "no match starts on a bad table (" .. label .. ")")
end

do
  local s = setup({ seed = 12, beforeNew = function(na)
    na.tamper = function(m)
      if m.type == "g3u_table" then m.table = copy(TABLES[2]) end
      return m
    end
  end })
  for _ = 1, 10 do s.a:update() s.b:update() end
  T.eq(s.b.result and s.b.result.why, "bad_table", "a Gen 2 table in a Gen 1 match is refused")
end

do
  local s = setup({ seed = 13 })
  s.nb:send({ type = "g3u_table", table = TABLES[1] })
  for _ = 1, 10 do s.a:update() s.b:update() end
  T.eq(s.a.result and s.a.result.why, "bad_table", "a table from the higher seat is refused")
end

local function partyCase(label, mutate, extraOpts)
  local o = { seed = 14 }
  for k, v in pairs(extraOpts or {}) do o[k] = v end
  o.beforeNew = function(_, nb)
    nb.tamper = function(m)
      if m.type == "g3u_party" then mutate(m.records) end
      return m
    end
  end
  local s = setup(o)
  for _ = 1, 10 do s.a:update() s.b:update() end
  T.eq(s.a.result and s.a.result.why, "bad_party", "receiver rejects party (" .. label .. ")")
  T.eq(s.b.result and s.b.result.why, "bad_party", "sender learns the party was rejected (" .. label .. ")")
end

partyCase("atk above level range", function(r) r[1].atk = r[1].atk + 200 end)
partyCase("speed below level range", function(r) r[1].speed = 1 end)
partyCase("maxHp above range", function(r) r[1].maxHp = r[1].maxHp + 150 r[1].hp = r[1].maxHp end)
partyCase("hp not full", function(r) r[1].hp = r[1].maxHp - 1 end)
partyCase("species out of dex", function(r) r[1].species = 152 end)
partyCase("unknown key", function(r) r[1].ability = 5 end)
partyCase("pp above max", function(r) r[1].moves[1].pp = 63 end)
partyCase("duplicate move", function(r) r[1].moves[2] = copy(r[1].moves[1]) end)
partyCase("bad level", function(r) r[1].level = 101 end)
partyCase("too many for go.size", function(r) r[#r + 1] = copy(r[1]) end, { goSize = 3, size1 = 3 })
partyCase("empty", function(r) for i = #r, 1, -1 do r[i] = nil end end)

do
  local t = TABLES[1]
  local rec = F.record(t, 25, { 84, 85 }, 50)
  T.check(BS.checkParty({ rec }, t), "a table-derived record passes the bounds check")
  local hi = copy(rec)
  hi.spAtk = rec.spAtk + 60
  T.check(not BS.checkParty({ hi }, t, { senderGen = 1 }), "Gen 1 sender SpA is held to the Special base")
  T.check(BS.checkParty({ hi }, t, { senderGen = 2 }), "Gen 2 sender SpA vs a Gen 1 table uses the loose cap")
  hi.atk = rec.atk + 100
  T.check(not BS.checkParty({ hi }, t, { senderGen = 2 }), "non-special stats stay bounded for every sender")
end

do
  local t = TABLES[1]
  local rec = F.record(t, 25, { 84, 85 }, 50)
  local mon = copy(rec)
  mon.national, mon.ability, mon.item, mon.nature, mon.shiny, mon.sourceGen = 25, 0, 0, 0, false, 1
  mon.evs, mon.gender, mon.unownLetter = { hp = 0, atk = 0, def = 0, spe = 0, spa = 0, spd = 0 }, "female", nil
  mon.moves[1].name, mon.moves[1].maxPp = "THUNDERSHOCK", rec.moves[1].pp
  local w = BS.wireRecord(mon)
  T.check(BS.checkParty({ w }, t), "a prep battleMon record converts to a valid wire record")
  T.eq(w.gender, 1, "string gender maps to the wire code")
  T.check(w.ability == nil and w.evs == nil and w.national == nil, "prep-only fields stay off the wire")
end

do
  local t = TABLES[1]
  local own = F.record(t, 65, { 94 }, 50)
  own.spDef = own.spDef - 40
  local s = setup({ seed = 26, p1 = { own } })
  for _ = 1, 10 do s.a:update() s.b:update() end
  T.check(s.b.result == nil and s.b.match ~= nil, "a Gen 3 seat's SpD below the Gen 1 Special range is not refused by itself")
  T.check(s.a.result == nil and s.a.match ~= nil, "and the Gen 1 receiver accepts it")
end

do
  local t = TABLES[1]
  local bad = { F.record(t, 25, { 84 }, 50, { atk = 999 }) }
  local s = setup({ seed = 15, p0 = bad })
  T.eq(s.a.result and s.a.result.why, "bad_party", "own invalid party never starts")
  T.check(#s.na.sent == 1 and s.na.sent[1].type == "g3u_bye", "only a bye goes out for an invalid own party")
end

do
  local t = TABLES[1]
  local s = setup({ seed = 16, p0 = { F.record(t, 25, { 84, 85 }, 50) }, p1 = { F.record(t, 6, { 33 }, 50) } })
  for _ = 1, 10 do s.a:update() s.b:update() end
  s.nb:send({ type = "g3u_action", turn = 1, kind = "move", slot = 4 })
  s.a:update()
  T.eq(s.a.result and s.a.result.why, "illegal", "a move slot the mon does not have is illegal")
  s.b:update()
  T.eq(s.b.result and s.b.result.why, "illegal", "peer learns its action was refused")
end

do
  local s = setup({ seed = 17 })
  for _ = 1, 10 do s.a:update() s.b:update() end
  s.nb:send({ type = "g3u_action", turn = 3, kind = "move", slot = 1 })
  s.a:update()
  T.eq(s.a.result and s.a.result.why, "illegal", "an action for a future turn is illegal")
end

do
  local s = setup({ seed = 18 })
  for _ = 1, 10 do s.a:update() s.b:update() end
  s.nb:send({ type = "g3u_action", turn = 1, kind = "move", slot = 1, extra = true })
  s.a:update()
  T.eq(s.a.result and s.a.result.why, "illegal", "unknown keys in an action are refused")
end

do
  local s = setup({ seed = 19 })
  for _ = 1, 10 do s.a:update() s.b:update() end
  s.na.closed = true
  s.a:update()
  T.eq(s.a.result and s.a.result.why, "disconnect", "closed session ends as disconnect")
  T.eq(#s.reports[0], 0, "a disconnect sends no report (relay settles it)")
end

do
  local s = setup({ seed = 20 })
  for _ = 1, 10 do s.a:update() s.b:update() end
  s.nb.online = false
  s.a:update()
  s.clock.t = s.clock.t + BS.PEER_GONE - 1
  s.a:update()
  T.check(s.a.result == nil, "a short peer outage keeps the battle")
  s.nb.online = true
  s.a:update()
  s.clock.t = s.clock.t + BS.PEER_GONE + 5
  s.a:update()
  T.check(s.a.result == nil, "peer back online resets the outage clock")
  s.nb.online = false
  s.a:update()
  s.clock.t = s.clock.t + BS.PEER_GONE + 1
  s.a:update()
  T.eq(s.a.result and s.a.result.why, "disconnect", "peer gone past the window ends as disconnect")
end

do
  local s = setup({ seed = 21 })
  local state = "ok"
  s.a.linkState = function() return state end
  for _ = 1, 10 do s.a:update() s.b:update() end
  s.na.hold = true
  s.a:choose(s.a:legal()[1])
  state = "resuming"
  s.a:update()
  s.clock.t = s.clock.t + 30
  s.a:update()
  T.check(s.a.result == nil, "own resume inside the window keeps the battle")
  state = "ok"
  s.na.hold = false
  s.na:flush()
  run(s, { seed = 21 })
  T.eq(s.a.result.why, "faint", "battle resumes after the replayed messages")
  T.eq(s.b.result.why, "faint", "peer finishes after the replay")
end

do
  local s = setup({ seed = 22 })
  local state = "ok"
  s.a.linkState = function() return state end
  for _ = 1, 10 do s.a:update() s.b:update() end
  state = "resuming"
  s.a:update()
  s.clock.t = s.clock.t + BS.RESUME_WINDOW + 1
  s.a:update()
  T.eq(s.a.result and s.a.result.why, "disconnect", "resume past the window ends as disconnect")
end

do
  local na = L.pair()
  local clock = clockFn()
  local a = BS.new({ net = na, seat = 0, go = { seed = 1 }, gens = { [0] = 1, [1] = 3 }, data = DATA[1],
    records = F.randomParty(TABLES[1], L.lcg(1), 2), now = clock.fn })
  a:update()
  clock.t = BS.SETUP_TIMEOUT + 1
  a:update()
  T.eq(a.result and a.result.why, "disconnect", "no party from the peer ends the setup as disconnect")
end

do
  local s = setup({ seed = 23 })
  for _ = 1, 10 do s.a:update() s.b:update() end
  s.nb:send({ type = "xg_closed", why = "gone" })
  s.a:update()
  T.eq(s.a.result and s.a.result.why, "disconnect", "xg_closed during a battle ends as disconnect")
end

do
  local s = setup({ seed = 24 })
  local state = "ok"
  s.a.linkState = function() return state end
  s.nb.dropAll = false
  run(s, { seed = 24, each = function(x)
    if x.b.result and not x.a.result and x.a.phase == "ending" then state = "gone" end
  end })
  T.check(s.a.result and s.a.result.why ~= "disconnect", "room closing after the last turn keeps the faint result")
end

do
  local writes = 0
  local realOpen = io.open
  io.open = function(path, mode)
    if mode and mode:find("[wa+]") then writes = writes + 1 end
    return realOpen(path, mode)
  end
  local fs = love.filesystem
  local realWrite, realAppend = fs.write, fs.append
  fs.write = function(...) writes = writes + 1 return realWrite(...) end
  fs.append = function(...) writes = writes + 1 return realAppend and realAppend(...) end
  local okSD, SaveData = pcall(require, "src.core.SaveData")
  local realSave = okSD and SaveData.save or nil
  if realSave then SaveData.save = function(...) writes = writes + 1 return realSave(...) end end
  local s = setup({ seed = 25, size0 = 3, size1 = 3 })
  local before = { copy(s.recs[0]), copy(s.recs[1]) }
  local done = run(s, { seed = 25 })
  io.open = realOpen
  fs.write, fs.append = realWrite, realAppend
  if realSave then SaveData.save = realSave end
  T.check(done, "save-watch battle finishes")
  T.eq(writes, 0, "a full g3u battle writes no file and no save")
  T.check(deep(before[1], s.recs[0]) and deep(before[2], s.recs[1]), "battle records are untouched by the match")
end

T.finish("union_battle_session")
