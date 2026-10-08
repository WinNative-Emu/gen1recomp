local E = require("src.core.game3.battle.effect_ids")
local Identity = require("src.online.xgen.Identity")
local Map1 = require("src.battle.g3u.EffectMap1")
local Map2 = require("src.battle.g3u.EffectMap2")

local Table = {}

Table.VERSION = 1

Table.MOVE_COLS = { "power", "type", "accuracy", "pp", "effect", "chance", "target", "priority", "flags" }
Table.SPECIES_COLS = { "type1", "type2", "hp", "atk", "def", "spe", "spa", "spd" }

Table.LIMITS = {
  [1] = { moveMax = 165, dexMax = 151 },
  [2] = { moveMax = 251, dexMax = 251 },
}

local MAPS = { [1] = Map1, [2] = Map2 }
Table.MAPS = MAPS

-- pokefirered/include/constants/pokemon.h:239
local FLAG_PROTECT_AFFECTED = 2
local FLAG_MIRROR_MOVE_AFFECTED = 16

-- pokefirered/include/battle.h:59
local TARGET_SELECTED, TARGET_DEPENDS, TARGET_USER, TARGET_OPPONENTS_FIELD = 0, 1, 16, 64

local USER_EFFECTS = {}
for _, id in ipairs({
  E.ATTACK_UP, E.DEFENSE_UP, E.SPEED_UP, E.SPECIAL_ATTACK_UP, E.SPECIAL_DEFENSE_UP, E.ACCURACY_UP,
  E.EVASION_UP, E.HAZE, E.BIDE, E.CONVERSION, E.RESTORE_HP, E.LIGHT_SCREEN, E.REST, E.MIST,
  E.FOCUS_ENERGY, E.ATTACK_UP_2, E.DEFENSE_UP_2, E.SPEED_UP_2, E.SPECIAL_ATTACK_UP_2,
  E.SPECIAL_DEFENSE_UP_2, E.ACCURACY_UP_2, E.EVASION_UP_2, E.REFLECT, E.SUBSTITUTE, E.METRONOME,
  E.SPLASH, E.CONVERSION_2, E.SLEEP_TALK, E.DESTINY_BOND, E.HEAL_BELL, E.MINIMIZE, E.CURSE,
  E.PROTECT, E.SANDSTORM, E.ENDURE, E.SAFEGUARD, E.BATON_PASS, E.MORNING_SUN, E.SYNTHESIS,
  E.MOONLIGHT, E.RAIN_DANCE, E.SUNNY_DAY, E.BELLY_DRUM, E.TELEPORT, E.DEFENSE_CURL, E.SOFTBOILED,
  E.MIRROR_MOVE,
}) do USER_EFFECTS[id] = true end

local NO_MIRROR = { [E.MIRROR_MOVE] = true, [E.METRONOME] = true, [E.SLEEP_TALK] = true }

-- pokefirered/src/data/battle_moves.h:465
local CERTAIN_SECONDARY = { [E.TRAP] = true, [E.PAY_DAY] = true }

local function targetOf(effect)
  if effect == E.COUNTER or effect == E.MIRROR_COAT then return TARGET_DEPENDS end
  if effect == E.SPIKES then return TARGET_OPPONENTS_FIELD end
  if USER_EFFECTS[effect] then return TARGET_USER end
  return TARGET_SELECTED
end

local function flagsOf(effect, target)
  local f = 0
  if target == TARGET_SELECTED or target == TARGET_DEPENDS then f = f + FLAG_PROTECT_AFFECTED end
  if target == TARGET_SELECTED and not NO_MIRROR[effect] then f = f + FLAG_MIRROR_MOVE_AFFECTED end
  return f
end

local SUPPORTED = {}
for _, map in pairs(MAPS) do
  for _, row in pairs(map.EFFECTS) do SUPPORTED[row.effect] = true end
  for _, row in pairs(map.MOVES) do SUPPORTED[row.effect] = true end
end
Table.SUPPORTED_EFFECTS = SUPPORTED

local function gen3Type(name)
  return name and Identity.GEN3_TYPE_ID[name] or nil
end

function Table.mapMove(gen, id, mv)
  local map = MAPS[gen]
  if not map then return nil, "bad_gen" end
  if type(mv) ~= "table" then return nil, "missing_move" end
  local name = mv.effect
  local base = map.EFFECTS[name]
  if not base then
    if map.UNSUPPORTED[name] then return nil, "unsupported_effect", name end
    return nil, "unknown_effect", name
  end
  local over = map.MOVES[id] or {}
  local effect = over.effect or base.effect
  local chance
  if gen == 1 then
    chance = base.chance or 0
  else
    chance = math.floor(tonumber(mv.effectChance) or 0)
  end
  if over.chance then chance = over.chance end
  if chance == 0 and CERTAIN_SECONDARY[effect] then chance = 100 end
  local priority
  if gen == 1 then
    priority = map.PRIORITY[id] or 0
  else
    local raw = map.MOVE_PRIORITY[id] or map.EFFECT_PRIORITY[name] or map.BASE_PRIORITY
    priority = raw - map.BASE_PRIORITY
  end
  local typeId = gen3Type(mv.type)
  if not typeId then return nil, "unknown_type", mv.type end
  local target = targetOf(effect)
  return {
    math.floor(tonumber(mv.power) or 0), typeId, math.floor(tonumber(mv.accuracy) or 0),
    math.floor(tonumber(mv.pp) or 0), effect, chance, target, priority, flagsOf(effect, target),
  }
end

function Table.unsupportedMoves(data)
  local gen = data and data.generation
  local lim = Table.LIMITS[gen]
  local out = {}
  if not lim then return out end
  for id = 1, lim.moveMax do
    local mv = data.moves[id]
    if mv then
      local row, why, detail = Table.mapMove(gen, id, mv)
      if not row then out[#out + 1] = { id = id, why = why, effect = detail } end
    end
  end
  return out
end

local function speciesRow(sp)
  local t1 = gen3Type(sp.types and sp.types[1])
  local t2 = gen3Type(sp.types and (sp.types[2] or sp.types[1]))
  if not t1 or not t2 then return nil end
  local b = sp.base or {}
  local row = { t1, t2 }
  for _, k in ipairs({ "hp", "atk", "def", "spe", "spa", "spd" }) do
    local v = math.floor(tonumber(b[k]) or 0)
    if v < 1 then return nil end
    row[#row + 1] = v
  end
  return row
end

function Table.build(data, gen)
  if type(data) ~= "table" then return nil, "no_data" end
  gen = gen or data.generation
  local lim = Table.LIMITS[gen]
  if not lim or data.generation ~= gen then return nil, "bad_gen" end
  local t = { v = Table.VERSION, gen = gen, moveMax = lim.moveMax, dexMax = lim.dexMax,
    moves = {}, species = {}, illegal = {} }
  for id = 1, lim.moveMax do
    local mv = data.moves[id]
    if not mv then return nil, "missing_move", id end
    local row, why, detail = Table.mapMove(gen, id, mv)
    if not row then
      if why ~= "unsupported_effect" then return nil, why, { id = id, detail = detail } end
      row = { math.floor(tonumber(mv.power) or 0), gen3Type(mv.type) or 0, 0, 1, E.HIT, 0, TARGET_SELECTED, 0, 0 }
      t.illegal[#t.illegal + 1] = id
    end
    t.moves[id] = row
  end
  for n = 1, lim.dexMax do
    local sp = data.species[n]
    if not sp then return nil, "missing_species", n end
    local row = speciesRow(sp)
    if not row then return nil, "bad_species", n end
    t.species[n] = row
  end
  return t
end

local GEN1_TYPES, GEN2_TYPES = {}, {}
for _, name in ipairs(Identity.GEN1_TYPES) do GEN1_TYPES[Identity.GEN3_TYPE_ID[name]] = true end
for _, name in ipairs(Identity.TYPES) do GEN2_TYPES[Identity.GEN3_TYPE_ID[name]] = true end
GEN2_TYPES[Identity.GEN3_TYPE_ID.MYSTERY] = true
local TYPE_SETS = { [1] = GEN1_TYPES, [2] = GEN2_TYPES }

local VALID_TARGETS = { [TARGET_SELECTED] = true, [TARGET_DEPENDS] = true, [TARGET_USER] = true,
  [TARGET_OPPONENTS_FIELD] = true }

local function int(v, lo, hi)
  return type(v) == "number" and v == v and v == math.floor(v) and v >= lo and v <= hi
end

local function exact(row, n)
  if type(row) ~= "table" or #row ~= n then return false end
  local count = 0
  for _ in pairs(row) do count = count + 1 end
  return count == n
end

local MOVE_KEYS = { v = true, gen = true, moveMax = true, dexMax = true, moves = true, species = true, illegal = true }

function Table.validate(t, gen)
  if type(t) ~= "table" then return nil, "not_a_table" end
  for k in pairs(t) do
    if not MOVE_KEYS[k] then return nil, "unknown_key" end
  end
  if t.v ~= Table.VERSION then return nil, "bad_version" end
  if gen ~= nil and t.gen ~= gen then return nil, "gen_mismatch" end
  local lim = Table.LIMITS[t.gen]
  if not lim then return nil, "bad_gen" end
  if t.moveMax ~= lim.moveMax or t.dexMax ~= lim.dexMax then return nil, "bad_limits" end
  local types = TYPE_SETS[t.gen]
  if not exact(t.moves, lim.moveMax) then return nil, "bad_move_count" end
  for id = 1, lim.moveMax do
    local r = t.moves[id]
    if not exact(r, #Table.MOVE_COLS) then return nil, "bad_move_row", id end
    if not int(r[1], 0, 255) then return nil, "bad_power", id end
    if not int(r[2], 0, 17) or not types[r[2]] then return nil, "bad_type", id end
    if not int(r[3], 0, 100) then return nil, "bad_accuracy", id end
    if not int(r[4], 1, 64) then return nil, "bad_pp", id end
    if not int(r[5], 0, 255) or not SUPPORTED[r[5]] then return nil, "bad_effect", id end
    if not int(r[6], 0, 100) then return nil, "bad_chance", id end
    if not int(r[7], 0, 255) or not VALID_TARGETS[r[7]] then return nil, "bad_target", id end
    if not int(r[8], -6, 6) then return nil, "bad_priority", id end
    if not int(r[9], 0, 63) then return nil, "bad_flags", id end
  end
  if not exact(t.species, lim.dexMax) then return nil, "bad_species_count" end
  for n = 1, lim.dexMax do
    local r = t.species[n]
    if not exact(r, #Table.SPECIES_COLS) then return nil, "bad_species_row", n end
    if not int(r[1], 0, 17) or not types[r[1]] or not int(r[2], 0, 17) or not types[r[2]] then
      return nil, "bad_species_type", n
    end
    for i = 3, 8 do
      if not int(r[i], 1, 255) then return nil, "bad_base_stat", n end
    end
  end
  if type(t.illegal) ~= "table" or #t.illegal > lim.moveMax then return nil, "bad_illegal" end
  local count, prev = 0, 0
  for _ in pairs(t.illegal) do count = count + 1 end
  if count ~= #t.illegal then return nil, "bad_illegal" end
  for _, id in ipairs(t.illegal) do
    if not int(id, prev + 1, lim.moveMax) then return nil, "bad_illegal" end
    prev = id
  end
  return true
end

function Table.illegalSet(t)
  local out = {}
  for _, id in ipairs(t.illegal or {}) do out[id] = true end
  return out
end

function Table.engineRow(t, id)
  local r = t.moves[id]
  if not r then return nil end
  return { power = r[1], type = r[2], accuracy = r[3], pp = r[4], effect = r[5],
    secondaryChance = r[6], target = r[7], priority = r[8], flags = r[9] }
end

function Table.speciesTypes(t, n)
  local r = t.species[n]
  if not r then return nil end
  return { r[1], r[2] }
end

function Table.baseStats(t, n)
  local r = t.species[n]
  if not r then return nil end
  return { hp = r[3], atk = r[4], def = r[5], spe = r[6], spa = r[7], spd = r[8] }
end

return Table
