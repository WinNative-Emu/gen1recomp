-- engine/battle/move_effects/recoil.asm:28
-- engine/battle/move_effects/drain_hp.asm:81
-- engine/battle/core.asm:4899
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()
local Font = require("src.render.Font")
Font.load(Data)
local BattleState = require("src.battle.BattleState")
local Pokemon = require("src.pokemon.Pokemon")
local SaveData = require("src.core.SaveData")
local TypeChart = require("src.battle.TypeChart")
TypeChart.load(Data)

Data.moves.FIX_RECOIL = {
  id = "FIX_RECOIL", index = 98, name = "FIX RECOIL",
  type = "NORMAL", power = 90, accuracy = 100, pp = 20,
  effect = "RECOIL_EFFECT",
}
Data.moves.FIX_ABSORB = {
  id = "FIX_ABSORB", index = 97, name = "FIX ABSORB",
  type = "NORMAL", power = 60, accuracy = 100, pp = 20,
  effect = "DRAIN_HP_EFFECT",
}

local function mkseq(vals)
  local i = 0
  return function(_, hi)
    i = i + 1
    return vals[i] ~= nil and vals[i] or hi
  end
end

local function newBattle()
  local save = SaveData.newGame()
  save.party = { Pokemon.new(Data, "FIXMON_A", 30) }
  local game = { data = Data, save = save,
                 stack = { top = function() return nil end, push = function() end } }
  local battle = BattleState.newWild(game, "FIXMON_C", 40)
  battle.rng = mkseq({ 0, 255, 255 })
  return battle
end

local function rowsOf(battle)
  local out = {}
  for i, row in ipairs(battle.queue) do
    local kind
    if row.drain then
      kind = row.battler == battle.player and "drain:player"
             or row.battler == battle.enemy and "drain:enemy" or "drain"
    elseif row.text then
      kind = row.text:find("recoil", 1, true) and "text:recoil" or "text"
    end
    if kind then out[#out + 1] = { kind = kind, row = row, i = i } end
  end
  return out
end

local function find(rows, kind)
  for _, r in ipairs(rows) do
    if r.kind == kind then return r end
  end
end

local function replay(battle, row)
  battle.queue, battle.current = { row }, nil
  local frames = 0
  while battle:updateQueue() and frames < 8000 do frames = frames + 1 end
  T.check(frames < 8000, "drain row settles")
end

do
  local battle = newBattle()
  battle.player.mon.hp = battle.player.mon.stats.hp
  battle.player.shownHP = battle.player.mon.hp
  local pStart = battle.player.mon.hp
  local eStart = battle.enemy.mon.hp
  battle:performMove(battle.player, battle.enemy, { id = "FIX_RECOIL", pp = 20 })
  local dealt = eStart - battle.enemy.mon.hp
  local recoil = math.max(1, math.floor(dealt / 4))
  T.eq(pStart - battle.player.mon.hp, recoil, "recoil is a quarter of the damage")

  local rows = rowsOf(battle)
  local enemyRow, playerRow = find(rows, "drain:enemy"), find(rows, "drain:player")
  local recoilText = find(rows, "text:recoil")
  T.check(enemyRow and playerRow and recoilText, "target drain, user drain and recoil text all queued")
  if enemyRow and playerRow and recoilText then
    T.check(enemyRow.i < playerRow.i, "the target's bar drains before the user's")
    T.check(playerRow.i < recoilText.i, "the user's bar drains before the recoil text")
    T.eq(playerRow.row.stopAt, battle.player.mon.hp, "the user's row stops at the post-recoil HP")

    replay(battle, enemyRow.row)
    T.eq(battle.enemy.shownHP, battle.enemy.mon.hp, "the target bar settles on its row")
    T.eq(battle.player.shownHP, pStart, "the user's bar holds still during the target's row")

    replay(battle, playerRow.row)
    T.eq(battle.player.shownHP, battle.player.mon.hp, "the user's bar settles on the recoil row")
  end
end

do
  local battle = newBattle()
  battle.player.substituteHP = 10
  local pStart = battle.player.mon.hp
  battle:performMove(battle.player, battle.enemy, { id = "FIX_RECOIL", pp = 20 })
  T.check(battle.player.mon.hp < pStart, "recoil comes off the user's HP")
  T.eq(battle.player.substituteHP, 10, "the user's substitute is untouched by recoil")
  for _, row in ipairs(battle.queue) do
    T.check(not (row.text and row.text:find("SUBSTITUTE", 1, true)),
            "no substitute text for the user's recoil")
  end
end

do
  local battle = newBattle()
  battle.enemy.substituteHP = 1
  local pStart = battle.player.mon.hp
  battle:performMove(battle.player, battle.enemy, { id = "FIX_RECOIL", pp = 20 })
  T.eq(battle.enemy.substituteHP, nil, "the hit breaks the substitute")
  T.eq(battle.player.mon.hp, pStart, "no recoil after breaking a substitute")
  T.check(not find(rowsOf(battle), "text:recoil"), "no recoil text after breaking a substitute")
end

do
  local battle = newBattle()
  battle.player.mon.hp = 10
  battle.player.shownHP = 10
  battle.player.shownPx = nil
  battle:performMove(battle.player, battle.enemy, { id = "FIX_ABSORB", pp = 20 })
  T.check(battle.player.mon.hp > 10, "absorb heals the user")
  local rows = rowsOf(battle)
  local enemyRow, playerRow = find(rows, "drain:enemy"), find(rows, "drain:player")
  T.check(enemyRow and playerRow and enemyRow.i < playerRow.i,
          "the user's heal has its own row after the target's")
  if enemyRow then
    replay(battle, enemyRow.row)
    T.eq(battle.player.shownHP, 10, "the user's bar holds still during the target's row")
  end
  if playerRow then
    replay(battle, playerRow.row)
    T.eq(battle.player.shownHP, battle.player.mon.hp, "the user's bar settles on its row")
  end
end

do
  local battle = newBattle()
  battle.player.mon.hp = 10
  battle.enemy.substituteHP = 1
  battle:performMove(battle.player, battle.enemy, { id = "FIX_ABSORB", pp = 20 })
  T.eq(battle.player.mon.hp, 10, "no heal after breaking a substitute")
end

Data.moves.FIX_RECOIL, Data.moves.FIX_ABSORB = nil, nil
T.finish("recoil hp drain")
