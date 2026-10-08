local Metadata = {}
local NATURES = { "Hardy", "Lonely", "Brave", "Adamant", "Naughty", "Bold", "Docile",
  "Relaxed", "Impish", "Lax", "Timid", "Hasty", "Serious", "Jolly", "Naive", "Modest",
  "Mild", "Quiet", "Bashful", "Rash", "Calm", "Gentle", "Sassy", "Careful", "Quirky" }
Metadata.NATURES = NATURES
local function number(value) return tonumber(value) end
local function name(records, key)
  local value = records and records[key]
  if type(value) == "table" then return value.name or tostring(key) end
  return value or (key ~= nil and tostring(key) or nil)
end

function Metadata.describe(data, mon, d, def)
  local gen, pid = data.generation, number(mon.personality) or 0
  local meta = gen == 3 and data.meta[tonumber(mon.species)] or def
  d.trainer = mon.otName or mon.ot
  d.trainerId, d.secretId = mon.otId or mon.trainerId, mon.otSecretId
  d.friendship = mon.friendship or mon.happiness
  d.experience = mon.exp or mon.experience
  if gen == 3 then
    local Summary = require("src.core.game3.summary_data")
    local nature = pid % 25
    d.nature, d.natureId = NATURES[nature + 1], nature
    local ratio = meta and meta.genderRatio
    if ratio ~= nil then
      d.gender = ratio == 255 and "Genderless" or ratio == 0 and "Male"
        or ratio == 254 and "Female" or (pid % 256 < ratio and "Female" or "Male")
    end
    local pair = data.abilities[tonumber(mon.species)] or {}
    local slot = tonumber(mon.abilityNum)
    if slot == nil then slot = pid % 2 end
    local ability = pair[slot + 1]
    if not ability or ability == 0 then ability = pair[1] end
    d.ability = ability and name(data.abilityNames, ability) or nil
    local growth = meta and meta.growthRate
    if mon.level == nil and growth ~= nil and d.experience ~= nil then
      d.level = 1
      while d.level < 100 and Summary.expForLevel(growth, d.level + 1) <= d.experience do
        d.level = d.level + 1
      end
    end
    local base = data.stats[tonumber(mon.species)]
    if base and d.level > 0 then
      local iv, ev, stats = mon.ivs or {}, mon.evs or {}, {}
      for _, row in ipairs({ { "hp", "hp" }, { "atk", "attack" }, { "def", "defense" },
          { "spe", "speed" }, { "spa", "spAtk" }, { "spd", "spDef" } }) do
        local key, out = row[1], row[2]
        local value = math.floor((2 * (base[key] or 0) + (iv[key] or 0)
          + math.floor((ev[key] or 0) / 4)) * d.level / 100)
        if key == "hp" then value = d.national == 292 and 1 or value + d.level + 10
        else
          local natureKey = ({ spe = "spd", spa = "spAtk", spd = "spDef" })[key] or key
          local percent = math.floor(Summary.natureStatModifier(nature, natureKey) * 100 + 0.5)
          value = math.floor((value + 5) * percent / 100)
        end
        stats[out] = value
      end
      d.stats = stats
    end
    local location = data.locations[tonumber(mon.metLocation)]
    d.location = mon.metLocationName or (type(location) == "table" and location.name)
      or (mon.metLocation ~= nil and "Location " .. tostring(mon.metLocation) or nil)
    d.ball = name(data.items, mon.pokeball or mon.ball)
    d.metLevel, d.metGame = mon.metLevel, mon.metGame
    d.markings = tonumber(mon.markings) or 0
  elseif gen == 2 then
    if def and def.genderRatio ~= nil then
      local g = require("src.battle.gen2.Mon").vanillaGender(def, mon.dvs)
      d.gender = g == "male" and "Male" or g == "female" and "Female" or "Genderless"
    end
    if def and def.baseStats then
      d.stats = require("src.battle.gen2.Mon").stats(def.baseStats, mon.dvs, d.level, mon.statExp)
    end
    if mon.caughtLocation ~= nil then d.location = "Landmark " .. tostring(mon.caughtLocation) end
    d.metLevel = mon.caughtLevel
  elseif def and def.baseStats then
    d.stats = require("src.pokemon.Stats").calc(def, d.level, mon.dvs or {}, mon.statExp)
  end
  d.stats = d.stats or mon.stats or {}
  d.hp = d.stats.hp or mon.maxHp
  d.attack = d.stats.attack or mon.attack
  d.defense = d.stats.defense or mon.defense
  d.speed = d.stats.speed or mon.speed
  d.special = d.stats.special
  d.spAtk = d.stats.spAtk or d.stats.specialAttack or mon.spAtk
  d.spDef = d.stats.spDef or d.stats.specialDefense or mon.spDef
  d.moveDetails = {}
  local originalSlots = mon.cartExtra and mon.cartExtra.moveSlots
  local slotCursor = 1
  for i, move in ipairs(mon.moves or {}) do
    local key = type(move) == "table" and (move.moveId or move.id or move.move or move.name) or move
    if key and key ~= 0 then
      local nativeSlot = i
      if gen == 3 and originalSlots and originalSlots.moves then
        while slotCursor <= 4 and (originalSlots.moves[slotCursor] or 0) == 0 do slotCursor = slotCursor + 1 end
        if originalSlots.moves[slotCursor] == key then nativeSlot = slotCursor; slotCursor = slotCursor + 1 end
      end
      local battle = gen == 3 and data.battleMoves[key] or data.moves[key]
      local basePP = type(battle) == "table" and battle.pp
      local bonus = type(move) == "table" and (move.ppUps or move.ppUp or move.ppBonuses)
        or type(mon.ppBonuses) == "table" and mon.ppBonuses[i]
      bonus = tonumber(bonus) or math.floor((tonumber(mon.ppBonusesPacked) or 0) / 4^(nativeSlot - 1)) % 4
      local maxPP = type(move) == "table" and move.maxPp
        or basePP and basePP + math.floor(basePP * bonus / 5)
      d.moveDetails[#d.moveDetails + 1] = { name = name(data.moves, key),
        pp = type(move) == "table" and move.pp or (mon.pp or {})[i], maxPP = maxPP, ppUps = bonus }
    end
  end
  d.contest, d.ribbons, d.pokerus = mon.contest, mon.ribbons, mon.pokerus
  d.championRibbon, d.fateful = mon.championRibbon, mon.modernFatefulEncounter
  return d
end

function Metadata.summary(entry)
  local d, mon, gen = entry.display, entry.mon, entry.generation
  local rows = {}
  local function add(label, value)
    rows[#rows + 1] = { label, value == nil and "Not recorded" or tostring(value) }
  end
  add("Original Trainer", d.trainer)
  add("Trainer ID", d.trainerId)
  if gen == 3 then add("Secret ID", d.secretId) end
  add("Experience", d.experience)
  if gen >= 2 then add("Gender", d.gender); add("Friendship / egg cycles", d.friendship) end
  if gen == 3 then
    add("Nature", d.nature); add("Ability", d.ability); add("Poké Ball", d.ball)
    add("Met game", d.metGame); add("Markings", d.markings)
  end
  if gen >= 2 then add("Met location", d.location); add("Met level", d.metLevel); add("Pokérus", d.pokerus) end
  for _, move in ipairs(d.moveDetails or {}) do
    add(move.name, tostring(move.pp or "?") .. " / " .. tostring(move.maxPP or "?") .. " PP · " .. move.ppUps .. " PP Ups")
  end
  for _, field in ipairs({ { "Stats", d.stats }, { "IVs", mon.ivs }, { "DVs", mon.dvs },
      { gen == 3 and "EVs" or "Stat experience", gen == 3 and mon.evs or mon.statExp }, { "Contest", d.contest } }) do
    if type(field[2]) == "table" then
      local values = {}
      for key, value in pairs(field[2]) do values[#values + 1] = key .. " " .. tostring(value) end
      table.sort(values); add(field[1], #values > 0 and table.concat(values, " · ")
        or (field[1] == "EVs" or field[1] == "Stat experience") and "All zero" or "Not recorded")
    end
  end
  if gen == 3 then
    local Ribbons = require("src.core.game3.rse.ribbons")
    local names = {}
    for _, key in ipairs(Ribbons.COUNTED) do
      local count = Ribbons.get(mon, key)
      if count > 0 then names[#names + 1] = key .. (count > 1 and " ×" .. count or "") end
    end
    add("Ribbons", #names > 0 and table.concat(names, ", ") or "None")
    add("Fateful encounter", d.fateful)
  end
  return rows
end

return Metadata
