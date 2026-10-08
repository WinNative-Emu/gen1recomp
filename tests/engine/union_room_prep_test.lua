package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")
local T = require("tests.harness")
local FakeRelay = require("tests.support.fake_relay")
local Participant = require("src.online.union.Participant")
local Room = require("src.online.union.Room")
local Prep = require("src.online.union.Prep")

local CLOCK = 0
love.timer.getTime = function() return CLOCK end

local function pid(n) return ("%08x"):format(n) end
local D1, D2, D3 = "00000000000000a1", "00000000000000b2", "00000000000000c3"

local FP = { red = "1111111111111111", yellow = "2222222222222222", gold = "3333333333333333",
             emerald = "6666666666666666", firered = "5555555555555555" }

local function ctxFor(version, name, tid)
  local gen = Participant.genOf(version)
  return { version = version, name = name, trainerId = tid, gender = 0,
           profile = { engine = gen, version = version, engineVersion = "0.0.0-dev", apiVersion = 2,
                       fingerprint = FP[version], rulesetId = gen == 3 and "g3_single" or "union",
                       kind = "vanilla" },
           vanillaFingerprint = FP[version], gameplayMods = false }
end

local function world()
  local w = { relay = FakeRelay.new({ clock = function() return CLOCK end }), clients = {}, rooms = {}, seats = {} }
  function w:add(n, name)
    local seat = self.relay:seat(pid(n), name)
    package.loaded["src.online.Client"] = nil
    local C = require("src.online.Client")
    C.reset()
    C.configure({ relayAddress = "fake:3", connect = function() return seat.transport end })
    C.connect({ name = name, profiles = {} })
    self.clients[#self.clients + 1] = C
    self.seats[#self.seats + 1] = seat
    local r = Room.new({ client = C })
    self.rooms[#self.rooms + 1] = r
    return r, C, seat
  end
  function w:pump(rounds)
    for _ = 1, rounds or 4 do
      self.relay:pump()
      for _, C in ipairs(self.clients) do C.update(0) end
    end
  end
  return w
end

local function pair(va, vb, activity)
  local w = world()
  local ra, ca, sa = w:add(1, "A")
  local rb, cb, sb = w:add(2, "B")
  w:pump()
  ra:join(ctxFor(va, "A", 1))
  rb:join(ctxFor(vb, "B", 2))
  w:pump()
  ra:poll(); rb:poll()
  ra:invite(pid(2), activity)
  w:pump()
  rb:reply(rb:incoming()[1].id, true)
  w:pump()
  local pa, pb = ra:prep(), rb:prep()
  return w, pa, pb, { ra = ra, rb = rb, ca = ca, cb = cb, sa = sa, sb = sb }
end

local function kinds(events)
  local out = {}
  for _, e in ipairs(events) do out[#out + 1] = e.kind end
  return table.concat(out, ",")
end

local function has(events, kind, pred)
  for _, e in ipairs(events) do
    if e.kind == kind and (pred == nil or pred(e)) then return e end
  end
  return nil
end

do
  local w, pa, pb = pair("red", "emerald", "xg_battle")
  T.check(pa ~= nil and pb ~= nil, "both seats get a prep")
  local ea = pa:poll()
  pb:poll()
  T.check(has(ea, "rules") ~= nil, "rules arrive right after accept from plaza caps (" .. kinds(ea) .. ")")
  T.eq(pa.rules.ruleset, "g3u", "Gen 1 vs Gen 3 resolves g3u")
  T.eq(pa.rules.dexMax, 151, "g3u dex is the lower gen's")
  T.eq(pa.rev, 1, "the rules bump the rev to 1")
  T.eq(pa.state, "prep", "the prep is open")
  T.check(not pa:canReady(), "no ready before rosters")
  T.check(pa:roster(3, D1), "seat 0 sends a roster")
  w:pump()
  local eb = pb:poll()
  pa:poll()
  T.eq(pb.peer.roster.size, 3, "the peer roster is seen")
  T.eq(pb.rev, 2, "the roster bumps the rev")
  T.eq(pa.rev, 2, "the sender learns the new rev from xg_rev")
  T.eq(pa.mine.roster and pa.mine.roster.size, 3, "xg_rev confirms the sender's roster")
  T.check(has(eb, "peer_roster") ~= nil, "a peer_roster event fires")
  pb:roster(5, D2)
  w:pump()
  pa:poll(); pb:poll()
  T.eq(pa.size, 3, "two rosters give xg_size = the smaller")
  T.eq(pa.rev, 3, "the second roster bumps to 3")
  T.check(pa:canReady(), "ready is allowed with rules and a size")
  pa:ready(D1)
  w:pump()
  pb:poll()
  T.check(pb.peer.ready ~= nil, "the peer's ready is seen at the current rev")
  pa:sizeRequest(2)
  w:pump()
  local ea2 = pa:poll()
  pb:poll()
  T.eq(pa.mine.ready, nil, "a later change clears my ready")
  T.eq(pb.peer.ready, nil, "a later change clears the peer ready")
  T.check(pa:ackInvalidated(), "the invalidation is surfaced")
  T.check(has(ea2, "rev") ~= nil, "a rev event fires")

  local stale = pb.rev
  pa:roster(2, D3)
  w:pump(1)
  w.relay:pump()
  pb.rev = stale
  pb.session.send(require("src.online.Protocol2").xgRoster(stale - 1, 2, D2))
  w:pump()
  local ebn = pb:poll()
  local nack = has(ebn, "nack")
  T.check(nack ~= nil and nack.why == "stale_rev" and nack.of == "xg_roster", "a stale roster is nacked stale_rev")
  T.eq(pb.rev, w.relay.rooms[w.clients[1].room().room].xg.rev, "the nack refreshes the rev to the relay's")
  T.check(pb.invalidated, "a stale nack surfaces invalidated")
  pa:poll()
  T.eq(pa.rev, pb.rev, "both seats agree on the rev")

  pa:ready(D1)
  pb:ready(D2)
  w:pump()
  local ga, gb = pa:poll(), pb:poll()
  local go = has(ga, "go")
  T.check(go ~= nil, "both ready on the same rev gives xg_go")
  T.eq(pa.state, "go", "seat 0 is in go")
  T.eq(pb.state, "go", "seat 1 is in go")
  T.eq(go.go.ruleset, "g3u", "xg_go carries the ruleset")
  T.eq(go.go.size, 2, "xg_go carries the agreed size")
  T.eq(go.go.dexMax, 151, "xg_go carries the dex limit")
  T.eq(pa.go.seed, pb.go.seed, "both seats get the same seed")
  T.check(has(gb, "go") ~= nil, "seat 1 sees xg_go")
end

do
  local w, pa, pb = pair("red", "gold", "xg_battle")
  pa:poll(); pb:poll()
  pb:cancel("changed my mind")
  w:pump()
  local ea = pa:poll()
  local closed = has(ea, "closed")
  T.check(closed ~= nil, "a cancel closes the peer's prep")
  T.eq(closed and closed.why, "cancel", "the close says cancel")
  T.eq(closed and closed.seat, 1, "the close names the cancelling seat")
  T.eq(pa.state, "closed", "the prep is closed")
  T.check(w.clients[1].room() == nil, "the client left the closed room")
  T.check(not pa:roster(1, D1), "a closed prep sends nothing")
end

do
  local w, pa, pb, x = pair("red", "gold", "xg_battle")
  pa:poll(); pb:poll()
  pa:roster(4, D1)
  w:pump()
  pa:poll(); pb:poll()
  pb:roster(6, D2)
  w:pump(1)
  w.relay:drop(x.sa)
  w:pump()
  w.relay:reconnect(x.sa)
  CLOCK = CLOCK + 2
  w:pump(6)
  local ev = pa:poll()
  T.check(has(ev, "snapshot") ~= nil, "a resume re-applies the room_state snapshot")
  local relayRev = w.relay.rooms[w.clients[1].room().room].xg.rev
  T.eq(pa.rev, relayRev, "the resumed prep has the relay's rev")
  T.eq(pa.peer.roster and pa.peer.roster.size, 6, "the resumed prep has the peer roster")
  T.eq(pa.mine.roster and pa.mine.roster.size, 4, "the resumed prep has its own roster")
  T.eq(pa.size, 4, "the resumed prep has the agreed size")
  T.eq(pa.state, "prep", "the resumed prep is still open")
end

do
  local w, pa, pb = pair("firered", "red", "xg_trade")
  pa:poll(); pb:poll()
  T.eq(pa.rules and pa.rules.mode, "trade", "trade rules arrive")
  T.check(not pa:roster(1, D1), "rosters are battle only")
  pa:offer({ species = 25, level = 12, nickname = "PIKACHU" }, D3)
  pb:offer({ species = 1, level = 5 }, D3)
  w:pump()
  pa:poll()
  local raced = pb:poll()
  T.check(has(raced, "nack", function(e) return e.why == "stale_rev" and e.of == "xg_offer" end) ~= nil,
    "two offers on one rev: the later one is nacked stale_rev")
  T.eq(pb.mine.offer, nil, "the nacked offer is not counted")
  pb:offer({ species = 1, level = 5 }, D3)
  w:pump()
  pa:poll(); pb:poll()
  T.eq(pb.offerRev, 2, "a re-sent offer takes the next offerRev")
  T.eq(pb.peer.offer.payload.species, 25, "the offer payload reaches the peer")
  T.eq(pa.offerRev, 1, "offerRev starts at 1")
  T.check(pa:canReady(), "both offers allow ready")
  pa:ready(D1)
  pb:ready(D2)
  w:pump()
  local ea = pa:poll()
  pb:poll()
  local nack = has(ea, "nack")
  T.check(nack ~= nil and nack.why == "digest", "different trade digests are nacked digest")
  T.check(pa.invalidated and pa.mine.ready == nil, "a digest nack clears ready")
  pa:ready(D3)
  pb:ready(D3)
  w:pump()
  pa:poll(); pb:poll()
  T.eq(pa.state, "go", "agreed digests give xg_go")
  T.eq(pa.go.ruleset, "trade", "the go is a trade")
  local Protocol2 = require("src.online.Protocol2")
  w.clients[1].roomSession():send({ type = "trade_confirm", digest = "ffffffffffffffff" })
  w:pump()
  local en = pa:poll()
  T.check(has(en, "nack", function(e) return e.why == "digest_unagreed" end) ~= nil,
    "a confirm with another digest is nacked digest_unagreed")
  w.clients[1].roomSession():send({ type = "trade_confirm", digest = D3 })
  w.clients[2].roomSession():send({ type = "trade_confirm", digest = D3 })
  w:pump()
  local commit = w.clients[1].roomSession():take("trade_commit")
  T.check(commit ~= nil, "the trade layer still reads trade_commit")
  local er = pa:poll()
  pb:poll()
  T.check(has(er, "trade_round") ~= nil, "the barrier sends the prep back for another round")
  T.eq(pa.state, "prep", "the prep reopens after a trade")
  T.eq(pa.mine.offer, nil, "offers are cleared after a round")
  T.eq(pa.round, 1, "the round counter advances")
  pa:offer({ species = 4 }, D1)
  T.eq(pa.offerRev, 2, "offerRev keeps rising across rounds")
  T.check(Protocol2.isXg({ type = "xg_go" }), "xg_go is an xg message")
end

do
  local sent = {}
  local inbox = {}
  local snapshot = { mode = "battle", rev = 7, gens = { 1, 2 },
                     rules = { mode = "battle", ruleset = "g3u", dexMax = 151 },
                     rosters = { { size = 3, digest16 = D1 } }, sizeReq = {}, offers = {},
                     ready = { true, false }, caps = { true, true } }
  local session = {
    send = function(m) sent[#sent + 1] = m return true end,
    take = function(pred)
      for i, m in ipairs(inbox) do
        if pred(m) then return table.remove(inbox, i) end
      end
      return nil
    end,
    snapshot = function() return snapshot, { stage = "prep" } end,
    seat = function() return 0 end,
    open = function() return true end,
  }
  local p = Prep.new(session, { mode = "battle" })
  T.eq(p.rev, 7, "a prep built from a snapshot starts at its rev")
  T.check(p.mine.ready ~= nil, "a snapshot ready flag is kept")
  T.eq(p.mine.roster.size, 3, "a snapshot roster is mine by seat")
  inbox[#inbox + 1] = { type = "xg_rules", rev = 3, mode = "battle", ruleset = "g3u", dexMax = 251, relay = true }
  inbox[#inbox + 1] = { type = "game3_hello" }
  p:poll()
  T.eq(p.rev, 7, "an older replayed message never lowers the rev")
  T.eq(#inbox, 1, "the prep leaves non-xg messages for the battle layer")
  inbox[#inbox + 1] = { type = "xg_closed", why = "timeout", relay = true, seat = -1 }
  local ev = p:poll()
  T.check(has(ev, "closed", function(e) return e.why == "timeout" end) ~= nil, "xg_closed timeout closes")
  T.eq(p.closed.seat, nil, "a relay close names no seat")
  session.open = function() return false end
  local p2 = Prep.new(session, { mode = "battle" })
  local ev2 = p2:poll()
  T.check(has(ev2, "closed", function(e) return e.why == "gone" end) ~= nil, "a vanished room closes the prep")
  T.eq(#sent, 0, "a passive prep sends nothing")
end

T.finish()
