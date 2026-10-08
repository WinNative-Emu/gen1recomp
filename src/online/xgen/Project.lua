local bit = require("bit")
local Identity = require("src.online.xgen.Identity")
local Datasets = require("src.online.xgen.Datasets")
local Policy = require("src.online.xgen.Policy")

local Project = {}

local function int(v, lo, hi, default)
  local n = tonumber(v)
  if not n or n ~= n then return default end
  n = math.floor(n)
  if lo and n < lo then n = lo end
  if hi and n > hi then n = hi end
  return n
end

local function copy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = copy(x) end
  return out
end
Project.copy = copy

function Project.hpDv(dvs)
  -- engine/pokemon/move_mon.asm:1483
  return (dvs.attack % 2) * 8 + (dvs.defense % 2) * 4 + (dvs.speed % 2) * 2 + (dvs.special % 2)
end

function Project.shinyDv(dvs)
  -- engine/gfx/color.asm:8
  if dvs.defense ~= 10 or dvs.speed ~= 10 or dvs.special ~= 10 then return false end
  return dvs.attack % 4 >= 2
end

function Project.genderDv(ratio, dvs)
  return require("src.core.gen2.Gender").of(ratio, dvs)
end

function Project.unownLetterDv(dvs)
  return require("src.core.gen2.Unown").letterFromDVs(dvs)
end

function Project.shiny3(personality, otId, otSecretId)
  local p = (tonumber(personality) or 0) % 4294967296
  -- src/pokemon.c:6740
  local value = bit.bxor(bit.bxor(int(otId, 0, 65535, 0), int(otSecretId, 0, 65535, 0)),
    bit.bxor(math.floor(p / 65536), p % 65536))
  return value < 8
end

function Project.gender3(ratio, personality)
  -- src/pokemon.c:3452
  if ratio == nil or ratio == 255 then return "unknown" end
  if ratio == 0 then return "male" end
  if ratio == 254 then return "female" end
  return ratio > (int(personality, 0, nil, 0) % 256) and "female" or "male"
end

function Project.unownLetter3(personality)
  return require("src.core.game3.pokemon").unownLetter(personality)
end

local function gen3MoveRows(rec)
  local rows = {}
  local list = type(rec.moves) == "table" and rec.moves or {}
  for slot = 1, math.min(4, #list) do
    local entry = list[slot]
    local id = type(entry) == "table" and tonumber(entry.id or entry.moveId or entry.move) or tonumber(entry)
    local ups
    if type(rec.ppBonusesPacked) == "number" then
      ups = math.floor(rec.ppBonusesPacked / 4 ^ (slot - 1)) % 4
    elseif type(rec.ppBonuses) == "number" then
      ups = math.floor(rec.ppBonuses / 4 ^ (slot - 1)) % 4
    elseif type(entry) == "table" then
      ups = int(entry.ppUps, 0, 3, 0)
    end
    local pp = tonumber(rec.pp and rec.pp[slot]) or (type(entry) == "table" and tonumber(entry.pp)) or nil
    rows[#rows + 1] = { localKey = id, ppUps = ups or 0, pp = pp }
  end
  return rows
end

local function gbMoveRows(rec, data)
  local rows = {}
  for _, entry in ipairs(type(rec.moves) == "table" and rec.moves or {}) do
    local key = type(entry) == "table" and (entry.id or entry.move) or entry
    local ups = type(entry) == "table" and tonumber(entry.ppUps) or nil
    if ups == nil and type(entry) == "table" and tonumber(entry.maxPp) then
      local mv = data.moves[Identity.moveOf(data, key) or -1]
      local base = mv and mv.pp or 0
      local bonus = math.floor(base / 5)
      if bonus > 0 and entry.maxPp > base and (entry.maxPp - base) % bonus == 0 then
        ups = (entry.maxPp - base) / bonus
      end
    end
    rows[#rows + 1] = { localKey = key, ppUps = int(ups, 0, 3, 0),
      pp = type(entry) == "table" and tonumber(entry.pp) or nil }
  end
  return rows
end

function Project.read(rec, data)
  if type(rec) ~= "table" then return nil, "bad_record" end
  if type(data) ~= "table" then return nil, "missing_import" end
  local gen = data.generation
  local localSpecies = rec.species
  if gen == 3 then localSpecies = tonumber(rec.speciesId or rec.species) end
  local national = Identity.speciesOf(data, localSpecies)
  if not national then return nil, "species_unknown" end
  local sp = data.species[national]
  local view = { gen = gen, version = data.version, national = national, localSpecies = localSpecies,
    speciesName = sp.name, isEgg = rec.isEgg == true or rec.isBadEgg == true }
  local rows = gen == 3 and gen3MoveRows(rec) or gbMoveRows(rec, data)
  view.moves = {}
  for _, row in ipairs(rows) do
    if row.localKey ~= nil and row.localKey ~= 0 then
      local id = Identity.moveOf(data, row.localKey)
      if not id then return nil, "move_unknown", { move = row.localKey } end
      view.moves[#view.moves + 1] = { move = id, ppUps = row.ppUps, pp = row.pp }
    end
  end
  if #view.moves > Policy.MAX_MOVES then return nil, "bad_record", { field = "moves" } end
  view.exp = tonumber(rec.exp or rec.experience)
  view.level = int(rec.level, 1, 100, nil)
  if not view.level and view.exp then view.level = Datasets.levelForExp(data, national, view.exp) end
  if not view.level then return nil, "bad_record", { field = "level" } end
  view.nickname = type(rec.nickname) == "string" and rec.nickname ~= "" and rec.nickname or nil
  view.otName = rec.otName or rec.ot
  view.otId = tonumber(rec.otId)
  view.otSecretId = gen == 3 and int(rec.otSecretId, 0, 65535, nil) or nil
  if gen == 3 and view.otId and view.otId > 65535 then
    view.otSecretId = view.otSecretId or math.floor(view.otId / 65536)
    view.otId = view.otId % 65536
  end
  if gen == 3 then
    local iv, ev = type(rec.ivs) == "table" and rec.ivs or {}, type(rec.evs) == "table" and rec.evs or {}
    view.ivs, view.evs = {}, {}
    for _, k in ipairs(Policy.STAT_ORDER) do
      view.ivs[k] = int(iv[k], 0, 31, 0)
      view.evs[k] = int(ev[k], 0, 255, 0)
    end
    view.personality = int(rec.personality, 0, 4294967295, 0)
    view.nature = view.personality % 25
    view.abilityNum = int(rec.abilityNum, 0, 1, nil)
    if view.abilityNum == nil then
      local pair = sp.abilities or {}
      view.abilityNum = (pair[2] or 0) ~= 0 and view.personality % 2 or 0
    end
    view.ability = (sp.abilities or {})[view.abilityNum + 1]
    if view.ability == 0 then view.ability = (sp.abilities or {})[1] end
    view.friendship = int(rec.friendship or rec.happiness, 0, 255, nil)
    local item = rec.heldItem
    if item == nil then item = rec.item end
    view.item = tonumber(item) or 0
  else
    if type(rec.dvs) ~= "table" then return nil, "bad_record", { field = "dvs" } end
    local d = rec.dvs
    view.dvs = { attack = int(d.attack, 0, 15, 0), defense = int(d.defense, 0, 15, 0),
      speed = int(d.speed, 0, 15, 0), special = int(d.special or d.specialAttack, 0, 15, 0) }
    view.dvs.hp = Project.hpDv(view.dvs)
    local se = type(rec.statExp) == "table" and rec.statExp or {}
    view.statExp = {}
    for _, k in ipairs(Policy.GB_STAT_ORDER) do
      local v = se[k]
      if k == "special" and v == nil then v = se.specialAttack end
      view.statExp[k] = int(v, 0, 65535, 0)
    end
    if gen == 2 then
      view.item = rec.item
      view.friendship = int(rec.happiness, 0, 255, nil)
    else
      view.catchRate = int(rec.catchRate, 0, 255, nil)
    end
  end
  view.pokerus = int(rec.pokerus, 0, 255, 0)
  return view
end

function Project.ivs(view)
  if view.gen == 3 then return copy(view.ivs) end
  local d = view.dvs
  return { hp = Policy.ivFromDv(d.hp), atk = Policy.ivFromDv(d.attack), def = Policy.ivFromDv(d.defense),
    spe = Policy.ivFromDv(d.speed), spa = Policy.ivFromDv(d.special), spd = Policy.ivFromDv(d.special) }
end

function Project.evs(view)
  if view.gen == 3 then return copy(view.evs) end
  local s = view.statExp
  local raw = { hp = s.hp, atk = s.attack, def = s.defense, spe = s.speed, spa = s.special, spd = s.special }
  local out, total = {}, 0
  for _, k in ipairs(Policy.STAT_ORDER) do
    local ev = math.min(Policy.evFromStatExp(raw[k]), Policy.EV_TOTAL - total)
    out[k], total = ev, total + ev
  end
  return out
end

function Project.natureMultiplier(nature, statIndex)
  -- src/pokemon.c:1365
  local up, down = math.floor(nature / 5) + 1, nature % 5 + 1
  if up == down then return 1 end
  if statIndex == up then return 1.1 end
  if statIndex == down then return 0.9 end
  return 1
end

function Project.stats3(base, level, ivs, evs, nature, national)
  nature = tonumber(nature) or 0
  local out = {}
  -- src/pokemon.c:2845
  if national == 292 then
    out.hp = 1
  else
    out.hp = math.floor(((2 * base.hp + ivs.hp + math.floor(evs.hp / 4)) * level) / 100) + level + 10
  end
  -- src/pokemon.c:2814
  for index, key in ipairs({ "atk", "def", "spe", "spa", "spd" }) do
    local n = math.floor(((2 * base[key] + ivs[key] + math.floor(evs[key] / 4)) * level) / 100) + 5
    local mul = Project.natureMultiplier(nature, index)
    if mul > 1 then n = math.floor(n * 110 / 100) elseif mul < 1 then n = math.floor(n * 90 / 100) end
    out[key] = n
  end
  return out
end

function Project.moveRecord(data, move, ppUps)
  local mv = data.moves[move]
  if not mv then return nil end
  local maxPp = Policy.maxPp(mv.pp, ppUps)
  return { id = mv.id, name = mv.name, type = mv.type, power = mv.power, accuracy = mv.accuracy,
    pp = maxPp, maxPp = maxPp, ppUps = ppUps or 0, basePp = mv.pp, priority = mv.priority,
    effect = mv.effect, effectChance = mv.effectChance, category = mv.category,
    sourceGen = data.generation }
end

function Project.traits(view, data)
  local sp = data.species[view.national]
  if view.gen == 3 then
    local letter = view.national == 201 and Project.unownLetter3(view.personality) or nil
    return { gender = Project.gender3(sp.genderRatio, view.personality),
      shiny = Project.shiny3(view.personality, view.otId, view.otSecretId), unownLetter = letter }
  end
  return { gender = view.gen == 2 and Project.genderDv(sp.genderRatio, view.dvs) or nil,
    shiny = Project.shinyDv(view.dvs),
    unownLetter = view.national == 201 and Project.unownLetterDv(view.dvs) - 1 or nil }
end

function Project.battleMon(view, data, opts)
  opts = opts or {}
  local sp = data.species[view.national]
  local legacy = opts.legacyPresent ~= false
  local ivs, evs = Project.ivs(view), Project.evs(view)
  local nature = (not legacy and view.gen == 3) and view.nature or Policy.NATURE_NEUTRAL
  local level = view.level
  local stats = Project.stats3(sp.base, level, ivs, evs, nature, view.national)
  local moves = {}
  local list = opts.moves or view.moves
  for _, m in ipairs(list) do
    local mv = data.moves[m.move]
    if mv then
      local ups = math.max(0, math.min(3, math.floor(tonumber(m.ppUps) or 0)))
      moves[#moves + 1] = { id = mv.id, pp = Policy.maxPp(mv.pp, ups), ppUps = ups }
    end
  end
  local traits = Project.traits(view, data)
  local out = {
    national = view.national, species = view.national, nickname = view.nickname or sp.name,
    level = level, hp = stats.hp, maxHp = stats.hp, atk = stats.atk, def = stats.def,
    spAtk = stats.spa, spDef = stats.spd, speed = stats.spe, moves = moves,
    ability = 0, item = 0, ivs = ivs, evs = evs, nature = nature,
    gender = traits.gender, shiny = traits.shiny, unownLetter = traits.unownLetter,
    sourceGen = view.gen, rental = opts.rental or nil,
  }
  if not legacy and view.gen == 3 then
    out.ability, out.abilityNum, out.personality = view.ability or 0, view.abilityNum, view.personality
    out.item = tonumber(view.item) or 0
  end
  return out
end

function Project.mon(rec, data, opts)
  local view, code, detail = Project.read(rec, data)
  if not view then return nil, code, detail end
  return Project.battleMon(view, data, opts)
end

return Project
