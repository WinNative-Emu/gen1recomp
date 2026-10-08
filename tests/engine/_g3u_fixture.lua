local F = {}

local GEN1_MOVES = {
  { 1, "NO_ADDITIONAL_EFFECT", "NORMAL", 40, 100, 35 },
  { 2, "NO_ADDITIONAL_EFFECT", "FIGHTING", 50, 100, 25 },
  { 3, "TWO_TO_FIVE_ATTACKS_EFFECT", "NORMAL", 15, 85, 10 },
  { 4, "FREEZE_SIDE_EFFECT2", "ICE", 70, 90, 10 },
  { 5, "ATTACK_DOWN2_EFFECT", "NORMAL", 0, 100, 20 },
  { 6, "PAY_DAY_EFFECT", "NORMAL", 40, 100, 20 },
  { 7, "BURN_SIDE_EFFECT1", "FIRE", 75, 100, 15 },
  { 8, "FREEZE_SIDE_EFFECT1", "ICE", 75, 100, 15 },
  { 9, "SPEED_DOWN2_EFFECT", "BUG", 0, 85, 20 },
  { 10, "SPECIAL_DOWN2_EFFECT", "NORMAL", 0, 100, 20 },
  { 13, "CHARGE_EFFECT", "NORMAL", 80, 75, 10 },
  { 14, "ATTACK_UP2_EFFECT", "NORMAL", 0, 100, 30 },
  { 18, "SWITCH_AND_TELEPORT_EFFECT", "NORMAL", 0, 85, 20 },
  { 19, "FLY_EFFECT", "FLYING", 70, 95, 15 },
  { 20, "TRAPPING_EFFECT", "NORMAL", 15, 75, 20 },
  { 23, "FLINCH_SIDE_EFFECT2", "NORMAL", 65, 100, 20 },
  { 24, "ATTACK_TWICE_EFFECT", "FIGHTING", 30, 100, 30 },
  { 26, "JUMP_KICK_EFFECT", "FIGHTING", 70, 95, 25 },
  { 28, "ACCURACY_DOWN1_EFFECT", "NORMAL", 0, 100, 15 },
  { 32, "OHKO_EFFECT", "NORMAL", 1, 30, 5 },
  { 33, "NO_ADDITIONAL_EFFECT", "NORMAL", 35, 95, 35 },
  { 34, "PARALYZE_SIDE_EFFECT2", "NORMAL", 85, 100, 15 },
  { 36, "RECOIL_EFFECT", "NORMAL", 90, 85, 20 },
  { 37, "THRASH_PETAL_DANCE_EFFECT", "NORMAL", 90, 100, 20 },
  { 39, "DEFENSE_DOWN1_EFFECT", "NORMAL", 0, 100, 30 },
  { 40, "POISON_SIDE_EFFECT1", "POISON", 15, 100, 35 },
  { 41, "TWINEEDLE_EFFECT", "BUG", 25, 100, 20 },
  { 44, "FLINCH_SIDE_EFFECT1", "NORMAL", 60, 100, 25 },
  { 45, "ATTACK_DOWN1_EFFECT", "NORMAL", 0, 100, 40 },
  { 48, "CONFUSION_EFFECT", "NORMAL", 0, 55, 20 },
  { 49, "SPECIAL_DAMAGE_EFFECT", "NORMAL", 1, 90, 20 },
  { 50, "DISABLE_EFFECT", "NORMAL", 0, 55, 20 },
  { 51, "DEFENSE_DOWN_SIDE_EFFECT", "POISON", 40, 100, 30 },
  { 53, "BURN_SIDE_EFFECT1", "FIRE", 95, 100, 15 },
  { 54, "MIST_EFFECT", "ICE", 0, 100, 30 },
  { 55, "NO_ADDITIONAL_EFFECT", "WATER", 40, 100, 25 },
  { 58, "FREEZE_SIDE_EFFECT1", "ICE", 95, 100, 10 },
  { 60, "CONFUSION_SIDE_EFFECT", "PSYCHIC_TYPE", 65, 100, 20 },
  { 61, "SPEED_DOWN_SIDE_EFFECT", "WATER", 65, 100, 20 },
  { 62, "ATTACK_DOWN_SIDE_EFFECT", "ICE", 65, 100, 20 },
  { 63, "HYPER_BEAM_EFFECT", "NORMAL", 150, 90, 5 },
  { 68, "NO_ADDITIONAL_EFFECT", "FIGHTING", 1, 100, 20 },
  { 69, "SPECIAL_DAMAGE_EFFECT", "FIGHTING", 1, 100, 20 },
  { 71, "DRAIN_HP_EFFECT", "GRASS", 20, 100, 20 },
  { 73, "LEECH_SEED_EFFECT", "GRASS", 0, 90, 10 },
  { 74, "SPECIAL_UP1_EFFECT", "NORMAL", 0, 100, 40 },
  { 76, "CHARGE_EFFECT", "GRASS", 120, 100, 10 },
  { 77, "POISON_EFFECT", "POISON", 0, 75, 35 },
  { 78, "PARALYZE_EFFECT", "GRASS", 0, 75, 30 },
  { 79, "SLEEP_EFFECT", "GRASS", 0, 75, 15 },
  { 81, "SPEED_DOWN1_EFFECT", "BUG", 0, 95, 40 },
  { 82, "SPECIAL_DAMAGE_EFFECT", "DRAGON", 1, 100, 10 },
  { 84, "PARALYZE_SIDE_EFFECT1", "ELECTRIC", 40, 100, 30 },
  { 85, "PARALYZE_SIDE_EFFECT1", "ELECTRIC", 95, 100, 15 },
  { 86, "PARALYZE_EFFECT", "ELECTRIC", 0, 100, 20 },
  { 89, "NO_ADDITIONAL_EFFECT", "GROUND", 100, 100, 10 },
  { 91, "CHARGE_EFFECT", "GROUND", 100, 100, 10 },
  { 92, "POISON_EFFECT", "POISON", 0, 85, 10 },
  { 93, "CONFUSION_SIDE_EFFECT", "PSYCHIC_TYPE", 50, 100, 25 },
  { 94, "SPECIAL_DOWN_SIDE_EFFECT", "PSYCHIC_TYPE", 90, 100, 10 },
  { 97, "SPEED_UP2_EFFECT", "PSYCHIC_TYPE", 0, 100, 30 },
  { 98, "NO_ADDITIONAL_EFFECT", "NORMAL", 40, 100, 30 },
  { 99, "RAGE_EFFECT", "NORMAL", 20, 100, 20 },
  { 100, "SWITCH_AND_TELEPORT_EFFECT", "PSYCHIC_TYPE", 0, 100, 20 },
  { 101, "SPECIAL_DAMAGE_EFFECT", "GHOST", 0, 100, 15 },
  { 102, "MIMIC_EFFECT", "NORMAL", 0, 100, 10 },
  { 103, "DEFENSE_DOWN2_EFFECT", "NORMAL", 0, 85, 40 },
  { 104, "EVASION_UP1_EFFECT", "NORMAL", 0, 100, 15 },
  { 105, "HEAL_EFFECT", "NORMAL", 0, 100, 20 },
  { 106, "DEFENSE_UP1_EFFECT", "NORMAL", 0, 100, 30 },
  { 112, "DEFENSE_UP2_EFFECT", "PSYCHIC_TYPE", 0, 100, 30 },
  { 113, "LIGHT_SCREEN_EFFECT", "PSYCHIC_TYPE", 0, 100, 30 },
  { 114, "HAZE_EFFECT", "ICE", 0, 100, 30 },
  { 115, "REFLECT_EFFECT", "PSYCHIC_TYPE", 0, 100, 20 },
  { 116, "FOCUS_ENERGY_EFFECT", "NORMAL", 0, 100, 30 },
  { 117, "BIDE_EFFECT", "NORMAL", 0, 100, 10 },
  { 118, "METRONOME_EFFECT", "NORMAL", 0, 100, 10 },
  { 119, "MIRROR_MOVE_EFFECT", "FLYING", 0, 100, 20 },
  { 120, "EXPLODE_EFFECT", "NORMAL", 130, 100, 5 },
  { 123, "POISON_SIDE_EFFECT2", "POISON", 20, 70, 20 },
  { 126, "BURN_SIDE_EFFECT2", "FIRE", 120, 85, 5 },
  { 129, "SWIFT_EFFECT", "NORMAL", 60, 100, 20 },
  { 133, "SPECIAL_UP2_EFFECT", "PSYCHIC_TYPE", 0, 100, 20 },
  { 138, "DREAM_EATER_EFFECT", "PSYCHIC_TYPE", 100, 100, 15 },
  { 143, "CHARGE_EFFECT", "FLYING", 140, 90, 5 },
  { 144, "TRANSFORM_EFFECT", "NORMAL", 0, 100, 10 },
  { 150, "SPLASH_EFFECT", "NORMAL", 0, 100, 40 },
  { 156, "HEAL_EFFECT", "PSYCHIC_TYPE", 0, 100, 10 },
  { 160, "CONVERSION_EFFECT", "NORMAL", 0, 100, 30 },
  { 162, "SUPER_FANG_EFFECT", "NORMAL", 1, 90, 10 },
  { 163, "NO_ADDITIONAL_EFFECT", "NORMAL", 70, 100, 20 },
  { 164, "SUBSTITUTE_EFFECT", "NORMAL", 0, 100, 10 },
  { 165, "RECOIL_EFFECT", "NORMAL", 50, 100, 10 },
}

local GEN1_SPECIES = {
  [6] = { "FIRE", "FLYING" }, [25] = { "ELECTRIC" }, [81] = { "ELECTRIC" }, [94] = { "GHOST", "POISON" },
  [95] = { "ROCK", "GROUND" }, [143] = { "NORMAL" }, [150] = { "PSYCHIC" },
}

local GEN2_MOVES = {
  { 1, "EFFECT_NORMAL_HIT", "NORMAL", 40, 0 }, { 2, "EFFECT_NORMAL_HIT", "FIGHTING", 50, 0 },
  { 3, "EFFECT_MULTI_HIT", "NORMAL", 15, 0 }, { 6, "EFFECT_PAY_DAY", "NORMAL", 40, 0 },
  { 7, "EFFECT_BURN_HIT", "FIRE", 75, 10 }, { 8, "EFFECT_FREEZE_HIT", "ICE", 75, 10 },
  { 13, "EFFECT_RAZOR_WIND", "NORMAL", 80, 0 }, { 14, "EFFECT_ATTACK_UP_2", "NORMAL", 0, 0 },
  { 16, "EFFECT_GUST", "FLYING", 40, 0 }, { 18, "EFFECT_FORCE_SWITCH", "NORMAL", 0, 0 },
  { 19, "EFFECT_FLY", "FLYING", 70, 0 }, { 20, "EFFECT_TRAP_TARGET", "NORMAL", 15, 0 },
  { 23, "EFFECT_STOMP", "NORMAL", 65, 30 }, { 24, "EFFECT_DOUBLE_HIT", "FIGHTING", 30, 0 },
  { 26, "EFFECT_JUMP_KICK", "FIGHTING", 70, 0 }, { 28, "EFFECT_ACCURACY_DOWN", "GROUND", 0, 0 },
  { 32, "EFFECT_OHKO", "NORMAL", 1, 0 }, { 34, "EFFECT_PARALYZE_HIT", "NORMAL", 85, 30 },
  { 36, "EFFECT_RECOIL_HIT", "NORMAL", 90, 0 }, { 37, "EFFECT_RAMPAGE", "NORMAL", 90, 0 },
  { 39, "EFFECT_DEFENSE_DOWN", "NORMAL", 0, 0 }, { 40, "EFFECT_POISON_HIT", "POISON", 15, 30 },
  { 41, "EFFECT_POISON_MULTI_HIT", "BUG", 25, 20 }, { 44, "EFFECT_FLINCH_HIT", "DARK", 60, 30 },
  { 45, "EFFECT_ATTACK_DOWN", "NORMAL", 0, 0 }, { 48, "EFFECT_CONFUSE", "NORMAL", 0, 0 },
  { 49, "EFFECT_STATIC_DAMAGE", "NORMAL", 20, 0 }, { 50, "EFFECT_DISABLE", "NORMAL", 0, 0 },
  { 51, "EFFECT_DEFENSE_DOWN_HIT", "POISON", 40, 10 }, { 54, "EFFECT_MIST", "ICE", 0, 0 },
  { 60, "EFFECT_CONFUSE_HIT", "PSYCHIC_TYPE", 65, 10 }, { 61, "EFFECT_SPEED_DOWN_HIT", "WATER", 65, 10 },
  { 62, "EFFECT_ATTACK_DOWN_HIT", "ICE", 65, 10 }, { 63, "EFFECT_HYPER_BEAM", "NORMAL", 150, 0 },
  { 68, "EFFECT_COUNTER", "FIGHTING", 1, 0 }, { 69, "EFFECT_LEVEL_DAMAGE", "FIGHTING", 1, 0 },
  { 71, "EFFECT_LEECH_HIT", "GRASS", 20, 0 }, { 73, "EFFECT_LEECH_SEED", "GRASS", 0, 0 },
  { 74, "EFFECT_SP_ATK_UP", "NORMAL", 0, 0 }, { 76, "EFFECT_SOLARBEAM", "GRASS", 120, 0 },
  { 77, "EFFECT_POISON", "POISON", 0, 0 }, { 78, "EFFECT_PARALYZE", "GRASS", 0, 0 },
  { 79, "EFFECT_SLEEP", "GRASS", 0, 0 }, { 81, "EFFECT_SPEED_DOWN", "BUG", 0, 0 },
  { 82, "EFFECT_STATIC_DAMAGE", "DRAGON", 40, 0 }, { 87, "EFFECT_THUNDER", "ELECTRIC", 120, 30 },
  { 89, "EFFECT_EARTHQUAKE", "GROUND", 100, 0 }, { 91, "EFFECT_FLY", "GROUND", 60, 0 },
  { 92, "EFFECT_TOXIC", "POISON", 0, 0 }, { 94, "EFFECT_SP_DEF_DOWN_HIT", "PSYCHIC_TYPE", 90, 10 },
  { 97, "EFFECT_SPEED_UP_2", "PSYCHIC_TYPE", 0, 0 }, { 98, "EFFECT_PRIORITY_HIT", "NORMAL", 40, 0 },
  { 99, "EFFECT_RAGE", "NORMAL", 20, 0 }, { 100, "EFFECT_TELEPORT", "PSYCHIC_TYPE", 0, 0 },
  { 102, "EFFECT_MIMIC", "NORMAL", 0, 0 }, { 103, "EFFECT_DEFENSE_DOWN_2", "NORMAL", 0, 0 },
  { 104, "EFFECT_EVASION_UP", "NORMAL", 0, 0 }, { 105, "EFFECT_HEAL", "NORMAL", 0, 0 },
  { 106, "EFFECT_DEFENSE_UP", "NORMAL", 0, 0 }, { 107, "EFFECT_EVASION_UP", "NORMAL", 0, 0 },
  { 111, "EFFECT_DEFENSE_CURL", "NORMAL", 0, 0 }, { 112, "EFFECT_DEFENSE_UP_2", "PSYCHIC_TYPE", 0, 0 },
  { 113, "EFFECT_LIGHT_SCREEN", "PSYCHIC_TYPE", 0, 0 }, { 114, "EFFECT_RESET_STATS", "ICE", 0, 0 },
  { 115, "EFFECT_REFLECT", "PSYCHIC_TYPE", 0, 0 }, { 116, "EFFECT_FOCUS_ENERGY", "NORMAL", 0, 0 },
  { 117, "EFFECT_BIDE", "NORMAL", 0, 0 }, { 118, "EFFECT_METRONOME", "NORMAL", 0, 0 },
  { 119, "EFFECT_MIRROR_MOVE", "FLYING", 0, 0 }, { 120, "EFFECT_SELFDESTRUCT", "NORMAL", 200, 0 },
  { 129, "EFFECT_ALWAYS_HIT", "NORMAL", 60, 0 }, { 130, "EFFECT_SKULL_BASH", "NORMAL", 100, 0 },
  { 133, "EFFECT_SP_DEF_UP_2", "PSYCHIC_TYPE", 0, 0 }, { 138, "EFFECT_DREAM_EATER", "PSYCHIC_TYPE", 100, 0 },
  { 143, "EFFECT_SKY_ATTACK", "FLYING", 140, 0 }, { 144, "EFFECT_TRANSFORM", "NORMAL", 0, 0 },
  { 150, "EFFECT_SPLASH", "NORMAL", 0, 0 }, { 156, "EFFECT_HEAL", "PSYCHIC_TYPE", 0, 0 },
  { 160, "EFFECT_CONVERSION", "NORMAL", 0, 0 }, { 161, "EFFECT_TRI_ATTACK", "NORMAL", 80, 20 },
  { 162, "EFFECT_SUPER_FANG", "NORMAL", 1, 0 }, { 164, "EFFECT_SUBSTITUTE", "NORMAL", 0, 0 },
  { 165, "EFFECT_RECOIL_HIT", "NORMAL", 50, 0 }, { 166, "EFFECT_SKETCH", "NORMAL", 0, 0 },
  { 167, "EFFECT_TRIPLE_KICK", "FIGHTING", 10, 0 }, { 168, "EFFECT_THIEF", "DARK", 40, 100 },
  { 169, "EFFECT_MEAN_LOOK", "BUG", 0, 0 }, { 170, "EFFECT_LOCK_ON", "NORMAL", 0, 0 },
  { 171, "EFFECT_NIGHTMARE", "GHOST", 0, 0 }, { 172, "EFFECT_FLAME_WHEEL", "FIRE", 60, 10 },
  { 173, "EFFECT_SNORE", "NORMAL", 40, 30 }, { 174, "EFFECT_CURSE", "CURSE_TYPE", 0, 0 },
  { 175, "EFFECT_REVERSAL", "NORMAL", 1, 0 }, { 176, "EFFECT_CONVERSION2", "NORMAL", 0, 0 },
  { 178, "EFFECT_SPEED_DOWN_2", "GRASS", 0, 0 }, { 180, "EFFECT_SPITE", "GHOST", 0, 0 },
  { 182, "EFFECT_PROTECT", "NORMAL", 0, 0 }, { 187, "EFFECT_BELLY_DRUM", "NORMAL", 0, 0 },
  { 189, "EFFECT_ACCURACY_DOWN_HIT", "GROUND", 20, 100 }, { 191, "EFFECT_SPIKES", "GROUND", 0, 0 },
  { 193, "EFFECT_FORESIGHT", "NORMAL", 0, 0 }, { 194, "EFFECT_DESTINY_BOND", "GHOST", 0, 0 },
  { 195, "EFFECT_PERISH_SONG", "NORMAL", 0, 0 }, { 201, "EFFECT_SANDSTORM", "ROCK", 0, 0 },
  { 203, "EFFECT_ENDURE", "NORMAL", 0, 0 }, { 204, "EFFECT_ATTACK_DOWN_2", "NORMAL", 0, 0 },
  { 205, "EFFECT_ROLLOUT", "ROCK", 30, 0 }, { 206, "EFFECT_FALSE_SWIPE", "NORMAL", 40, 0 },
  { 207, "EFFECT_SWAGGER", "NORMAL", 0, 100 }, { 210, "EFFECT_FURY_CUTTER", "BUG", 10, 0 },
  { 211, "EFFECT_DEFENSE_UP_HIT", "STEEL", 70, 10 }, { 213, "EFFECT_ATTRACT", "NORMAL", 0, 0 },
  { 214, "EFFECT_SLEEP_TALK", "NORMAL", 0, 0 }, { 215, "EFFECT_HEAL_BELL", "NORMAL", 0, 0 },
  { 216, "EFFECT_RETURN", "NORMAL", 1, 0 }, { 217, "EFFECT_PRESENT", "NORMAL", 1, 0 },
  { 218, "EFFECT_FRUSTRATION", "NORMAL", 1, 0 }, { 219, "EFFECT_SAFEGUARD", "NORMAL", 0, 0 },
  { 220, "EFFECT_PAIN_SPLIT", "NORMAL", 0, 0 }, { 221, "EFFECT_SACRED_FIRE", "FIRE", 100, 50 },
  { 222, "EFFECT_MAGNITUDE", "GROUND", 1, 0 }, { 226, "EFFECT_BATON_PASS", "NORMAL", 0, 0 },
  { 227, "EFFECT_ENCORE", "NORMAL", 0, 0 }, { 228, "EFFECT_PURSUIT", "DARK", 40, 0 },
  { 229, "EFFECT_RAPID_SPIN", "NORMAL", 20, 0 }, { 232, "EFFECT_ATTACK_UP_HIT", "STEEL", 50, 10 },
  { 233, "EFFECT_ALWAYS_HIT", "FIGHTING", 70, 0 }, { 234, "EFFECT_MORNING_SUN", "NORMAL", 0, 0 },
  { 235, "EFFECT_SYNTHESIS", "GRASS", 0, 0 }, { 236, "EFFECT_MOONLIGHT", "NORMAL", 0, 0 },
  { 237, "EFFECT_HIDDEN_POWER", "NORMAL", 1, 0 }, { 239, "EFFECT_TWISTER", "DRAGON", 40, 20 },
  { 240, "EFFECT_RAIN_DANCE", "WATER", 0, 0 }, { 241, "EFFECT_SUNNY_DAY", "FIRE", 0, 0 },
  { 243, "EFFECT_MIRROR_COAT", "PSYCHIC_TYPE", 1, 0 }, { 244, "EFFECT_PSYCH_UP", "NORMAL", 0, 0 },
  { 245, "EFFECT_PRIORITY_HIT", "NORMAL", 80, 0 }, { 246, "EFFECT_ALL_UP_HIT", "ROCK", 60, 10 },
  { 248, "EFFECT_FUTURE_SIGHT", "PSYCHIC_TYPE", 80, 0 }, { 251, "EFFECT_BEAT_UP", "DARK", 10, 0 },
  { 252, "EFFECT_NORMAL_HIT", "NORMAL", 40, 0 },
}

local function canonType(name)
  local s = name:gsub("_TYPE$", "")
  if s == "CURSE" then return "MYSTERY" end
  return s
end

local function species(gen, dexMax, special)
  local out = {}
  for n = 1, dexMax do
    local types = special[n] or { "NORMAL" }
    local t = {}
    for _, name in ipairs(types) do t[#t + 1] = canonType(name) end
    local spa = 60 + (n % 40)
    local spd = (gen == 1) and spa or (55 + (n % 30))
    out[n] = { national = n, types = t,
      base = { hp = 50 + (n % 50), atk = 40 + (n % 60), def = 45 + (n % 45), spe = 30 + (n % 70), spa = spa,
        spd = spd } }
  end
  return out
end

function F.gen1(extra)
  local moves = {}
  for id = 1, 165 do
    moves[id] = { id = id, type = "NORMAL", power = 40, accuracy = 100, pp = 20, effect = "NO_ADDITIONAL_EFFECT" }
  end
  for _, r in ipairs(GEN1_MOVES) do
    moves[r[1]] = { id = r[1], effect = r[2], type = canonType(r[3]), power = r[4], accuracy = r[5], pp = r[6] }
  end
  for id, row in pairs(extra or {}) do moves[id] = row end
  return { generation = 1, dexMax = 151, moveMax = 165, moves = moves, species = species(1, 151, GEN1_SPECIES) }
end

function F.gen2(extra)
  local moves = {}
  for id = 1, 251 do
    moves[id] = { id = id, type = "NORMAL", power = 40, accuracy = 100, pp = 20, effect = "EFFECT_NORMAL_HIT",
      effectChance = 0 }
  end
  for _, r in ipairs(GEN2_MOVES) do
    if r[1] <= 251 then
      moves[r[1]] = { id = r[1], effect = r[2], type = canonType(r[3]), power = r[4], accuracy = 100, pp = 15,
        effectChance = r[5] }
    end
  end
  for id, row in pairs(extra or {}) do moves[id] = row end
  local special = { [81] = { "ELECTRIC", "STEEL" }, [197] = { "DARK" }, [25] = { "ELECTRIC" } }
  return { generation = 2, dexMax = 251, moveMax = 251, moves = moves, species = species(2, 251, special) }
end

function F.real(version, identity)
  local home = os.getenv("POKEPORT_REAL_HOME") or os.getenv("HOME")
  if not home then return nil end
  local root = home .. "/Library/Application Support/LOVE/" .. identity
  local Datasets = require("src.online.xgen.Datasets")
  local probe = io.open(root .. "/" .. version .. "/data/generated/moves.lua", "rb")
  if not probe then return nil end
  probe:close()
  Datasets.setReader(Datasets.directoryReader(root))
  local data = Datasets.get(version)
  Datasets.setReader(nil)
  return data
end

local function lcg(seed)
  local r = seed % 2147483648
  return function(n)
    r = (r * 1103515245 + 12345) % 2147483648
    return math.floor(r / 65536) % n + 1
  end
end
F.lcg = lcg

function F.record(t, n, moveIds, level, opts)
  opts = opts or {}
  local b = t.species[n]
  level = level or 50
  local function st(base) return math.floor((2 * base + 31) * level / 100) + 5 end
  local hp = math.floor((2 * b[3] + 31) * level / 100) + level + 10
  local moves = {}
  for i, id in ipairs(moveIds) do moves[i] = { id = id, pp = t.moves[id][4], ppUps = 0 } end
  return {
    species = n, level = level, hp = hp, maxHp = hp, atk = opts.atk or st(b[4]), def = opts.def or st(b[5]),
    speed = opts.speed or st(b[6]), spAtk = opts.spAtk or st(b[7]), spDef = opts.spDef or st(b[8]),
    moves = moves, gender = opts.gender or 2, friendship = opts.friendship or 70, nickname = opts.nickname,
    ivs = { hp = 31, atk = 31, def = 31, spe = 31, spa = 31, spd = 31 },
  }
end

function F.randomParty(t, rnd, size)
  local illegal = {}
  for _, id in ipairs(t.illegal) do illegal[id] = true end
  local party = {}
  for i = 1, size do
    local n = rnd(t.dexMax)
    local ids, used = {}, {}
    while #ids < 4 do
      local id = rnd(t.moveMax)
      if not used[id] and not illegal[id] and id ~= 165 then
        used[id] = true
        ids[#ids + 1] = id
      end
    end
    party[i] = F.record(t, n, ids, 30 + rnd(40), { gender = rnd(3) - 1, friendship = rnd(256) - 1 })
  end
  return party
end

function F.pick(m, seat, rnd)
  local l = m:legalActions(seat)
  if #l > 1 and rnd(50) ~= 1 then
    local filtered = {}
    for _, a in ipairs(l) do if a.kind ~= "forfeit" then filtered[#filtered + 1] = a end end
    l = filtered
  end
  return l[rnd(#l)]
end

return F
