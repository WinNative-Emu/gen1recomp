package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")
local T = require("tests.harness")
local F = require("tests.engine._xgen_fixture")
local FakeRelay = require("tests.support.fake_relay")
local Participant = require("src.online.union.Participant")
local Room = require("src.online.union.Room")
local Model = require("src.online.union.TradePrepModel")
local Txn = require("src.online.union.TradeTxn")
local TradeConvert = require("src.online.xgen.TradeConvert")
local GameVersion = require("src.core.GameVersion")
local SaveData = require("src.core.SaveData")
local Save2 = require("src.core.gen2.Save")
local LT = require("src.core.game3.link.trade")

local CLOCK = 0
love.timer.getTime = function() return CLOCK end

local fixtures = { red = F.data("red"), gold = F.data("gold"), emerald = F.data("emerald") }
Model.datasetSource = function(version) return fixtures[version] end

local OUTCOME = { value = "commit", asked = 0 }
LT.outcomeClient = {
  send = function(_, _, _, _, opts)
    OUTCOME.asked = OUTCOME.asked + 1
    OUTCOME.last = opts and opts.params
    return { id = OUTCOME.asked }
  end,
  poll = function() return { status = "ok", data = { outcome = OUTCOME.value } } end,
  release = function() end,
}

local function pid(n) return ("%08x"):format(n) end
local FP = { red = "1111111111111111", gold = "3333333333333333", emerald = "6666666666666666" }

local function ctxFor(version, name, tid)
  local gen = Participant.genOf(version)
  return { version = version, name = name, trainerId = tid, gender = 0,
           profile = { engine = gen, version = version, engineVersion = "0.0.0-dev", apiVersion = 2,
                       fingerprint = FP[version], rulesetId = gen == 3 and "g3_single" or "union", kind = "vanilla" },
           vanillaFingerprint = FP[version], gameplayMods = false }
end

local function world()
  local w = { relay = FakeRelay.new({ clock = function() return CLOCK end }), clients = {} }
  function w:add(n, name)
    local seat = self.relay:seat(pid(n), name)
    package.loaded["src.online.Client"] = nil
    local C = require("src.online.Client")
    C.reset()
    C.configure({ relayAddress = "fake:3", connect = function() return seat.transport end })
    C.connect({ name = name, profiles = {} })
    self.clients[#self.clients + 1] = C
    return Room.new({ client = C }), C
  end
  function w:pump(rounds)
    for _ = 1, rounds or 4 do
      self.relay:pump()
      for _, C in ipairs(self.clients) do C.update(0) end
    end
  end
  return w
end

local function pika1(level)
  return { species = "PIKACHU", level = level or 25, exp = 15625, hp = 50, nickname = "ZAPPY", ot = "RED", otId = 4242,
    dvs = { attack = 10, defense = 10, speed = 10, special = 10 },
    statExp = { hp = 100, attack = 400, defense = 0, speed = 900, special = 2500 },
    stats = { hp = 50, attack = 40, defense = 30, speed = 60, special = 40 },
    moves = { { id = "THUNDERSHOCK", pp = 30 }, { id = "GROWL", pp = 40 } }, catchRate = 190 }
end

local function bulba2()
  return { species = "BULBASAUR", level = 10, experience = 560, ot = "GOLD", otId = 9,
    dvs = { attack = 12, defense = 9, speed = 5, special = 7, hp = 8 }, statExp = { hp = 0, attack = 0, defense = 0, speed = 0, special = 0 },
    stats = { hp = 30, attack = 15, defense = 15, speed = 12, specialAttack = 16, specialDefense = 16 }, hp = 30,
    moves = { { id = "TACKLE", pp = 35, maxPp = 35 }, { id = "GROWL", pp = 40, maxPp = 40 } }, happiness = 90, pokerus = 0 }
end

local function g1game()
  local save = { version = "red", party = { pika1(), pika1(30) }, pokedex = { seen = {}, owned = {} },
    player = { map = "PALLET_TOWN", x = 5, y = 5, facing = "down", name = "RED" } }
  return { save = save, data = F.raw("red") }
end

local function g2game()
  local was = GameVersion.get()
  GameVersion.set("gold")
  local save = Save2.newGame({ playerName = "GOLD" })
  GameVersion.set(was)
  save.version = "gold"
  save.party = { bulba2() }
  return { save = save, data = F.raw("gold") }
end

local function side(room, game, version, peerVersion)
  local adapter = Txn.newAdapter(game, version)
  local s = { room = room, game = game, adapter = adapter, prep = room:prep() }
  s.model = Model.new({ version = version, peerVersion = peerVersion, owned = adapter:owned() })
  s.txn = Txn.new({ game = game, prep = s.prep, model = s.model, adapter = adapter, peerName = "PEER" })
  return s
end

local function offer(w, s, other)
  local r = s.model:choose(1)
  assert(r.ok, "offerable: " .. tostring(r.blocks[1] and r.blocks[1].code))
  local payload, digest = s.model:payload()
  s.prep:offer(payload, digest)
  w:pump()
  s.prep:poll()
  other.prep:poll()
end

local function receiveBoth(a, b)
  local okA, whyA = a.model:receive(a.prep.peer.offer.payload, function(final) return a.adapter:validate(final) end)
  local okB, whyB = b.model:receive(b.prep.peer.offer.payload, function(final) return b.adapter:validate(final) end)
  return okA, okB, whyA, whyB
end

local function setup()
  Txn.reset()
  love.filesystem._reset = nil
  local w = world()
  local ra = w:add(1, "A")
  local rb = w:add(2, "B")
  w:pump()
  ra:join(ctxFor("red", "A", 1))
  rb:join(ctxFor("gold", "B", 2))
  w:pump()
  ra:poll(); rb:poll()
  ra:invite(pid(2), "xg_trade")
  w:pump()
  rb:reply(rb:incoming()[1].id, true)
  w:pump()
  local a = side(ra, g1game(), "red", "gold")
  local b = side(rb, g2game(), "gold", "red")
  a.prep:poll(); b.prep:poll()
  offer(w, a, b)
  offer(w, b, a)
  local okA, okB, whyA, whyB = receiveBoth(a, b)
  assert(okA and okB, "receive: " .. tostring(whyA) .. " " .. tostring(whyB))
  return w, a, b
end

local function readyBoth(w, a, b)
  a.prep:ready(a.txn:readyDigest())
  b.prep:ready(b.txn:readyDigest())
  w:pump()
  a.prep:poll(); b.prep:poll()
end

local function wipeDisk()
  for _, v in ipairs({ "red", "gold" }) do
    local main = SaveData.saveFilename(v)
    for _, p in ipairs({ main, main .. ".bak", main .. ".tmp", Txn.journalPath(v), Txn.journalPath(v) .. ".tmp" }) do
      if love.filesystem.getInfo(p) then love.filesystem.remove(p) end
    end
  end
end

local function persist(s)
  T.check(s.adapter:write(), s.adapter.version .. " save written before the trade")
end

local function species(game, i) return game.save.party[i] and game.save.party[i].species end

local function diskSave(version)
  if version == "gold" then return (Save2.load("gold")) end
  return (SaveData.load(version))
end

local function contains(text, needle) return type(text) == "string" and text:find(needle, 1, true) ~= nil end

do
  wipeDisk()
  local w, a, b = setup()
  persist(a); persist(b)
  local stale = a.txn:readyDigest()
  readyBoth(w, a, b)
  T.eq(a.prep.state, "go", "agreed digests open the trade")
  T.check(a.txn:confirm(), "seat 0 journals and confirms")
  T.eq(#Txn.pending("red"), 1, "the journal entry is written before trade_confirm")
  local entry = Txn.pending("red")[1]
  T.eq(entry.digest, stale, "the journal binds the agreed digest")
  T.check(entry.out and entry.out.canonical and entry.incoming, "the entry holds the outgoing record and the incoming converted record")
  T.check(b.txn:confirm(), "seat 1 journals and confirms")
  w:pump()
  local ea = a.txn:pump(0)
  local eb = b.txn:pump(0)
  T.eq(a.txn.state, "done", "seat 0 applied and saved")
  T.eq(b.txn.state, "done", "seat 1 applied and saved")
  T.eq(species(a.game, 1), "BULBASAUR", "Red received the Bulbasaur in the outgoing slot")
  T.eq(species(b.game, 1), "PIKACHU", "Gold received the Pikachu in the outgoing slot")
  T.eq(species(a.game, 2), "PIKACHU", "the other party mon is untouched")
  T.check(a.game.save.pokedex.owned.BULBASAUR, "Red marks the received species owned")
  T.check(b.game.save.pokedex.caught.PIKACHU, "Gold marks the received species caught")
  T.eq(#Txn.pending("red") + #Txn.pending("gold"), 0, "journals dropped after the save")
  local diskA = diskSave("red")
  T.eq(diskA and diskA.party[1].species, "BULBASAUR", "the trade is on disk for Red")
  local report = SaveData.validate(diskA, F.raw("red"))
  T.eq(#report.lostMons, 0, "the received mon passes Gen 1 save validation")
  local diskB = diskSave("gold")
  T.eq(diskB and diskB.party[1].species, "PIKACHU", "the trade is on disk for Gold")
  local main = SaveData.saveFilename("red")
  local bak = love.filesystem.read(main .. ".bak")
  T.check(not contains(bak, "ZAPPY") or contains(bak, "BULBASAUR"), "the rolling backup no longer holds the traded-away mon alone")
  local outCount = 0
  for _, mon in ipairs(SaveData.decode(bak).party or {}) do if mon.nickname == "ZAPPY" and mon.level == 25 then outCount = outCount + 1 end end
  T.eq(outCount, 0, "no restorable copy of the traded-away mon remains in the backup")
  local items = love.filesystem.getDirectoryItems("") or {}
  local archives = 0
  for _, name in ipairs(items) do if name:find("trade%-bak") or name:find("_xtrade") then archives = archives + 1 end end
  T.eq(archives, 0, "no archive or journal file remains")
  T.check(eb[1] and eb[#eb].kind == "done", "the receiver gets a done event")
  T.check(ea[#ea].kind == "done", "the sender gets a done event")
  local rounds = a.prep:poll()
  local round
  for _, e in ipairs(rounds) do if e.kind == "trade_round" then round = e end end
  T.check(round ~= nil or a.prep.round >= 1, "the room returns to prep for another round")
  T.check(a.txn:nextRound(), "the transaction resets for the next round")

  local dup = { type = "trade_commit", n = 1, digests = { stale, stale } }
  a.prep.session.take = (function(orig)
    local sent = false
    return function(pred)
      if not sent and pred(dup) then sent = true return dup end
      return orig(pred)
    end
  end)(a.prep.session.take)
  a.txn:pump(0)
  T.eq(species(a.game, 1), "BULBASAUR", "a duplicate trade_commit does not apply twice")
  T.eq(#a.game.save.party, 2, "party size unchanged by the duplicate")
  T.check(not a.txn:onCommit(dup), "onCommit refuses outside commit_wait")
end

do
  wipeDisk()
  local w, a, b = setup()
  local first = a.txn:readyDigest()
  a.prep:ready(first)
  w:pump()
  a.prep:poll(); b.prep:poll()
  T.check(b.prep.peer.ready ~= nil, "the peer sees seat 0 ready")
  b.model:choose(1)
  b.model:stage(1, 0)
  local payload, digest = b.model:payload()
  b.prep:offer(payload, digest)
  w:pump()
  a.prep:poll(); b.prep:poll()
  T.eq(a.prep.mine.ready, nil, "a changed offer clears my ready")
  T.eq(b.prep.peer.ready, nil, "a changed offer clears the peer's ready on the other side")
  a.model:receive(a.prep.peer.offer.payload, function(f) return a.adapter:validate(f) end)
  local second = a.txn:readyDigest()
  T.check(second ~= first, "the agreed digest changes when an offer changes")
  a.prep:ready(first)
  b.prep:ready(b.txn:readyDigest())
  w:pump()
  local ea = a.prep:poll()
  b.prep:poll()
  T.check(a.prep.state ~= "go", "a ready bound to the old offer cannot open the trade")
  local nacked = false
  for _, e in ipairs(ea) do if e.kind == "nack" then nacked = true end end
  T.check(nacked, "the stale approval is nacked")
end

do
  wipeDisk()
  local w, a, b = setup()
  persist(a); persist(b)
  readyBoth(w, a, b)
  a.game.save.party[1].level = 26
  T.check(not a.txn:confirm(), "a changed outgoing record refuses to confirm")
  T.eq(a.txn.state, "aborted", "the round aborts locally")
  T.eq(#Txn.pending("red"), 0, "no journal entry without a confirm")
  local confirms = 0
  for _, l in ipairs(w.relay.log) do
    if l.msg.type == "room_msg" and l.msg.msg and l.msg.msg.type == "trade_confirm" then confirms = confirms + 1 end
  end
  T.eq(confirms, 0, "no trade_confirm was sent")
  w:pump()
  b.prep:poll()
  T.eq(b.prep.state, "closed", "the peer sees the room close")
  T.eq(species(b.game, 1), "BULBASAUR", "the peer keeps its original")
end

do
  wipeDisk()
  local w, a, b = setup()
  persist(a); persist(b)
  readyBoth(w, a, b)
  a.txn:confirm()
  T.eq(#Txn.pending("red"), 1, "journal written")
  local written = Txn.pending("red")[1]
  Txn.reset()
  local reloaded = { save = diskSave("red"), data = F.raw("red") }
  OUTCOME.value = "abort"
  local st = Txn.resumePending(reloaded, { manual = true })
  T.check(st ~= nil, "a pending journal starts the resolver at boot")
  for _ = 1, 4 do if Txn.step(st, 1) then break end end
  T.eq(#Txn.pending("red"), 0, "an aborted outcome drops the journal")
  T.eq(reloaded.save.party[1].species, "PIKACHU", "the original stays")
  T.eq(reloaded.save.party[1].nickname, "ZAPPY", "the original is unchanged")
  T.check(OUTCOME.last and OUTCOME.last.room == written.room and OUTCOME.last.digest == written.digest,
    "the outcome was asked by room and digest")
  OUTCOME.value = "commit"
end

do
  wipeDisk()
  local w, a, b = setup()
  persist(a); persist(b)
  readyBoth(w, a, b)
  a.adapter.writer = function() return false end
  a.txn:confirm(); b.txn:confirm()
  w:pump()
  a.txn:pump(0); b.txn:pump(0)
  T.eq(a.txn.state, "saving", "a failed save leaves the round in saving")
  T.eq(#Txn.pending("red"), 1, "the journal is kept while the save fails")
  T.eq(Txn.pending("red")[1].state, "committed", "the journal records the commit")
  Txn.reset()
  local reloaded = { save = diskSave("red"), data = F.raw("red") }
  T.eq(reloaded.save.party[1].species, "PIKACHU", "the disk still has the pre-trade save after the crash")
  local asked = OUTCOME.asked
  local st = Txn.resumePending(reloaded, { manual = true })
  T.eq(reloaded.save.party[1].species, "BULBASAUR", "a committed journal applies at boot without the network")
  T.eq(OUTCOME.asked, asked, "no outcome query is needed for a recorded commit")
  T.eq(#Txn.pending("red"), 0, "journal dropped once saved")
  T.eq(diskSave("red").party[1].species, "BULBASAUR", "the applied trade reached disk")
  Txn.reset()
  local again = { save = diskSave("red"), data = F.raw("red") }
  T.eq(Txn.resumePending(again, { manual = true }), nil, "nothing left to resume")
  T.eq(#again.save.party, 2, "applied exactly once")
  local _ = st
end

do
  wipeDisk()
  local w, a, b = setup()
  persist(a); persist(b)
  readyBoth(w, a, b)
  a.txn:confirm(); b.txn:confirm()
  w:pump()
  b.txn:pump(0)
  T.eq(a.txn.state, "commit_wait", "seat 0 never read the commit")
  Txn.reset()
  local reloaded = { save = diskSave("red"), data = F.raw("red") }
  OUTCOME.value = "commit"
  local st = Txn.resumePending(reloaded, { manual = true })
  for _ = 1, 4 do if Txn.step(st, 1) then break end end
  T.eq(reloaded.save.party[1].species, "BULBASAUR", "the server ledger's commit applies after a restart")
  T.eq(#Txn.pending("red"), 0, "journal settled")
  T.eq(species(b.game, 1), "PIKACHU", "the peer has the traded mon")
end

do
  wipeDisk()
  local w, a, b = setup()
  persist(a); persist(b)
  readyBoth(w, a, b)
  a.txn:confirm(); b.txn:confirm()
  local kept = Txn.pending("red")[1]
  w:pump()
  a.txn:pump(0); b.txn:pump(0)
  T.eq(a.txn.state, "done", "applied and saved")
  kept.state = "committed"
  Txn.journalPut("red", kept)
  Txn.reset()
  local reloaded = { save = diskSave("red"), data = F.raw("red") }
  Txn.resumePending(reloaded, { manual = true })
  T.eq(#reloaded.save.party, 2, "the save marker stops a second apply")
  T.eq(reloaded.save.party[1].species, "BULBASAUR", "the received mon stays")
  T.eq(reloaded.save.party[2].species, "PIKACHU", "the other mon is not taken")
  T.eq(#Txn.pending("red"), 0, "the stale journal is dropped")
  Txn.journalPut("red", kept)
  Txn.reset()
  local noMarker = { save = diskSave("red"), data = F.raw("red") }
  noMarker.save.unionTrades = nil
  Txn.resumePending(noMarker, { manual = true })
  T.eq(noMarker.save.party[2].species, "PIKACHU", "without a marker the received mon's identity still stops a second apply")
  T.eq(#Txn.pending("red"), 0, "and the journal is dropped")
end

do
  wipeDisk()
  local w, a, b = setup()
  persist(a); persist(b)
  readyBoth(w, a, b)
  local fails = 2
  a.adapter.writer = function(ad)
    if fails > 0 then fails = fails - 1 return false end
    return SaveData.save(ad:save()) == true
  end
  a.txn:confirm(); b.txn:confirm()
  w:pump()
  local ev = a.txn:pump(0)
  T.eq(ev[#ev].kind, "save_failed", "the failed save is reported")
  T.eq(#Txn.pending("red"), 1, "the journal survives the failed save")
  a.txn:pump(Txn.SAVE_RETRY_SECONDS + 0.1)
  T.eq(a.txn.state, "saving", "a second failure keeps retrying")
  a.txn:pump(Txn.SAVE_RETRY_SECONDS + 0.1)
  T.eq(a.txn.state, "done", "the retry lands")
  T.eq(#Txn.pending("red"), 0, "journal dropped after the retry")
  T.eq(#a.game.save.party, 2, "applied once across retries")
end

do
  wipeDisk()
  local w, a, b = setup()
  persist(a); persist(b)
  readyBoth(w, a, b)
  a.txn:confirm()
  b.txn.confirm = function() return false end
  w.relay:handle(w.relay.sessions[pid(2)], { type = "room_leave" })
  w:pump()
  a.txn:pump(0)
  T.check(a.txn.state == "aborted" or a.txn.state == "unresolved", "a peer leaving mid-barrier never commits")
  if a.txn.state == "unresolved" then
    OUTCOME.value = "abort"
    local st = Txn._resolver
    st.adapter.ready = function() return true end
    for _ = 1, 4 do if Txn.step(st, 1) then break end end
    OUTCOME.value = "commit"
  end
  T.eq(#Txn.pending("red"), 0, "the journal is settled as aborted")
  T.eq(species(a.game, 1), "PIKACHU", "seat 0 keeps its original")
  T.eq(species(b.game, 1), "BULBASAUR", "seat 1 keeps its original")
end

T.finish("union_trade_txn")
