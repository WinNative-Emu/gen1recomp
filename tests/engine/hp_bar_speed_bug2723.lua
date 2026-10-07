package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
love = love or require("tests.love_stub")
local Data = T.fixtures.fresh()

local Timing = require("src.core.Timing")
local PartyMenu = require("src.ui.PartyMenu")

local function partyGame(mon)
  local game = {
    data = { pokemon = { MEWTWO = { name = "MEWTWO" } } },
    save = { party = { mon }, inventory = {}, options = {}, flags = {} },
    overworld = { map = { def = { tileset = "OVERWORLD" }, id = "PALLET_TOWN" },
                  dark = false, partyKnows = function() return nil end },
  }
  game.stack = {
    states = {},
    push = function(self, s) table.insert(self.states, s) end,
    pop = function(self) return table.remove(self.states) end,
    top = function(self) return self.states[#self.states] end,
  }
  game.input = { wasPressed = function() return false end,
                 isDown = function() return false end }
  return game
end

local function healFrames(fromHP, maxHP)
  local mon = { species = "MEWTWO", hp = maxHP, stats = { hp = maxHP },
                level = 100, moves = {} }
  local game = partyGame(mon)
  local pm = PartyMenu.new(game, {})
  game.stack:push(pm)
  local done, frames, lastShown, jumps = 0, 0, fromHP, 0
  pm:animateTo(mon, fromHP, function() done = done + 1 end)
  while pm.heal and frames < 5000 do
    pm:update(1 / 60)
    frames = frames + 1
    if pm.heal then
      if pm.heal.shown - lastShown > 1 then jumps = jumps + 1 end
      lastShown = pm.heal.shown
    end
  end
  return frames, done, jumps
end

-- engine/items/item_effects.asm:1208, engine/gfx/hp_bar.asm:81-135
do
  local frames, done, jumps = healFrames(1, 415)
  T.eq(frames, Timing.hpDrainFrames(1, 415, 415, true),
    "a 1 -> 415 party heal runs UpdateHPBar2's D + 2P + 6 frames")
  T.eq(frames, 414 + 2 * 47 + 6, "which is 514 frames for 414 HP over 47 px")
  T.eq(done, 1, "onDone fires once")
  T.eq(jumps, 0, "the shown HP walks one point at a time")
end

do
  local frames = healFrames(20, 40)
  T.eq(frames, Timing.hpDrainFrames(20, 40, 40, true),
    "a small-HP heal pays two frames per pixel per point")
end

do
  local frames, done = healFrames(415, 415)
  T.eq(done, 1, "a heal with nothing to fill returns at once")
  T.check(frames <= 1, "and takes no animation frames")
end

-- engine/gfx/hp_bar.asm:244-269
local BattleState = require("src.battle.BattleState")
local Pokemon = require("src.pokemon.Pokemon")
local SaveData = require("src.core.SaveData")
local TypeChart = require("src.battle.TypeChart")
TypeChart.load(Data)

local function newBattle(level)
  local save = SaveData.newGame()
  save.party = { Pokemon.new(Data, "FIXMON_A", 30) }
  local game = { data = Data, save = save,
                 stack = { top = function() return nil end,
                           push = function() end } }
  return BattleState.newWild(game, "FIXMON_C", level)
end

local function drainFrames(battle, battler, toHP)
  battler.mon.hp = toHP
  local frames = 0
  while battle:stepHPDrain() and frames < 20000 do frames = frames + 1 end
  return frames
end

do
  local b = newBattle(100)
  local eMax = b.enemy.mon.stats.hp
  T.check(eMax > 96, "the enemy has more than two HP per pixel (" .. eMax .. ")")
  local frames = drainFrames(b, b.enemy, 0)
  T.eq(frames, Timing.hpDrainFrames(eMax, 0, eMax, false),
    "the enemy drain stepper matches the closed form")
  T.check(frames > 2 * 48 + 5,
    "and a big enemy drain pays the per-step CPU lag on top of 2P + 5")
end

do
  local b = newBattle(100)
  local eMax = b.enemy.mon.stats.hp
  local target = eMax - math.floor(eMax / 3)
  T.eq(drainFrames(b, b.enemy, target),
       Timing.hpDrainFrames(eMax, target, eMax, false),
    "a partial enemy drain matches the closed form exactly")
end

local function cartDrain(side, maxHP, fromHP, toHP)
  local b = newBattle(100)
  local battler = b[side]
  battler.mon.stats.hp = maxHP
  battler.mon.hp = fromHP
  battler.shownHP = fromHP
  battler.shownPx = nil
  battler.drainHold = nil
  return drainFrames(b, battler, toHP), battler
end

-- engine/gfx/hp_bar.asm:81-135
for _, m in ipairs({
  { "enemy", 200, 200, 1, 152 }, { "enemy", 150, 150, 0, 147 },
  { "enemy", 400, 400, 0, 243 }, { "enemy", 300, 300, 263, 29 },
  { "enemy", 240, 240, 1, 171 },
  { "player", 150, 150, 0, 250 }, { "player", 399, 399, 199, 254 },
  { "player", 256, 256, 0, 356 },
}) do
  local frames, battler = cartDrain(m[1], m[2], m[3], m[4])
  T.eq(frames, m[5], string.format("%s stepper %d -> %d of %d runs %d frames",
    m[1], m[3], m[4], m[2], m[5]))
  T.eq(frames, Timing.hpDrainFrames(m[3], m[4], m[2], m[1] == "player"),
    string.format("%s stepper %d -> %d of %d matches the closed form",
      m[1], m[3], m[4], m[2]))
  T.eq(battler.shownPx, Timing.hpBarPixels(m[4], m[2]),
    string.format("%s bar settles on %d px", m[1], Timing.hpBarPixels(m[4], m[2])))
end

T.finish("hp bar speed")
