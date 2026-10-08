local Json = require("src.link.Json")

local L = {}

local Net = {}
Net.__index = Net

function Net:send(msg)
  if self.closed then return end
  self.sent[#self.sent + 1] = msg
  local wire = Json.encode(msg)
  if self.tamper then
    local out = self.tamper(Json.decode(wire))
    if out == nil then return end
    wire = Json.encode(out)
  end
  local other = self.other
  if other.dropAll then return end
  if self.hold then
    self.held[#self.held + 1] = wire
    return
  end
  other.inbox[#other.inbox + 1] = wire
end

function Net:flush()
  for _, wire in ipairs(self.held) do self.other.inbox[#self.other.inbox + 1] = wire end
  self.held = {}
end

function Net:poll()
  local out = {}
  for i, wire in ipairs(self.inbox) do out[i] = Json.decode(wire) end
  self.inbox = {}
  return out
end

function Net:takeWhere(pred)
  for i, wire in ipairs(self.inbox) do
    local msg = Json.decode(wire)
    if pred(msg) then
      table.remove(self.inbox, i)
      return msg
    end
  end
  return nil
end

function Net:update() end

function Net:peerOnline()
  return self.other.online ~= false
end

function Net:close()
  self.closed = true
end

function L.pair()
  local a = setmetatable({ inbox = {}, sent = {}, held = {}, closed = false }, Net)
  local b = setmetatable({ inbox = {}, sent = {}, held = {}, closed = false }, Net)
  a.other, b.other = b, a
  return a, b
end

function L.lcg(seed)
  local r = seed % 2147483648
  return function(n)
    r = (r * 1103515245 + 12345) % 2147483648
    return math.floor(r / 65536) % n + 1
  end
end

function L.bot(bs, opts)
  opts = opts or {}
  local rnd = opts.rnd or L.lcg(opts.seed or 7)
  return function()
    bs:update()
    if bs.phase == "choose" then
      local list = {}
      for _, a in ipairs(bs:legal()) do
        if a.kind ~= "forfeit" and (opts.switches or a.kind ~= "switch") then list[#list + 1] = a end
      end
      if #list == 0 then list = bs:legal() end
      local pick = opts.pick and opts.pick(bs, list) or list[rnd(#list)]
      if pick then bs:choose(pick) end
    elseif bs.phase == "replace" then
      local list = bs:legal()
      if #list > 0 then bs:pickReplacement(list[rnd(#list)].index) end
    end
  end
end

return L
