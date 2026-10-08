local Datasets = require("src.online.xgen.Datasets")
local Identity = require("src.online.xgen.Identity")
local Policy = require("src.online.xgen.Policy")
local Project = require("src.online.xgen.Project")
local Recommend = require("src.recommend.Recommend")

local Rentals = {}

Rentals.VERSION = 1
Rentals.LEVEL = 50
Rentals.IV = 20
Rentals.PERSONALITY = 150

-- src/battle_script_commands.c:8909
Rentals.HIDDEN_POWER_TYPES = { "FIGHTING", "FLYING", "POISON", "GROUND", "ROCK", "BUG", "GHOST", "STEEL",
  "FIRE", "WATER", "GRASS", "ELECTRIC", "PSYCHIC", "ICE", "DRAGON", "DARK" }

-- src/battle_script_commands.c:8898
local HP_BITS = { "hp", "atk", "def", "spe", "spa", "spd" }

Rentals.DEFINITIONS = {
  ["g3u-gen1"] = {
    { type = "NORMAL", species = 128, moves = { 70, 33, 59, 87 } },
    { type = "FIGHTING", species = 68, moves = { 66, 67, 126, 89 } },
    { type = "FLYING", species = 142, moves = { 17, 126, 36, 44 } },
    { type = "POISON", species = 89, moves = { 124, 87, 126, 1 } },
    { type = "GROUND", species = 28, moves = { 89, 70, 40, 163 } },
    { type = "ROCK", species = 76, moves = { 157, 88, 126, 89 } },
    { type = "BUG", species = 127, moves = { 66, 70, 11, 15 } },
    { type = "GHOST", species = 94, moves = { 122, 87, 94, 70 } },
    { type = "FIRE", species = 59, moves = { 126, 53, 36, 52 } },
    { type = "WATER", species = 130, moves = { 56, 57, 59, 87 } },
    { type = "GRASS", species = 3, moves = { 75, 22, 15, 33 } },
    { type = "ELECTRIC", species = 135, moves = { 87, 84, 36, 44 } },
    { type = "PSYCHIC", species = 97, moves = { 94, 93, 29, 1 } },
    { type = "ICE", species = 124, moves = { 59, 8, 94, 1 } },
    { type = "DRAGON", species = 149, moves = { 59, 87, 126, 57 } },
  },
  ["g3u-gen2"] = {
    { type = "NORMAL", species = 128, moves = { 70, 30, 59, 87 } },
    { type = "FIGHTING", species = 68, moves = { 223, 238, 126, 89 } },
    { type = "FLYING", species = 18, moves = { 17, 16, 211, 185 } },
    { type = "POISON", species = 89, moves = { 188, 124, 87, 126 } },
    { type = "GROUND", species = 51, moves = { 89, 189, 188, 163 } },
    { type = "ROCK", species = 76, moves = { 157, 88, 126, 89 } },
    { type = "BUG", species = 127, moves = { 66, 70, 168, 11 } },
    { type = "GHOST", species = 94, moves = { 247, 122, 87, 94 } },
    { type = "STEEL", species = 208, moves = { 231, 89, 21, 157 } },
    { type = "FIRE", species = 59, moves = { 126, 53, 231, 36 } },
    { type = "WATER", species = 130, moves = { 56, 57, 59, 87 } },
    { type = "GRASS", species = 3, moves = { 202, 75, 15, 22 } },
    { type = "ELECTRIC", species = 135, moves = { 87, 84, 231, 36 } },
    { type = "PSYCHIC", species = 65, moves = { 94, 60, 247, 7 } },
    { type = "ICE", species = 124, moves = { 59, 8, 94, 247 } },
    { type = "DRAGON", species = 149, moves = { 225, 239, 59, 87 } },
    { type = "DARK", species = 197, moves = { 44, 185, 231, 36 } },
  },
  ["g3u-gen3"] = {
    { type = "NORMAL", species = 128, moves = { 70, 290, 59, 87 } },
    { type = "FIGHTING", species = 68, moves = { 223, 238, 126, 89 } },
    { type = "FLYING", species = 18, moves = { 17, 332, 211, 290 } },
    { type = "POISON", species = 89, moves = { 188, 124, 87, 126 } },
    { type = "GROUND", species = 51, moves = { 89, 189, 188, 161 } },
    { type = "ROCK", species = 76, moves = { 157, 88, 38, 126 } },
    { type = "BUG", species = 127, moves = { 89, 66, 70, 185 } },
    { type = "GHOST", species = 94, moves = { 247, 325, 87, 94 } },
    { type = "STEEL", species = 208, moves = { 231, 89, 21, 157 } },
    { type = "FIRE", species = 59, moves = { 315, 126, 231, 36 } },
    { type = "WATER", species = 130, moves = { 56, 57, 59, 87 } },
    { type = "GRASS", species = 3, moves = { 202, 345, 89, 188 } },
    { type = "ELECTRIC", species = 135, moves = { 87, 85, 231, 36 } },
    { type = "PSYCHIC", species = 65, moves = { 94, 60, 231, 247 } },
    { type = "ICE", species = 124, moves = { 59, 58, 94, 247 } },
    { type = "DRAGON", species = 149, moves = { 337, 225, 59, 87 } },
    { type = "DARK", species = 197, moves = { 44, 185, 231, 36 } },
  },
}

function Rentals.definitions(rulesetId)
  return Project.copy(Rentals.DEFINITIONS[rulesetId])
end

local function hasType(types, want)
  for _, t in ipairs(types or {}) do
    if t == want then return true end
  end
  return false
end

function Rentals.moveCode(species, move, ruleset, data, unsupported)
  if move > ruleset.moveMax or not data.moves[move] then return "move_not_in_ruleset" end
  if unsupported and unsupported[move] then return "move_unsupported" end
  if not Datasets.learnable(data, species, move, Rentals.LEVEL) then return "move_not_legal" end
  return nil
end

function Rentals.validate(def, ruleset, data, unsupported)
  local sp = data.species[def.species]
  if def.species > ruleset.dexMax or not sp then return "species_not_in_ruleset" end
  if not hasType(sp.types, def.type) then return "rental_type_mismatch" end
  local seen = {}
  for _, move in ipairs(def.moves) do
    if seen[move] then return "rental_duplicate_move", { move = move } end
    seen[move] = true
    local code = Rentals.moveCode(def.species, move, ruleset, data, unsupported)
    if code then return code, { move = move } end
  end
  if #def.moves < 1 or #def.moves > Policy.MAX_MOVES then return "rental_bad_moves" end
  return nil
end

function Rentals.speciesNames(rulesetId, data)
  local out = {}
  for _, def in ipairs(Rentals.DEFINITIONS[rulesetId] or {}) do
    local sp = type(data) == "table" and data.species[def.species]
    if sp then out[#out + 1] = sp.name end
  end
  return out
end

function Rentals.hiddenPowerType(ivs)
  local bits = 0
  for i, k in ipairs(HP_BITS) do bits = bits + (math.floor(tonumber(ivs[k]) or 0) % 2) * 2 ^ (i - 1) end
  return Rentals.HIDDEN_POWER_TYPES[math.floor(bits * 15 / 63) + 1]
end

function Rentals.hiddenPowerIvs(want, from)
  local ivs = {}
  for _, k in ipairs(HP_BITS) do
    local v = math.floor(tonumber(type(from) == "table" and from[k]) or 31)
    ivs[k] = math.max(0, math.min(31, v))
  end
  if Rentals.hiddenPowerType(ivs) == want then return ivs end
  local best, bestCount
  for bits = 0, 63 do
    if Rentals.HIDDEN_POWER_TYPES[math.floor(bits * 15 / 63) + 1] == want then
      local count = 0
      for i = 0, 5 do count = count + math.floor(bits / 2 ^ i) % 2 end
      if not best or count > bestCount then best, bestCount = bits, count end
    end
  end
  if not best then return nil end
  for i, k in ipairs(HP_BITS) do ivs[k] = math.floor(best / 2 ^ (i - 1)) % 2 == 1 and 31 or 30 end
  return ivs
end

local function moveIndex(data)
  local index = {}
  for id, mv in pairs(data.moves) do
    if mv.key then
      if index[mv.key] == nil then index[mv.key] = id else index[mv.key] = false end
    end
  end
  return index
end

local function resolveMove(index, name)
  local hp = Recommend.hiddenPowerType(name)
  local token = hp and "HIDDENPOWER" or Identity.normalize(tostring(name or ""))
  if token and Recommend.RENAMED[token] and index[Recommend.RENAMED[token]] then token = Recommend.RENAMED[token] end
  return token and index[token] or nil, hp
end

function Rentals.fromSet(def, entry, ruleset, data, unsupported, index)
  local set = type(entry) == "table" and (entry.set or entry) or nil
  if type(set) ~= "table" or type(set.moves) ~= "table" or not data.species[def.species] then return nil, {} end
  index = index or moveIndex(data)
  local moves, dropped, seen, hpType = {}, {}, {}, nil
  for _, name in ipairs(set.moves) do
    if type(name) == "table" then name = name[1] end
    local id, hp = resolveMove(index, name)
    local code
    if not id then
      code = "move_unknown"
    elseif seen[id] then
      code = "rental_duplicate_move"
    elseif #moves >= Policy.MAX_MOVES then
      code = "rental_bad_moves"
    elseif hp and not Rentals.hiddenPowerIvs(hp, set.ivs) then
      code = "hidden_power_type"
    else
      code = Rentals.moveCode(def.species, id, ruleset, data, unsupported)
    end
    if code then
      dropped[#dropped + 1] = { move = tostring(name), id = id or nil, code = code }
    else
      seen[id] = true
      moves[#moves + 1] = id
      if hp then hpType = hp end
    end
  end
  if #moves == 0 then return nil, dropped end
  local out = { type = def.type, species = def.species, moves = moves }
  if hpType then out.ivs = Rentals.hiddenPowerIvs(hpType, set.ivs) end
  return out, dropped
end

function Rentals.build(rulesetId, data, opts)
  opts = opts or {}
  local ruleset = Policy.ruleset(rulesetId)
  local out = { version = Rentals.VERSION, ruleset = rulesetId, rentals = {}, excluded = {}, dropped = {},
    padded = {}, defaulted = {} }
  local defs = Rentals.DEFINITIONS[rulesetId]
  if not ruleset or not defs then
    out.excluded[1] = { code = "unknown_ruleset", detail = { ruleset = rulesetId } }
    return out
  end
  if type(data) ~= "table" then
    out.excluded[1] = { code = "missing_import" }
    return out
  end
  local unsupported = {}
  for k, v in pairs(opts.unsupported or {}) do
    if v == true then unsupported[tonumber(k) or k] = true elseif tonumber(v) then unsupported[tonumber(v)] = true end
  end
  local sets = type(opts.sets) == "table" and opts.sets or nil
  local byKey = sets and moveIndex(data) or nil
  for index, base in ipairs(defs) do
    local def, source = base, "default"
    if sets then
      local sp = data.species[base.species]
      local entry = sp and sets[Recommend.key(sp.name)]
      local made, dropped = Rentals.fromSet(base, entry, ruleset, data, unsupported, byKey)
      for _, d in ipairs(dropped) do
        d.index, d.type, d.species = index, base.type, base.species
        out.dropped[#out.dropped + 1] = d
      end
      if made then
        def, source = made, "recommended"
        local have = {}
        for _, m in ipairs(made.moves) do have[m] = true end
        for _, m in ipairs(base.moves) do
          if #made.moves < Policy.MAX_MOVES and not have[m] and not Rentals.moveCode(base.species, m, ruleset, data, unsupported) then
            have[m] = true
            made.moves[#made.moves + 1] = m
            out.padded[#out.padded + 1] = { index = index, type = base.type, species = base.species, id = m }
          end
        end
      else
        out.defaulted[#out.defaulted + 1] = { index = index, type = base.type, species = base.species,
          code = entry and "no_legal_moves" or "no_set" }
      end
    end
    local code, detail = Rentals.validate(def, ruleset, data, unsupported)
    if code then
      out.excluded[#out.excluded + 1] = { index = index, type = def.type, species = def.species, code = code, detail = detail }
    else
      local ivs, evs = {}, {}
      for _, k in ipairs(Policy.STAT_ORDER) do ivs[k], evs[k] = def.ivs and def.ivs[k] or Rentals.IV, 0 end
      local view = { gen = 3, national = def.species, level = Rentals.LEVEL, ivs = ivs, evs = evs,
        personality = Rentals.PERSONALITY, nature = Rentals.PERSONALITY % 25, otId = 0, otSecretId = 0,
        abilityNum = 0, item = 0, moves = {} }
      for _, move in ipairs(def.moves) do view.moves[#view.moves + 1] = { move = move, ppUps = 0 } end
      local record = Project.battleMon(view, data, { legacyPresent = opts.legacyPresent ~= false, rental = true })
      record.nickname = data.species[def.species].name
      local disclosed = {}
      for _, move in ipairs(def.moves) do disclosed[#disclosed + 1] = Project.moveRecord(data, move, 0) end
      out.rentals[#out.rentals + 1] = { rental = true, index = index, source = source, type = def.type, national = def.species,
        name = data.species[def.species].name, types = Project.copy(data.species[def.species].types),
        level = Rentals.LEVEL, record = record, moves = disclosed,
        stats = { hp = record.maxHp, atk = record.atk, def = record.def, spAtk = record.spAtk,
          spDef = record.spDef, speed = record.speed } }
    end
  end
  return out
end

return Rentals
