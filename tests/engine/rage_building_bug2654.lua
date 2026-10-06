-- engine/battle/core.asm:3227
-- engine/battle/core.asm:4913
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

Data.moves.FIX_LEAFISH = {
  id = "FIX_LEAFISH", index = 97, name = "FIX LEAF",
  type = "GRASS", power = 40, accuracy = 100, pp = 25,
  effect = "NO_ADDITIONAL_EFFECT",
}
Data.moves.FIX_MULTI = {
  id = "FIX_MULTI", index = 98, name = "FIX MULTI",
  type = "NORMAL", power = 15, accuracy = 100, pp = 10,
  effect = "TWO_TO_FIVE_ATTACKS_EFFECT", multiHit = 3,
}

local save = SaveData.newGame()
save.party = { Pokemon.new(Data, "FIXMON_A", 30) }
local game = { data = Data, save = save,
               stack = { top = function() return nil end, push = function() end } }

local function lowRolls(lo, hi)
  if lo and lo > 0 then return hi end
  return 0
end

local function mkseq(vals)
  local i = 0
  return function(_, hi)
    i = i + 1
    return vals[i] ~= nil and vals[i] or hi
  end
end

local function rager(rng)
  local b = BattleState.newWild(game, "FIXMON_C", 40)
  b.rng = rng or lowRolls
  b.enemy.rageMove = { id = "RAGE", pp = 20 }
  b.enemy.stages.attack = 0
  return b
end

local function texts(b)
  local out = {}
  for _, row in ipairs(b.queue) do
    if row.text then out[#out + 1] = row.text end
  end
  return out
end

local function find(list, needle, from)
  for i = from or 1, #list do
    if list[i]:find(needle, 1, true) then return i end
  end
  return nil
end

local function count(list, needle)
  local n = 0
  for _, t in ipairs(list) do
    if t:find(needle, 1, true) then n = n + 1 end
  end
  return n
end

do
  local b = rager()
  b:performMove(b.player, b.enemy, { id = "FIX_LEAFISH", pp = 25 })
  local t = texts(b)
  local crit = find(t, "Critical hit!")
  local super = find(t, "super")
  local rage = find(t, "RAGE is building!")
  local rose = find(t, "rose!")
  T.check(crit and super and rage and rose, "crit, effectiveness, rage and rose rows all queued")
  T.check(crit and super and crit < super, "crit text precedes effectiveness")
  T.check(super and rage and super < rage, "rage text follows effectiveness")
  T.check(rage and rose and rage < rose, "ATTACK rose! follows the rage text")
  T.check(rose and t[rose]:find("ATTACK", 1, true) ~= nil, "the rose row names ATTACK")
  T.eq(b.enemy.stages.attack, 1, "rage raises the attack stage once")
end

do
  local b = rager()
  b.enemy.mon.hp = 1
  b:performMove(b.player, b.enemy, { id = "FIX_TACKLE", pp = 35 })
  local t = texts(b)
  T.eq(b.enemy.mon.hp, 0, "the hit knocks the rager out")
  T.eq(find(t, "RAGE is building!"), nil, "no rage text on the fainting hit")
  T.eq(find(t, "rose!"), nil, "no stat text on the fainting hit")
  T.eq(b.enemy.stages.attack, 0, "no stage gained on the fainting hit")
end

do
  local b = rager()
  b.enemy.stages.attack = 6
  b:performMove(b.player, b.enemy, { id = "FIX_TACKLE", pp = 35 })
  local t = texts(b)
  T.eq(find(t, "RAGE is building!"), nil, "maxed attack stays silent")
  T.eq(find(t, "Nothing happened!"), nil, "maxed attack prints no fallback either")
  T.eq(b.enemy.stages.attack, 6, "stage stays at +6")
end

do
  local b = rager()
  b.enemy.substituteHP = 200
  local hp = b.enemy.mon.hp
  b:performMove(b.player, b.enemy, { id = "FIX_TACKLE", pp = 35 })
  local t = texts(b)
  T.eq(b.enemy.mon.hp, hp, "the substitute takes the hit")
  T.check(find(t, "RAGE is building!") ~= nil, "rage still builds behind a substitute")
  T.eq(b.enemy.stages.attack, 1, "substitute hit raises the stage")
end

do
  local b = rager(mkseq({ 0, 255, 255 }))
  b.enemy.mon.maxHP, b.enemy.mon.hp = 999, 999
  b:performMove(b.player, b.enemy, { id = "FIX_MULTI", pp = 10 })
  local t = texts(b)
  T.eq(count(t, "RAGE is building!"), 3, "rage builds once per strike")
  T.eq(count(t, "rose!"), 3, "a rose line per strike")
  T.eq(b.enemy.stages.attack, 3, "three strikes, three stages")
  local multi = find(t, "times!")
  local lastRose
  for i, s in ipairs(t) do if s:find("rose!", 1, true) then lastRose = i end end
  T.check(multi and lastRose and lastRose < multi, "hit count text follows the last strike's rage")
end

do
  local probe = rager(mkseq({ 0, 255, 255 }))
  probe.enemy.mon.maxHP, probe.enemy.mon.hp = 999, 999
  probe:performMove(probe.player, probe.enemy, { id = "FIX_MULTI", pp = 10 })
  local perStrike = math.floor((999 - probe.enemy.mon.hp) / 3)
  local b = rager(mkseq({ 0, 255, 255 }))
  b.enemy.mon.hp = perStrike + 1
  b:performMove(b.player, b.enemy, { id = "FIX_MULTI", pp = 10 })
  local t = texts(b)
  T.eq(b.enemy.mon.hp, 0, "the second strike knocks the rager out")
  T.eq(count(t, "RAGE is building!"), 1, "only the first strike built rage")
  T.eq(find(t, "times!"), nil, "no hit count text when a strike faints the target")
  T.check(find(t, "fainted!") ~= nil, "the target faints")
end

Data.moves.FIX_BOOM = {
  id = "FIX_BOOM", index = 99, name = "FIX BOOM",
  type = "NORMAL", power = 170, accuracy = 100, pp = 5,
  effect = "EXPLODE_EFFECT",
}

for _, arm in ipairs({
  { label = "accuracy miss", seq = { 255 } },
  { label = "invulnerable target", seq = { 0, 255, 255 }, invulnerable = true },
}) do
  save.party = { Pokemon.new(Data, "FIXMON_A", 30) }
  local b = rager(mkseq(arm.seq))
  b.enemy.invulnerable = arm.invulnerable
  b:performMove(b.player, b.enemy, { id = "FIX_BOOM", pp = 5 })
  local t = texts(b)
  T.check(find(t, "attack missed!") ~= nil, arm.label .. ": the Explosion missed")
  T.eq(b.player.mon.hp, 0, arm.label .. ": the exploder still faints")
  local rage = find(t, "RAGE is building!")
  local faint = find(t, "fainted!")
  T.check(rage ~= nil, arm.label .. ": a missed Explosion still builds rage")
  T.check(rage and faint and rage < faint, arm.label .. ": rage text precedes the exploder's faint")
  T.eq(b.enemy.stages.attack, 1, arm.label .. ": stage +1 after the miss")
end

Data.moves.FIX_LEAFISH = nil
Data.moves.FIX_MULTI = nil
Data.moves.FIX_BOOM = nil
T.finish("rage building order")
