local Loop = {}
Loop.__index = Loop

Loop.PEER_DIGEST = "00000000000000b2"

local function copy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = copy(x) end
  return out
end

function Loop.new(opts)
  opts = opts or {}
  local self = setmetatable({ seat = opts.seat or 0, rev = 0, inbox = {}, rosters = {}, sizeReq = {},
    ready = {}, size = nil, rules = nil, closed = false, stage = "prep", sent = {} }, Loop)
  local me = self
  self.session = {
    send = function(m)
      me.sent[#me.sent + 1] = copy(m)
      me:fromSeat(me.seat, m)
      return not me.closed
    end,
    take = function(pred)
      for i, m in ipairs(me.inbox) do
        if pred(m) then return table.remove(me.inbox, i) end
      end
      return nil
    end,
    seat = function() return me.seat end,
    open = function() return not me.closed or #me.inbox > 0 end,
    leave = function() me.closed = true end,
  }
  return self
end

function Loop:peer() return 1 - self.seat end

function Loop:push(m)
  m.relay = true
  self.inbox[#self.inbox + 1] = m
end

function Loop:bump()
  self.rev = self.rev + 1
  self.ready = {}
end

function Loop:setRules(r)
  self:bump()
  self.rules = copy(r)
  local m = copy(r)
  m.type, m.rev = "xg_rules", self.rev
  m.mode = m.mode or "battle"
  self:push(m)
end

function Loop:sizeOf()
  local a, b = self.rosters[0], self.rosters[1]
  if not a or not b then return nil end
  local q0, q1 = self.sizeReq[0], self.sizeReq[1]
  if q0 and q0 == q1 and q0 <= a.size and q0 <= b.size then return q0 end
  return math.min(a.size, b.size)
end

function Loop:nack(seat, kind, why, rev)
  if seat == self.seat then
    self:push({ type = "xg_nack", of = kind, why = why, rev = rev, current = self.rev })
  end
end

function Loop:fromSeat(seat, m)
  if self.closed or type(m) ~= "table" then return end
  local kind = m.type
  if kind == "xg_cancel" then return self:close("cancel", seat) end
  if self.stage ~= "prep" then return end
  if m.rev ~= self.rev then return self:nack(seat, kind, "stale_rev", m.rev) end
  local fwd
  if kind == "xg_roster" then
    self.rosters[seat] = { size = m.size, digest16 = m.digest16 }
    fwd = { type = kind, rev = m.rev, size = m.size, digest16 = m.digest16 }
  elseif kind == "xg_size_req" then
    self.sizeReq[seat] = m.size
    fwd = { type = kind, rev = m.rev, size = m.size }
  elseif kind == "xg_ready" then
    if not self.rules then return self:nack(seat, kind, "no_rules", m.rev) end
    if not self.size then return self:nack(seat, kind, "no_roster", m.rev) end
    if self.ready[seat] then return end
    self.ready[seat] = m.digest16
    if seat ~= self.seat then self:push({ type = kind, rev = self.rev, digest16 = m.digest16 }) end
    if self.ready[0] and self.ready[1] then self:go() end
    return
  else
    return
  end
  self:bump()
  if seat ~= self.seat then self:push(fwd) end
  self:push({ type = "xg_rev", rev = self.rev, seat = seat, cause = kind })
  self.size = self:sizeOf()
  if self.size then self:push({ type = "xg_size", rev = self.rev, size = self.size }) end
end

function Loop:go()
  self.stage = "battling"
  local r = self.rules or {}
  self:push({ type = "xg_go", rev = self.rev, seed = 777, match = "loop-m1", mode = "battle",
    ruleset = r.ruleset, size = self.size, gen = r.gen, dexMax = r.dexMax, moveMax = r.moveMax, moveGen = r.moveGen })
end

function Loop:close(why, seat)
  if self.closed then return end
  self:push({ type = "xg_closed", why = why, seat = seat })
  self.closed = true
end

function Loop:peerRoster(size, digest)
  self:fromSeat(self:peer(), { type = "xg_roster", rev = self.rev, size = size, digest16 = digest or Loop.PEER_DIGEST })
end

function Loop:peerSizeReq(size)
  self:fromSeat(self:peer(), { type = "xg_size_req", rev = self.rev, size = size })
end

function Loop:peerReady(digest)
  self:fromSeat(self:peer(), { type = "xg_ready", rev = self.rev, digest16 = digest or Loop.PEER_DIGEST })
end

function Loop:peerCancel()
  self:close("cancel", self:peer())
end

function Loop:prep()
  local Prep = require("src.online.union.Prep")
  return Prep.new(self.session, { mode = "battle" })
end

return Loop
