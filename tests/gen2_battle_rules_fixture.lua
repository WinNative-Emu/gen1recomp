local function rules()
  return {
    criticalChances = { [0] = 17, 32, 64, 85, 128, 128, 128 },
    accuracyMultipliers = {
      [-6] = { 33, 100 }, [-5] = { 36, 100 }, [-4] = { 43, 100 },
      [-3] = { 50, 100 }, [-2] = { 60, 100 }, [-1] = { 75, 100 },
      [0] = { 1, 1 }, [1] = { 133, 100 }, [2] = { 166, 100 },
      [3] = { 2, 1 }, [4] = { 233, 100 }, [5] = { 133, 50 }, [6] = { 3, 1 },
    },
    highCriticalMoves = { KARATE_CHOP = true, RAZOR_WIND = true,
      RAZOR_LEAF = true, CRABHAMMER = true, SLASH = true,
      AEROBLAST = true, CROSS_CHOP = true },
    moveScripts = {
      EFFECT_NORMAL_HIT = { "kingsrock" },
      EFFECT_PRIORITY_HIT = { "kingsrock" },
      EFFECT_DOUBLE_HIT = { "kingsrock" },
      EFFECT_MULTI_HIT = { "kingsrock" },
      EFFECT_FLINCH_HIT = { "effectchance", "applydamage", "flinchtarget" },
      EFFECT_STOMP = { "effectchance", "applydamage", "flinchtarget" },
      EFFECT_TWISTER = { "effectchance", "applydamage", "flinchtarget" },
      EFFECT_SNORE = { "effectchance", "applydamage", "flinchtarget", "kingsrock" },
      EFFECT_SKY_ATTACK = { "effectchance", "applydamage", "flinchtarget", "kingsrock" },
      EFFECT_FLAME_WHEEL = { "effectchance", "applydamage", "defrost", "burntarget" },
      EFFECT_SACRED_FIRE = { "effectchance", "applydamage", "defrost", "burntarget" },
      EFFECT_STATIC_DAMAGE = { "applydamage", "kingsrock" },
      EFFECT_LEVEL_DAMAGE = { "applydamage", "kingsrock" },
    },
    flailPower = { { 255, 20 } },
    presentPower = { { 255, 40 } },
  }
end

return rules
