package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")
local T = require("tests.harness")
local F = require("tests.engine._g3u_fixture")
local Table = require("src.battle.g3u.Table")
local Map1 = require("src.battle.g3u.EffectMap1")
local Map2 = require("src.battle.g3u.EffectMap2")
local E = require("src.core.game3.battle.effect_ids")
local Effects = require("src.core.game3.battle.effects")
local Json = require("src.link.Json")
local Wire = require("src.battle.g3u.Wire")

local GEN1_CONSTANTS = {
  "NO_ADDITIONAL_EFFECT", "EFFECT_01", "POISON_SIDE_EFFECT1", "DRAIN_HP_EFFECT", "BURN_SIDE_EFFECT1",
  "FREEZE_SIDE_EFFECT1", "PARALYZE_SIDE_EFFECT1", "EXPLODE_EFFECT", "DREAM_EATER_EFFECT", "MIRROR_MOVE_EFFECT",
  "ATTACK_UP1_EFFECT", "DEFENSE_UP1_EFFECT", "SPEED_UP1_EFFECT", "SPECIAL_UP1_EFFECT", "ACCURACY_UP1_EFFECT",
  "EVASION_UP1_EFFECT", "PAY_DAY_EFFECT", "SWIFT_EFFECT", "ATTACK_DOWN1_EFFECT", "DEFENSE_DOWN1_EFFECT",
  "SPEED_DOWN1_EFFECT", "SPECIAL_DOWN1_EFFECT", "ACCURACY_DOWN1_EFFECT", "EVASION_DOWN1_EFFECT",
  "CONVERSION_EFFECT", "HAZE_EFFECT", "BIDE_EFFECT", "THRASH_PETAL_DANCE_EFFECT", "SWITCH_AND_TELEPORT_EFFECT",
  "TWO_TO_FIVE_ATTACKS_EFFECT", "EFFECT_1E", "FLINCH_SIDE_EFFECT1", "SLEEP_EFFECT", "POISON_SIDE_EFFECT2",
  "BURN_SIDE_EFFECT2", "FREEZE_SIDE_EFFECT2", "PARALYZE_SIDE_EFFECT2", "FLINCH_SIDE_EFFECT2", "OHKO_EFFECT",
  "CHARGE_EFFECT", "SUPER_FANG_EFFECT", "SPECIAL_DAMAGE_EFFECT", "TRAPPING_EFFECT", "FLY_EFFECT",
  "ATTACK_TWICE_EFFECT", "JUMP_KICK_EFFECT", "MIST_EFFECT", "FOCUS_ENERGY_EFFECT", "RECOIL_EFFECT",
  "CONFUSION_EFFECT", "ATTACK_UP2_EFFECT", "DEFENSE_UP2_EFFECT", "SPEED_UP2_EFFECT", "SPECIAL_UP2_EFFECT",
  "ACCURACY_UP2_EFFECT", "EVASION_UP2_EFFECT", "HEAL_EFFECT", "TRANSFORM_EFFECT", "ATTACK_DOWN2_EFFECT",
  "DEFENSE_DOWN2_EFFECT", "SPEED_DOWN2_EFFECT", "SPECIAL_DOWN2_EFFECT", "ACCURACY_DOWN2_EFFECT",
  "EVASION_DOWN2_EFFECT", "LIGHT_SCREEN_EFFECT", "REFLECT_EFFECT", "POISON_EFFECT", "PARALYZE_EFFECT",
  "ATTACK_DOWN_SIDE_EFFECT", "DEFENSE_DOWN_SIDE_EFFECT", "SPEED_DOWN_SIDE_EFFECT", "SPECIAL_DOWN_SIDE_EFFECT",
  "CONFUSION_SIDE_EFFECT", "TWINEEDLE_EFFECT", "SUBSTITUTE_EFFECT", "HYPER_BEAM_EFFECT", "RAGE_EFFECT",
  "MIMIC_EFFECT", "METRONOME_EFFECT", "LEECH_SEED_EFFECT", "SPLASH_EFFECT", "DISABLE_EFFECT",
}

local GEN2_CONSTANTS = {
  "EFFECT_NORMAL_HIT", "EFFECT_SLEEP", "EFFECT_POISON_HIT", "EFFECT_LEECH_HIT", "EFFECT_BURN_HIT",
  "EFFECT_FREEZE_HIT", "EFFECT_PARALYZE_HIT", "EFFECT_SELFDESTRUCT", "EFFECT_DREAM_EATER", "EFFECT_MIRROR_MOVE",
  "EFFECT_ATTACK_UP", "EFFECT_DEFENSE_UP", "EFFECT_SPEED_UP", "EFFECT_SP_ATK_UP", "EFFECT_SP_DEF_UP",
  "EFFECT_ACCURACY_UP", "EFFECT_EVASION_UP", "EFFECT_ALWAYS_HIT", "EFFECT_ATTACK_DOWN", "EFFECT_DEFENSE_DOWN",
  "EFFECT_SPEED_DOWN", "EFFECT_SP_ATK_DOWN", "EFFECT_SP_DEF_DOWN", "EFFECT_ACCURACY_DOWN", "EFFECT_EVASION_DOWN",
  "EFFECT_RESET_STATS", "EFFECT_BIDE", "EFFECT_RAMPAGE", "EFFECT_FORCE_SWITCH", "EFFECT_MULTI_HIT",
  "EFFECT_CONVERSION", "EFFECT_FLINCH_HIT", "EFFECT_HEAL", "EFFECT_TOXIC", "EFFECT_PAY_DAY", "EFFECT_LIGHT_SCREEN",
  "EFFECT_TRI_ATTACK", "EFFECT_UNUSED_25", "EFFECT_OHKO", "EFFECT_RAZOR_WIND", "EFFECT_SUPER_FANG",
  "EFFECT_STATIC_DAMAGE", "EFFECT_TRAP_TARGET", "EFFECT_UNUSED_2B", "EFFECT_DOUBLE_HIT", "EFFECT_JUMP_KICK",
  "EFFECT_MIST", "EFFECT_FOCUS_ENERGY", "EFFECT_RECOIL_HIT", "EFFECT_CONFUSE", "EFFECT_ATTACK_UP_2",
  "EFFECT_DEFENSE_UP_2", "EFFECT_SPEED_UP_2", "EFFECT_SP_ATK_UP_2", "EFFECT_SP_DEF_UP_2", "EFFECT_ACCURACY_UP_2",
  "EFFECT_EVASION_UP_2", "EFFECT_TRANSFORM", "EFFECT_ATTACK_DOWN_2", "EFFECT_DEFENSE_DOWN_2",
  "EFFECT_SPEED_DOWN_2", "EFFECT_SP_ATK_DOWN_2", "EFFECT_SP_DEF_DOWN_2", "EFFECT_ACCURACY_DOWN_2",
  "EFFECT_EVASION_DOWN_2", "EFFECT_REFLECT", "EFFECT_POISON", "EFFECT_PARALYZE", "EFFECT_ATTACK_DOWN_HIT",
  "EFFECT_DEFENSE_DOWN_HIT", "EFFECT_SPEED_DOWN_HIT", "EFFECT_SP_ATK_DOWN_HIT", "EFFECT_SP_DEF_DOWN_HIT",
  "EFFECT_ACCURACY_DOWN_HIT", "EFFECT_EVASION_DOWN_HIT", "EFFECT_SKY_ATTACK", "EFFECT_CONFUSE_HIT",
  "EFFECT_POISON_MULTI_HIT", "EFFECT_UNUSED_4E", "EFFECT_SUBSTITUTE", "EFFECT_HYPER_BEAM", "EFFECT_RAGE",
  "EFFECT_MIMIC", "EFFECT_METRONOME", "EFFECT_LEECH_SEED", "EFFECT_SPLASH", "EFFECT_DISABLE",
  "EFFECT_LEVEL_DAMAGE", "EFFECT_PSYWAVE", "EFFECT_COUNTER", "EFFECT_ENCORE", "EFFECT_PAIN_SPLIT", "EFFECT_SNORE",
  "EFFECT_CONVERSION2", "EFFECT_LOCK_ON", "EFFECT_SKETCH", "EFFECT_DEFROST_OPPONENT", "EFFECT_SLEEP_TALK",
  "EFFECT_DESTINY_BOND", "EFFECT_REVERSAL", "EFFECT_SPITE", "EFFECT_FALSE_SWIPE", "EFFECT_HEAL_BELL",
  "EFFECT_PRIORITY_HIT", "EFFECT_TRIPLE_KICK", "EFFECT_THIEF", "EFFECT_MEAN_LOOK", "EFFECT_NIGHTMARE",
  "EFFECT_FLAME_WHEEL", "EFFECT_CURSE", "EFFECT_UNUSED_6E", "EFFECT_PROTECT", "EFFECT_SPIKES", "EFFECT_FORESIGHT",
  "EFFECT_PERISH_SONG", "EFFECT_SANDSTORM", "EFFECT_ENDURE", "EFFECT_ROLLOUT", "EFFECT_SWAGGER",
  "EFFECT_FURY_CUTTER", "EFFECT_ATTRACT", "EFFECT_RETURN", "EFFECT_PRESENT", "EFFECT_FRUSTRATION",
  "EFFECT_SAFEGUARD", "EFFECT_SACRED_FIRE", "EFFECT_MAGNITUDE", "EFFECT_BATON_PASS", "EFFECT_PURSUIT",
  "EFFECT_RAPID_SPIN", "EFFECT_UNUSED_82", "EFFECT_UNUSED_83", "EFFECT_MORNING_SUN", "EFFECT_SYNTHESIS",
  "EFFECT_MOONLIGHT", "EFFECT_HIDDEN_POWER", "EFFECT_RAIN_DANCE", "EFFECT_SUNNY_DAY", "EFFECT_DEFENSE_UP_HIT",
  "EFFECT_ATTACK_UP_HIT", "EFFECT_ALL_UP_HIT", "EFFECT_FAKE_OUT", "EFFECT_BELLY_DRUM", "EFFECT_PSYCH_UP",
  "EFFECT_MIRROR_COAT", "EFFECT_SKULL_BASH", "EFFECT_TWISTER", "EFFECT_EARTHQUAKE", "EFFECT_FUTURE_SIGHT",
  "EFFECT_GUST", "EFFECT_STOMP", "EFFECT_SOLARBEAM", "EFFECT_THUNDER", "EFFECT_TELEPORT", "EFFECT_BEAT_UP",
  "EFFECT_FLY", "EFFECT_DEFENSE_CURL",
}

local function pretConstants(path, pattern)
  local f = io.open(path, "rb")
  if not f then return nil end
  local out = {}
  for line in f:lines() do
    local name = line:match("^%s*const%s+(" .. pattern .. ")")
    if name then out[#out + 1] = name end
  end
  f:close()
  return out
end

local function coverage(label, list, map)
  local mapped, unsupported = 0, 0
  for _, name in ipairs(list) do
    local m, u = map.EFFECTS[name] ~= nil, map.UNSUPPORTED[name] ~= nil
    T.check(m ~= u, label .. " " .. name .. " is mapped or listed unsupported, not both")
    if m then mapped = mapped + 1 end
    if u then unsupported = unsupported + 1 end
  end
  local known = {}
  for _, name in ipairs(list) do known[name] = true end
  for name in pairs(map.EFFECTS) do T.check(known[name], label .. " map key " .. name .. " is a real constant") end
  for name in pairs(map.UNSUPPORTED) do T.check(known[name], label .. " unsupported " .. name .. " is a real constant") end
  return mapped, unsupported
end

local m1, u1 = coverage("gen1", GEN1_CONSTANTS, Map1)
local m2, u2 = coverage("gen2", GEN2_CONSTANTS, Map2)
T.eq(m1 + u1, #GEN1_CONSTANTS, "every Gen 1 effect constant is accounted for")
T.eq(m2 + u2, #GEN2_CONSTANTS, "every Gen 2 effect constant is accounted for")

local red = pretConstants("../pokered/constants/move_effect_constants.asm", "[%w_]+")
if red then T.same(red, GEN1_CONSTANTS, "Gen 1 constant list matches pokered") else print("[skip] ../pokered not checked out") end
local crystal = pretConstants("../pokecrystal/constants/move_effect_constants.asm", "EFFECT_[%w_]+")
if crystal then T.same(crystal, GEN2_CONSTANTS, "Gen 2 constant list matches pokecrystal") else print("[skip] ../pokecrystal not checked out") end

local function engineHandles(effect)
  local setup = E.STATUS_SETUP[effect]
  if setup == "EXP_STAT_FROM_EFFECT" then return E.STAT_CHANGES[effect] ~= nil end
  if setup then return Effects.get(setup) ~= nil end
  return true
end

local STATUS_ONLY = {
  [E.SPEED_UP] = true, [E.SPECIAL_DEFENSE_UP] = true, [E.ACCURACY_UP] = true, [E.SPECIAL_ATTACK_DOWN] = true,
  [E.SPECIAL_DEFENSE_DOWN] = true, [E.ACCURACY_UP_2] = true, [E.EVASION_UP_2] = true,
  [E.SPECIAL_ATTACK_DOWN_2] = true, [E.ACCURACY_DOWN_2] = true, [E.EVASION_DOWN_2] = true,
}
for _, map in ipairs({ Map1, Map2 }) do
  for name, row in pairs(map.EFFECTS) do
    T.check(engineHandles(row.effect) and not STATUS_ONLY[row.effect],
      "gen" .. map.GEN .. " " .. name .. " maps to an effect the engine runs (" .. row.effect .. ")")
  end
  for id, row in pairs(map.MOVES) do
    T.check(engineHandles(row.effect), "gen" .. map.GEN .. " move " .. id .. " exception maps to a handled effect")
  end
end
for id in pairs(STATUS_ONLY) do
  T.check(E.STATUS_SETUP[id] == nil, "Gen 3 status effect " .. id .. " has no engine handler, so it stays unsupported")
end

local d1 = F.gen1()
local t1, why = Table.build(d1)
T.check(t1 ~= nil, "Gen 1 fixture builds a table " .. tostring(why))
T.eq(#t1.moves, 165, "Gen 1 table has 165 move rows")
T.eq(#t1.species, 151, "Gen 1 table has 151 species rows")
T.same(t1.moves[44], { 60, 0, 100, 25, E.FLINCH_HIT, 10, 0, 0, 18 }, "Bite: Normal, 60 power, FLINCH_HIT, 10 percent")
T.eq(t1.moves[40][6], 20, "Poison Sting poisons 20 percent (pokered effects.asm:101)")
T.eq(t1.moves[123][6], 40, "Smog poisons 40 percent (pokered effects.asm:104)")
T.eq(t1.moves[34][6], 30, "Body Slam paralyzes 30 percent")
T.eq(t1.moves[51][6], 33, "Acid lowers Defense 33 percent (pokered effects.asm:562)")
T.eq(t1.moves[94][5], E.SPECIAL_DEFENSE_DOWN_HIT, "Psychic's Special drop lowers Sp. Def")
T.eq(t1.moves[41][6], 20, "Twineedle poisons 20 percent (pokered effects.asm:967)")
T.eq(t1.moves[20][6], 100, "Bind traps every hit, as Gen 3 trapping moves do")
T.eq(t1.moves[98][8], 1, "Gen 1 Quick Attack moves first")
T.eq(t1.moves[68][5], E.COUNTER, "Gen 1 Counter is a Counter, not a plain hit")
T.eq(t1.moves[68][8], -1, "Gen 1 Counter moves last")
T.eq(t1.moves[2][5], E.HIGH_CRITICAL, "Karate Chop keeps its high critical ratio")
T.eq(t1.moves[91][5], E.SEMI_INVULNERABLE, "Dig digs")
T.eq(t1.moves[156][5], E.REST, "Rest is Rest")
T.eq(t1.moves[92][5], E.TOXIC, "Toxic badly poisons")
T.eq(t1.moves[14][7], 16, "Swords Dance targets the user")
T.same(t1.species[81], { 13, 13, t1.species[81][3], t1.species[81][4], t1.species[81][5], t1.species[81][6],
  t1.species[81][7], t1.species[81][7] }, "Gen 1 Magnemite is pure Electric with one Special")
T.eq(#t1.illegal, 0, "the Gen 1 fixture has no unsupported moves")
T.check(Table.validate(t1, 1), "the Gen 1 fixture table validates")

local t2 = assert(Table.build(F.gen2()))
T.same(Table.speciesTypes(t2, 81), { 13, 8 }, "Gen 2 Magnemite is Electric/Steel")
T.eq(t2.moves[44][2], 17, "Gen 2 Bite is Dark")
T.eq(t2.moves[44][6], 30, "Gen 2 Bite flinches 30 percent")
T.eq(t2.moves[182][8], 2, "Gen 2 Protect priority 3 is Gen 3 +2")
T.eq(t2.moves[98][8], 1, "Gen 2 Quick Attack priority 2 is Gen 3 +1")
T.eq(t2.moves[18][8], -1, "Gen 2 Whirlwind priority 0 is Gen 3 -1")
T.eq(t2.moves[233][8], -1, "Gen 2 Vital Throw goes last")
T.eq(t2.moves[107][5], E.MINIMIZE, "Gen 2 Minimize sets the minimize flag")
T.eq(t2.moves[23][5], E.FLINCH_MINIMIZE_HIT, "Gen 2 Stomp punishes Minimize")
T.eq(t2.moves[174][2], 9, "Gen 2 Curse is the ??? type")
T.eq(t2.moves[20][6], 100, "Gen 2 Bind traps every hit")
T.check(Table.validate(t2, 2), "the Gen 2 fixture table validates")
T.check(not Table.validate(t2, 1), "a Gen 2 table is refused where Gen 1 is expected")

local withBad = F.gen1({ [5] = { id = 5, type = "NORMAL", power = 0, accuracy = 100, pp = 20, effect = "SPEED_UP1_EFFECT" } })
local tb = assert(Table.build(withBad))
T.same(tb.illegal, { 5 }, "a move with an unsupported effect is listed illegal")
local un = Table.unsupportedMoves(withBad)
T.eq(#un, 1, "unsupportedMoves reports it")
T.eq(un[1] and un[1].id, 5, "unsupportedMoves names the move id")
T.eq(un[1] and un[1].effect, "SPEED_UP1_EFFECT", "unsupportedMoves names the effect")
local unknown = F.gen1({ [5] = { id = 5, type = "NORMAL", power = 0, accuracy = 100, pp = 20, effect = "MADE_UP" } })
T.check(Table.build(unknown) == nil, "an unknown effect constant refuses the table")

local function copy(v)
  if type(v) ~= "table" then return v end
  local o = {}
  for k, x in pairs(v) do o[k] = copy(x) end
  return o
end

local MUTATIONS = {
  { "wrong version", function(t) t.v = 2 end },
  { "unknown key", function(t) t.extra = 1 end },
  { "short move list", function(t) t.moves[165] = nil end },
  { "extra move row", function(t) t.moves[166] = { 1, 0, 100, 10, 0, 0, 0, 0, 0 } end },
  { "power out of range", function(t) t.moves[1][1] = 300 end },
  { "fractional accuracy", function(t) t.moves[1][3] = 99.5 end },
  { "NaN pp", function(t) t.moves[1][4] = 0 / 0 end },
  { "zero pp", function(t) t.moves[1][4] = 0 end },
  { "Dark type in a Gen 1 table", function(t) t.moves[1][2] = 17 end },
  { "unknown effect id", function(t) t.moves[1][5] = 213 end },
  { "chance over 100", function(t) t.moves[1][6] = 101 end },
  { "unknown target", function(t) t.moves[1][7] = 32 end },
  { "priority out of range", function(t) t.moves[1][8] = 7 end },
  { "short row", function(t) t.moves[1][9] = nil end },
  { "string in a row", function(t) t.moves[1][1] = "40" end },
  { "short species list", function(t) t.species[151] = nil end },
  { "zero base stat", function(t) t.species[1][3] = 0 end },
  { "species type out of set", function(t) t.species[1][1] = 8 end },
  { "unsorted illegal list", function(t) t.illegal = { 5, 4 } end },
  { "illegal id out of range", function(t) t.illegal = { 200 } end },
  { "wrong moveMax", function(t) t.moveMax = 251 end },
  { "bad gen", function(t) t.gen = 3 end },
}
for _, mu in ipairs(MUTATIONS) do
  local t = copy(t1)
  mu[2](t)
  local ok = Table.validate(t, 1)
  T.check(not ok, "validate rejects a table with " .. mu[1])
end
T.check(not Table.validate("x"), "validate rejects a non-table")

local bytes = #Json.encode(Wire.table(t2))
T.check(bytes <= Wire.MAX_BYTES.g3u_table, "a Gen 2 table fits the g3u_table byte cap (" .. bytes .. ")")
local round = Json.decode(Json.encode(t1))
T.check(Table.validate(round, 1), "a Gen 1 table survives a JSON round trip")

for _, pair in ipairs({ { "red", "g1r-red", 1 }, { "gold", "g1r-gold", 2 } }) do
  local data = F.real(pair[1], pair[2])
  if data then
    local t, err = Table.build(data)
    T.check(t ~= nil, pair[1] .. " cache builds a table " .. tostring(err))
    if t then
      T.check(Table.validate(t, pair[3]), pair[1] .. " table validates")
      T.eq(#t.illegal, 0, pair[1] .. " has no unsupported moves")
      local bite = t.moves[44]
      if pair[3] == 1 then
        T.same({ bite[2], bite[5], bite[6] }, { 0, E.FLINCH_HIT, 10 }, "red Bite is Normal with a 10 percent flinch")
        T.same(Table.speciesTypes(t, 81), { 13, 13 }, "red Magnemite is pure Electric")
        T.eq(t.species[65][7], t.species[65][8], "red Alakazam has one Special for both sides")
      else
        T.same({ bite[2], bite[5], bite[6] }, { 17, E.FLINCH_HIT, 30 }, "gold Bite is Dark with a 30 percent flinch")
        T.same(Table.speciesTypes(t, 81), { 13, 8 }, "gold Magnemite is Electric/Steel")
      end
      local size = #Json.encode(Wire.table(t))
      T.check(size <= Wire.MAX_BYTES.g3u_table, pair[1] .. " table fits the byte cap (" .. size .. ")")
    end
  else
    print("[skip] " .. pair[1] .. " cache not imported")
  end
end

T.finish("g3u table")
