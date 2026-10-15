local Damage = require("src.battle.gen2.Damage")

local MoveRules = {}

-- engine/battle/move_effects/future_sight.asm:26
local function futureSight(self, attacker, defender, def)
  local side = self:sideOf(attacker)
  self.moveRuleFutureSight = self.moveRuleFutureSight or {}
  if self.moveRuleFutureSight[side] then
    -- engine/battle/move_effects/future_sight.asm:72
    self.moveRuleLastDamage = 0
    self:failText(attacker, defender, "ButItFailedText")
    return
  end
  local attackStats, defenseStats = attacker.stats or {}, defender.stats or {}
  local effect, parameter = self:heldEffect(attacker, "damage")
  local wanted = "HELD_" .. (def.type == "PSYCHIC_TYPE" and "PSYCHIC" or def.type) .. "_BOOST"
  local damage = Damage.calc({ level = attacker.level, power = def.power,
    moveType = def.type, critical = false, noVariation = true,
    attacker = { attack = attackStats.attack, specialAttack = attackStats.specialAttack,
      stages = self.stages[side], types = {},
      badgeStatBoosts = self:battleBadgeBoosts(attacker) },
    defender = { defense = defenseStats.defense, specialDefense = defenseStats.specialDefense,
      stages = self.stages[self:sideOf(defender)], types = {},
      badgeStatBoosts = self:battleBadgeBoosts(defender) },
    types = self.data.type_chart.types, matchups = {},
    itemBoostPercent = effect == wanted and parameter or nil,
    attackDoubled = (self:volatile(attacker).preTransform or attacker).species == "PIKACHU"
      and attacker.item == "LIGHT_BALL",
    metalPowder = (self:volatile(defender).preTransform or defender).species == "DITTO"
      and defender.item == "METAL_POWDER",
    screen = self:screenActive(defender, false),
    reflectOverflowFixed = self:reflectOverflowFixed(),
  })
  self.moveRuleFutureSight[side] = { count = 4, damage = damage }
  self:moveText("ForesawAttackText", attacker, defender)
end

-- engine/battle/core.asm:1466
local function tickFutureSight(self, mon)
  local side = self:sideOf(mon)
  local pending = self.moveRuleFutureSight and self.moveRuleFutureSight[side]
  if not pending then return end
  pending.count = pending.count - 1
  if pending.count ~= 1 then return end
  self.moveRuleFutureSight[side] = nil
  self.moveRuleLastDamage = 0
  local attacker = side == "player" and self.player or self.enemy
  local target = side == "player" and self.enemy or self.player
  if target.hp <= 0 then return end
  self:moveText("BattleText_TargetWasHitByFutureSight", attacker, target)
  local damage = pending.damage
  if damage >= 2 then
    damage = math.floor(damage * (217 + self:roller()(39)) / 255)
  end
  local def = self:moveDef("FUTURE_SIGHT")
  local state = self:volatile(target)
  local sure = self:consumeLockOn(target) or self:volatile(attacker).xAccuracy
  if state.protect or (state.vanished and not sure)
      or (not sure and not self:accuracyRoll(def, attacker, target)) then
    -- engine/battle/effect_commands.asm:2197
    self:failText(attacker, target, "ButItFailedText", "ItFailedText")
    return
  end
  -- data/moves/effects.asm:1943
  self:dealDamage(attacker, target, damage, { checkFaint = true })
  self.moveRuleLastDamage = 0
end

-- engine/battle/effect_commands.asm:2220
local function jumpKickCrash(self, attacker, defender, damage, info)
  if info and info.effectiveness == 0 then return end
  local amount = math.max(1, math.floor(damage / 8))
  attacker.hp = math.max(0, attacker.hp - amount)
  if self.moveEvent then self.moveEvent.animParam = 1 end
  self:moveText("CrashedText", attacker, defender)
  self:emit({ kind = "damage", side = self:sideOf(attacker), amount = amount,
    hp = attacker.hp })
end

-- engine/battle/core.asm:4157
local function pursuitSwitch(self, outgoing, moveId)
  local def = moveId and self:moveDef(moveId)
  if not def or def.effect ~= "EFFECT_PURSUIT" then return false end
  local attacker = outgoing == self.player and self.enemy or self.player
  local side = self:sideOf(attacker)
  self.moveRulePursuitSpent = self.moveRulePursuitSpent or {}
  if self.moveRulePursuitSpent[side] == self.turn then return false end
  self.moveRulePursuitSpent[side] = self.turn
  self.moveRuleSwitching = self:sideOf(outgoing)
  if self:canAct(attacker, moveId) then self:useMove(attacker, outgoing, moveId) end
  self.moveRuleSwitching = nil
  if outgoing.hp <= 0 then
    if outgoing == self.player then self:announcePlayerFaint(true)
    else self:announceEnemyFaint() end
  end
  return true
end

function MoveRules.install(Battle)
  Battle.MOVE_EFFECTS.EFFECT_FUTURE_SIGHT = futureSight
  Battle.MOVE_EFFECT_RECORDS.EFFECT_FUTURE_SIGHT = { kind = "primary", run = futureSight }
  Battle.tickFutureSight = tickFutureSight
  Battle.jumpKickCrash = jumpKickCrash
  Battle.pursuitSwitch = pursuitSwitch
  local originalHit = Battle.hitOnce
  -- engine/battle/move_effects/pursuit.asm:1
  Battle.hitOnce = function(self, attacker, defender, def, opts)
    if def.effect == "EFFECT_PURSUIT" and self.moveRuleSwitching == self:sideOf(defender) then
      opts = opts or {}
      opts.finalMultiplier = (opts.finalMultiplier or 1) * 2
    end
    return originalHit(self, attacker, defender, def, opts)
  end
  local originalDamage = Battle.dealDamage
  -- engine/battle/move_effects/counter.asm:38
  Battle.dealDamage = function(self, attacker, defender, damage, opts)
    local before = defender.hp or 0
    -- engine/battle/effect_commands.asm:3553
    local substitute = (self:volatile(defender).substitute or 0) > 0
    local dealt = originalDamage(self, attacker, defender, math.min(65535, damage), opts)
    self.moveRuleLastDamage = substitute and 0 or math.min(dealt, before)
    return dealt
  end
  local originalMove = Battle.useMove
  -- engine/battle/move_effects/counter.asm:1
  Battle.useMove = function(self, attacker, defender, moveId)
    local def = self:moveDef(moveId)
    local side = self:sideOf(attacker)
    if def and (def.effect == "EFFECT_COUNTER" or def.effect == "EFFECT_MIRROR_COAT") then
      local last = self:volatile(defender).lastMove
      local previous = last and self:moveDef(last)
      local physical = previous and Damage.isPhysical(previous.type, self.data.type_chart.types)
      local kind = def.effect == "EFFECT_COUNTER" and "physical" or "special"
      local wentSecond = self.moveRuleFirstSide and self.moveRuleFirstSide ~= side
        or (not self.moveRuleFirstSide and self.moveRuleLastTurn == self.turn
          and self.moveRuleLastSide ~= side)
      local valid = previous and (previous.power or 0) > 0 and previous.effect ~= def.effect
        and physical == (kind == "physical") and wentSecond
        and Damage.typeMultiplier(def.type, self:battlerTypes(defender),
          self:matchupsAgainst(defender)) ~= 0
      local state = self:volatile(attacker)
      state.tookThisTurn = valid and (self.moveRuleLastDamage or 0) or 0
      state.tookKind = kind
    end
    self.moveRuleLastTurn, self.moveRuleLastSide = self.turn, side
    return originalMove(self, attacker, defender, moveId)
  end
end

return MoveRules
