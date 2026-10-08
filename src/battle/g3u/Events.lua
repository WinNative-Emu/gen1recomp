local Events = {}

Events.KINDS = {
  "msg", "move", "hp", "status", "stage", "faint", "withdraw", "sendout", "weather",
  "anim", "need_replacement", "end",
}

local SEAT = { player = 0, enemy = 1 }

function Events.seatOf(side)
  if side == nil then return nil end
  if type(side) == "number" then return side % 2 end
  return SEAT[side]
end

local seatOf = Events.seatOf

local function isBattler(v)
  return type(v) == "table" and (v.side == "player" or v.side == "enemy") and v.mon ~= nil
end

local function value(v, depth)
  local t = type(v)
  if t == "string" then
    local kind, n = v:match("^{(%a+):(%-?%d+)}$")
    if kind then return { [kind] = tonumber(n) } end
    return v
  end
  if t == "number" or t == "boolean" then return v end
  if t == "table" then
    if isBattler(v) then return { side = seatOf(v.side), index = v.partyIndex } end
    if (depth or 0) > 2 then return nil end
    local out = {}
    for k, x in pairs(v) do
      if type(k) == "string" or type(k) == "number" then out[k] = value(x, (depth or 0) + 1) end
    end
    return out
  end
  return nil
end

function Events.fill(fill)
  local out = {}
  for k, v in pairs(fill or {}) do
    if type(k) == "string" then out[k] = value(v, 0) end
  end
  return out
end

function Events.normalize(raw, out)
  out = out or {}
  for _, ev in ipairs(raw or {}) do
    local k = ev.kind
    if k == "msg" then
      out[#out + 1] = { kind = "msg", id = ev.id, fill = Events.fill(ev.fill) }
    elseif k == "move" then
      out[#out + 1] = { kind = "move", moveId = tonumber(ev.moveId) or ev.moveId,
        user = seatOf(ev.attacker), target = seatOf(ev.target), turn = ev.turn }
    elseif k == "hp" or k == "hit" then
      out[#out + 1] = { kind = "hp", side = seatOf(ev.side), from = ev.from, to = ev.to, max = ev.maxHp,
        hit = k == "hit" or nil }
    elseif k == "status_apply" then
      out[#out + 1] = { kind = "status", side = seatOf(ev.side), status = ev.status }
    elseif k == "status_clear" then
      out[#out + 1] = { kind = "status", side = seatOf(ev.side), status = "NONE" }
    elseif k == "stage" then
      out[#out + 1] = { kind = "stage", side = seatOf(ev.side), stat = ev.stat, delta = ev.delta }
    elseif k == "faint" then
      out[#out + 1] = { kind = "faint", side = seatOf(ev.side) }
    elseif k == "switch" then
      local seat = seatOf(ev.side)
      out[#out + 1] = { kind = "withdraw", side = seat, index = ev.from, reason = ev.reason }
      out[#out + 1] = { kind = "sendout", side = seat, index = ev.to, reason = ev.reason }
    elseif k == "anim" then
      out[#out + 1] = { kind = "anim", anim = ev.anim, name = ev.name, user = seatOf(ev.attacker),
        target = seatOf(ev.target), arg = ev.arg }
    end
  end
  return out
end

return Events
