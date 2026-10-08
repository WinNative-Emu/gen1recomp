local Protocol2 = require("src.online.Protocol2")
local Wire = require("src.link.Wire")

local Prep = {}
Prep.__index = Prep

Prep.STATES = { rules_wait = true, blocked = true, prep = true, go = true, closed = true }

local BUMPING = { xg_roster = true, xg_size_req = true, xg_offer = true, xg_counter = true }
local TRADE_CAUSES = { trade_commit = true, trade_abort = true }

local function isXg(msg)
  return Protocol2.isXg(msg)
end

function Prep.new(session, opts)
  opts = opts or {}
  local self = setmetatable({
    session = session,
    mode = opts.mode,
    rev = 0,
    rules = nil,
    blocked = nil,
    size = nil,
    state = "rules_wait",
    go = nil,
    closed = nil,
    round = 0,
    offerRev = 0,
    invalidated = false,
    mine = { pending = {} },
    peer = {},
    events = {},
    snapshotSeen = nil,
    sent = {},
  }, Prep)
  self:syncSnapshot()
  return self
end

function Prep:seat()
  local seat = self.session.seat and self.session.seat() or nil
  if seat ~= nil then self.mySeat = seat end
  return self.mySeat
end

function Prep:emit(kind, fields)
  local e = { kind = kind }
  for k, v in pairs(fields or {}) do e[k] = v end
  self.events[#self.events + 1] = e
  return e
end

function Prep:clearReady(reason)
  if self.mine.ready then
    self.invalidated = true
    self:emit("invalidated", { reason = reason })
  end
  self.mine.ready = nil
  self.peer.ready = nil
end

function Prep:setRev(rev, cause)
  rev = tonumber(rev)
  if not rev or rev <= self.rev then return false end
  self.rev = rev
  self:clearReady(cause or "rev")
  self:emit("rev", { rev = rev, cause = cause })
  return true
end

function Prep:enterPrepState()
  if self.state == "go" or self.state == "closed" then return end
  if self.blocked then
    self.state = "blocked"
  elseif self.rules then
    self.state = "prep"
  else
    self.state = "rules_wait"
  end
end

local function pairAt(list, seat)
  if type(list) ~= "table" or seat == nil then return nil end
  return list[seat + 1]
end

function Prep:syncSnapshot()
  if not self.session.snapshot then return end
  local x, room = self.session.snapshot()
  if type(x) ~= "table" or x == self.snapshotSeen then return end
  self.snapshotSeen = x
  self.mode = x.mode or self.mode
  local seat = self:seat()
  if seat == nil then return end
  local other = 1 - seat
  if x.rev < self.rev then return end
  if x.rev > self.rev then
    self.rev = x.rev
    self:clearReady("resume")
  end
  self.rules = x.rules
  self.blocked = x.blocked
  self.size = x.size
  self.mine.roster = pairAt(x.rosters, seat)
  self.peer.roster = pairAt(x.rosters, other)
  self.mine.sizeReq = pairAt(x.sizeReq, seat)
  self.peer.sizeReq = pairAt(x.sizeReq, other)
  local myOffer, peerOffer = pairAt(x.offers, seat), pairAt(x.offers, other)
  if myOffer then
    self.offerRev = math.max(self.offerRev, myOffer.offerRev)
    if not (self.mine.offer and self.mine.offer.offerRev == myOffer.offerRev) then
      self.mine.offer = { offerRev = myOffer.offerRev, digest16 = myOffer.digest16 }
    end
  else
    self.mine.offer = nil
  end
  if peerOffer then
    if not (self.peer.offer and self.peer.offer.offerRev == peerOffer.offerRev) then
      self.peer.offer = { offerRev = peerOffer.offerRev, digest16 = peerOffer.digest16 }
    end
  else
    self.peer.offer = nil
  end
  if pairAt(x.ready, seat) then
    self.mine.ready = self.mine.ready or { rev = x.rev }
  else
    self.mine.ready = nil
  end
  self.peer.ready = pairAt(x.ready, other) and { rev = x.rev } or nil
  self.peer.capsSent = pairAt(x.caps, other) == true
  self.mine.capsSent = pairAt(x.caps, seat) == true
  local stage = type(room) == "table" and room.stage or nil
  if stage == "prep" then
    if self.state == "go" then self.state = "rules_wait" end
    self.go = nil
    self:enterPrepState()
  elseif stage == "trading" or stage == "battling" or stage == "ended" then
    if self.state ~= "closed" then self.state = "go" end
  else
    self:enterPrepState()
  end
  self:emit("snapshot", { rev = self.rev })
end

function Prep:confirm(cause)
  local pending = self.mine.pending[cause]
  if not pending then return end
  self.mine.pending[cause] = nil
  if cause == "xg_roster" then
    self.mine.roster = { size = pending.size, digest16 = pending.digest16 }
  elseif cause == "xg_size_req" then
    self.mine.sizeReq = pending.size
  elseif cause == "xg_offer" then
    self.mine.offer = pending
  elseif cause == "xg_counter" then
    self.mine.counter = pending.gen
  end
end

function Prep:handleRelay(m)
  local kind = m.type
  if kind == "xg_rules" then
    self:setRev(m.rev, "rules")
    self.rules = Wire.xgRules(m)
    self.blocked = nil
    self:enterPrepState()
    self:emit("rules", { rules = self.rules })
  elseif kind == "xg_blocked" then
    self:setRev(m.rev, "blocked")
    self.rules = nil
    self.blocked = m.why
    self:enterPrepState()
    self:emit("blocked", { why = m.why })
  elseif kind == "xg_rev" then
    self:setRev(m.rev, m.cause)
    if m.seat ~= nil and m.seat == self:seat() then self:confirm(m.cause) end
    if m.seat == -1 and TRADE_CAUSES[m.cause] then
      self.mine.offer, self.peer.offer = nil, nil
      self.mine.pending.xg_offer = nil
      self.go = nil
      if self.state == "go" then self.state = "rules_wait" end
      self.round = self.round + 1
      self:enterPrepState()
      self:emit("trade_round", { round = self.round, cause = m.cause })
    end
  elseif kind == "xg_size" then
    self:setRev(m.rev, "size")
    self.size = m.size
    self:emit("size", { size = m.size })
  elseif kind == "xg_nack" then
    self.mine.pending[m.of or ""] = nil
    if m.of == "xg_ready" then
      if self.mine.ready then self.invalidated = true end
      self.mine.ready = nil
    end
    if m.why == "stale_rev" then
      self:setRev(m.current, "stale_rev")
      self.invalidated = true
    elseif m.why == "digest" then
      self.invalidated = true
      self.mine.ready, self.peer.ready = nil, nil
    end
    self:emit("nack", { of = m.of, why = m.why, rev = m.rev, current = m.current })
  elseif kind == "xg_go" then
    if self.state == "closed" then return end
    self.go = {
      rev = m.rev, seed = m.seed, match = m.match, mode = m.mode or self.mode,
      ruleset = m.ruleset, size = m.size, gen = m.gen, dexMax = m.dexMax,
      moveMax = m.moveMax, moveGen = m.moveGen,
    }
    self.state = "go"
    self:emit("go", { go = self.go })
  elseif kind == "xg_closed" then
    self.state = "closed"
    self.closed = { why = m.why, seat = m.seat ~= -1 and m.seat or nil, detail = m.detail }
    self:emit("closed", self.closed)
  end
end

function Prep:handlePeer(m)
  local kind = m.type
  if kind == "xg_roster" then
    self.peer.roster = { size = m.size, digest16 = m.digest16 }
    self:emit("peer_roster", { size = m.size })
  elseif kind == "xg_size_req" then
    self.peer.sizeReq = m.size
    self:emit("peer_size_req", { size = m.size })
  elseif kind == "xg_offer" then
    self.peer.offer = { offerRev = m.offerRev, payload = m.payload, digest16 = m.digest16 }
    self:emit("peer_offer", { offerRev = m.offerRev })
  elseif kind == "xg_ready" then
    if m.rev == self.rev then
      self.peer.ready = { rev = m.rev, digest16 = m.digest16 }
      self:emit("peer_ready", { rev = m.rev })
    end
  elseif kind == "xg_caps" then
    self.peer.caps = m.caps
    self.peer.capsSent = true
    self:emit("peer_caps", {})
  elseif kind == "xg_counter" then
    self.peer.counter = m.gen
    self:emit("peer_counter", { gen = m.gen })
  elseif kind == "xg_cancel" then
    self:emit("peer_cancel", { why = m.why })
  end
end

function Prep:handle(m)
  if type(m) ~= "table" then return end
  if Protocol2.XG_RELAY_TYPES[m.type] then
    self:handleRelay(m)
  else
    self:handlePeer(m)
  end
end

function Prep:poll()
  self:syncSnapshot()
  local take = self.session.take
  if take then
    for _ = 1, 256 do
      local m = take(isXg)
      if not m then break end
      self:handle(m)
      self:syncSnapshot()
    end
  end
  if self.state ~= "closed" and self.session.open and not self.session.open() then
    self.state = "closed"
    self.closed = { why = "gone" }
    self:emit("closed", self.closed)
  end
  local out = self.events
  self.events = {}
  return out
end

function Prep:open()
  return self.state ~= "closed"
end

function Prep:send(msg)
  if not msg or self.state == "closed" then return false end
  self.sent[#self.sent + 1] = msg.type
  return self.session.send(msg) and true or false
end

function Prep:localChange(kind)
  if BUMPING[kind] and self.mine.ready then
    self.mine.ready = nil
    self.invalidated = true
    self:emit("invalidated", { reason = kind })
  end
end

function Prep:roster(size, digest16)
  if self.mode ~= "battle" or self.state == "go" then return false end
  self:localChange("xg_roster")
  self.mine.pending.xg_roster = { size = size, digest16 = digest16 }
  return self:send(Protocol2.xgRoster(self.rev, size, digest16))
end

function Prep:sizeRequest(size)
  if self.mode ~= "battle" or self.state == "go" then return false end
  self:localChange("xg_size_req")
  self.mine.pending.xg_size_req = { size = size }
  return self:send(Protocol2.xgSizeReq(self.rev, size))
end

function Prep:counter(gen)
  if self.mode ~= "battle" or self.state == "go" then return false end
  self:localChange("xg_counter")
  self.mine.pending.xg_counter = { gen = gen }
  return self:send(Protocol2.xgCounter(self.rev, gen))
end

function Prep:offer(payload, digest16)
  if self.mode ~= "trade" or self.state == "go" then return false end
  self:localChange("xg_offer")
  self.offerRev = self.offerRev + 1
  self.mine.pending.xg_offer = { offerRev = self.offerRev, payload = payload, digest16 = digest16 }
  return self:send(Protocol2.xgOffer(self.rev, self.offerRev, payload, digest16))
end

function Prep:sendCaps(caps)
  return self:send(Protocol2.xgCaps(caps))
end

function Prep:canReady()
  if self.state ~= "prep" or not self.rules then return false end
  if self.mode == "battle" then return self.size ~= nil end
  if self.mode == "trade" then return self.mine.offer ~= nil and self.peer.offer ~= nil end
  return false
end

function Prep:ready(digest16)
  if self.state ~= "prep" or self.mine.ready then return false end
  self.invalidated = false
  self.mine.ready = { rev = self.rev, digest16 = digest16 }
  return self:send(Protocol2.xgReady(self.rev, digest16))
end

function Prep:cancel(why)
  if self.state == "closed" then return false end
  return self:send(Protocol2.xgCancel(why or "cancel"))
end

function Prep:leave()
  if self.session.leave then self.session.leave() end
end

function Prep:ackInvalidated()
  local was = self.invalidated
  self.invalidated = false
  return was
end

function Prep:bothReady()
  return self.mine.ready ~= nil and self.peer.ready ~= nil
end

return Prep
