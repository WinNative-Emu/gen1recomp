local E = require("src.core.game3.battle.effect_ids")

local M = {}

M.GEN = 1

local function e(effect, chance) return { effect = effect, chance = chance or 0 } end

-- pokered/constants/move_effect_constants.asm:7
M.EFFECTS = {
  NO_ADDITIONAL_EFFECT = e(E.HIT),
  -- pokered/engine/battle/effects.asm:101
  POISON_SIDE_EFFECT1 = e(E.POISON_HIT, 20),
  -- pokered/engine/battle/effects.asm:104
  POISON_SIDE_EFFECT2 = e(E.POISON_HIT, 40),
  DRAIN_HP_EFFECT = e(E.ABSORB),
  -- pokered/engine/battle/effects.asm:215
  BURN_SIDE_EFFECT1 = e(E.BURN_HIT, 10),
  FREEZE_SIDE_EFFECT1 = e(E.FREEZE_HIT, 10),
  PARALYZE_SIDE_EFFECT1 = e(E.PARALYZE_HIT, 10),
  -- pokered/engine/battle/effects.asm:218
  BURN_SIDE_EFFECT2 = e(E.BURN_HIT, 30),
  FREEZE_SIDE_EFFECT2 = e(E.FREEZE_HIT, 30),
  PARALYZE_SIDE_EFFECT2 = e(E.PARALYZE_HIT, 30),
  -- pokered/engine/battle/effects.asm:984
  FLINCH_SIDE_EFFECT1 = e(E.FLINCH_HIT, 10),
  -- pokered/engine/battle/effects.asm:986
  FLINCH_SIDE_EFFECT2 = e(E.FLINCH_HIT, 30),
  -- pokered/engine/battle/effects.asm:1116
  CONFUSION_SIDE_EFFECT = e(E.CONFUSE_HIT, 10),
  -- pokered/engine/battle/effects.asm:562
  ATTACK_DOWN_SIDE_EFFECT = e(E.ATTACK_DOWN_HIT, 33),
  DEFENSE_DOWN_SIDE_EFFECT = e(E.DEFENSE_DOWN_HIT, 33),
  SPEED_DOWN_SIDE_EFFECT = e(E.SPEED_DOWN_HIT, 33),
  SPECIAL_DOWN_SIDE_EFFECT = e(E.SPECIAL_DEFENSE_DOWN_HIT, 33),
  -- pokered/engine/battle/effects.asm:967
  TWINEEDLE_EFFECT = e(E.TWINEEDLE, 20),
  -- pokered/constants/move_effect_constants.asm:14
  EXPLODE_EFFECT = e(E.EXPLOSION),
  DREAM_EATER_EFFECT = e(E.DREAM_EATER),
  MIRROR_MOVE_EFFECT = e(E.MIRROR_MOVE),
  ATTACK_UP1_EFFECT = e(E.ATTACK_UP),
  DEFENSE_UP1_EFFECT = e(E.DEFENSE_UP),
  SPECIAL_UP1_EFFECT = e(E.SPECIAL_ATTACK_UP),
  EVASION_UP1_EFFECT = e(E.EVASION_UP),
  PAY_DAY_EFFECT = e(E.PAY_DAY),
  SWIFT_EFFECT = e(E.ALWAYS_HIT),
  ATTACK_DOWN1_EFFECT = e(E.ATTACK_DOWN),
  DEFENSE_DOWN1_EFFECT = e(E.DEFENSE_DOWN),
  SPEED_DOWN1_EFFECT = e(E.SPEED_DOWN),
  ACCURACY_DOWN1_EFFECT = e(E.ACCURACY_DOWN),
  EVASION_DOWN1_EFFECT = e(E.EVASION_DOWN),
  -- pokered/constants/move_effect_constants.asm:31
  CONVERSION_EFFECT = e(E.CONVERSION),
  HAZE_EFFECT = e(E.HAZE),
  BIDE_EFFECT = e(E.BIDE),
  THRASH_PETAL_DANCE_EFFECT = e(E.RAMPAGE),
  SWITCH_AND_TELEPORT_EFFECT = e(E.ROAR),
  TWO_TO_FIVE_ATTACKS_EFFECT = e(E.MULTI_HIT),
  SLEEP_EFFECT = e(E.SLEEP),
  OHKO_EFFECT = e(E.OHKO),
  CHARGE_EFFECT = e(E.RAZOR_WIND),
  SUPER_FANG_EFFECT = e(E.SUPER_FANG),
  SPECIAL_DAMAGE_EFFECT = e(E.LEVEL_DAMAGE),
  TRAPPING_EFFECT = e(E.TRAP),
  FLY_EFFECT = e(E.SEMI_INVULNERABLE),
  ATTACK_TWICE_EFFECT = e(E.DOUBLE_HIT),
  JUMP_KICK_EFFECT = e(E.RECOIL_IF_MISS),
  MIST_EFFECT = e(E.MIST),
  FOCUS_ENERGY_EFFECT = e(E.FOCUS_ENERGY),
  RECOIL_EFFECT = e(E.RECOIL),
  CONFUSION_EFFECT = e(E.CONFUSE),
  -- pokered/constants/move_effect_constants.asm:57
  ATTACK_UP2_EFFECT = e(E.ATTACK_UP_2),
  DEFENSE_UP2_EFFECT = e(E.DEFENSE_UP_2),
  SPEED_UP2_EFFECT = e(E.SPEED_UP_2),
  SPECIAL_UP2_EFFECT = e(E.SPECIAL_DEFENSE_UP_2),
  HEAL_EFFECT = e(E.RESTORE_HP),
  TRANSFORM_EFFECT = e(E.TRANSFORM),
  ATTACK_DOWN2_EFFECT = e(E.ATTACK_DOWN_2),
  DEFENSE_DOWN2_EFFECT = e(E.DEFENSE_DOWN_2),
  SPEED_DOWN2_EFFECT = e(E.SPEED_DOWN_2),
  SPECIAL_DOWN2_EFFECT = e(E.SPECIAL_DEFENSE_DOWN_2),
  LIGHT_SCREEN_EFFECT = e(E.LIGHT_SCREEN),
  REFLECT_EFFECT = e(E.REFLECT),
  POISON_EFFECT = e(E.POISON),
  PARALYZE_EFFECT = e(E.PARALYZE),
  -- pokered/constants/move_effect_constants.asm:86
  SUBSTITUTE_EFFECT = e(E.SUBSTITUTE),
  HYPER_BEAM_EFFECT = e(E.RECHARGE),
  RAGE_EFFECT = e(E.RAGE),
  MIMIC_EFFECT = e(E.MIMIC),
  METRONOME_EFFECT = e(E.METRONOME),
  LEECH_SEED_EFFECT = e(E.LEECH_SEED),
  SPLASH_EFFECT = e(E.SPLASH),
  DISABLE_EFFECT = e(E.DISABLE),
}

-- pokered/constants/move_effect_constants.asm:8
M.UNSUPPORTED = {
  EFFECT_01 = "unused",
  EFFECT_1E = "unused",
  SPEED_UP1_EFFECT = "no_engine_handler",
  ACCURACY_UP1_EFFECT = "no_engine_handler",
  SPECIAL_DOWN1_EFFECT = "no_engine_handler",
  ACCURACY_UP2_EFFECT = "no_engine_handler",
  EVASION_UP2_EFFECT = "no_engine_handler",
  ACCURACY_DOWN2_EFFECT = "no_engine_handler",
  EVASION_DOWN2_EFFECT = "no_engine_handler",
}

M.MOVES = {
  -- pokered/data/battle/critical_hit_moves.asm:1
  [2] = { effect = E.HIGH_CRITICAL },
  [75] = { effect = E.HIGH_CRITICAL },
  [152] = { effect = E.HIGH_CRITICAL },
  [163] = { effect = E.HIGH_CRITICAL },
  -- pokered/engine/battle/core.asm:4566
  [68] = { effect = E.COUNTER },
  -- pokered/engine/battle/core.asm:4647
  [69] = { effect = E.LEVEL_DAMAGE },
  [101] = { effect = E.LEVEL_DAMAGE },
  [49] = { effect = E.SONICBOOM },
  [82] = { effect = E.DRAGON_RAGE },
  [149] = { effect = E.PSYWAVE },
  -- pokered/engine/battle/effects.asm:1036
  [13] = { effect = E.RAZOR_WIND },
  [76] = { effect = E.SOLAR_BEAM },
  [130] = { effect = E.SKULL_BASH },
  [143] = { effect = E.SKY_ATTACK },
  [91] = { effect = E.SEMI_INVULNERABLE },
  -- pokered/engine/battle/effects.asm:836
  [100] = { effect = E.TELEPORT },
  -- pokered/engine/battle/effects.asm:135
  [92] = { effect = E.TOXIC },
  -- pokered/engine/battle/move_effects/heal.asm:22
  [156] = { effect = E.REST },
}

-- pokered/engine/battle/core.asm:371
M.PRIORITY = {
  [98] = 1,
  -- pokered/engine/battle/core.asm:382
  [68] = -1,
}

return M
