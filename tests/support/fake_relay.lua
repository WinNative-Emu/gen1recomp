local Protocol2 = require("src.online.Protocol2")

local FakeRelay = {}
FakeRelay.__index = FakeRelay

local function copy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, val in pairs(v) do out[k] = copy(val) end
  return out
end

FakeRelay.copy = copy

function FakeRelay.transport()
  local t = { paired = true, closed = false, error = nil, inbox = {}, outbox = {} }
  function t:update() end
  function t:poll()
    local messages = self.inbox
    self.inbox = {}
    return messages
  end
  function t:send(msg) table.insert(self.outbox, copy(msg)) end
  function t:close() self.closed = true end
  return t
end

function FakeRelay.new(opts)
  opts = opts or {}
  return setmetatable({
    clock = opts.clock or function() return 0 end,
    sessions = {},
    order = {},
    rooms = {},
    roomNo = 0,
    inviteNo = 0,
    tokenNo = 0,
    invites = {},
    tokens = {},
    plazas = { union = {} },
    plazaRev = 0,
    wireless = {},
    groups = {},
    groupWatch = {},
    queue = {},
    directWatch = {},
    minProtocol = opts.minProtocol or 3,
    legacy = opts.legacy == true,
    epoch = opts.epoch or 1000,
    log = {},
  }, FakeRelay)
end

function FakeRelay:now()
  return self.epoch + math.floor(self.clock() * 1000)
end

function FakeRelay:seat(id, name)
  local s = { id = id, name = name, transport = FakeRelay.transport(),
              online = true, profiles = {}, presence = {}, since = 0,
              clientSeq = {} }
  self.sessions[id] = s
  self.order[#self.order + 1] = id
  return s
end

function FakeRelay:reconnect(s)
  s.transport = FakeRelay.transport()
  return s.transport
end

function FakeRelay:drop(s)
  s.transport.closed = true
  s.online = false
  local g = self:groupOf(s)
  if g and g.leader == s.id then
    self:groupBroadcast(g, self:groupStateMsg(g))
  elseif g then
    self:leaveGroup(s, true)
    s.groupLost = g.leader
  end
end

function FakeRelay:forget(s)
  s.forgotten = true
  for _, inst in ipairs(self.plazas.union) do inst.slots[s.id] = nil end
  self.wireless[s.id] = nil
  s.presence.board = nil
end

function FakeRelay:to(s, msg)
  if not s or not s.online or s.transport.closed then return end
  table.insert(s.transport.inbox, copy(msg))
end

function FakeRelay:sent(s, kind)
  local out = {}
  for _, m in ipairs(self.log) do
    if m.from == s.id and (kind == nil or m.msg.type == kind) then out[#out + 1] = m.msg end
  end
  return out
end

local function profileOf(s, engine)
  for _, p in ipairs(s.profiles or {}) do
    if engine == nil or p.engine == engine then return p end
  end
  return nil
end

local function compatible(a, b, battle)
  if type(a) ~= "table" or type(b) ~= "table" then return false end
  if a.engine ~= b.engine or a.fingerprint ~= b.fingerprint then return false end
  if battle and a.rulesetId ~= b.rulesetId then return false end
  return true
end

function FakeRelay:newRoom(fields)
  self.roomNo = self.roomNo + 1
  local room = {
    room = ("r%016x"):format(0x3000 + self.roomNo),
    intent = fields.intent or "battle",
    engine = fields.engine or 3,
    profile = copy(fields.profile),
    seats = fields.seats or 2,
    locked = fields.pin ~= nil,
    pin = fields.pin,
    listed = fields.listed ~= false,
    auto = fields.auto == true,
    origin = fields.origin or "create",
    players = {},
    spectators = {},
    stage = "waiting",
    host = nil,
    seed = nil,
    match = nil,
    matchNo = 0,
    maxSpectators = 8,
    leader = fields.intent == "minigame" and 0 or nil,
    epoch = 1,
    log = {},
    seq = 0,
    barrier = { n = 1, confirms = {} },
    pinFails = {},
    since = self:now() + self.roomNo,
  }
  self.rooms[room.room] = room
  return room
end

function FakeRelay:roomStateMsg(room)
  local players, spectators = {}, {}
  for _, p in ipairs(room.players) do
    local s = self.sessions[p.id]
    local row = { id = p.id, name = p.name, verified = true,
                  ready = false, online = s and s.online or false,
                  seat = p.seat }
    if room.xg then
      row.gen = room.xg.gens[p.seat + 1]
      row.avatar = s and copy(s.avatar) or nil
    end
    players[#players + 1] = row
  end
  for _, sp in ipairs(room.spectators) do
    spectators[#spectators + 1] = { id = sp.id, name = sp.name, verified = true,
                                    online = true }
  end
  return { type = "room_state", room = room.room, intent = room.intent,
           engine = room.engine, profile = room.profile, seats = room.seats,
           locked = room.locked, listed = room.listed, auto = room.auto,
           origin = room.origin, players = players, spectators = spectators,
           stage = room.stage, host = room.host, seed = room.seed,
           match = room.match, maxSpectators = room.maxSpectators,
           leader = room.leader, deadlines = {},
           mode = room.xg and room.xg.mode or nil,
           xg = room.xg and self:xgSnapshot(room) or nil }
end

function FakeRelay:roomBroadcast(room, msg)
  for _, p in ipairs(room.players) do self:to(self.sessions[p.id], msg) end
  for _, sp in ipairs(room.spectators) do self:to(self.sessions[sp.id], msg) end
end

function FakeRelay:roomState(room)
  self:roomBroadcast(room, self:roomStateMsg(room))
end

function FakeRelay:seatPlayer(room, s)
  local p = { id = s.id, name = s.name, seat = #room.players }
  room.players[#room.players + 1] = p
  s.room = room.room
  if not room.host then room.host = s.id end
  return p
end

function FakeRelay:startRoom(room)
  room.stage = "battling"
  room.matchNo = room.matchNo + 1
  room.match = room.room .. "-m" .. room.matchNo
  room.seed = 424242
  self:roomState(room)
  local players = {}
  for _, p in ipairs(room.players) do
    players[#players + 1] = { id = p.id, name = p.name, seat = p.seat }
  end
  local ruleset = room.profile and room.profile.rulesetId or nil
  for _, p in ipairs(room.players) do
    self:to(self.sessions[p.id], {
      type = "match_start", room = room.room, match = room.match,
      role = Protocol2.SEAT_ROLES[p.seat], seat = p.seat, seats = room.seats,
      engine = room.engine, seed = room.seed, ruleset = ruleset,
      players = players })
  end
  for _, sp in ipairs(room.spectators) do
    self:to(self.sessions[sp.id], {
      type = "match_start_spectate", room = room.room, match = room.match,
      role = "spectator", seats = room.seats, engine = room.engine,
      seed = room.seed, ruleset = ruleset, players = players })
  end
end

function FakeRelay:seatOf(room, id)
  for _, p in ipairs(room.players) do
    if p.id == id then return p.seat end
  end
  return nil
end

function FakeRelay:isSpectator(room, id)
  for _, sp in ipairs(room.spectators) do
    if sp.id == id then return true end
  end
  return false
end

function FakeRelay:appendLog(room, entry)
  room.seq = room.seq + 1
  entry.seq = room.seq
  room.log[#room.log + 1] = entry
  return entry
end

function FakeRelay:relayInner(room, inner)
  local entry = self:appendLog(room, { seat = -1, relay = true, msg = copy(inner) })
  self:roomBroadcast(room, { type = "room_msg", seq = entry.seq, seat = -1,
                             relay = true, msg = copy(inner) })
end

local RELAY_ONLY = Protocol2.RELAY_INNER

function FakeRelay:fanout(s, clientSeq, inner)
  local room = s.room and self.rooms[s.room]
  if not room or type(inner) ~= "table" then return end
  local seat = self:seatOf(room, s.id)
  if seat == nil then return end
  if room.xg and self:xgRoomMsg(room, s, seat, clientSeq, inner) then return end
  if RELAY_ONLY[inner.type] then return end
  if inner.type == "game3_mg_state" and room.leader ~= seat then return end
  room.clientSeq = room.clientSeq or {}
  if clientSeq and room.clientSeq[s.id] and clientSeq <= room.clientSeq[s.id] then
    return
  end
  if clientSeq then room.clientSeq[s.id] = clientSeq end
  local entry = self:appendLog(room, { seat = seat, clientSeq = clientSeq,
                                       msg = copy(inner) })
  for _, p in ipairs(room.players) do
    if p.id ~= s.id then
      self:to(self.sessions[p.id], { type = "room_msg", seq = entry.seq,
                                     clientSeq = clientSeq, seat = seat,
                                     msg = copy(inner) })
    end
  end
  for _, sp in ipairs(room.spectators) do
    self:to(self.sessions[sp.id], { type = "room_msg", seq = entry.seq,
                                    clientSeq = clientSeq, seat = seat,
                                    msg = copy(inner) })
  end
  if inner.type == "game3_trade_confirm" or inner.type == "trade_confirm" then
    local b = room.barrier
    b.confirms[seat] = inner.digest
    if b.confirms[0] and b.confirms[1] then
      if b.confirms[0] == b.confirms[1] then
        self:relayInner(room, { type = "trade_commit", n = b.n,
                                digests = { b.confirms[0], b.confirms[1] } })
      else
        self:relayInner(room, { type = "trade_abort", n = b.n, why = "digest" })
      end
      room.barrier = { n = b.n + 1, confirms = {} }
    end
  end
end

function FakeRelay:replay(s, from)
  local room = s.room and self.rooms[s.room]
  if not room then return end
  local mine = self:seatOf(room, s.id)
  local msgs = {}
  for _, e in ipairs(room.log) do
    if e.seq > from and (e.relay or e.seat ~= mine) then
      msgs[#msgs + 1] = { seq = e.seq, clientSeq = e.clientSeq, seat = e.seat,
                          relay = e.relay, msg = copy(e.msg) }
    end
  end
  self:to(s, { type = "room_replay", from = from, msgs = msgs,
               yourSeq = (room.clientSeq or {})[s.id] or 0 })
end

function FakeRelay:migrateLeader(roomId)
  local room = self.rooms[roomId]
  local prev = room.leader
  local nextSeat
  for _, p in ipairs(room.players) do
    local s = self.sessions[p.id]
    if p.seat > prev and s and s.online then nextSeat = p.seat break end
  end
  if nextSeat == nil then
    for _, p in ipairs(room.players) do
      local s = self.sessions[p.id]
      if p.seat ~= prev and s and s.online then nextSeat = p.seat break end
    end
  end
  room.leader = nextSeat
  room.epoch = room.epoch + 1
  self:relayInner(room, { type = "game3_mg_leader", seat = nextSeat, prev = prev,
                          epoch = room.epoch })
  self:roomState(room)
end

function FakeRelay:joinError(s, reason, extra)
  local msg = { type = "join_error", reason = reason }
  for k, v in pairs(extra or {}) do msg[k] = v end
  self:to(s, msg)
end

function FakeRelay:handleRoomJoin(s, msg)
  local room
  local viaInvite = false
  if msg.invite then
    local tok = self.tokens[msg.invite]
    if not tok then return self:joinError(s, "invite_expired") end
    room = self.rooms[tok.room]
    viaInvite = true
  elseif msg.room then
    room = self.rooms[msg.room]
  else
    return self:joinError(s, "bad_room")
  end
  if not room then return self:joinError(s, "not_found") end
  if not room.listed and not viaInvite then return self:joinError(s, "not_found") end
  if room.locked and not viaInvite then
    local fails = room.pinFails[s.id] or 0
    if fails >= 5 then return self:joinError(s, "pin_locked", { retryAt = self:now() + 600000 }) end
    if msg.pin == nil then return self:joinError(s, "pin_required") end
    if msg.pin ~= room.pin then
      fails = fails + 1
      room.pinFails[s.id] = fails
      if fails >= 5 then
        return self:joinError(s, "pin_locked", { retryAt = self:now() + 600000 })
      end
      return self:joinError(s, "bad_pin", { triesLeft = 5 - fails })
    end
  end
  if not compatible(msg.profile, room.profile, room.intent == "battle") then
    return self:joinError(s, "profile_mismatch")
  end
  if msg.as == "spectator" then
    room.spectators[#room.spectators + 1] = { id = s.id, name = s.name }
    s.room = room.room
    self:roomState(room)
    if room.stage == "battling" then
      self:to(s, { type = "match_start_spectate", room = room.room, match = room.match,
                   role = "spectator", seats = room.seats, engine = room.engine,
                   seed = room.seed })
      self:replay(s, 0)
    end
    return
  end
  if #room.players >= room.seats then return self:joinError(s, "full") end
  self:seatPlayer(room, s)
  if #room.players == room.seats and room.engine == 3 then
    self:startRoom(room)
  else
    self:roomState(room)
  end
end

local XG_FAMILIES = {
  [1] = { red = true, blue = true, yellow = true },
  [2] = { gold = true, silver = true, crystal = true },
  [3] = { firered = true, leafgreen = true, emerald = true, ruby = true, sapphire = true },
}
FakeRelay.XG_FAMILIES = XG_FAMILIES
local XG_DEX = { [1] = { 151, 165 }, [2] = { 251, 251 }, [3] = { 386, 354 } }
local XG_MODE = { xg_battle = "battle", xg_trade = "trade" }
local XG_STATUS = { battle = "battling", trade = "trading" }

local function memberOf(s, slot)
  local status = s.status or (s.recruiting and "recruiting" or "idle")
  if s.xgen then status = s.xgStatus or s.presence.status or status end
  local out = { id = s.id, name = s.name, verified = true, slot = slot,
                online = s.online, status = status,
                avatar = copy(s.avatar), recruiting = copy(s.recruiting),
                board = copy(s.presence.board), group = copy(s.group) }
  if s.xgen then out.caps = copy(s.caps) end
  return out
end

local function xgAvatar(raw, gen)
  if type(raw) ~= "table" or type(raw.version) ~= "string" or not XG_FAMILIES[gen][raw.version] then
    return nil
  end
  local style = raw.style
  if style == nil then style = "player" end
  if type(style) ~= "string" or #style > 16 or not style:match("^[a-z0-9:_%-]+$") then return nil end
  local name = tostring(raw.name or "")
  return { name = name:sub(1, 10), trainerId = math.floor(tonumber(raw.trainerId) or 0) % 65536,
           gender = raw.gender == 1 and 1 or 0, version = raw.version, style = style, gen = gen }
end

local function xgCaps(raw)
  if type(raw) ~= "table" then return nil end
  if type(raw.proto) ~= "number" or type(raw.policy) ~= "number" then return nil end
  local gens = {}
  for k, list in pairs(raw.gens or {}) do
    local gen = tonumber(k)
    if not XG_FAMILIES[gen] or type(list) ~= "table" then return nil end
    local out = {}
    for _, e in ipairs(list) do
      if type(e) ~= "table" or not XG_FAMILIES[gen][e.version] or type(e.fp) ~= "string" then return nil end
      out[#out + 1] = { version = e.version, fp = e.fp:lower() }
    end
    gens[tostring(gen)] = out
  end
  return { proto = raw.proto, policy = raw.policy, gens = gens }
end

function FakeRelay:plazaInstance(s)
  for i, inst in ipairs(self.plazas.union) do
    if inst.slots[s.id] then return inst, i end
  end
  return nil
end

FakeRelay.PLAZA_CAP = 40

function FakeRelay:plazaDelta(inst, index, fields, except)
  self.plazaRev = self.plazaRev + 1
  inst.rev = self.plazaRev
  local msg = { type = "plaza_delta", kind = "union", instance = index, rev = inst.rev,
                joined = fields.joined or {}, left = fields.left or {},
                changed = fields.changed or {} }
  for id in pairs(inst.slots) do
    if id ~= except then self:to(self.sessions[id], msg) end
  end
end

function FakeRelay:plazaStateMsg(s)
  local inst, index = self:plazaInstance(s)
  local members = {}
  for id, slot in pairs(inst.slots) do
    members[#members + 1] = memberOf(self.sessions[id], slot)
  end
  table.sort(members, function(a, b) return a.slot < b.slot end)
  return { type = "plaza_state", kind = "union", instance = index, cap = FakeRelay.PLAZA_CAP,
           rev = inst.rev, you = inst.slots[s.id], members = members }
end

function FakeRelay:plazaJoin(s, msg)
  if msg.kind == "wireless" then
    self.wireless[s.id] = true
    return
  end
  local xgen = not self.legacy and (msg.xgen == 1 or msg.xgen == true)
  if xgen then
    if not (math.floor(tonumber(msg.cap) or 0) >= FakeRelay.PLAZA_CAP) then
      self:to(s, { type = "upgrade_required", protocol = self.minProtocol, minBuild = nil,
                   text = "This build is too old for online play. Please update." })
      s.transport.closed = true
      return
    end
    local p = msg.profile
    local engine = type(p) == "table" and tonumber(p.engine) or nil
    if not XG_FAMILIES[engine] or not XG_FAMILIES[engine][p.version]
       or (engine ~= 3 and p.rulesetId ~= "union") then
      return self:joinError(s, "bad_profile")
    end
    local av = xgAvatar(msg.avatar, engine)
    if not av then return self:joinError(s, "bad_avatar") end
    if msg.caps ~= nil then
      local caps = xgCaps(msg.caps)
      if not caps then return self:joinError(s, "bad_caps") end
      s.caps = caps
    end
    s.avatar = av
    s.xgen = true
    s.plazaProfile = copy(p)
  else
    if type(msg.profile) ~= "table" or msg.profile.engine ~= 3 then
      return self:joinError(s, "bad_profile")
    end
    if not (math.floor(tonumber(msg.cap) or 0) >= FakeRelay.PLAZA_CAP) then
      self:to(s, { type = "upgrade_required", protocol = self.minProtocol, minBuild = nil,
                   text = "This build is too old for online play. Please update." })
      s.transport.closed = true
      return
    end
    s.avatar = copy(msg.avatar)
    if self.legacy and s.avatar then s.avatar.style, s.avatar.gen = nil, nil end
    s.xgen = false
    s.plazaProfile = copy(msg.profile)
  end
  local shard = xgen and "u" or "g3"
  s.where = "union"
  local current = self:plazaInstance(s)
  if current and current.shard ~= shard then self:plazaLeave(s, "union") end
  if self:plazaInstance(s) then return self:to(s, self:plazaStateMsg(s)) end
  local best, bestIndex
  for i, inst in ipairs(self.plazas.union) do
    local n = 0
    for _ in pairs(inst.slots) do n = n + 1 end
    if inst.shard == shard and n < FakeRelay.PLAZA_CAP and (not best or n > best.n) then
      best, bestIndex = { inst = inst, n = n }, i
    end
  end
  local inst, index
  if best then
    inst, index = best.inst, bestIndex
  else
    inst = { slots = {}, rev = 0, shard = shard }
    self.plazas.union[#self.plazas.union + 1] = inst
    index = #self.plazas.union
  end
  local used = {}
  for _, slot in pairs(inst.slots) do used[slot] = true end
  local slot = 1
  while used[slot] do slot = slot + 1 end
  inst.slots[s.id] = slot
  self:plazaDelta(inst, index, { joined = { memberOf(s, slot) } }, s.id)
  self:to(s, self:plazaStateMsg(s))
end

function FakeRelay:plazaLeave(s, kind)
  if kind == "wireless" then
    self.wireless[s.id] = nil
    return
  end
  local inst, index = self:plazaInstance(s)
  if not inst then return end
  inst.slots[s.id] = nil
  s.where = "launcher"
  self:plazaDelta(inst, index, { left = { s.id } })
end

function FakeRelay:plazaChanged(s)
  local inst, index = self:plazaInstance(s)
  if not inst then return end
  self:plazaDelta(inst, index, { changed = { memberOf(s, inst.slots[s.id]) } })
end

function FakeRelay:counts()
  local union, trade, battle, minigame = 0, 0, 0, 0
  for _, inst in ipairs(self.plazas.union) do
    for _ in pairs(inst.slots) do union = union + 1 end
  end
  for _, room in pairs(self.rooms) do
    if room.engine == 3 then
      local n = #room.players
      if room.intent == "trade" then trade = trade + n
      elseif room.intent == "battle" then battle = battle + n
      elseif room.intent == "minigame" then minigame = minigame + n end
    end
  end
  return { type = "plaza_counts", union = union, trade = trade, battle = battle,
           chat = 0, minigame = minigame, total = trade + battle + union }
end

function FakeRelay:closeInvite(inv, why, room)
  self.invites[inv.id] = nil
  local msg = { type = "invite_closed", id = inv.id, why = why, room = room }
  self:to(self.sessions[inv.from], msg)
  self:to(self.sessions[inv.to], msg)
end

function FakeRelay:acceptInvite(inv)
  local from, to = self.sessions[inv.from], self.sessions[inv.to]
  if inv.activity == "watch" then
    local room = self.rooms[inv.detail and inv.detail.room or ""]
    self:closeInvite(inv, "accepted", room and room.room)
    if room then
      room.spectators[#room.spectators + 1] = { id = to.id, name = to.name }
      to.room = room.room
      self:roomState(room)
    end
    return
  end
  if XG_MODE[inv.activity or ""] then return self:xgAccept(inv, from, to) end
  local profile = copy(inv.profile or profileOf(from, 3))
  local room = self:newRoom({ intent = Protocol2.ACTIVITY_INTENT[inv.activity] or "battle",
                              engine = profile and profile.engine or 3,
                              profile = profile, seats = 2, listed = false,
                              origin = "invite" })
  self:closeInvite(inv, "accepted", room.room)
  self:seatPlayer(room, from)
  self:seatPlayer(room, to)
  if room.engine == 3 then self:startRoom(room) else self:roomState(room) end
end

local INVITABLE = { idle = true, recruiting = true, waiting = true }

function FakeRelay:handleInvite(s, msg)
  local refuse = function(why)
    self:to(s, { type = "invite_closed", why = why, to = msg.to,
                 activity = msg.activity })
  end
  if msg.to == s.id then return refuse("self") end
  local target = self.sessions[msg.to or ""]
  if not target or not target.online then return refuse("offline") end
  if XG_MODE[msg.activity or ""] then
    if self.legacy then return refuse("bad_activity") end
    local a, b = self:plazaInstance(s), self:plazaInstance(target)
    if not (s.xgen and target.xgen and a and a == b) then return refuse("not_plaza") end
    if s.room then return refuse("busy") end
    local status = target.xgStatus or target.presence.status or "idle"
    if target.room or not INVITABLE[status] then return refuse("busy") end
  elseif target.room or target.presence.where == "game" then
    return refuse("busy")
  end
  for _, inv in pairs(self.invites) do
    if inv.from == target.id and inv.to == s.id and inv.activity == msg.activity then
      self.inviteNo = self.inviteNo + 1
      local mine = ("i%016x"):format(self.inviteNo)
      self:to(s, { type = "invite_closed", id = mine, why = "crossed",
                   to = msg.to, activity = msg.activity })
      self:acceptInvite(inv)
      return
    end
  end
  self.inviteNo = self.inviteNo + 1
  local inv = { id = ("i%016x"):format(self.inviteNo), from = s.id, to = target.id,
                activity = msg.activity, detail = copy(msg.detail),
                profile = copy(msg.profile), expiresAt = self:now() + 20000 }
  self.invites[inv.id] = inv
  local queued = self.queue[target.id]
  if queued and queued.auto and queued.activity == msg.activity then
    self.queue[target.id] = nil
    self:to(target, { type = "direct_state", activity = msg.activity, queued = false,
                      why = "paired" })
    self:acceptInvite(inv)
    return
  end
  self:to(s, { type = "invite_sent", id = inv.id, to = inv.to,
               activity = inv.activity, expiresAt = inv.expiresAt })
  self:to(target, { type = "invite_in", id = inv.id,
                    from = { id = s.id, name = s.name, verified = true,
                             where = s.presence.where or "launcher",
                             avatar = copy(s.avatar) },
                    activity = inv.activity, detail = copy(inv.detail),
                    expiresAt = inv.expiresAt })
end

function FakeRelay:handleInviteReply(s, msg)
  local inv = self.invites[msg.id or ""]
  if not inv or inv.to ~= s.id then return end
  if msg.accept then self:acceptInvite(inv) else self:closeInvite(inv, "declined") end
end

function FakeRelay:groupStateMsg(g)
  local function people(list)
    local out = copy(list)
    for _, p in ipairs(out) do
      local s = self.sessions[p.id]
      p.online = s ~= nil and s.online == true
    end
    return out
  end
  return { type = "group_state", leader = g.leader, activity = g.activity,
           min = g.min, max = g.max, members = people(g.members),
           pending = people(g.pending) }
end

function FakeRelay:groupOf(s)
  if self.groups[s.id] then return self.groups[s.id] end
  for _, g in pairs(self.groups) do
    for _, list in ipairs({ g.members, g.pending }) do
      for _, p in ipairs(list) do
        if p.id == s.id then return g end
      end
    end
  end
  return nil
end

function FakeRelay:leaveGroup(s, quiet)
  local g = self:groupOf(s)
  if not g then return end
  if g.leader == s.id then
    self.groups[s.id] = nil
    s.recruiting = nil
    self:groupBroadcast(g, { type = "group_closed", leader = g.leader, why = "leader_left" })
    return
  end
  for _, list in ipairs({ g.members, g.pending }) do
    for i = #list, 1, -1 do
      if list[i].id == s.id then table.remove(list, i) end
    end
  end
  for i, m in ipairs(g.members) do m.seat = i - 1 end
  local lead = self.sessions[g.leader]
  if lead and lead.recruiting then lead.recruiting.joined = #g.members end
  if not quiet then self:to(s, { type = "group_closed", leader = g.leader, why = "left" }) end
  self:groupBroadcast(g, self:groupStateMsg(g))
end

function FakeRelay:groupBroadcast(g, msg)
  for _, m in ipairs(g.members) do self:to(self.sessions[m.id], msg) end
  for _, m in ipairs(g.pending) do self:to(self.sessions[m.id], msg) end
end

function FakeRelay:groupListMsg(activity)
  local groups = {}
  for _, g in pairs(self.groups) do
    if g.activity == activity then
      local leader = self.sessions[g.leader]
      groups[#groups + 1] = { leader = g.leader, name = leader.name,
                              avatar = copy(leader.avatar), version = "firered",
                              joined = #g.members, min = g.min, max = g.max }
    end
  end
  table.sort(groups, function(a, b) return a.leader < b.leader end)
  return { type = "group_list", activity = activity, groups = groups }
end

function FakeRelay:handleGroup(s, msg)
  local kind = msg.type
  if kind == "group_open" then
    local cap = Protocol2.GROUP_CAPACITY[msg.activity or ""]
    if not cap then return self:joinError(s, "bad_activity") end
    s.avatar = copy(msg.avatar) or s.avatar
    local g = { leader = s.id, activity = msg.activity, min = cap[1], max = cap[2],
                members = { { id = s.id, name = s.name, avatar = copy(s.avatar), seat = 0 } },
                pending = {} }
    self.groups[s.id] = g
    s.recruiting = { activity = msg.activity, joined = 1, min = cap[1], max = cap[2] }
    self:to(s, self:groupStateMsg(g))
    self:plazaChanged(s)
  elseif kind == "group_list" then
    if msg.activity == nil then
      self.groupWatch[s.id] = nil
      return
    end
    self.groupWatch[s.id] = msg.activity
    self:to(s, self:groupListMsg(msg.activity))
  elseif kind == "group_join" then
    local g = self.groups[msg.leader or ""]
    if not g then return self:joinError(s, "group_not_found") end
    if #g.members >= g.max then return self:joinError(s, "group_full") end
    s.avatar = copy(msg.avatar) or s.avatar
    g.pending[#g.pending + 1] = { id = s.id, name = s.name, avatar = copy(s.avatar) }
    self:to(self.sessions[g.leader], { type = "group_request", from = s.id,
                                       name = s.name, avatar = copy(s.avatar) })
    self:groupBroadcast(g, self:groupStateMsg(g))
  elseif kind == "group_accept" then
    local g = self.groups[s.id]
    if not g then return self:joinError(s, "not_leader") end
    for i, p in ipairs(g.pending) do
      if p.id == msg.from then
        table.remove(g.pending, i)
        if msg.ok then
          p.seat = #g.members
          g.members[#g.members + 1] = p
        else
          self:to(self.sessions[p.id], { type = "group_closed", leader = g.leader,
                                         why = "declined" })
        end
        break
      end
    end
    s.recruiting.joined = #g.members
    self:groupBroadcast(g, self:groupStateMsg(g))
  elseif kind == "group_start" then
    local g = self.groups[s.id]
    if not g then return self:joinError(s, "not_leader") end
    if #g.members < g.min then return self:joinError(s, "group_below_min") end
    self.groups[s.id] = nil
    s.recruiting = nil
    local room = self:newRoom({ intent = Protocol2.ACTIVITY_INTENT[g.activity],
                                engine = 3, profile = profileOf(s, 3),
                                seats = #g.members, listed = false, origin = "group" })
    for _, m in ipairs(g.members) do self:seatPlayer(room, self.sessions[m.id]) end
    self:startRoom(room)
    for _, m in ipairs(g.pending) do
      self:to(self.sessions[m.id], { type = "group_closed", leader = g.leader, why = "full" })
    end
    g.pending = {}
    self:groupBroadcast(g, { type = "group_closed", leader = g.leader, why = "started" })
  elseif kind == "group_leave" then
    self:leaveGroup(s, false)
  end
end

function FakeRelay:directEntries(activity, viewer)
  local entries = {}
  for id, q in pairs(self.queue) do
    if id ~= viewer.id and q.activity == activity and q.auto then
      local s = self.sessions[id]
      entries[#entries + 1] = { kind = "player", id = id, name = s.name, verified = true,
                                avatar = copy(q.avatar), version = "firered",
                                preview = copy(q.preview), since = q.since }
    end
  end
  for _, room in pairs(self.rooms) do
    if room.origin == "direct" and room.listed and room.stage == "waiting"
       and room.activity == activity and #room.players < room.seats then
      local host = self.sessions[room.host]
      entries[#entries + 1] = { kind = "room", room = room.room, host = room.host,
                                name = host.name, avatar = copy(host.avatar),
                                version = "firered", locked = room.locked,
                                auto = room.auto, seats = room.seats,
                                players = #room.players, since = room.since }
    end
  end
  table.sort(entries, function(a, b) return (a.since or 0) < (b.since or 0) end)
  return entries
end

function FakeRelay:pushDirect(activity)
  for id, act in pairs(self.directWatch) do
    if act == activity then
      local s = self.sessions[id]
      self:to(s, { type = "direct_list", activity = activity,
                   entries = self:directEntries(activity, s) })
    end
  end
end

function FakeRelay:paired(s, activity)
  self.queue[s.id] = nil
  self:to(s, { type = "direct_state", activity = activity, queued = false,
               why = "paired" })
end

function FakeRelay:tryPair(activity)
  local seats = activity == "battle_multi" and 4 or 2
  local waiting = {}
  for id, q in pairs(self.queue) do
    if q.activity == activity and q.auto then waiting[#waiting + 1] = { id = id, q = q } end
  end
  table.sort(waiting, function(a, b) return a.q.since < b.q.since end)
  for _, room in pairs(self.rooms) do
    if room.origin == "direct" and room.activity == activity and room.stage == "waiting"
       and (not room.locked or room.auto) and #waiting > 0 then
      while #waiting > 0 and #room.players < room.seats do
        local w = table.remove(waiting, 1)
        local s = self.sessions[w.id]
        self:paired(s, activity)
        self:seatPlayer(room, s)
      end
      if #room.players == room.seats then self:startRoom(room) else self:roomState(room) end
    end
  end
  while #waiting >= seats do
    local picked = {}
    for i = 1, seats do picked[i] = table.remove(waiting, 1) end
    local first = self.sessions[picked[1].id]
    local room = self:newRoom({ intent = Protocol2.ACTIVITY_INTENT[activity],
                                engine = 3, profile = picked[1].q.profile,
                                seats = seats, listed = false, origin = "direct" })
    room.activity = activity
    for _, w in ipairs(picked) do
      local s = self.sessions[w.id]
      self:paired(s, activity)
      self:seatPlayer(room, s)
    end
    room.host = first.id
    self:startRoom(room)
  end
  self:pushDirect(activity)
end

function FakeRelay:handleDirect(s, msg)
  local kind = msg.type
  if kind == "direct_queue" then
    if not Protocol2.DIRECT_ACTIVITIES[msg.activity or ""] then
      return self:joinError(s, "bad_activity")
    end
    s.avatar = copy(msg.avatar) or s.avatar
    if msg.pin ~= nil or msg.auto == false then
      local room = self:newRoom({ intent = Protocol2.ACTIVITY_INTENT[msg.activity],
                                  engine = 3, profile = msg.profile,
                                  seats = msg.activity == "battle_multi" and 4 or 2,
                                  pin = msg.pin, auto = msg.auto, origin = "direct" })
      room.activity = msg.activity
      self:seatPlayer(room, s)
      self:to(s, { type = "direct_state", activity = msg.activity, queued = false,
                   hosting = room.room })
      self:roomState(room)
      self:tryPair(msg.activity)
      return
    end
    self.queue[s.id] = { activity = msg.activity, auto = true, profile = copy(msg.profile),
                         avatar = copy(msg.avatar), preview = copy(msg.preview),
                         since = self:now() + #self.log }
    self:to(s, { type = "direct_state", activity = msg.activity, queued = true })
    self:tryPair(msg.activity)
  elseif kind == "direct_list" then
    if msg.activity == nil then
      self.directWatch[s.id] = nil
      return
    end
    self.directWatch[s.id] = msg.activity
    self:to(s, { type = "direct_list", activity = msg.activity,
                 entries = self:directEntries(msg.activity, s) })
  elseif kind == "direct_leave" then
    self.queue[s.id] = nil
    self.directWatch[s.id] = nil
    self:to(s, { type = "direct_state", queued = false, why = "left" })
  end
end

function FakeRelay:xgSnapshot(room)
  local x = room.xg
  local rosters, offers = {}, {}
  for i = 1, 2 do
    local r, o = x.rosters[i], x.offers[i]
    rosters[i] = r and { size = r.size, digest16 = r.digest16 } or nil
    offers[i] = o and { offerRev = o.offerRev, digest16 = o.digest16 } or nil
  end
  return { mode = x.mode, rev = x.rev, gens = copy(x.gens), rules = copy(x.rules),
           blocked = x.blocked, size = x.size, caps = { x.caps[1] ~= nil, x.caps[2] ~= nil },
           rosters = rosters, sizeReq = { x.sizeReq[1], x.sizeReq[2] }, offers = offers,
           ready = { x.ready[1] ~= nil, x.ready[2] ~= nil } }
end

function FakeRelay:xgAccept(inv, from, to)
  local a, b = self:plazaInstance(from), self:plazaInstance(to)
  if not (from.xgen and to.xgen and a and a == b) then return self:closeInvite(inv, "not_plaza") end
  if from.room or to.room then return self:closeInvite(inv, "busy") end
  local pf, pt = from.plazaProfile, to.plazaProfile
  local room = self:newRoom({ intent = "xg", engine = pf.engine, profile = pf, seats = 2,
                              listed = false, origin = "invite" })
  room.stage = "prep"
  room.maxSpectators = 0
  room.activity = inv.activity
  room.xg = { mode = XG_MODE[inv.activity], gens = { pf.engine, pt.engine },
              fps = { pf.fingerprint, pt.fingerprint }, rev = 0,
              caps = { copy(from.caps), copy(to.caps) }, rules = nil, rulesSig = nil,
              blocked = nil, counter = nil, rosters = {}, sizeReq = {}, size = nil,
              offers = {}, ready = {}, agreed = nil, closed = false }
  self:closeInvite(inv, "accepted", room.room)
  self:seatPlayer(room, from)
  self:seatPlayer(room, to)
  room.host = from.id
  for _, who in ipairs({ from, to }) do
    who.xgStatus = XG_STATUS[room.xg.mode]
    self:plazaChanged(who)
  end
  self:roomState(room)
  self:xgResolve(room, false)
  return room
end

local function rulesSig(r)
  if not r then return "" end
  if r.blocked then return "blocked:" .. r.blocked end
  local t = r.rules
  return table.concat({ t.mode, tostring(t.ruleset), tostring(t.gen), tostring(t.dexMax),
                        tostring(t.moveGen), tostring(t.policy) }, "|")
end

function FakeRelay:xgRulesFor(room)
  local x = room.xg
  local c0, c1 = x.caps[1], x.caps[2]
  if not c0 or not c1 then return nil end
  if c0.proto ~= c1.proto then return { blocked = "proto" } end
  local gens = copy(x.gens)
  if x.mode == "trade" then
    if c0.policy ~= c1.policy then return { blocked = "policy_mismatch" } end
    return { rules = { mode = "trade", gens = gens, policy = c0.policy } }
  end
  if gens[1] == gens[2] then
    if gens[1] ~= 3 and x.fps[1] ~= x.fps[2] then return { blocked = "fingerprint" } end
    return { rules = { mode = "battle", ruleset = "native", gen = gens[1], gens = gens } }
  end
  local low = math.min(gens[1], gens[2], x.counter or 3)
  return { rules = { mode = "battle", ruleset = "g3u", dexMax = XG_DEX[low][1],
                     moveMax = XG_DEX[low][2], moveGen = low, gens = gens } }
end

function FakeRelay:xgBump(room)
  local x = room.xg
  x.rev = x.rev + 1
  x.ready = {}
  return x.rev
end

function FakeRelay:xgResolve(room, bumped)
  local x = room.xg
  local r = self:xgRulesFor(room)
  if not r then return end
  local sig = rulesSig(r)
  if sig == x.rulesSig then return end
  x.rulesSig = sig
  if not bumped then self:xgBump(room) end
  if r.rules then
    x.rules, x.blocked = r.rules, nil
    local msg = copy(r.rules)
    msg.type, msg.rev = "xg_rules", x.rev
    self:relayInner(room, msg)
  else
    x.rules, x.blocked = nil, r.blocked
    self:relayInner(room, { type = "xg_blocked", rev = x.rev, why = r.blocked })
  end
end

function FakeRelay:xgNack(room, s, seat, kind, why, rev)
  self.nacks = (self.nacks or 0) + 1
  self:to(s, { type = "room_msg", seq = nil, seat = -1, relay = true, to = seat,
               msg = { type = "xg_nack", of = kind, why = why,
                       rev = type(rev) == "number" and rev or nil, current = room.xg.rev } })
end

function FakeRelay:xgForward(room, s, seat, clientSeq, out)
  local entry = self:appendLog(room, { seat = seat, clientSeq = clientSeq, msg = copy(out) })
  for _, p in ipairs(room.players) do
    if p.id ~= s.id then
      self:to(self.sessions[p.id], { type = "room_msg", seq = entry.seq, clientSeq = clientSeq,
                                     seat = seat, msg = copy(out) })
    end
  end
end

function FakeRelay:xgSizeOf(x)
  local a, b = x.rosters[1], x.rosters[2]
  if not a or not b then return nil end
  local q0, q1 = x.sizeReq[1], x.sizeReq[2]
  if q0 ~= nil and q0 == q1 and q0 <= a.size and q0 <= b.size then return q0 end
  return math.min(a.size, b.size)
end

local XG_SEAT = { xg_caps = true, xg_counter = true, xg_roster = true, xg_size_req = true,
                  xg_offer = true, xg_ready = true, xg_cancel = true }
local DIGEST = "^" .. ("[0-9a-f]"):rep(16) .. "$"

local function smallInt(v, lo, hi)
  if type(v) ~= "number" or v ~= math.floor(v) or v < lo or v > hi then return nil end
  return v
end

function FakeRelay:xgGo(room)
  local x = room.xg
  room.matchNo = room.matchNo + 1
  room.match = room.room .. "-m" .. room.matchNo
  room.seed = 777
  local go = { type = "xg_go", rev = x.rev, seed = room.seed, match = room.match, mode = x.mode,
               ruleset = x.mode == "trade" and "trade" or x.rules.ruleset }
  if x.mode == "battle" then
    for _, k in ipairs({ "gen", "dexMax", "moveMax", "moveGen" }) do go[k] = x.rules[k] end
    go.size = x.size
    room.engine = x.rules.ruleset == "native" and x.rules.gen or 3
    room.stage = "battling"
  else
    x.agreed = x.ready[1]
    room.stage = "trading"
  end
  self:relayInner(room, go)
  self:roomState(room)
end

function FakeRelay:xgAfterBarrier(room, cause)
  local x = room.xg
  if x.closed or room.stage ~= "trading" then return end
  room.stage = "prep"
  x.offers, x.agreed = {}, nil
  self:xgBump(room)
  self:relayInner(room, { type = "xg_rev", rev = x.rev, seat = -1, cause = cause })
  self:roomState(room)
end

function FakeRelay:xgClose(room, why, extra)
  local x = room.xg
  if not x or x.closed then return end
  x.closed = true
  local msg = { type = "xg_closed", why = why }
  for k, v in pairs(extra or {}) do msg[k] = v end
  self:relayInner(room, msg)
  self:roomBroadcast(room, { type = "room_closed", reason = why, room = room.room })
  for _, p in ipairs(room.players) do
    local member = self.sessions[p.id]
    if member then
      member.room = nil
      member.xgStatus = nil
      self:plazaChanged(member)
    end
  end
  self.rooms[room.room] = nil
end

local function xgWhy(v)
  if type(v) ~= "string" or v == "" then return nil end
  return v:sub(1, 40)
end

function FakeRelay:xgRoomMsg(room, s, seat, clientSeq, inner)
  local x = room.xg
  local kind = inner.type
  if room.stage ~= "prep" then
    if kind == "xg_cancel" then
      if room.stage ~= "battling" then self:xgClose(room, "cancel", { seat = seat, detail = xgWhy(inner.why) }) end
      return true
    end
    if room.stage == "trading" and kind == "trade_confirm" and inner.digest ~= x.agreed then
      self:xgNack(room, s, seat, kind, "digest_unagreed", nil)
      return true
    end
    if room.stage == "trading" and kind == "trade_confirm" then
      local b = room.barrier
      b.confirms[seat] = inner.digest
      self:xgForward(room, s, seat, clientSeq, inner)
      if b.confirms[0] and b.confirms[1] then
        self:relayInner(room, { type = "trade_commit", n = b.n, digests = { b.confirms[0], b.confirms[1] } })
        room.barrier = { n = b.n + 1, confirms = {} }
        self:xgAfterBarrier(room, "trade_commit")
      end
      return true
    end
    return false
  end
  if not XG_SEAT[kind] then return true end
  room.clientSeq = room.clientSeq or {}
  if clientSeq and room.clientSeq[s.id] and clientSeq <= room.clientSeq[s.id] then return true end
  if clientSeq then room.clientSeq[s.id] = clientSeq end
  local rev = inner.rev
  if kind == "xg_cancel" then
    self:xgClose(room, "cancel", { seat = seat, detail = xgWhy(inner.why) })
    return true
  end
  if kind == "xg_caps" then
    local caps = xgCaps(inner.caps)
    if not caps then return self:xgNack(room, s, seat, kind, "bad", rev) or true end
    x.caps[seat + 1] = caps
    self:xgForward(room, s, seat, clientSeq, { type = "xg_caps", caps = caps })
    self:xgResolve(room, false)
    return true
  end
  if type(rev) ~= "number" then return self:xgNack(room, s, seat, kind, "bad", rev) or true end
  if rev ~= x.rev then return self:xgNack(room, s, seat, kind, "stale_rev", rev) or true end
  local battleOnly = kind == "xg_roster" or kind == "xg_size_req" or kind == "xg_counter"
  if (battleOnly and x.mode ~= "battle") or (kind == "xg_offer" and x.mode ~= "trade") then
    return self:xgNack(room, s, seat, kind, "mode", rev) or true
  end
  local out
  if kind == "xg_roster" then
    local size = smallInt(inner.size, 1, 6)
    if not size or type(inner.digest16) ~= "string" or not inner.digest16:match(DIGEST) then
      return self:xgNack(room, s, seat, kind, "bad", rev) or true
    end
    x.rosters[seat + 1] = { size = size, digest16 = inner.digest16 }
    out = { type = kind, rev = rev, size = size, digest16 = inner.digest16 }
  elseif kind == "xg_size_req" then
    local size = smallInt(inner.size, 1, 6)
    if not size then return self:xgNack(room, s, seat, kind, "bad", rev) or true end
    x.sizeReq[seat + 1] = size
    out = { type = kind, rev = rev, size = size }
  elseif kind == "xg_counter" then
    local low = math.min(x.gens[1], x.gens[2])
    local gen = smallInt(inner.gen, 1, low)
    if not gen then return self:xgNack(room, s, seat, kind, "bad", rev) or true end
    if x.gens[1] == x.gens[2] then return self:xgNack(room, s, seat, kind, "same_gen", rev) or true end
    x.counter = gen ~= low and gen or nil
    out = { type = kind, rev = rev, gen = gen }
  elseif kind == "xg_offer" then
    local offerRev = smallInt(inner.offerRev, 0, 2147483647)
    if not offerRev or type(inner.payload) ~= "table" or type(inner.digest16) ~= "string"
       or not inner.digest16:match(DIGEST) then
      return self:xgNack(room, s, seat, kind, "bad", rev) or true
    end
    local prev = x.offers[seat + 1]
    if prev and offerRev <= prev.offerRev then
      return self:xgNack(room, s, seat, kind, "stale_offer", rev) or true
    end
    x.offers[seat + 1] = { offerRev = offerRev, digest16 = inner.digest16 }
    out = { type = kind, rev = rev, offerRev = offerRev, payload = copy(inner.payload),
            digest16 = inner.digest16 }
  elseif kind == "xg_ready" then
    if type(inner.digest16) ~= "string" or not inner.digest16:match(DIGEST) then
      return self:xgNack(room, s, seat, kind, "bad", rev) or true
    end
    if not x.rules then return self:xgNack(room, s, seat, kind, "no_rules", rev) or true end
    if x.mode == "battle" and x.size == nil then
      return self:xgNack(room, s, seat, kind, "no_roster", rev) or true
    end
    if x.mode == "trade" and not (x.offers[1] and x.offers[2]) then
      return self:xgNack(room, s, seat, kind, "no_offer", rev) or true
    end
    if x.ready[seat + 1] then return true end
    x.ready[seat + 1] = inner.digest16
    self:xgForward(room, s, seat, clientSeq, { type = kind, rev = x.rev, digest16 = inner.digest16 })
    if not (x.ready[1] and x.ready[2]) then return true end
    if x.mode == "trade" and x.ready[1] ~= x.ready[2] then
      x.ready = {}
      for _, p in ipairs(room.players) do
        self:xgNack(room, self.sessions[p.id], p.seat, kind, "digest", x.rev)
      end
      return true
    end
    self:xgGo(room)
    return true
  end
  self:xgBump(room)
  self:xgForward(room, s, seat, clientSeq, out)
  self:relayInner(room, { type = "xg_rev", rev = x.rev, seat = seat, cause = kind })
  if kind == "xg_counter" then self:xgResolve(room, true) end
  if kind == "xg_roster" or kind == "xg_size_req" then
    x.size = self:xgSizeOf(x)
    if x.size then self:relayInner(room, { type = "xg_size", rev = x.rev, size = x.size }) end
  end
  return true
end

function FakeRelay:welcome(s, resumed)
  s.online = true
  s.forgotten = false
  self:to(s, { type = "lobby_welcome", session = "S-" .. s.id,
               you = { id = s.id, name = s.name, verified = true },
               serverTime = self:now(), heartbeatMs = 10000,
               resumed = resumed == true })
end

function FakeRelay:handle(s, msg)
  local kind = msg.type
  self.log[#self.log + 1] = { from = s.id, msg = copy(msg) }
  if kind == "lobby_hello" then
    if (msg.protocol or 0) < self.minProtocol then
      self:to(s, { type = "upgrade_required", protocol = self.minProtocol,
                   minBuild = nil,
                   text = "This build is too old for online play. Please update." })
      s.transport.closed = true
      return
    end
    s.name = msg.name or s.name
    s.profiles = copy(msg.profiles or {})
    if msg.presence then
      for k, v in pairs(msg.presence) do
        if k ~= "board" or self:plazaInstance(s) then s.presence[k] = copy(v) end
      end
    end
    self:welcome(s, false)
  elseif kind == "resume" then
    if s.forgotten then
      s.online = true
      return self:joinError(s, "resume_expired")
    end
    self:welcome(s, true)
    local room = s.room and self.rooms[s.room]
    if room then
      self:to(s, self:roomStateMsg(room))
      self:replay(s, math.max(0, msg.ack or 0))
    end
    if self:plazaInstance(s) then self:to(s, self:plazaStateMsg(s)) end
    local q = self.queue[s.id]
    if q then self:to(s, { type = "direct_state", activity = q.activity, queued = true }) end
    if self.groups[s.id] then self:groupBroadcast(self.groups[s.id], self:groupStateMsg(self.groups[s.id])) end
    if s.groupLost and not self:groupOf(s) then
      self:to(s, { type = "group_closed", leader = s.groupLost, why = "left" })
    end
    s.groupLost = nil
    for _, inv in pairs(self.invites) do
      if inv.to == s.id then
        self:to(s, { type = "invite_in", id = inv.id,
                     from = { id = inv.from, name = self.sessions[inv.from].name,
                              verified = true, where = "launcher" },
                     activity = inv.activity, detail = copy(inv.detail),
                     expiresAt = inv.expiresAt })
      end
    end
  elseif kind == "set_profiles" then
    s.profiles = copy(msg.profiles or {})
  elseif kind == "presence" then
    for _, k in ipairs({ "where", "status", "version", "engine" }) do
      if msg[k] ~= nil then s.presence[k] = msg[k] end
    end
    if s.xgen and msg.status ~= nil and msg.board == nil then self:plazaChanged(s) end
    if msg.board == false then
      s.presence.board = nil
      self:plazaChanged(s)
    elseif type(msg.board) == "table" and self:plazaInstance(s) then
      s.presence.board = copy(msg.board)
      self:plazaChanged(s)
    end
  elseif kind == "room_create" then
    if msg.private and not msg.pin then return self:joinError(s, "bad_pin") end
    local profile = msg.profile
    local engine = profile and profile.engine or 1
    local seats = msg.seats or 2
    if engine == 3 then seats = profile.rulesetId == "g3_multi" and 4 or 2 end
    local room = self:newRoom({ intent = msg.intent, engine = engine, profile = profile,
                                seats = seats, pin = msg.private and msg.pin or nil,
                                auto = msg.auto, origin = "create" })
    self:seatPlayer(room, s)
    self:roomState(room)
  elseif kind == "room_join" then
    self:handleRoomJoin(s, msg)
  elseif kind == "invite_token" then
    local room = self.rooms[msg.room or ""]
    if not room then return self:joinError(s, "not_found") end
    self.tokenNo = self.tokenNo + 1
    local token = ("%032x"):format(0xbeef00 + self.tokenNo)
    self.tokens[token] = { room = room.room }
    self:to(s, { type = "invite_token", room = room.room, token = token,
                 expiresAt = self:now() + 1800000 })
  elseif kind == "room_msg" then
    self:fanout(s, msg.seq, msg.msg)
  elseif kind == "room_ack" then
    s.ack = math.max(s.ack or 0, msg.seq or 0)
  elseif kind == "room_leave" then
    local room = s.room and self.rooms[s.room]
    s.room = nil
    if room and room.xg then
      local seat = self:seatOf(room, s.id)
      for i = #room.players, 1, -1 do
        if room.players[i].id == s.id then table.remove(room.players, i) end
      end
      self:xgClose(room, "left", { seat = seat })
      return
    end
    if room then
      for i = #room.players, 1, -1 do
        if room.players[i].id == s.id then table.remove(room.players, i) end
      end
      for i = #room.spectators, 1, -1 do
        if room.spectators[i].id == s.id then table.remove(room.spectators, i) end
      end
      if room.barrier and next(room.barrier.confirms) ~= nil then
        self:relayInner(room, { type = "trade_abort", n = room.barrier.n, why = "left" })
        room.barrier = { n = room.barrier.n + 1, confirms = {} }
      end
      if #room.players == 0 and #room.spectators == 0 then
        self.rooms[room.room] = nil
        return
      end
      if room.host == s.id then
        room.host = (room.players[1] or room.spectators[1]).id
      end
      self:roomState(room)
    end
  elseif kind == "room_close" then
    local room = s.room and self.rooms[s.room]
    if not room or room.host ~= s.id then return end
    self.closedRooms = (self.closedRooms or 0) + 1
    self:roomBroadcast(room, { type = "room_closed", reason = "closed", room = room.room })
    for _, list in ipairs({ room.players, room.spectators }) do
      for _, p in ipairs(list) do
        local member = self.sessions[p.id]
        if member then member.room = nil end
      end
    end
    self.rooms[room.room] = nil
  elseif kind == "invite" then
    self:handleInvite(s, msg)
  elseif kind == "invite_reply" then
    self:handleInviteReply(s, msg)
  elseif kind == "set_caps" then
    local caps = not self.legacy and xgCaps(msg.caps) or nil
    if not self.legacy and not caps then return self:joinError(s, "bad_caps") end
    if caps then
      s.caps = caps
      self:plazaChanged(s)
    end
  elseif kind == "plaza_join" then
    self:plazaJoin(s, msg)
  elseif kind == "plaza_leave" then
    self:plazaLeave(s, msg.kind)
  elseif kind:sub(1, 6) == "group_" then
    self:handleGroup(s, msg)
  elseif kind:sub(1, 7) == "direct_" then
    self:handleDirect(s, msg)
  end
end

function FakeRelay:tick()
  local counts = self:counts()
  for id in pairs(self.wireless) do self:to(self.sessions[id], counts) end
  for id, activity in pairs(self.groupWatch) do
    self:to(self.sessions[id], self:groupListMsg(activity))
  end
end

function FakeRelay:pump()
  for _, id in ipairs(self.order) do
    local s = self.sessions[id]
    local outbox = s.transport.outbox
    s.transport.outbox = {}
    for _, msg in ipairs(outbox) do
      if type(msg) == "table" and type(msg.type) == "string" then self:handle(s, msg) end
    end
  end
end

return FakeRelay
