local GameVersion = require("src.core.GameVersion")
local Model = require("src.online.union.TradePrepModel")
local TradeConvert = require("src.online.xgen.TradeConvert")

local Txn = {}
Txn.__index = Txn

Txn.JOURNAL_VERSION = 1
Txn.JOURNAL_TTL = 24 * 60 * 60
Txn.RETRY_SECONDS = 5
Txn.SAVE_RETRY_SECONDS = 3
Txn.MARKERS = 32
Txn.TICK_KEY = "union_xtrade"

Txn.fs = nil
Txn.now = nil
Txn._applied = {}
Txn._live = {}
Txn._resolver = nil

local function now()
  if type(Txn.now) == "function" then return Txn.now() end
  return os.time()
end

local function SaveData()
  return require("src.core.SaveData")
end

local function disk()
  if Txn.fs then return Txn.fs end
  return SaveData().persistenceFs()
end

local function copy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = copy(x) end
  return out
end

local function log(fmt, ...)
  print("[union-trade] " .. fmt:format(...))
end

local function lt()
  return require("src.core.game3.link.trade")
end


local function decode(text)
  if type(text) ~= "string" or text == "" then return nil end
  local ok, data = pcall(SaveData().decode, text)
  if ok and type(data) == "table" then return data end
  return nil
end

local function readFile(fs, path)
  if not fs.getInfo(path) then return nil end
  local ok, text = pcall(fs.read, path)
  return ok and text or nil
end

function Txn.writeAtomic(path, text)
  local fs = disk()
  if not (fs and path) then return false end
  local tmp = path .. ".tmp"
  local ok, wrote = pcall(fs.write, tmp, text)
  if not (ok and wrote) or readFile(fs, tmp) ~= text then return false end
  if fs.getInfo(path) then pcall(fs.remove, path) end
  ok, wrote = pcall(fs.write, path, text)
  if not (ok and wrote) or readFile(fs, path) ~= text then return false end
  pcall(fs.remove, tmp)
  return true
end

function Txn.journalPath(version)
  local main = SaveData().saveFilename(version)
  if type(main) ~= "string" or main == "" then return nil end
  return (main:gsub("%.lua$", "")) .. "_xtrade.lua"
end

function Txn.readJournal(version)
  local fs = disk()
  local path = Txn.journalPath(version)
  if not (fs and path) then return {} end
  local data = decode(readFile(fs, path)) or decode(readFile(fs, path .. ".tmp"))
  if not (data and type(data.entries) == "table") then return {} end
  local out = {}
  for _, e in ipairs(data.entries) do
    if type(e) == "table" and type(e.key) == "string" then out[#out + 1] = e end
  end
  return out
end

function Txn.writeJournal(version, entries)
  local fs = disk()
  local path = Txn.journalPath(version)
  if not (fs and path) then return false end
  if #entries == 0 then
    for _, p in ipairs({ path, path .. ".tmp" }) do
      if fs.getInfo(p) then
        local ok, removed = pcall(fs.remove, p)
        if not ok or removed == false then return false end
      end
    end
    return true
  end
  local ok, text = pcall(SaveData().encode, { v = Txn.JOURNAL_VERSION, entries = entries })
  if not ok then return false end
  return Txn.writeAtomic(path, text)
end

function Txn.journalPut(version, entry)
  local kept = {}
  for _, e in ipairs(Txn.readJournal(version)) do
    if e.key ~= entry.key then kept[#kept + 1] = e end
  end
  kept[#kept + 1] = entry
  return Txn.writeJournal(version, kept)
end

function Txn.journalDrop(version, key)
  local list, kept = Txn.readJournal(version), {}
  for _, e in ipairs(list) do
    if e.key ~= key then kept[#kept + 1] = e end
  end
  if #kept == #list then return true end
  return Txn.writeJournal(version, kept)
end

function Txn.pending(version)
  return Txn.readJournal(version)
end

function Txn.entryKey(room, n, digest)
  return tostring(room) .. ":" .. tostring(n) .. ":" .. tostring(digest)
end


local function protocol()
  return require("src.link.Protocol")
end

local function identityOf(gen, rec)
  if type(rec) ~= "table" then return nil end
  if gen == 3 then
    return ("%s:%s:%s"):format(tostring(tonumber(rec.personality) or 0), tostring((tonumber(rec.otId) or 0) % 65536),
      tostring(tonumber(rec.otSecretId) or 0))
  end
  local d = type(rec.dvs) == "table" and rec.dvs or {}
  return ("%s:%s:%s:%s:%s:%s"):format(tostring(rec.ot or rec.otName), tostring(rec.otId), tostring(d.attack),
    tostring(d.defense), tostring(d.speed), tostring(d.special or d.specialAttack))
end
Txn.identityOf = identityOf

local Adapter = {}
Adapter.__index = Adapter

local function newAdapter(game, gen, version)
  return setmetatable({ game = game, gen = gen, version = version }, Adapter)
end

function Adapter:data()
  return self.game and self.game.data
end

function Adapter:save()
  if self.gen == 3 then
    local g = self.game
    if g and g.session then return g.session end
    local Runtime = package.loaded["src.core.game3.runtime"]
    return Runtime and Runtime.getSession and Runtime.getSession() or nil
  end
  return self.game and self.game.save
end

local function game3()
  local Runtime = package.loaded["src.core.game3.runtime"]
  return Runtime and Runtime._game or nil
end

function Adapter:ready()
  local s = self:save()
  if type(s) ~= "table" or type(s.party) ~= "table" then return false end
  local g = self.game or (self.gen == 3 and game3() or nil)
  if self.gen == 3 and g and g.phase ~= nil and g.phase ~= "field" then return false end
  return true
end

local GEN_BOXES = { [1] = 12, [2] = 14 }

function Adapter:lists()
  local s = self:save()
  local out = {}
  if type(s) ~= "table" then return out end
  out[#out + 1] = { where = "party", list = s.party or {} }
  if self.gen ~= 3 then
    if self.gen == 1 then require("src.pokemon.Boxes").ensure(s) end
    s.boxes = s.boxes or {}
    for b = 1, GEN_BOXES[self.gen] do
      if type(s.boxes[b]) == "table" then out[#out + 1] = { where = "box", box = b, list = s.boxes[b] } end
    end
  end
  return out
end

function Adapter:listFor(ref)
  local s = self:save()
  if type(s) ~= "table" or type(ref) ~= "table" then return nil end
  if ref.where == "party" then return s.party end
  if ref.where == "box" and self.gen ~= 3 and type(s.boxes) == "table" then return s.boxes[tonumber(ref.box) or -1] end
  return nil
end

function Adapter:at(ref)
  local list = self:listFor(ref)
  return list and list[tonumber(ref.index) or -1] or nil
end

function Adapter:pack(mon)
  if type(mon) ~= "table" then return nil end
  local P = protocol()
  local ok, rec = pcall(function()
    if self.gen == 3 then return P.packMon3(mon) end
    if self.gen == 2 then return P.packMon2(mon) end
    local r = P.packMon(mon)
    r.catchRate = mon.catchRate
    return r
  end)
  if not ok then return nil end
  return Model.plain(rec)
end

function Adapter:canonicalAt(ref)
  local rec = self:pack(self:at(ref))
  return rec and TradeConvert.canonical(rec) or nil
end

function Adapter:lockOf(ref, mon, pending)
  if self.gen == 2 then
    local Mail = require("src.core.gen2.Mail")
    if Mail.monHoldsMail(mon) then return "mail" end
    local s = self:save()
    local mail = type(s.mail) == "table" and type(s.mail.party) == "table" and s.mail.party or nil
    if ref.where == "party" and mail and mail[ref.index] ~= nil then return "mail" end
  end
  if type(mon) == "table" and (mon.rental == true or mon.projected == true) then return "rental" end
  local id = pending and next(pending) ~= nil and identityOf(self.gen, self:pack(mon)) or nil
  if id and pending[id] then return "pending" end
  return nil
end

function Adapter:owned()
  local out, pending = {}, {}
  for _, e in ipairs(Txn.readJournal(self.version)) do
    if type(e.out) == "table" and e.out.identity then pending[e.out.identity] = true end
  end
  for _, l in ipairs(self:lists()) do
    for i, mon in ipairs(l.list) do
      local ref = { where = l.where, box = l.box, index = i }
      out[#out + 1] = { ref = ref, rec = self:pack(mon), live = mon, locked = self:lockOf(ref, mon, pending) }
    end
  end
  return out
end

function Adapter:native(final)
  if type(final) ~= "table" then return nil, "bad_record" end
  local P = protocol()
  local data = self:data()
  local ok, mon, why = pcall(function()
    if self.gen == 3 then return P.unpackMon3(nil, copy(final), { strict = true }) end
    if self.gen == 2 then return P.unpackMon2(data, copy(final), { strict = true }) end
    return P.unpackMon(data, copy(final), { strict = true })
  end)
  if not ok then return nil, "not_valid_here", { error = tostring(mon) } end
  if not mon then return nil, "not_valid_here", { error = why } end
  if mon.level ~= final.level then return nil, "not_valid_here", { field = "level" } end
  if type(final.moves) == "table" and #mon.moves ~= #final.moves then return nil, "not_valid_here", { field = "moves" } end
  if self.gen == 1 then
    mon.catchRate = final.catchRate
    mon.traded = true
  elseif self.gen == 2 then
    mon.traded = true
  end
  return mon
end

function Adapter:validate(final)
  local mon, code, detail = self:native(final)
  if not mon then return false, code, detail end
  return true
end

local function markDex1(save, species)
  save.pokedex = save.pokedex or {}
  save.pokedex.seen = save.pokedex.seen or {}
  save.pokedex.owned = save.pokedex.owned or {}
  save.pokedex.seen[species] = true
  save.pokedex.owned[species] = true
end

function Adapter:evolve1(list, index, mon)
  local data = self:data()
  local def = data and data.pokemon and data.pokemon[mon.species]
  for _, evo in ipairs(def and def.evolutions or {}) do
    -- engine/pokemon/evos_moves.asm:70
    if evo.method == "TRADE" and data.pokemon[evo.species] then
      require("src.pokemon.Evolution").apply(self.game, mon, evo.species, "TRADE")
      return evo.species
    end
  end
  return nil
end

function Adapter:put(ref, mon)
  local list = self:listFor(ref)
  local index = tonumber(ref.index)
  if not (list and index and list[index]) then return nil, "missing" end
  local s = self:save()
  local sent = list[index]
  local evolved
  if self.gen == 1 then
    list[index] = mon
    markDex1(s, mon.species)
    -- engine/link/cable_club.asm:801
    if self.version == "yellow" then
      pcall(function() require("src.world.PikachuFollower").modifyHappiness(s, "TRADE", sent) end)
    end
    evolved = self:evolve1(list, index, mon)
  elseif self.gen == 2 then
    local Evolution = require("src.core.gen2.Evolution")
    list[index] = mon
    Evolution.markPokedex(s, mon.species)
    local data = self:data()
    -- engine/pokemon/evolve.asm:144
    local entry = Evolution.checkMon(data, mon, { link = true })
    if entry then
      local next = Evolution.apply(data, mon, entry)
      if next then
        list[index] = next
        Evolution.markPokedex(s, entry.into)
        evolved = entry.into
      end
    end
  else
    local Trade = require("src.core.game3.scripting.natives_trade")
    if not Trade.tradeMons(s, index - 1, mon) then return nil, "swap" end
    local okQ, key, args = pcall(Trade.noteLinkTrade, s, sent, mon, self.peerName, true)
    if okQ and key then pcall(function() require("src.core.game3.quest_log_recorder").event(s, key, args) end) end
    -- pokefirered/src/trade_scene.c:2311
    local Evolution = require("src.core.game3.evolution")
    local target = Evolution.tradeTarget(mon, s)
    if target then
      Evolution.apply(mon, target, s, s.bag, "trade")
      evolved = target
    end
  end
  return true, evolved
end

function Adapter:hasMarker(key)
  if self.gen == 3 then return false end
  local s = self:save()
  for _, k in ipairs(type(s) == "table" and type(s.unionTrades) == "table" and s.unionTrades or {}) do
    if k == key then return true end
  end
  return false
end

function Adapter:mark(key)
  if self.gen == 3 then return end
  local s = self:save()
  local list = type(s.unionTrades) == "table" and s.unionTrades or {}
  list[#list + 1] = key
  while #list > Txn.MARKERS do table.remove(list, 1) end
  s.unionTrades = list
end

function Adapter:write()
  local g = self.game or (self.gen == 3 and game3() or nil)
  if type(self.writer) == "function" then return self.writer(self) == true end
  if self.gen == 3 then
    local Runtime = package.loaded["src.core.game3.runtime"]
    if Runtime and Runtime._mod and g then
      local okB, Bridge = pcall(require, "src.core.game3.bridge")
      if okB and Bridge.persistSessionOnly then
        if not pcall(Bridge.persistSessionOnly, Runtime._mod, g) then return false end
      end
    end
    if not (g and g.saveGame) then return false end
    local ok, wrote = pcall(g.saveGame, g)
    return ok and wrote ~= false
  end
  if g and g.writeSave then
    local ok, wrote = pcall(g.writeSave, g)
    if not ok then log("save failed: %s", tostring(wrote)) end
    return ok and wrote ~= false and wrote ~= nil
  end
  local s = self:save()
  if self.gen == 2 then
    local ok, wrote = pcall(require("src.core.gen2.Save").save, s)
    return ok and wrote == true
  end
  local ok, wrote = pcall(SaveData().save, s)
  return ok and wrote == true
end

function Adapter:scrubBackup()
  local fs = disk()
  local main = SaveData().saveFilename(self.version)
  if not (fs and main) then return end
  local bak = main .. ".bak"
  if not fs.getInfo(bak) then return end
  local body = readFile(fs, main)
  if decode(body) then pcall(fs.write, bak, body) end
end

function Adapter:find(test)
  for _, l in ipairs(self:lists()) do
    for i, mon in ipairs(l.list) do
      local rec = self:pack(mon)
      if rec and test(rec) then return { where = l.where, box = l.box, index = i } end
    end
  end
  return nil
end

Txn.Adapter = Adapter

function Txn.adapterFor(game, opts)
  opts = opts or {}
  if type(opts.adapter) == "table" then return opts.adapter end
  if type(game) == "table" and type(game.unionTradeAdapter) == "table" then return game.unionTradeAdapter end
  local version = opts.version or (type(game) == "table" and type(game.save) == "table" and game.save.version)
  if type(game) == "table" and type(game.session) == "table" and game.session.version then
    version = opts.version or game.session.version
  end
  if not (type(version) == "string" and GameVersion.VERSIONS[version]) then version = GameVersion.get() end
  return newAdapter(game, GameVersion.generation(version), version)
end

function Txn.newAdapter(game, version)
  return newAdapter(game, GameVersion.generation(version), version)
end


local function locateFor(adapter, entry)
  if adapter:hasMarker(entry.key) then return nil, "already" end
  local out = entry.out or {}
  if out.ref and adapter:canonicalAt(out.ref) == out.canonical then return out.ref end
  local inId = entry.incomingIdentity
  if inId and adapter:find(function(r) return identityOf(adapter.gen, r) == inId end) then return nil, "already" end
  local ref = adapter:find(function(r) return TradeConvert.canonical(r) == out.canonical end)
  if ref then return ref end
  ref = out.identity and adapter:find(function(r) return identityOf(adapter.gen, r) == out.identity end)
  if ref then return ref end
  return nil, "missing"
end

function Txn.applyEntry(adapter, entry)
  local ref, why = locateFor(adapter, entry)
  if not ref then return why end
  local mon, code = adapter:native(entry.incoming)
  if not mon then return "invalid", code end
  local ok, evolved = adapter:put(ref, mon)
  if not ok then return "invalid", evolved end
  adapter:mark(entry.key)
  entry.evolved = evolved
  return "applied", evolved
end

function Txn.settleCommit(adapter, entry)
  if Txn._applied[entry.key] == "saved" then
    Txn.journalDrop(adapter.version, entry.key)
    return "done"
  end
  local status = "applied"
  if Txn._applied[entry.key] ~= "memory" then
    local detail
    status, detail = Txn.applyEntry(adapter, entry)
    if status == "missing" or status == "invalid" then
      log("committed trade %s could not be applied: %s %s", entry.key, status, tostring(detail))
      Txn.journalDrop(adapter.version, entry.key)
      return status
    end
    Txn._applied[entry.key] = "memory"
  end
  if not adapter:write() then return "save_failed" end
  adapter:scrubBackup()
  Txn._applied[entry.key] = "saved"
  Txn.journalDrop(adapter.version, entry.key)
  return status == "already" and "done_already" or "done"
end

function Txn.settle(adapter, entry, outcome)
  if outcome == "abort" then
    Txn.journalDrop(adapter.version, entry.key)
    return "aborted"
  end
  if outcome == "commit" then
    if entry.state ~= "committed" then
      entry.state = "committed"
      Txn.journalPut(adapter.version, entry)
    end
    return Txn.settleCommit(adapter, entry)
  end
  return nil
end


local function liveKeys()
  local out = {}
  for _, t in pairs(Txn._live) do
    if t.entry then out[t.entry.key] = true end
  end
  return out
end

function Txn.step(st, dt)
  local adapter = st.adapter
  if not adapter:ready() then return false end
  local live = liveKeys()
  if st.job then
    local status, outcome = lt().pollOutcome(st.job)
    if status == "pending" then return false end
    local entry = st.job.entry
    st.job = nil
    local result = status == "ok" and Txn.settle(adapter, entry, outcome) or nil
    local settled = result ~= nil and result ~= "save_failed"
    st.fails = settled and 0 or math.min((st.fails or 0) + 1, 6)
    st.wait = (result == "save_failed" and Txn.SAVE_RETRY_SECONDS or Txn.RETRY_SECONDS) * (settled and 1 or 2 ^ st.fails)
    if settled then st.wait = 0 end
    st.last = result or outcome or status
  end
  if (st.wait or 0) > 0 then
    st.wait = st.wait - (tonumber(dt) or 0)
    return false
  end
  local open = {}
  for _, e in ipairs(Txn.readJournal(adapter.version)) do
    if not live[e.key] then
      if e.state == "committed" then
        local r = Txn.settleCommit(adapter, e)
        st.last = r
        if r == "save_failed" then
          st.wait = Txn.SAVE_RETRY_SECONDS
          return false
        end
      elseif now() - (tonumber(e.at) or 0) > Txn.JOURNAL_TTL then
        Txn.journalDrop(adapter.version, e.key)
      else
        open[#open + 1] = e
      end
    end
  end
  if #open == 0 then return true end
  st.index = ((st.index or 0) % #open) + 1
  st.job = lt().fetchOutcome(open[st.index])
  return false
end

local function tick()
  local st = Txn._resolver
  if not st then return end
  local t = (type(love) == "table" and love.timer and love.timer.getTime) and love.timer.getTime() or os.clock()
  local dt = st.lastTick and (t - st.lastTick) or 0
  st.lastTick = t
  local ok, done = pcall(Txn.step, st, dt)
  if not ok then
    log("resolver failed: %s", tostring(done))
    done = true
  end
  if done then
    Txn._resolver = nil
    return
  end
  require("src.core.DeferredWrite").schedule(Txn.TICK_KEY, tick)
end

function Txn.resumePending(game, opts)
  local adapter = Txn.adapterFor(game, opts)
  if #Txn.readJournal(adapter.version) == 0 then return nil end
  if Txn._resolver and Txn._resolver.adapter.version == adapter.version then
    Txn._resolver.adapter = adapter
    return Txn._resolver
  end
  local st = { adapter = adapter, wait = 0, fails = 0, index = 0 }
  Txn._resolver = st
  if adapter:ready() then
    for _, e in ipairs(Txn.readJournal(adapter.version)) do
      if e.state == "committed" and not liveKeys()[e.key] then Txn.settleCommit(adapter, e) end
    end
  end
  if not (opts and opts.manual) then
    require("src.core.DeferredWrite").schedule(Txn.TICK_KEY, tick)
  end
  return st
end


function Txn.new(opts)
  local adapter = opts.adapter or Txn.adapterFor(opts.game, opts)
  local self = setmetatable({
    game = opts.game, prep = opts.prep, model = opts.model, adapter = adapter,
    roomId = opts.roomId, peerName = opts.peerName, state = "prep", entry = nil,
    digest = nil, events = {}, saveWait = 0,
  }, Txn)
  adapter.peerName = opts.peerName
  Txn._live[self] = self
  return self
end

function Txn:emit(kind, fields)
  local e = { kind = kind }
  for k, v in pairs(fields or {}) do e[k] = v end
  self.events[#self.events + 1] = e
end

function Txn:room()
  if self.roomId then return self.roomId end
  local session = self.prep and self.prep.session
  if session and session.snapshot then
    local _, r = session.snapshot()
    if type(r) == "table" and type(r.room) == "string" then return r.room end
  end
  return nil
end

function Txn:send(msg)
  local session = self.prep and self.prep.session
  return session and session.send and session.send(msg) and true or false
end

function Txn:cancel(why)
  self.state = "aborted"
  self.why = why
  if self.prep and self.prep.cancel then self.prep:cancel(why) end
  self:emit("aborted", { why = why, roundEnded = true })
end

function Txn:recheck()
  local m = self.model and self.model.mine
  if not (m and m.half) then return false, "no_offer" end
  local s = self.adapter:save()
  if type(s) ~= "table" then return false, "no_save" end
  local list = self.adapter:listFor(m.ref)
  if not (list and list[m.ref.index]) then return false, "capacity" end
  if self.adapter:canonicalAt(m.ref) ~= m.half.source then return false, "changed" end
  local ok, code = self.adapter:validate(self.model.peer and self.model.peer.final)
  if not ok then return false, code end
  return true
end

function Txn:readyDigest()
  local prep, m = self.prep, self.model
  if not (prep and m and prep.mine.offer and prep.peer.offer) then return nil end
  local mineRev = prep.mine.offer.offerRev
  local peerRev = prep.peer.offer.offerRev
  return m:agreed(prep:seat(), mineRev, peerRev)
end

function Txn:confirm()
  if self.state ~= "prep" and self.state ~= "ready" then return false end
  local digest = self:readyDigest()
  if not digest then
    self:cancel("no_offer")
    return false
  end
  local ok, why = self:recheck()
  if not ok then
    self:cancel("recheck_" .. tostring(why))
    return false
  end
  local room = self:room()
  if not room then
    self:cancel("no_room")
    return false
  end
  local m = self.model
  local round = (self.prep and self.prep.round or 0) + 1
  local entry = {
    key = Txn.entryKey(room, round, digest), room = room, n = round, digest = digest, at = now(),
    gen = self.adapter.gen, version = self.adapter.version, state = "confirming",
    peer = { name = self.peerName, version = m.peer and m.peer.version },
    out = { ref = copy(m.mine.ref), record = copy(m.mine.rec), canonical = m.mine.half.source,
      identity = identityOf(self.adapter.gen, m.mine.rec) },
    incoming = copy(m.peer.final), incomingCanonical = m.peer.half.result,
    incomingIdentity = identityOf(self.adapter.gen, m.peer.final),
  }
  if not Txn.journalPut(self.adapter.version, entry) then
    self:cancel("journal")
    return false
  end
  self.entry, self.digest = entry, digest
  self.state = "commit_wait"
  self:send({ type = "trade_confirm", digest = digest })
  self:emit("confirming", { digest = digest })
  return true
end

function Txn:onCommit(msg)
  if self.state ~= "commit_wait" then return false end
  local d = type(msg) == "table" and msg.digests or nil
  if type(d) ~= "table" or d[1] ~= self.digest or d[2] ~= self.digest then return false end
  local entry = self.entry
  entry.state = "committed"
  entry.commitN = tonumber(msg.n)
  Txn.journalPut(self.adapter.version, entry)
  local status, detail = Txn.applyEntry(self.adapter, entry)
  if status == "missing" or status == "invalid" then
    log("committed trade %s could not be applied: %s %s", entry.key, status, tostring(detail))
    Txn.journalDrop(self.adapter.version, entry.key)
    self.state = "failed"
    self:emit("failed", { why = status })
    return true
  end
  Txn._applied[entry.key] = "memory"
  self.evolved = entry.evolved
  self.state = "saving"
  self:trySave()
  return true
end

function Txn:trySave()
  if self.state ~= "saving" then return false end
  if self.adapter:write() then
    self.adapter:scrubBackup()
    Txn._applied[self.entry.key] = "saved"
    Txn.journalDrop(self.adapter.version, self.entry.key)
    self.state = "done"
    self:emit("done", { evolved = self.evolved })
    return true
  end
  self.saveFailed = true
  self.saveWait = Txn.SAVE_RETRY_SECONDS
  self:emit("save_failed", {})
  return false
end

function Txn:onAbort(msg)
  if self.state ~= "commit_wait" then return false end
  Txn.journalDrop(self.adapter.version, self.entry.key)
  self.state = "aborted"
  self.why = type(msg) == "table" and msg.why or "aborted"
  self:emit("aborted", { why = self.why })
  return true
end

function Txn:lost()
  if self.state ~= "commit_wait" then return false end
  self.state = "unresolved"
  Txn._live[self] = nil
  Txn.resumePending(self.game, { adapter = self.adapter })
  self:emit("unresolved", {})
  return true
end

local function isBarrier(m)
  return type(m) == "table" and (m.type == "trade_commit" or m.type == "trade_abort")
end

function Txn:pump(dt)
  local session = self.prep and self.prep.session
  if self.state == "commit_wait" and session and session.take then
    for _ = 1, 16 do
      local m = session.take(isBarrier)
      if not m then break end
      if m.type == "trade_commit" then self:onCommit(m) else self:onAbort(m) end
      if self.state ~= "commit_wait" then break end
    end
    if self.state == "commit_wait" and session.open and not session.open() then self:lost() end
  elseif self.state ~= "commit_wait" and session and session.take then
    for _ = 1, 16 do
      if not session.take(isBarrier) then break end
    end
  end
  if self.state == "saving" then
    self.saveWait = self.saveWait - (tonumber(dt) or 0)
    if self.saveWait <= 0 then self:trySave() end
  end
  local out = self.events
  self.events = {}
  return out
end

function Txn:nextRound()
  if self.state == "commit_wait" or self.state == "saving" then return false end
  self.state, self.entry, self.digest, self.evolved, self.why = "prep", nil, nil, nil, nil
  return true
end

function Txn:close()
  if self.state == "commit_wait" then self:lost() end
  Txn._live[self] = nil
  if self.state == "saving" then Txn.resumePending(self.game, { adapter = self.adapter }) end
end

function Txn.reset()
  Txn._applied = {}
  Txn._live = {}
  Txn._resolver = nil
end

return Txn
