local Map1 = require("src.battle.g3u.EffectMap1")
local Map2 = require("src.battle.g3u.EffectMap2")
local E = require("src.core.game3.battle.effect_ids")
local Gen1 = require("src.battle.MoveEffects")
local Gen2 = require("src.battle.gen2.Effects")

local Effects = {}

local function sortedKeys(t)
  local out = {}
  for key in pairs(t) do out[#out + 1] = key end
  table.sort(out)
  return out
end

local function names(text)
  local out = {}
  for name in text:gmatch("%S+") do out[name] = true end
  return out
end

local supported2 = names([[
  EFFECT_NORMAL_HIT EFFECT_SLEEP EFFECT_POISON EFFECT_TOXIC EFFECT_PARALYZE
  EFFECT_BURN EFFECT_FREEZE EFFECT_CONFUSE EFFECT_POISON_HIT EFFECT_BURN_HIT
  EFFECT_FREEZE_HIT EFFECT_PARALYZE_HIT EFFECT_SLEEP_HIT EFFECT_CONFUSE_HIT
  EFFECT_SACRED_FIRE EFFECT_SELFDESTRUCT EFFECT_MIRROR_MOVE EFFECT_ALWAYS_HIT
  EFFECT_BIDE EFFECT_RAMPAGE EFFECT_FORCE_SWITCH EFFECT_MULTI_HIT
  EFFECT_FLINCH_HIT EFFECT_HEAL EFFECT_PAY_DAY EFFECT_LIGHT_SCREEN EFFECT_OHKO
  EFFECT_SUPER_FANG EFFECT_STATIC_DAMAGE EFFECT_TRAP_TARGET EFFECT_DOUBLE_HIT
  EFFECT_MIST EFFECT_FOCUS_ENERGY EFFECT_RECOIL_HIT EFFECT_SUBSTITUTE
  EFFECT_HYPER_BEAM EFFECT_RAGE EFFECT_METRONOME EFFECT_LEECH_SEED EFFECT_SPLASH
  EFFECT_DISABLE EFFECT_LEVEL_DAMAGE EFFECT_PSYWAVE EFFECT_ENCORE EFFECT_SNORE
  EFFECT_LOCK_ON EFFECT_SKETCH EFFECT_SLEEP_TALK EFFECT_SPITE EFFECT_FALSE_SWIPE
  EFFECT_PRIORITY_HIT EFFECT_TRIPLE_KICK EFFECT_THIEF EFFECT_MEAN_LOOK
  EFFECT_NIGHTMARE EFFECT_CURSE EFFECT_PROTECT EFFECT_SPIKES EFFECT_FORESIGHT
  EFFECT_PERISH_SONG EFFECT_ENDURE EFFECT_ROLLOUT EFFECT_FURY_CUTTER
  EFFECT_ATTRACT EFFECT_RETURN EFFECT_FRUSTRATION EFFECT_SAFEGUARD
  EFFECT_MAGNITUDE EFFECT_BATON_PASS EFFECT_ALL_UP_HIT EFFECT_BELLY_DRUM
  EFFECT_PSYCH_UP EFFECT_FUTURE_SIGHT EFFECT_TELEPORT EFFECT_BEAT_UP
  EFFECT_DEFENSE_CURL EFFECT_TRANSFORM EFFECT_REFLECT
]])
local nativeOnly2 = names("EFFECT_FREEZE EFFECT_SLEEP_HIT EFFECT_ALWAYS_CRIT")
for id in pairs(nativeOnly2) do supported2[id] = true end
for _, source in ipairs({ Gen2.STAT_CHANGES, Gen2.STAT_CHANGES_ON_HIT,
    Gen2.DRAIN, Gen2.CHARGE, Gen2.COUNTER, Gen2.WEATHER, Gen2.SUN_HEAL }) do
  for id in pairs(source) do supported2[id] = true end
end

local supported3 = {}
for effect in pairs(E.STATUS_SETUP) do supported3[effect] = true end
for effect in pairs(E.SECONDARY) do supported3[effect] = true end
for name in pairs(names([[
  HIT ABSORB EXPLOSION DREAM_EATER MIRROR_MOVE ALWAYS_HIT BIDE RAMPAGE
  MULTI_HIT METRONOME OHKO RAZOR_WIND SUPER_FANG DRAGON_RAGE DOUBLE_HIT
  RECOIL_IF_MISS SKY_ATTACK VITAL_THROW RAGE LEVEL_DAMAGE PSYWAVE COUNTER
  SNORE SLEEP_TALK FLAIL FALSE_SWIPE TRIPLE_KICK ROLLOUT FURY_CUTTER
  RETURN PRESENT FRUSTRATION MAGNITUDE PURSUIT SONICBOOM MIRROR_COAT
  SKULL_BASH EARTHQUAKE GUST SOLAR_BEAM BEAT_UP SEMI_INVULNERABLE
  SPIT_UP FACADE FOCUS_PUNCH NATURE_POWER ASSIST REVENGE BRICK_BREAK
  ENDEAVOR ERUPTION LOW_KICK SECRET_POWER WEATHER_BALL SKY_UPPERCUT
]])) do supported3[E[name]] = true end

local aliases3 = { RECOVER = true, THRASH = true, RECOIL_25 = true, FLY = true }
local nativeNames3 = {}
for _, name in ipairs(sortedKeys(E)) do
  local value = E[name]
  if type(value) == "number" and not aliases3[name] and not nativeNames3[value] then
    nativeNames3[value] = name
  end
end

local native2 = {}
for id, row in pairs(Map2.EFFECTS) do native2[id] = row.effect end
native2.EFFECT_POISON = E.POISON
native2.EFFECT_BURN = E.WILL_O_WISP

local reverse1, reverse2, canonical = {}, {}, {}
local function append(t, effect, id)
  local list = t[effect]
  if not list then list = {}; t[effect] = list end
  list[#list + 1] = id
end
for _, id in ipairs(sortedKeys(Map1.EFFECTS)) do
  local row = Map1.EFFECTS[id]
  canonical[id] = row
  append(reverse1, row.effect, id)
end
for _, id in ipairs(sortedKeys(native2)) do
  if supported2[id] then append(reverse2, native2[id], id) end
end

local inherited = {}
for _, row in pairs(Map1.MOVES) do inherited[row.effect] = true end
for effect in pairs(reverse1) do inherited[effect] = true end
for _, id in ipairs(sortedKeys(native2)) do
  local effect = native2[id]
  if not inherited[effect] and not canonical[id] then
    canonical[id] = { effect = effect }
  end
end
for _, name in ipairs(sortedKeys(E)) do
  local effect = E[name]
  if type(effect) == "number" and not aliases3[name]
      and supported3[effect] and not inherited[effect] then
    local older = reverse2[effect]
    if not older then canonical[name] = { effect = effect } end
  end
end

local function chance(record, generation)
  if type(record) ~= "table" then return nil end
  if generation == 2 then
    if type(record.effectChance) == "number" then return record.effectChance end
    if type(record.effectChanceRaw) == "number" then
      return math.floor(record.effectChanceRaw * 100 / 255 + 0.5)
    end
  elseif generation == 3 then
    return record.secondaryChance
  end
end

local function nativeId(value, generation)
  if value == nil then return nil end
  local name = value
  if generation == 3 and type(value) == "number" then
    name = nativeNames3[value] or tostring(value)
  elseif type(value) == "string" and value:match("^%d+$") then
    name = "string:" .. value
  end
  return "native:" .. generation .. ":" .. tostring(name)
end

function Effects.read(value, generation, record)
  if value == nil then return nil end
  if generation == 1 then return value end
  if generation ~= 2 and generation ~= 3 then return nil end
  if generation == 2 then
    if nativeOnly2[value] then return value end
    if type(record) == "table" and record._modEffectId == value and type(value) == "string"
        and not supported2[value] and not canonical[value] then
      return value
    end
    if not supported2[value] then return nativeId(value, generation) end
  end
  local effect = generation == 2 and native2[value] or nil
  if generation == 3 then
    effect = type(value) == "number" and value or E[value]
    if type(effect) ~= "number" then effect = nil end
  end
  local authored = type(record) == "table" and record._modEffectId
  if generation == 3 and type(authored) == "string" and effect == E.HIT
      and not canonical[authored] and E[authored] == nil
      and not Map1.UNSUPPORTED[authored] and not Map2.UNSUPPORTED[authored] then
    return authored
  end
  if authored and canonical[authored] and canonical[authored].effect == effect then return authored end
  local variants = effect and reverse1[effect]
  if variants then
    local probability = chance(record, generation)
    for _, id in ipairs(variants) do
      if Map1.EFFECTS[id].chance == probability then return id end
    end
    return variants[1]
  end
  local older = effect and reverse2[effect]
  if older then
    for _, id in ipairs(older) do
      if canonical[id] then return id end
    end
  end
  local name = effect and nativeNames3[effect]
  if name and canonical[name] then return name end
  return nativeId(value, generation)
end

local function defaultChance(row)
  if row.chance == 0 and (row.effect == E.TRAP or row.effect == E.PAY_DAY) then
    return 100
  end
  return row.chance
end

function Effects.write(id, generation, record, registered)
  if generation ~= 1 and generation ~= 2 and generation ~= 3 then
    return nil, "unsupported generation"
  end
  if type(id) ~= "string" or id == "" then
    return nil, "move effect must be a string id"
  end
  id = ({ HIT = "NO_ADDITIONAL_EFFECT", SLEEP = "SLEEP_EFFECT" })[id] or id
  if type(record) == "table" and record.effect ~= nil
      and (id == Effects.read(record.effect, generation, record)
        or id == nativeId(record.effect, generation)) then
    return record.effect
  end
  if id:match("^native:") then
    return nil, "native move effect requires its original record"
  end
  if generation == 1 then
    if Gen1.RECORDS[id] then return id end
    if Map1.EFFECTS[id] or Map1.UNSUPPORTED[id] or canonical[id] or nativeOnly2[id]
        or Map2.EFFECTS[id] or Map2.UNSUPPORTED[id] or E[id] ~= nil then
      return nil, "move effect has no Gen 1 handler: " .. id
    end
    return id
  end
  if nativeOnly2[id] then
    if generation == 2 then return id end
    return nil, "move effect has no Gen 3 handler: " .. id
  end
  local row = canonical[id]
  if not row and (generation == 2 or generation == 3) and registered and registered(id)
      and not native2[id] and not Map2.UNSUPPORTED[id]
      and not Map1.UNSUPPORTED[id] and E[id] == nil then
    if generation == 3 then return E.HIT end
    return id
  end
  if not row then return nil, "unsupported move effect: " .. id end
  if generation == 2 then
    if native2[id] and not supported2[id] then
      return nil, "move effect has no Gen 2 handler: " .. id
    end
    local targets = reverse2[row.effect]
    if not targets then return nil, "move effect has no Gen 2 handler: " .. id end
    local target = supported2[id] and native2[id] == row.effect and id or targets[1]
    return target, defaultChance(row)
  end
  if not supported3[row.effect] then
    return nil, "move effect has no Gen 3 handler: " .. id
  end
  return row.effect, defaultChance(row)
end

return Effects
