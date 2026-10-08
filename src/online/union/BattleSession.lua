local Table = require("src.battle.g3u.Table")
local Match = require("src.battle.g3u.Match")
local Wire = require("src.battle.g3u.Wire")
local Policy = require("src.online.xgen.Policy")

local BattleSession = {}
BattleSession.__index = BattleSession

BattleSession.SETUP_TIMEOUT = 60
BattleSession.RESUME_WINDOW = 120
BattleSession.PEER_GONE = 45
BattleSession.FINAL_HASH_WAIT = 5

local OWN = {}
for _, t in ipairs(Wire.TYPES) do OWN[t] = true end
OWN.xg_closed = true

local REPORT = { win = "win", lose = "lose", draw = "draw" }

local function clock()
  if love and love.timer and love.timer.getTime then return love.timer.getTime() end
  return os.clock()
end

local function copyAct(a)
  return { kind = a.kind, slot = a.slot, index = a.index }
end

local function msgBytes(m)
  local ok, n = pcall(Wire.size, m)
  return ok and n or math.huge
end

function BattleSession.lowerSeat(gens)
  local g0, g1 = tonumber(gens and gens[0]), tonumber(gens and gens[1])
  if g0 and g1 and g1 < g0 then return 1 end
  return 0
end

-- pokefirered/src/pokemon.c:2845
local function hpRange(base, level)
  local lo = math.floor((2 * base) * level / 100) + level + 10
  local hi = math.floor((2 * base + 31 + 63) * level / 100) + level + 10
  return lo, hi
end

-- pokefirered/src/pokemon.c:2814
local function statRange(base, level)
  local lo = math.floor((2 * base) * level / 100) + 5
  local hi = math.floor((2 * base + 31 + 63) * level / 100) + 5
  return lo, hi
end

local STAT_KEYS = { { "atk", "atk" }, { "def", "def" }, { "speed", "spe" }, { "spAtk", "spa" }, { "spDef", "spd" } }

function BattleSession.checkParty(records, t, opts)
  opts = opts or {}
  local msg = Wire.party(records)
  local ok, why = Wire.validate(msg, { table = t, bytes = msgBytes(msg) })
  if not ok then return nil, why end
  if opts.size and #records > opts.size then return nil, "party_size" end
  local loose = opts.senderGen ~= nil and t.gen == 1 and opts.senderGen > 1
  for i, r in ipairs(records) do
    local base = Table.baseStats(t, r.species)
    if r.hp ~= r.maxHp then return nil, "record_" .. i .. ":hp_not_full" end
    local lo, hi = hpRange(base.hp, r.level)
    if r.maxHp < lo or r.maxHp > hi then return nil, "record_" .. i .. ":hp_range" end
    for _, pair in ipairs(STAT_KEYS) do
      local key, b = pair[1], pair[2]
      if not (loose and (b == "spa" or b == "spd")) then
        local slo, shi = statRange(base[b], r.level)
        if r[key] < slo or r[key] > shi then return nil, "record_" .. i .. ":" .. key .. "_range" end
      end
    end
    for j, mv in ipairs(r.moves) do
      local full = math.min(64, Policy.maxPp(t.moves[mv.id][4], mv.ppUps or 0))
      if mv.pp > full then return nil, "record_" .. i .. ":pp_" .. j end
    end
  end
  return true
end

local GENDER_CODE = { male = 0, M = 0, female = 1, F = 1, unknown = 2, U = 2, genderless = 2 }
local IV_KEYS = { "hp", "atk", "def", "spe", "spa", "spd" }

function BattleSession.wireRecord(mon)
  if type(mon) ~= "table" then return nil end
  local moves = {}
  for _, m in ipairs(mon.moves or {}) do
    local id = type(m) == "table" and (m.id or m.move) or m
    if tonumber(id) then
      moves[#moves + 1] = { id = tonumber(id), pp = tonumber(type(m) == "table" and m.pp) or 0,
        ppUps = tonumber(type(m) == "table" and m.ppUps) or 0 }
    end
  end
  local r = {
    species = tonumber(mon.species) or tonumber(mon.national), level = mon.level, hp = mon.hp, maxHp = mon.maxHp,
    atk = mon.atk, def = mon.def, spAtk = mon.spAtk, spDef = mon.spDef, speed = mon.speed, moves = moves,
  }
  if type(mon.nickname) == "string" and mon.nickname ~= "" then r.nickname = mon.nickname end
  local g = mon.gender
  if type(g) == "string" then g = GENDER_CODE[g] end
  if type(g) == "number" then r.gender = g end
  if tonumber(mon.friendship) then r.friendship = tonumber(mon.friendship) end
  if type(mon.ivs) == "table" then
    r.ivs = {}
    for _, k in ipairs(IV_KEYS) do r.ivs[k] = tonumber(mon.ivs[k]) or 0 end
  end
  return r
end

function BattleSession.wireRecords(list)
  local out = {}
  for i, mon in ipairs(list or {}) do out[i] = BattleSession.wireRecord(mon) end
  return out
end

function BattleSession.new(opts)
  assert(type(opts) == "table", "BattleSession.new needs opts")
  assert(type(opts.net) == "table", "BattleSession.new needs a net")
  local seat = tonumber(opts.seat)
  assert(seat == 0 or seat == 1, "BattleSession.new needs seat 0 or 1")
  local go = opts.go or {}
  local gens = opts.gens or {}
  local self = setmetatable({
    net = opts.net,
    seat = seat,
    peer = 1 - seat,
    go = go,
    seed = tonumber(go.seed) or 0,
    size = tonumber(go.size),
    gens = { [0] = tonumber(gens[0]), [1] = tonumber(gens[1]) },
    data = opts.data,
    records = type(opts.records) == "table" and BattleSession.wireRecords(opts.records) or nil,
    names = opts.names or {},
    client = opts.client,
    linkState = opts.linkState,
    now = opts.now or clock,
    timeouts = {
      setup = (opts.timeouts and opts.timeouts.setup) or BattleSession.SETUP_TIMEOUT,
      resume = (opts.timeouts and opts.timeouts.resume) or BattleSession.RESUME_WINDOW,
      peer = (opts.timeouts and opts.timeouts.peer) or BattleSession.PEER_GONE,
      final = (opts.timeouts and opts.timeouts.final) or BattleSession.FINAL_HASH_WAIT,
    },
    phase = "setup",
    queue = {},
    table = opts.table,
    peerRecords = nil,
    match = nil,
    mine = {},
    theirs = {},
    myRep = nil,
    theirReps = {},
    hashSent = {},
    myHashes = {},
    peerHashes = {},
    result = nil,
    reported = false,
    log = {},
  }, BattleSession)
  self.lower = BattleSession.lowerSeat(self.gens)
  self.tableGen = math.min(self.gens[0] or 3, self.gens[1] or 3)
  self.startedAt = self.now()
  self:_begin()
  return self
end

function BattleSession:isLower()
  return self.seat == self.lower
end

function BattleSession:_note(fmt, ...)
  local line = select("#", ...) > 0 and fmt:format(...) or fmt
  self.log[#self.log + 1] = line
end

function BattleSession:_push(ev)
  self.queue[#self.queue + 1] = ev
end

function BattleSession:events()
  local out = self.queue
  self.queue = {}
  return out
end

function BattleSession:_send(msg)
  local net = self.net
  if net.closed then return false end
  net:send(msg)
  return true
end

function BattleSession:_begin()
  if self:isLower() then
    local t, why = self.table, nil
    if not t then
      if type(self.data) ~= "table" then return self:_fail("bad_table", "no_data") end
      t, why = Table.build(self.data, self.tableGen)
      if not t then return self:_fail("bad_table", why) end
    end
    local ok, vwhy = Table.validate(t, self.tableGen)
    if not ok then return self:_fail("bad_table", vwhy) end
    self.table = t
  end
  if type(self.records) ~= "table" or #self.records == 0 then return self:_fail("bad_party", "no_records") end
  if self.table then
    local ok, why = BattleSession.checkParty(self.records, self.table, { size = self.size, senderGen = self.gens[self.seat] })
    if not ok then return self:_fail("bad_party", why) end
    self:_send(Wire.table(self.table))
  end
  self:_send(Wire.party(self.records))
end

function BattleSession:_finish(outcome, why, opts)
  if self.result then return end
  opts = opts or {}
  self.result = { outcome = outcome, why = why, detail = opts.detail }
  self.phase = "over"
  if opts.bye then self:_send(Wire.bye(opts.bye)) end
  self:_note("over %s %s %s", tostring(outcome), tostring(why), tostring(opts.detail))
  self:_push({ kind = "over", outcome = outcome, why = why, detail = opts.detail })
  self:_report()
end

function BattleSession:_fail(why, detail)
  local bye = Wire.BYE[why] and why or "error"
  self:_finish("draw", why, { bye = bye, detail = detail })
end

function BattleSession:_report()
  if self.reported then return end
  local r = self.result
  if not r or r.why == "disconnect" then return end
  self.reported = true
  local client = self.client
  if type(client) ~= "table" then return end
  local word = REPORT[r.outcome] or "draw"
  local fn = client.report
  if type(fn) == "function" then pcall(fn, word) end
end

function BattleSession:_mapEnd(result)
  if result.draw then return "draw" end
  return result.winner == self.seat and "win" or "lose"
end

function BattleSession:_absorb(events)
  for _, ev in ipairs(events or {}) do
    self:_push(ev)
  end
  local m = self.match
  local h = m:hash(m.turn)
  if h and not self.hashSent[m.turn] then
    self.hashSent[m.turn] = true
    self.myHashes[m.turn] = h
    local out = h
    if self.tamperHash then out = self.tamperHash(m.turn, h) or h end
    self:_send(Wire.hash(m.turn, out))
  end
  self:_checkHashes()
  if self.result then return end
  if m.phase == "over" then
    self.overAt = self.overAt or self.now()
    self.matchResult = m.result
    self.phase = "ending"
    self:_tryEnd()
    return
  end
  if m.phase == "choose" then
    self.phase = "choose"
    self:_push({ kind = "prompt", what = "move", turn = m.turn + 1 })
  elseif m.phase == "replace" then
    if m:needs(self.seat) then
      self.phase = "replace"
      self:_push({ kind = "prompt", what = "replace", turn = m.turn, reason = m.need[self.seat].kind })
    else
      self.phase = "replace_wait"
      self:_push({ kind = "waiting", what = "replace" })
    end
    self:_tryReplace()
  end
end

function BattleSession:_tryEnd()
  if self.phase ~= "ending" or self.result then return end
  local m = self.match
  local turn = m.turn
  local theirs = self.peerHashes[turn]
  if theirs == nil and self.now() - self.overAt < self.timeouts.final then return end
  local r = self.matchResult
  self:_finish(self:_mapEnd(r), r.why, { winner = r.winner })
end

function BattleSession:_checkHashes()
  for turn, mine in pairs(self.myHashes) do
    local theirs = self.peerHashes[turn]
    if theirs ~= nil and theirs ~= mine then
      self:_note("desync turn %d mine %s theirs %s", turn, mine, theirs)
      self:_finish("draw", "desync", { bye = "desync", detail = turn })
      return
    end
  end
end

function BattleSession:_tryStart()
  if self.match or self.result then return end
  if not (self.table and self.peerRecords) then return end
  local parties = { [self.seat] = self.records, [self.peer] = self.peerRecords }
  local ok, m = pcall(Match.new, { table = self.table, parties = parties, seed = self.seed,
    names = self.names })
  if not ok then return self:_fail("error", tostring(m)) end
  self.match = m
  self:_push({ kind = "ready", seat = self.seat, table = self.table, parties = parties,
    names = self.names, tableGen = self.table.gen })
  local okS, events = pcall(m.start, m)
  if not okS then return self:_fail("error", tostring(events)) end
  self:_absorb(events)
end

function BattleSession:_onTable(msg)
  if self:isLower() then return self:_fail("bad_table", "from_higher_seat") end
  if self.table then return self:_fail("bad_table", "duplicate") end
  local ok, why = Wire.validate(msg, { gen = self.tableGen, bytes = msgBytes(msg) })
  if not ok then return self:_fail("bad_table", why) end
  self.table = msg.table
  local okP, pwhy = BattleSession.checkParty(self.records, self.table, { size = self.size, senderGen = self.gens[self.seat] })
  if not okP then return self:_fail("bad_party", pwhy) end
  if self.peerRecords then
    local okQ, qwhy = BattleSession.checkParty(self.peerRecords, self.table,
      { size = self.size, senderGen = self.gens[self.peer] })
    if not okQ then return self:_fail("bad_party", qwhy) end
  end
  self:_tryStart()
end

function BattleSession:_onParty(msg)
  if self.peerRecords then return self:_fail("bad_party", "duplicate") end
  if type(msg.records) ~= "table" then return self:_fail("bad_party", "shape") end
  if msgBytes(msg) > Wire.MAX_BYTES.g3u_party then return self:_fail("bad_party", "too_big") end
  if self.table then
    local ok, why = BattleSession.checkParty(msg.records, self.table,
      { size = self.size, senderGen = self.gens[self.peer] })
    if not ok then return self:_fail("bad_party", why) end
  end
  self.peerRecords = msg.records
  self:_tryStart()
end

function BattleSession:_tryResolve()
  local m = self.match
  if not m or m.phase ~= "choose" or self.result then return end
  local turn = m.turn + 1
  local mine, theirs = self.mine[turn], self.theirs[turn]
  if not (mine and theirs) then return end
  if not m:isLegal(self.peer, theirs) then
    return self:_finish("draw", "illegal", { bye = "illegal", detail = turn })
  end
  local acts = { [self.seat] = copyAct(mine), [self.peer] = copyAct(theirs) }
  local ok, events = pcall(m.submit, m, acts)
  if not ok then return self:_fail("error", tostring(events)) end
  self:_absorb(events)
end

function BattleSession:_tryReplace()
  local m = self.match
  if not m or m.phase ~= "replace" or self.result then return end
  local picks = {}
  for s = 0, 1 do
    if m:needs(s) then
      if s == self.seat then
        if not self.myRep then return end
        picks[s] = self.myRep
      else
        local rep = self.theirReps[1]
        if not rep then return end
        if not m:isLegal(s, { kind = "switch", index = rep.index }) then
          return self:_finish("draw", "illegal", { bye = "illegal", detail = m.turn })
        end
        picks[s] = rep.index
      end
    end
  end
  if picks[self.seat] then self.myRep = nil end
  if picks[self.peer] then table.remove(self.theirReps, 1) end
  local ok, events = pcall(m.replace, m, picks)
  if not ok then return self:_fail("error", tostring(events)) end
  self:_absorb(events)
end

function BattleSession:_onBye(msg)
  local why = msg.why
  if why == "forfeit" or why == "quit" or why == "timeout" then
    return self:_finish("win", "forfeit")
  end
  if why == "desync" then return self:_finish("draw", "desync") end
  if why == "illegal" then return self:_finish("draw", "illegal") end
  if why == "bad_table" or why == "bad_party" then return self:_finish("draw", why, { detail = "peer" }) end
  return self:_finish("draw", "error", { detail = why })
end

function BattleSession:_handle(msg)
  local t = msg.type
  if t == "xg_closed" then
    return self:_finish("draw", "disconnect", { detail = msg.why })
  end
  if msg.seat ~= nil and msg.seat ~= -1 and msg.seat ~= self.peer then return end
  local bytes = msgBytes(msg)
  local clean = {}
  for k, v in pairs(msg) do
    if k ~= "seat" and k ~= "relay" then clean[k] = v end
  end
  if t == "g3u_table" then return self:_onTable(clean) end
  if t == "g3u_party" then return self:_onParty(clean) end
  local ok, why = Wire.validate(clean, { bytes = bytes })
  if not ok then
    self:_note("drop %s %s", tostring(t), tostring(why))
    return self:_finish("draw", "illegal", { bye = "illegal", detail = t .. ":" .. tostring(why) })
  end
  if t == "g3u_bye" then return self:_onBye(clean) end
  if t == "g3u_hash" then
    if self.peerHashes[clean.turn] == nil then self.peerHashes[clean.turn] = clean.hash end
    self:_checkHashes()
    self:_tryEnd()
    return
  end
  if not self.match then return self:_fail("error", "early_" .. t) end
  if t == "g3u_action" then
    local m = self.match
    if clean.turn ~= m.turn + 1 or self.theirs[clean.turn] then
      return self:_finish("draw", "illegal", { bye = "illegal", detail = "turn" })
    end
    local act = Wire.toAction(clean)
    if m.phase == "choose" and not m:isLegal(self.peer, act) then
      return self:_finish("draw", "illegal", { bye = "illegal", detail = clean.turn })
    end
    self.theirs[clean.turn] = act
    self:_tryResolve()
  elseif t == "g3u_replace" then
    if clean.turn ~= self.match.turn then
      return self:_finish("draw", "illegal", { bye = "illegal", detail = "replace_turn" })
    end
    self.theirReps[#self.theirReps + 1] = { index = clean.index, turn = clean.turn }
    self:_tryReplace()
  end
end

local function wanted(msg)
  return type(msg) == "table" and OWN[msg.type] == true
end

function BattleSession:_drain()
  local net = self.net
  if type(net.takeWhere) == "function" then
    for _ = 1, 256 do
      if self.result then return end
      local msg = net:takeWhere(wanted)
      if not msg then return end
      self:_handle(msg)
    end
    return
  end
  if type(net.poll) == "function" then
    for _, msg in ipairs(net:poll() or {}) do
      if self.result then return end
      if wanted(msg) then self:_handle(msg) end
    end
  end
end

function BattleSession:_link()
  if self.linkState then return self.linkState() end
  if self.net.closed then return "gone" end
  return "ok"
end

function BattleSession:_watchLink()
  local state = self:_link()
  local now = self.now()
  if state == "gone" then
    if self.phase == "ending" then
      local r = self.matchResult
      return self:_finish(self:_mapEnd(r), r.why)
    end
    return self:_finish("draw", "disconnect")
  end
  if state == "resuming" then
    self.resumingSince = self.resumingSince or now
    if now - self.resumingSince > self.timeouts.resume then return self:_finish("draw", "disconnect") end
  else
    self.resumingSince = nil
  end
  local online = true
  if type(self.net.peerOnline) == "function" then
    local ok, v = pcall(self.net.peerOnline, self.net, self.peer)
    online = not ok or v ~= false
  end
  if online then
    self.peerGoneSince = nil
  else
    self.peerGoneSince = self.peerGoneSince or now
    if now - self.peerGoneSince > self.timeouts.peer then return self:_finish("draw", "disconnect") end
  end
  if not self.match and now - self.startedAt > self.timeouts.setup then
    return self:_finish("draw", "disconnect", { bye = "timeout", detail = "setup" })
  end
end

function BattleSession:update()
  if self.result then return end
  if type(self.net.update) == "function" then pcall(self.net.update, self.net) end
  self:_drain()
  if self.result then return end
  self:_tryStart()
  self:_tryEnd()
  if self.result then return end
  self:_watchLink()
end

function BattleSession:legal()
  local m = self.match
  if not m or self.result then return {} end
  if self.phase == "choose" or self.phase == "replace" then return m:legalActions(self.seat) end
  return {}
end

function BattleSession:choose(act)
  local m = self.match
  if self.phase ~= "choose" or not m then return false, "not_choosing" end
  if not m:isLegal(self.seat, act) then return false, "illegal" end
  local turn = m.turn + 1
  self.mine[turn] = copyAct(act)
  self:_send(Wire.action(turn, act))
  self.phase = "wait"
  self:_push({ kind = "waiting", what = "move" })
  self:_tryResolve()
  return true
end

function BattleSession:pickReplacement(index)
  local m = self.match
  if self.phase ~= "replace" or not m then return false, "not_replacing" end
  local act = { kind = "switch", index = index }
  if not m:isLegal(self.seat, act) then return false, "illegal" end
  self.myRep = index
  self:_send(Wire.replace(m.turn, index))
  self.phase = "replace_wait"
  self:_push({ kind = "waiting", what = "replace" })
  self:_tryReplace()
  return true
end

function BattleSession:forfeit()
  if self.result then return false end
  if self.phase == "choose" then return self:choose({ kind = "forfeit" }) end
  self:_finish("lose", "forfeit", { bye = "forfeit" })
  return true
end

function BattleSession:quit()
  if self.result then return false end
  self:_finish("lose", "forfeit", { bye = "quit" })
  return true
end

function BattleSession:side(seat)
  if seat == nil then return nil end
  return seat == self.seat and "me" or "foe"
end

function BattleSession:myParty()
  return self.match and self.match:party(self.seat) or nil
end

function BattleSession:foeParty()
  return self.match and self.match:party(self.peer) or nil
end

function BattleSession:activeMon(seat)
  local st = self.match and self.match.st
  if not st then return nil end
  local b = require("src.core.game3.battle.state").battler(st, seat)
  return b and b.mon, b
end

function BattleSession:active(seat)
  return self.match and self.match:active(seat) or nil
end

function BattleSession:over()
  return self.result ~= nil
end

function BattleSession:close()
  if not self.result then self:quit() end
end

return BattleSession
