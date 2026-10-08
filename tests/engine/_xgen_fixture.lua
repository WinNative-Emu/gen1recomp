local Datasets = require("src.online.xgen.Datasets")

local F = {}

local function gbMove(index, id, name, typeName, power, pp, accuracy)
  return { index = index, id = id, name = name, type = typeName, power = power, pp = pp, accuracy = accuracy or 100 }
end

local GB_MOVES = {
  TACKLE = gbMove(33, "TACKLE", "TACKLE", "NORMAL", 35, 35, 95),
  GROWL = gbMove(45, "GROWL", "GROWL", "NORMAL", 0, 40),
  VINE_WHIP = gbMove(22, "VINE_WHIP", "VINE WHIP", "GRASS", 35, 10),
  RAZOR_LEAF = gbMove(75, "RAZOR_LEAF", "RAZOR LEAF", "GRASS", 55, 25, 95),
  THUNDERSHOCK = gbMove(84, "THUNDERSHOCK", "THUNDERSHOCK", "ELECTRIC", 40, 30),
  THUNDERBOLT = gbMove(85, "THUNDERBOLT", "THUNDERBOLT", "ELECTRIC", 95, 15),
  BODY_SLAM = gbMove(34, "BODY_SLAM", "BODY SLAM", "NORMAL", 85, 15),
  PSYCHIC_M = gbMove(94, "PSYCHIC_M", "PSYCHIC", "PSYCHIC_TYPE", 90, 10),
  SURF = gbMove(57, "SURF", "SURF", "WATER", 95, 15),
  TOXIC = gbMove(92, "TOXIC", "TOXIC", "POISON", 0, 10, 85),
  QUICK_ATTACK = gbMove(98, "QUICK_ATTACK", "QUICK ATTACK", "NORMAL", 40, 30),
}

local GEN2_MOVES = {
  GIGA_DRAIN = gbMove(202, "GIGA_DRAIN", "GIGA DRAIN", "GRASS", 60, 5),
  SWEET_SCENT = gbMove(230, "SWEET_SCENT", "SWEET SCENT", "NORMAL", 0, 20),
  CRUNCH = gbMove(242, "CRUNCH", "CRUNCH", "DARK", 80, 15),
}

local function merge(...)
  local out = {}
  for _, t in ipairs({ ... }) do for k, v in pairs(t) do out[k] = v end end
  return out
end

local function gen1Pokemon()
  return {
    BULBASAUR = { id = "BULBASAUR", name = "BULBASAUR", dex = 1, types = { "GRASS", "POISON" },
      baseStats = { hp = 45, attack = 49, defense = 49, speed = 45, special = 65 }, catchRate = 45,
      growthRate = "MEDIUM_SLOW", level1Moves = { "TACKLE", "GROWL" },
      learnset = { { level = 7, move = "VINE_WHIP" } }, tmhm = { "BODY_SLAM", "TOXIC" },
      evolutions = { { level = 16, method = "LEVEL", species = "IVYSAUR" } } },
    IVYSAUR = { id = "IVYSAUR", name = "IVYSAUR", dex = 2, types = { "GRASS", "POISON" },
      baseStats = { hp = 60, attack = 62, defense = 63, speed = 60, special = 80 }, catchRate = 45,
      growthRate = "MEDIUM_SLOW", level1Moves = { "TACKLE", "GROWL" },
      learnset = { { level = 22, move = "RAZOR_LEAF" } }, tmhm = { "BODY_SLAM", "TOXIC" }, evolutions = {} },
    PIKACHU = { id = "PIKACHU", name = "PIKACHU", dex = 25, types = { "ELECTRIC", "ELECTRIC" },
      baseStats = { hp = 35, attack = 55, defense = 30, speed = 90, special = 50 }, catchRate = 190,
      growthRate = "MEDIUM_FAST", level1Moves = { "THUNDERSHOCK", "GROWL" }, learnset = {},
      tmhm = { "THUNDERBOLT", "BODY_SLAM", "TOXIC" }, evolutions = {} },
    MEWTWO = { id = "MEWTWO", name = "MEWTWO", dex = 150, types = { "PSYCHIC_TYPE", "PSYCHIC_TYPE" },
      baseStats = { hp = 106, attack = 110, defense = 90, speed = 130, special = 154 }, catchRate = 3,
      growthRate = "SLOW", level1Moves = { "PSYCHIC_M" }, learnset = {}, tmhm = { "SURF", "BODY_SLAM" },
      evolutions = {} },
  }
end

local GROWTH = {
  GROWTH_MEDIUM_SLOW = { numerator = 6, denominator = 5, squared = -15, linear = 100, constant = 140 },
  GROWTH_MEDIUM_FAST = { numerator = 1, denominator = 1, squared = 0, linear = 0, constant = 0 },
  GROWTH_SLOW = { numerator = 5, denominator = 4, squared = 0, linear = 0, constant = 0 },
}

local function gen2Pokemon(layout)
  local function bs(hp, a, d, s, sa, sd) return { hp = hp, attack = a, defense = d, speed = s, specialAttack = sa, specialDefense = sd } end
  local rows = {
    BULBASAUR = { dex = 1, types = { "GRASS", "POISON" }, baseStats = bs(45, 49, 49, 45, 65, 65), genderRatio = 31,
      growthRate = "GROWTH_MEDIUM_SLOW", catchRate = 45,
      level = { { level = 1, move = "TACKLE" }, { level = 4, move = "GROWL" }, { level = 7, move = "VINE_WHIP" } },
      tmhm = { "TOXIC", "GIGA_DRAIN" }, egg = { "RAZOR_LEAF" }, evo = { { into = "IVYSAUR", level = 16, method = "EVOLVE_LEVEL" } } },
    IVYSAUR = { dex = 2, types = { "GRASS", "POISON" }, baseStats = bs(60, 62, 63, 60, 80, 80), genderRatio = 31,
      growthRate = "GROWTH_MEDIUM_SLOW", catchRate = 45,
      level = { { level = 1, move = "TACKLE" }, { level = 20, move = "SWEET_SCENT" } }, tmhm = { "TOXIC", "GIGA_DRAIN" }, egg = {}, evo = {} },
    PIKACHU = { dex = 25, types = { "ELECTRIC", "ELECTRIC" }, baseStats = bs(35, 55, 30, 90, 50, 40), genderRatio = 127,
      growthRate = "GROWTH_MEDIUM_FAST", catchRate = 190,
      level = { { level = 1, move = "THUNDERSHOCK" }, { level = 1, move = "GROWL" } }, tmhm = { "THUNDERBOLT", "TOXIC" }, egg = {}, evo = {} },
    CHIKORITA = { dex = 152, types = { "GRASS", "GRASS" }, baseStats = bs(45, 49, 65, 45, 49, 65), genderRatio = 31,
      growthRate = "GROWTH_MEDIUM_SLOW", catchRate = 45,
      level = { { level = 1, move = "TACKLE" }, { level = 1, move = "GROWL" }, { level = 8, move = "RAZOR_LEAF" } },
      tmhm = { "TOXIC", "GIGA_DRAIN" }, egg = {}, evo = {} },
    UMBREON = { dex = 197, types = { "DARK", "DARK" }, baseStats = bs(95, 65, 110, 65, 60, 130), genderRatio = 31,
      growthRate = "GROWTH_MEDIUM_FAST", catchRate = 45,
      level = { { level = 1, move = "TACKLE" }, { level = 30, move = "CRUNCH" } }, tmhm = { "TOXIC" }, egg = {}, evo = {} },
    UNOWN = { dex = 201, types = { "PSYCHIC_TYPE", "PSYCHIC_TYPE" }, baseStats = bs(48, 72, 48, 48, 72, 48), genderRatio = 255,
      growthRate = "GROWTH_MEDIUM_FAST", catchRate = 225, level = { { level = 1, move = "TACKLE" } }, tmhm = {}, egg = {}, evo = {} },
  }
  local out = { growthRates = GROWTH }
  for id, r in pairs(rows) do
    local def = { id = id, name = id, dex = r.dex, types = r.types, baseStats = r.baseStats, genderRatio = r.genderRatio,
      growthRate = r.growthRate, catchRate = r.catchRate, tmhm = r.tmhm, evolutions = r.evo }
    if layout == "learnset" then
      def.level1Moves, def.learnset = {}, {}
      for _, row in ipairs(r.level) do
        if row.level == 1 then def.level1Moves[#def.level1Moves + 1] = row.move else def.learnset[#def.learnset + 1] = row end
      end
      def.eggMoves = r.egg
    else
      def.levelMoves, def.eggMoves = r.level, r.egg
    end
    out[id] = def
  end
  return out
end

local function gen2Items()
  return {
    LEFTOVERS = { id = "LEFTOVERS", name = "LEFTOVERS", index = 146 },
    FLOWER_MAIL = { id = "FLOWER_MAIL", name = "FLOWER MAIL", index = 158 },
    PINK_BOW = { id = "PINK_BOW", name = "PINK BOW", index = 104 },
    POTION = { id = "POTION", name = "POTION", index = 18 },
    LIGHT_BALL = { id = "LIGHT_BALL", name = "LIGHT BALL", index = 163 },
    MINT_BERRY = { id = "MINT_BERRY", name = "MINT BERRY", index = 190 },
  }
end

local GEN3_TYPE = { NORMAL = 0, FIGHTING = 1, FLYING = 2, POISON = 3, GROUND = 4, ROCK = 5, BUG = 6, GHOST = 7,
  STEEL = 8, FIRE = 10, WATER = 11, GRASS = 12, ELECTRIC = 13, PSYCHIC = 14, ICE = 15, DRAGON = 16, DARK = 17 }

local function gen3Tables()
  local moveNames, battle = { [0] = "-" }, {}
  local function mv(id, name, t, power, pp, acc, priority)
    moveNames[id] = name
    battle[id] = { type = GEN3_TYPE[t], power = power, pp = pp, accuracy = acc or 100, priority = priority or 0, effect = 0 }
  end
  mv(33, "TACKLE", "NORMAL", 35, 35, 95)
  mv(45, "GROWL", "NORMAL", 0, 40)
  mv(22, "VINE WHIP", "GRASS", 35, 10)
  mv(75, "RAZOR LEAF", "GRASS", 55, 25, 95)
  mv(84, "THUNDERSHOCK", "ELECTRIC", 40, 30)
  mv(85, "THUNDERBOLT", "ELECTRIC", 95, 15)
  mv(34, "BODY SLAM", "NORMAL", 85, 15)
  mv(94, "PSYCHIC", "PSYCHIC", 90, 10)
  mv(57, "SURF", "WATER", 95, 15)
  mv(92, "TOXIC", "POISON", 0, 10, 85)
  mv(202, "GIGA DRAIN", "GRASS", 60, 5)
  mv(230, "SWEET SCENT", "NORMAL", 0, 20)
  mv(242, "CRUNCH", "DARK", 80, 15)
  mv(345, "MAGICAL LEAF", "GRASS", 60, 20)
  mv(98, "QUICK ATTACK", "NORMAL", 40, 30, 100, 1)
  local species = {
    [1] = { nat = 1, name = "BULBASAUR", types = { 12, 3 }, stats = { hp = 45, atk = 49, def = 49, spe = 45, spa = 65, spd = 65 },
      ratio = 31, growth = 3, friendship = 70, abilities = { 65, 0 }, learn = { { 1, 33 }, { 4, 45 }, { 7, 22 } },
      egg = { 75 }, evo = { { method = 4, param = 16, target = 2 } } },
    [2] = { nat = 2, name = "IVYSAUR", types = { 12, 3 }, stats = { hp = 60, atk = 62, def = 63, spe = 60, spa = 80, spd = 80 },
      ratio = 31, growth = 3, friendship = 70, abilities = { 65, 0 }, learn = { { 1, 33 }, { 20, 230 } }, egg = {}, evo = {} },
    [25] = { nat = 25, name = "PIKACHU", types = { 13, 13 }, stats = { hp = 35, atk = 55, def = 30, spe = 90, spa = 50, spd = 40 },
      ratio = 127, growth = 0, friendship = 70, abilities = { 9, 0 }, learn = { { 1, 84 }, { 1, 45 }, { 11, 98 } }, egg = {}, evo = {} },
    [150] = { nat = 150, name = "MEWTWO", types = { 14, 14 }, stats = { hp = 106, atk = 110, def = 90, spe = 130, spa = 154, spd = 90 },
      ratio = 255, growth = 5, friendship = 0, abilities = { 46, 0 }, learn = { { 1, 94 } }, egg = {}, evo = {} },
    [152] = { nat = 152, name = "CHIKORITA", types = { 12, 12 }, stats = { hp = 45, atk = 49, def = 65, spe = 45, spa = 49, spd = 65 },
      ratio = 31, growth = 3, friendship = 70, abilities = { 65, 0 }, learn = { { 1, 33 }, { 1, 45 }, { 8, 75 } }, egg = {}, evo = {} },
    [197] = { nat = 197, name = "UMBREON", types = { 17, 17 }, stats = { hp = 95, atk = 65, def = 110, spe = 65, spa = 60, spd = 130 },
      ratio = 31, growth = 0, friendship = 35, abilities = { 28, 0 }, learn = { { 1, 33 }, { 30, 242 } }, egg = {}, evo = {} },
    [201] = { nat = 201, name = "UNOWN", types = { 14, 14 }, stats = { hp = 48, atk = 72, def = 48, spe = 48, spa = 72, spd = 48 },
      ratio = 255, growth = 0, friendship = 70, abilities = { 26, 0 }, learn = { { 1, 33 } }, egg = {}, evo = {} },
    [277] = { nat = 252, name = "TREECKO", types = { 12, 12 }, stats = { hp = 40, atk = 45, def = 35, spe = 70, spa = 65, spd = 55 },
      ratio = 31, growth = 3, friendship = 70, abilities = { 65, 0 }, learn = { { 1, 33 }, { 1, 345 } }, egg = {}, evo = {} },
  }
  local t = { names = { [0] = "??????????" }, national = { toNational = {}, toSpecies = {} }, types = {}, stats = {},
    meta = {}, abilities = {}, learnsets = {}, eggMoves = {}, evolutions = {},
    battleMoves = { moves = battle }, moveNames = moveNames,
    tmhm = { machines = { [5] = 92, [23] = 85, [21] = 202 }, learnsets = {} },
    tutor = { moves = { [0] = 34, [1] = 57 }, learnsets = {} },
    typeNames = { [0] = "NORMAL", [12] = "GRASS", [13] = "ELECTR", [14] = "PSYCHC", [17] = "DARK", [9] = "???" },
    items = { items = {
      [13] = { name = "POTION" }, [200] = { name = "LEFTOVERS" }, [121] = { name = "ORANGE MAIL", fieldUseName = "ItemUseOutOfBattle_Mail" },
      [202] = { name = "LIGHT BALL" }, [44] = { name = "BERRY JUICE" },
    } },
  }
  for internal, s in pairs(species) do
    t.names[internal] = s.name
    t.national.toNational[internal], t.national.toSpecies[s.nat] = s.nat, internal
    t.types[internal], t.stats[internal] = s.types, s.stats
    t.meta[internal] = { genderRatio = s.ratio, growthRate = s.growth, friendship = s.friendship, catchRate = 45 }
    t.abilities[internal], t.learnsets[internal] = s.abilities, s.learn
    t.eggMoves[internal], t.evolutions[internal] = s.egg, s.evo
    t.tmhm.learnsets[internal] = { lo = 2 ^ 5 + 2 ^ 21 + (s.nat == 25 and 2 ^ 23 or 0), hi = 0 }
    t.tutor.learnsets[internal] = 1
  end
  return t
end

function F.raw(version)
  if version == "red" then return { pokemon = gen1Pokemon(), moves = merge(GB_MOVES), items = {} } end
  if version == "gold" then return { pokemon = gen2Pokemon("levelMoves"), moves = merge(GB_MOVES, GEN2_MOVES), items = gen2Items() } end
  if version == "silver" then return { pokemon = gen2Pokemon("learnset"), moves = merge(GB_MOVES, GEN2_MOVES), items = gen2Items() } end
  if version == "emerald" then return gen3Tables() end
  error("no fixture for " .. tostring(version))
end

function F.data(version)
  return assert(Datasets.build(version, F.raw(version)))
end

function F.deepEqual(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for k, v in pairs(a) do if not F.deepEqual(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

function F.copy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = F.copy(x) end
  return out
end

function F.shares(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then return false end
  local seen = {}
  local function walk(t, mark)
    if type(t) ~= "table" or seen[t] == mark then return end
    seen[t] = seen[t] and "both" or mark
    for _, v in pairs(t) do walk(v, mark) end
  end
  walk(a, "a")
  local hit = false
  local visited = {}
  local function walkB(t)
    if type(t) ~= "table" or visited[t] then return end
    visited[t] = true
    if seen[t] then hit = true end
    for _, v in pairs(t) do walkB(v) end
  end
  walkB(b)
  return hit
end

local function readable(path)
  local f = io.open(path, "rb")
  if f then f:close() return true end
  return false
end

function F.cacheRoot(version)
  local home = os.getenv("HOME")
  if not home or home == "" then return nil end
  local prefix = require("src.core.GameVersion").cachePrefix(version)
  local probe = require("src.core.GameVersion").generation(version) == 3 and "data/generated/gba/pokemon/names.lua"
    or "data/generated/pokemon.lua"
  local ids = {}
  local env = os.getenv("POKEPORT_IDENTITY")
  if env and env ~= "" then ids[#ids + 1] = env end
  ids[#ids + 1] = "g1r-" .. version
  ids[#ids + 1] = "pokeport-test-caches"
  for _, base in ipairs({ home .. "/Library/Application Support/LOVE", home .. "/.local/share/love" }) do
    for _, id in ipairs(ids) do
      local root = base .. "/" .. id
      if readable(root .. "/" .. prefix .. probe) then return root end
    end
  end
  return nil
end

local readerInstalled = false
function F.real(version)
  if not readerInstalled then
    readerInstalled = true
    local roots = {}
    Datasets.setReader(function(v, rel)
      if roots[v] == nil then roots[v] = F.cacheRoot(v) or false end
      if not roots[v] then return nil end
      return Datasets.directoryReader(roots[v])(v, rel)
    end)
  end
  if not F.cacheRoot(version) then return nil end
  return (Datasets.get(version))
end

function F.allReal()
  local out, list = {}, {}
  for _, version in ipairs(require("src.core.GameVersion").ORDER) do
    local d = F.real(version)
    if d then out[version] = d; list[#list + 1] = version end
  end
  return out, list
end

return F
