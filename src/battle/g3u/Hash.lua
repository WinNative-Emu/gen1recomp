local bit = require("bit")

local Hash = {}

Hash.PARTS = { "actives", "volatile", "bench", "field", "rng" }

local function fnv(text)
  local h = 0x811C9DC5
  for i = 1, #text do
    h = bit.bxor(h, text:byte(i)) % 4294967296
    h = ((bit.lshift(h, 24) % 4294967296) + h * 403) % 4294967296
  end
  return string.format("%08x", h)
end

Hash.fnv = fnv

local function scalar(v)
  local t = type(v)
  if t == "number" then
    if v == math.floor(v) then return string.format("%d", v) end
    return string.format("%.6f", v)
  end
  if t == "boolean" then return v and "T" or "F" end
  if t == "string" then return v end
  if v == nil then return "-" end
  return "t"
end

local STAGES = { "attack", "defense", "speed", "spAtk", "spDef", "accuracy", "evasion" }

local VOLATILE_KEYS = {
  "confusion", "substitute", "toxicCounter", "focusEnergy", "perishSong", "seeded", "trapped",
  "attracted", "disabled", "encore", "taunt", "bide", "rage", "endure", "protect", "destinyBond",
  "transformed", "isFirstTurn",
  "expCharged", "expCursed", "expDisableTurns", "expDisabledMove", "expEncoreMove", "expEncoreSlot",
  "expEncoreTurns", "expFocusEnergy", "expFuryCutter", "expInfatuated", "expIngrain", "expLockedMove",
  "expLockedSlot", "expMustRecharge", "expNightmare", "expPerishTurns", "expRampageTurns",
  "expRechargeTurns", "expRolloutTimer", "expSeeded", "expTauntedTurns", "expTormented",
  "expTransform", "expTrapTurns", "expTrapped", "expTruantCounter", "expUproarTurns", "expYawnTurns",
  "expCastformForm",
}

local function perspective(st)
  if st.linkMaster == false then
    return { 1, 0, 3, 2 }, { "enemy", "player" }
  end
  return { 0, 1, 2, 3 }, { "player", "enemy" }
end

local function battlerOf(st, id)
  local State = require("src.core.game3.battle.state")
  if State.isAbsent(st, id) then return nil end
  return State.battler(st, id)
end

local function sortedScalars(t, skip, st)
  if type(t) ~= "table" then return scalar(t) end
  local flip = st and st.linkMaster == false
  local keys = {}
  for k, v in pairs(t) do
    if (type(k) == "string" or type(k) == "number") and not (skip and skip[k])
        and type(v) ~= "table" and type(v) ~= "function" then
      keys[#keys + 1] = tostring(k)
    end
  end
  table.sort(keys)
  local out = {}
  for _, k in ipairs(keys) do
    local v = t[k]
    if v == nil then v = t[tonumber(k)] end
    if flip and type(v) == "number" and k:sub(-2) == "Id" and v >= 0 and v <= 3 then
      v = (v % 2 == 0) and (v + 1) or (v - 1)
    end
    out[#out + 1] = k .. "=" .. scalar(v)
  end
  return table.concat(out, ",")
end

local function monPp(mon)
  local pp = {}
  for i = 1, 4 do pp[i] = scalar(mon and mon.pp and mon.pp[i]) end
  return table.concat(pp, "/")
end

local SIDE_SKIP = { id = true }

function Hash.parts(st, draws)
  local order, sides = perspective(st)
  local actives, volatile = {}, {}
  for _, id in ipairs(order) do
    local b = battlerOf(st, id)
    if not b then
      actives[#actives + 1] = "-"
      volatile[#volatile + 1] = "-"
    else
      local mon = b.mon or {}
      local stages = {}
      for i, key in ipairs(STAGES) do stages[i] = scalar(b.stages and b.stages[key] or 0) end
      actives[#actives + 1] = table.concat({
        scalar(tonumber(b.species or mon.species)), scalar(tonumber(mon.hp)), scalar(tonumber(mon.maxHp)),
        scalar(b.status or mon.status), scalar(mon.sleep or b.sleepTurns), table.concat(stages, "/"),
        scalar(b.ability), scalar(tonumber(b.item) or 0), monPp(mon),
      }, ":")
      local vol = {}
      for _, key in ipairs(VOLATILE_KEYS) do vol[#vol + 1] = scalar(b[key]) end
      vol[#vol + 1] = sortedScalars(b.volatiles)
      volatile[#volatile + 1] = table.concat(vol, ":")
    end
  end
  local bench, field = {}, {}
  for _, side in ipairs(sides) do
    local party = (side == "player") and st.playerParty or st.foeParty
    local active = {}
    for _, id in ipairs((side == "player") and { 0, 2 } or { 1, 3 }) do
      local b = battlerOf(st, id)
      if b and b.partyIndex then active[b.partyIndex] = true end
    end
    local rows = {}
    for i, mon in ipairs(party or {}) do
      if active[i] then
        rows[#rows + 1] = "*"
      else
        rows[#rows + 1] = table.concat({
          scalar(tonumber(mon.species or mon.speciesId)), scalar(tonumber(mon.hp)), scalar(mon.status),
          scalar(tonumber(mon.item or mon.heldItem) or 0), monPp(mon),
        }, ":")
      end
    end
    bench[#bench + 1] = table.concat(rows, ";")
    local sideState = (side == "player") and st.playerSide or st.enemySide
    field[#field + 1] = sortedScalars(sideState, SIDE_SKIP, st) .. "|" .. sortedScalars(sideState and sideState.hazards, nil, st)
  end
  table.insert(field, 1, scalar(st.weather) .. ":" .. scalar(st.weatherTurns))
  local raw = {
    actives = table.concat(actives, "#"),
    volatile = table.concat(volatile, "#"),
    bench = table.concat(bench, "#"),
    field = table.concat(field, "#"),
  }
  return {
    actives = fnv(raw.actives),
    volatile = fnv(raw.volatile),
    bench = fnv(raw.bench),
    field = fnv(raw.field),
    rng = string.format("%d", draws and draws.n or 0),
  }, raw
end

function Hash.value(parts)
  local list = {}
  for i, key in ipairs(Hash.PARTS) do list[i] = tostring(parts[key] or "") end
  return fnv(table.concat(list, "|"))
end

return Hash
