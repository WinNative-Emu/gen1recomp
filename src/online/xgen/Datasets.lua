local Identity = require("src.online.xgen.Identity")

local Datasets = {}

local cached = {}
local readerOverride = nil

local GB_FILES = { pokemon = "data/generated/pokemon.lua", moves = "data/generated/moves.lua",
  items = "data/generated/items.lua" }
local GBA_ROOT = "data/generated/gba/pokemon/"
local GBA_FILES = {
  names = GBA_ROOT .. "names.lua", national = GBA_ROOT .. "national.lua",
  types = GBA_ROOT .. "types.lua", stats = GBA_ROOT .. "stats.lua", meta = GBA_ROOT .. "meta.lua",
  abilities = GBA_ROOT .. "abilities.lua", battleMoves = GBA_ROOT .. "battle_moves.lua",
  moveNames = GBA_ROOT .. "move_names.lua", learnsets = GBA_ROOT .. "learnsets.lua",
  tmhm = GBA_ROOT .. "tmhm.lua", tutor = GBA_ROOT .. "tutor.lua", eggMoves = GBA_ROOT .. "egg_moves.lua",
  evolutions = GBA_ROOT .. "evolutions.lua", items = "data/generated/gba/items/pack.lua",
  typeNames = GBA_ROOT .. "type_names.lua",
}
local GBA_REQUIRED = { "names", "national", "types", "stats", "meta", "battleMoves", "moveNames",
  "learnsets", "tmhm", "eggMoves", "evolutions", "items" }
local NO_TUTORS = { ruby = true, sapphire = true }

local function versionInfo(version)
  local GameVersion = require("src.core.GameVersion")
  return GameVersion.generation(version), GameVersion.cachePrefix(version)
end

local function defaultReader(version, rel)
  local _, prefix = versionInfo(version)
  return require("src.import.CacheFs").readAt(prefix .. rel)
end

function Datasets.directoryReader(root)
  local CacheBlob = require("src.import.CacheBlob")
  return function(version, rel)
    local _, prefix = versionInfo(version)
    local path = root .. "/" .. prefix .. rel
    local f = io.open(path, "rb")
    if not f then return nil end
    local body = f:read("*a")
    f:close()
    return CacheBlob.decode(path, body)
  end
end

function Datasets.setReader(fn)
  readerOverride = fn
  cached = {}
end

function Datasets.reset()
  cached = {}
end

local function evaluate(body, label)
  if type(body) ~= "string" then return nil end
  local chunk = (loadstring or load)(body, "@" .. label)
  if not chunk then return nil end
  if setfenv then setfenv(chunk, {}) end
  local ok, value = pcall(chunk)
  return ok and type(value) == "table" and value or nil
end

local function readTables(version, reader)
  local generation = versionInfo(version)
  local files = generation == 3 and GBA_FILES or GB_FILES
  local out = {}
  for name, rel in pairs(files) do
    out[name] = evaluate(reader(version, rel), version .. "/" .. rel)
  end
  return out
end

local function placeholder(name)
  return type(name) ~= "string" or name == "" or name:match("^%?+$") ~= nil or name == "TERU-SAMA"
end

local function addLevel(list, level, move)
  if move then list[#list + 1] = { level = tonumber(level) or 1, move = move } end
end

local function sortLevels(list)
  for i, row in ipairs(list) do row.order = i end
  table.sort(list, function(x, y)
    if x.level ~= y.level then return x.level < y.level end
    return x.order < y.order
  end)
  for _, row in ipairs(list) do row.order = nil end
end

local function newData(version, generation)
  return {
    version = version, generation = generation,
    dexMax = generation == 1 and 151 or generation == 2 and 251 or 386,
    moveMax = generation == 1 and 165 or generation == 2 and 251 or 354,
    species = {}, moves = {},
    localToNational = {}, nationalToLocal = {},
    localToMove = {}, moveToLocal = {},
    localToType = {}, typeToLocal = {},
    items = { byLocal = {}, byKey = {}, held = generation ~= 1 },
    problems = {},
  }
end

local function problem(data, code, detail)
  data.problems[#data.problems + 1] = { code = code, detail = detail }
end

local function buildGB(data, raw)
  local generation = data.generation
  local Growth = generation == 1 and require("src.pokemon.Growth") or nil
  local Mon = generation == 2 and require("src.battle.gen2.Mon") or nil
  local growthRows = raw.pokemon and raw.pokemon.growthRates
  for key, def in pairs(raw.moves or {}) do
    if type(def) == "table" and tonumber(def.index) and def.index >= 1 and def.index <= data.moveMax then
      local id = def.index
      local typeName = Identity.canonType(def.type, generation)
      data.localToMove[key], data.moveToLocal[id] = id, key
      if def.type ~= nil and typeName then data.localToType[def.type], data.typeToLocal[typeName] = typeName, def.type end
      data.moves[id] = { id = id, key = Identity.normalize(def.name or key), name = def.name or tostring(key),
        localKey = key, type = typeName, power = tonumber(def.power) or 0, accuracy = tonumber(def.accuracy),
        pp = tonumber(def.pp) or 0, effect = def.effect, effectChance = def.effectChance,
        category = Identity.category(typeName, def.power) }
    end
  end
  for key, def in pairs(raw.pokemon or {}) do
    if type(def) == "table" and tonumber(def.dex) and def.dex >= 1 and def.dex <= data.dexMax then
      local n = def.dex
      data.localToNational[key], data.nationalToLocal[n] = n, key
      local types = {}
      for _, t in ipairs(def.types or {}) do
        local name = Identity.canonType(t, generation)
        if name and types[#types] ~= name then types[#types + 1] = name end
      end
      local b = def.baseStats or {}
      local base = { hp = b.hp, atk = b.attack, def = b.defense, spe = b.speed,
        spa = b.specialAttack or b.special, spd = b.specialDefense or b.special, special = b.special }
      local curve = def.growthRate
      local exp = {}
      for level = 1, 100 do
        if generation == 1 then
          exp[level] = Growth.expForLevel(curve, level)
        else
          exp[level] = Mon.experienceForLevel(growthRows and growthRows[curve], level)
        end
      end
      local levelMoves, tmhm, tutor, egg = {}, {}, {}, {}
      for _, m in ipairs(def.level1Moves or {}) do addLevel(levelMoves, 1, m) end
      for _, row in ipairs(def.learnset or {}) do addLevel(levelMoves, row.level, row.move) end
      for _, row in ipairs(def.levelMoves or {}) do addLevel(levelMoves, row.level, row.move) end
      for _, m in ipairs(def.tmhm or {}) do tmhm[#tmhm + 1] = m end
      for _, m in ipairs(def.tutorMoves or {}) do tutor[#tutor + 1] = m end
      for _, m in ipairs(def.eggMoves or {}) do egg[#egg + 1] = m end
      local evolutions = {}
      for _, evo in ipairs(def.evolutions or {}) do
        evolutions[#evolutions + 1] = { into = evo.into or evo.species, method = evo.method,
          level = evo.level, item = evo.item }
      end
      data.species[n] = { national = n, key = Identity.normalize(def.name or key), name = def.name or tostring(key),
        localKey = key, types = types, base = base, genderRatio = def.genderRatio,
        catchRate = def.catchRate, growth = curve, exp = exp, friendship = generation == 2 and 70 or nil,
        rawLevel = levelMoves, rawTmhm = tmhm, rawTutor = tutor, rawEgg = egg, rawEvolutions = evolutions }
    end
  end
  local Mail = generation == 2 and require("src.core.gen2.Mail") or nil
  for key, def in pairs(generation == 2 and raw.items or {}) do
    if type(def) == "table" and not placeholder(def.name) then
      local norm = Identity.normalize(def.name)
      if norm then
        data.items.byLocal[key] = { key = norm, name = def.name, localKey = key,
          mail = Mail and Mail.isMail(key) or false, index = def.index }
        if data.items.byKey[norm] ~= nil and data.items.byKey[norm] ~= key then
          problem(data, "item_name_collision", { key = norm })
        end
        data.items.byKey[norm] = key
      end
    end
  end
  data.items.timeCapsule = raw.items and raw.items.timeCapsule
  data.raw = { items = raw.items, pokemon = raw.pokemon, moves = raw.moves }
end

local CAPE_BRINK_VERSIONS = { firered = true, leafgreen = true }

local function bitSet(value, index)
  return math.floor((tonumber(value) or 0) / 2 ^ index) % 2 == 1
end

local function buildGBA(data, raw)
  local generation = 3
  local SummaryData = require("src.core.game3.summary_data")
  for id = 1, data.moveMax do
    local row = raw.battleMoves and raw.battleMoves.moves and raw.battleMoves.moves[id]
    local name = raw.moveNames and raw.moveNames[id]
    if type(row) == "table" and not placeholder(name) then
      local typeName = Identity.canonType(row.type, generation)
      data.localToMove[id], data.moveToLocal[id] = id, id
      data.moves[id] = { id = id, key = Identity.normalize(name), name = name, localKey = id,
        type = typeName, power = tonumber(row.power) or 0, accuracy = tonumber(row.accuracy),
        pp = tonumber(row.pp) or 0, priority = tonumber(row.priority) or 0, effect = row.effect,
        effectChance = row.secondaryChance, target = row.target, flags = row.flags,
        category = Identity.category(typeName, row.power) }
    end
  end
  for id = 0, 17 do
    local name = Identity.GEN3_TYPES[id]
    data.localToType[id], data.typeToLocal[name] = name, id
    local shown = raw.typeNames and raw.typeNames[id]
    if shown and name ~= "MYSTERY" and not Identity.subsequence(Identity.normalize(shown) or "", name) then
      problem(data, "type_name_mismatch", { id = id, shown = shown, canonical = name })
    end
  end
  local toSpecies = raw.national and raw.national.toSpecies or {}
  local machines = raw.tmhm and raw.tmhm.machines or {}
  local tmLearn = raw.tmhm and raw.tmhm.learnsets or {}
  local tutorMoves = raw.tutor and raw.tutor.moves or {}
  local tutorLearn = raw.tutor and raw.tutor.learnsets or {}
  local tutorCount = 0
  while tutorMoves[tutorCount] ~= nil do tutorCount = tutorCount + 1 end
  for n = 1, data.dexMax do
    local internal = tonumber(toSpecies[n])
    local name = internal and raw.names and raw.names[internal]
    local stats = internal and raw.stats and raw.stats[internal]
    local meta = internal and raw.meta and raw.meta[internal]
    if internal and not placeholder(name) and type(stats) == "table" and type(meta) == "table" then
      data.localToNational[internal], data.nationalToLocal[n] = n, internal
      local types = {}
      for _, t in ipairs(raw.types and raw.types[internal] or {}) do
        local tn = Identity.canonType(t, generation)
        if tn and types[#types] ~= tn then types[#types + 1] = tn end
      end
      local exp = {}
      for level = 1, 100 do exp[level] = SummaryData.expForLevel(meta.growthRate, level) end
      local levelMoves, tmhm, tutor, egg = {}, {}, {}, {}
      for _, row in ipairs(raw.learnsets and raw.learnsets[internal] or {}) do
        addLevel(levelMoves, row[1] or row.level, tonumber(row[2] or row.move))
      end
      local tm = tmLearn[internal]
      if type(tm) == "table" then
        for index = 0, 57 do
          local bits = index < 32 and tm.lo or tm.hi
          if bitSet(bits, index < 32 and index or index - 32) and machines[index] then
            tmhm[#tmhm + 1] = tonumber(machines[index])
          end
        end
      end
      local tutorBits = tutorLearn[internal]
      for index = 0, tutorCount - 1 do
        if bitSet(tutorBits, index) then tutor[#tutor + 1] = tonumber(tutorMoves[index]) end
      end
      if CAPE_BRINK_VERSIONS[data.version] then
        for _, row in pairs(require("src.core.game3.move_learn").CAPE_BRINK) do
          if row.species == internal then tutor[#tutor + 1] = row.move end
        end
      end
      for _, m in ipairs(raw.eggMoves and raw.eggMoves[internal] or {}) do egg[#egg + 1] = tonumber(m) end
      local evolutions = {}
      for _, evo in ipairs(raw.evolutions and raw.evolutions[internal] or {}) do
        evolutions[#evolutions + 1] = { into = tonumber(evo.target), method = evo.method, param = evo.param }
      end
      local pair = raw.abilities and raw.abilities[internal] or {}
      data.species[n] = { national = n, key = Identity.normalize(name), name = name, localKey = internal,
        types = types, base = { hp = stats.hp, atk = stats.atk, def = stats.def, spe = stats.spe,
          spa = stats.spa, spd = stats.spd },
        genderRatio = meta.genderRatio, catchRate = meta.catchRate, growth = meta.growthRate, exp = exp,
        friendship = meta.friendship, abilities = { tonumber(pair[1]) or 0, tonumber(pair[2]) or 0 },
        rawLevel = levelMoves, rawTmhm = tmhm, rawTutor = tutor, rawEgg = egg, rawEvolutions = evolutions }
    end
  end
  for id, def in pairs(raw.items and raw.items.items or {}) do
    if type(def) == "table" and tonumber(id) and not placeholder(def.name) then
      local norm = Identity.normalize(def.name)
      if norm and norm ~= "" then
        data.items.byLocal[id] = { key = norm, name = def.name, localKey = id,
          mail = def.fieldUseName == "ItemUseOutOfBattle_Mail", index = id }
        if data.items.byKey[norm] == nil or id < data.items.byKey[norm] then data.items.byKey[norm] = id end
      end
    end
  end
  data.raw = { items = raw.items }
end

local function canonicalizeLearnsets(data)
  local function moveOf(m)
    if type(m) == "number" and data.generation == 3 then return data.moves[m] and m or nil end
    return data.localToMove[m]
  end
  local function setOf(list)
    local out = {}
    for _, m in ipairs(list) do
      local id = moveOf(m)
      if id then out[id] = true end
    end
    return out
  end
  for n, sp in pairs(data.species) do
    local level = {}
    for _, row in ipairs(sp.rawLevel) do
      local id = moveOf(row.move)
      if id then level[#level + 1] = { level = row.level, move = id } end
    end
    sortLevels(level)
    sp.levelMoves, sp.tmhm, sp.tutor, sp.egg = level, setOf(sp.rawTmhm), setOf(sp.rawTutor), setOf(sp.rawEgg)
    local evolutions = {}
    for _, evo in ipairs(sp.rawEvolutions) do
      local into = evo.into
      local target = into ~= nil and data.localToNational[into] or nil
      if target then
        evolutions[#evolutions + 1] = { into = target, method = evo.method, level = evo.level, param = evo.param }
        local child = data.species[target]
        if child and child.evolvesFrom == nil then child.evolvesFrom = n end
      end
    end
    sp.evolutions = evolutions
    sp.rawLevel, sp.rawTmhm, sp.rawTutor, sp.rawEgg, sp.rawEvolutions = nil, nil, nil, nil, nil
  end
end

function Datasets.build(version, raw)
  local generation = versionInfo(version)
  if not generation then return nil, "unknown_version" end
  local data = newData(version, generation)
  if generation == 3 then
    for _, name in ipairs(GBA_REQUIRED) do
      if type(raw[name]) ~= "table" then return nil, "missing_import", { file = GBA_FILES[name] } end
    end
    if not NO_TUTORS[version] and type(raw.tutor) ~= "table" then
      return nil, "missing_import", { file = GBA_FILES.tutor }
    end
    buildGBA(data, raw)
  else
    if type(raw.pokemon) ~= "table" or type(raw.moves) ~= "table" then
      return nil, "missing_import", { file = GB_FILES.pokemon }
    end
    buildGB(data, raw)
  end
  canonicalizeLearnsets(data)
  data.ready = next(data.species) ~= nil and next(data.moves) ~= nil
  if not data.ready then return nil, "missing_import" end
  return data
end

function Datasets.get(version)
  if cached[version] ~= nil then return cached[version] or nil, cached[version] == false and "missing_import" or nil end
  local reader = readerOverride or defaultReader
  local data = Datasets.build(version, readTables(version, reader))
  cached[version] = data or false
  if not data then return nil, "missing_import" end
  return data
end

function Datasets.put(version, data)
  cached[version] = data
end

function Datasets.chain(data, national)
  local out, seen = {}, {}
  local n = tonumber(national)
  while n and data.species[n] and not seen[n] do
    seen[n] = true
    out[#out + 1] = n
    n = data.species[n].evolvesFrom
  end
  return out
end

function Datasets.learnSources(data, national, level)
  level = tonumber(level) or 100
  local out = {}
  local function add(move, source)
    if move and move <= data.moveMax then
      out[move] = out[move] or {}
      out[move][source] = true
    end
  end
  for depth, n in ipairs(Datasets.chain(data, national)) do
    local sp = data.species[n]
    local tag = depth == 1 and "" or "_prevo"
    for _, row in ipairs(sp.levelMoves) do
      if row.level <= level then add(row.move, "level" .. tag) end
    end
    for move in pairs(sp.tmhm) do add(move, "tmhm" .. tag) end
    for move in pairs(sp.tutor) do add(move, "tutor" .. tag) end
    for move in pairs(sp.egg) do add(move, "egg" .. tag) end
  end
  return out
end

function Datasets.learnable(data, national, move, level)
  local sources = Datasets.learnSources(data, national, level)[tonumber(move) or -1]
  return sources ~= nil, sources
end

function Datasets.expAt(data, national, level)
  local sp = data.species[tonumber(national) or -1]
  return sp and sp.exp[math.max(1, math.min(100, math.floor(tonumber(level) or 1)))] or nil
end

function Datasets.levelForExp(data, national, exp)
  local sp = data.species[tonumber(national) or -1]
  if not sp then return nil end
  local level = 1
  while level < 100 and (sp.exp[level + 1] or math.huge) <= (tonumber(exp) or 0) do level = level + 1 end
  return level
end

return Datasets
