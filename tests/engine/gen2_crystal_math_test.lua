package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local Damage = require("src.battle.gen2.Damage")
local Mon = require("src.battle.gen2.Mon")

local function options()
  return {
    level = 50, power = 50, moveType = "NORMAL", variation = 255,
    attacker = { attack = 100, stages = {}, types = {} },
    defender = { defense = 100, stages = {}, types = {} },
    types = { NORMAL = { category = "physical" } }, matchups = {},
  }
end

local o = options()
o.critical = true
o.attacker.attackPenalty = { 1, 2 }
o.attacker.badgeStatBoosts = { attack = true }
o.screen = true
T.eq(Damage.calc(o), 46, "equal-stage critical bypasses burn, badge and screen")
o = options()
o.critical, o.screen = true, true
o.attacker.stages.attack, o.defender.stages.defense = 2, 1
T.eq(Damage.calc(o), 30, "higher attack stage retains both stages and Reflect")
o = options()
o.critical = true
o.attacker.stages.attack, o.defender.stages.defense = -1, -2
T.eq(Damage.calc(o), 60, "critical retains negative stages when attack stage is higher")
o.attacker.attackPenalty = { 1, 2 }
T.eq(Damage.calc(o), 30, "critical retains burn when using modified stats")

o = options()
o.level, o.power, o.attacker.attack, o.defender.defense = 100, 100, 7, 10
o.attacker.stages.attack = 1
o.attacker.badgeStatBoosts = { attack = true }
T.eq(Damage.calc(o), 94, "badge rounds after the attack stage")

o = options()
o.attackDoubled = true
T.eq(Damage.calc(o), 46, "species item doubles attack before truncation")
o = options()
o.metalPowder = true
T.eq(Damage.calc(o), 16, "Metal Powder boosts truncated defense")
o.attacker.attack, o.defender.defense = 200, 200
T.eq(Damage.calc(o), 16, "Metal Powder overflow halves attack and carries defense")

T.eq(Damage.criticalLevel({ speciesItemBonus = true, focusEnergy = true,
  highCritMove = true, scopeLens = true }), 2, "species crit item skips other bonuses")
local syntheticChances = { [0] = 73 }
for byte = 0, 255 do
  T.eq(Damage.rollCritical(0, function(n)
    T.eq(n, 256, "critical uses a byte roll")
    return byte
  end, syntheticChances), byte < 73, "cached critical byte boundary " .. byte)
end

local syntheticAccuracy = { [-1] = { 3, 4 }, [1] = { 4, 3 } }
for byte = 0, 255 do
  T.eq(Damage.rollHit(90, 0, 0, function(n)
    T.eq(n, 256, "accuracy uses a byte roll")
    return byte
  end, 229, syntheticAccuracy), byte < 229, "raw accuracy byte boundary " .. byte)
end
T.eq(Damage.rollHit(100, 0, 1, function() return 190 end, 255,
  syntheticAccuracy), true, "accuracy uses supplied accuracy ratio")
T.eq(Damage.rollHit(100, 0, 1, function() return 191 end, 255,
  syntheticAccuracy), false, "accuracy ratio floors before comparison")
T.eq(Damage.rollHit(100, 0, 0, function() error("unexpected roll") end,
  255, syntheticAccuracy), true, "maximum accuracy consumes no RNG")
T.eq(Damage.rollHit(100, 1, 0, function() return 254 end, 220,
  syntheticAccuracy, 1), false, "Bright Powder subtracts after stage cap")

for variation = 217, 255 do
  o = options()
  o.variation = variation
  T.eq(Damage.calc(o), math.floor(24 * variation / 255),
    "damage variation byte " .. variation)
end
o = options()
o.variation = nil
o.noVariation = true
o.random = function() error("unexpected variation roll") end
T.eq(Damage.calc(o), 24, "no-variation moves consume no variation RNG")
o.damageMultiplier = 3
T.eq(Damage.calc(o), 72, "damage multiplier follows DamageCalc minimum addition")

o = options()
o.power = 48
o.attacker.types = { "NORMAL" }
o.rageMultiplier = 2
T.eq(Damage.calc(o), 68, "Rage multiplies after STAB rounding")
o.rageMultiplier, o.damageMultiplier = nil, 2
T.eq(Damage.calc(o), 69, "Triple Kick multiplies before STAB rounding")
o = options()
o.power, o.variation, o.finalMultiplier = 48, 217, 2
T.eq(Damage.calc(o), 38, "conditional damage doubles after variation rounding")

local base = { hp = 50, attack = 50, defense = 50, speed = 50,
  specialAttack = 50, specialDefense = 50 }
local stats = Mon.stats(base, {}, 100, { hp = 10, attack = 10, defense = 16,
  speed = 0, special = 65535 })
T.eq(stats.hp, 211, "HP Stat Exp rounds square root up")
T.eq(stats.attack, 106, "Attack Stat Exp rounds square root up")
T.eq(stats.defense, 106, "perfect square remains exact")
T.eq(stats.speed, 105, "zero Stat Exp contributes nothing")
T.eq(stats.specialAttack, 168, "Stat Exp square root caps at 255")
T.eq(stats.specialDefense, 168, "special stats share Stat Exp")

T.finish("Crystal battle math")
