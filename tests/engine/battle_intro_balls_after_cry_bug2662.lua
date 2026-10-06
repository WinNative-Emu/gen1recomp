-- engine/battle/common_text.asm:10
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()
local Font = require("src.render.Font")
Font.load(Data)
local BattleState = require("src.battle.BattleState")
local Pokemon = require("src.pokemon.Pokemon")
local SaveData = require("src.core.SaveData")
local Sound = require("src.core.Sound")
local Music = require("src.core.Music")
local GameVersion = require("src.core.GameVersion")

local SOUND_FRAMES = 40
local soundLeft = 0
local function fakeSource()
  soundLeft = SOUND_FRAMES
  return { isPlaying = function() return soundLeft > 0 end,
           stop = function() soundLeft = 0 end }
end

local real = {}
for _, k in ipairs({ "playCry", "play", "playMove", "playMoveCry", "stopLoop" }) do
  real[k] = Sound[k]
end
local realMusic = { playBattle = Music.playBattle, play = Music.play }
Sound.playCry = function() return fakeSource() end
Sound.play = function(_, name)
  if name == "Trainer_Appeared" then return fakeSource() end
end
Sound.playMove = function() end
Sound.playMoveCry = function() end
Sound.stopLoop = function() end
Music.playBattle = function() end
Music.play = function() end

local function makeGame()
  local save = SaveData.newGame()
  save.party = { Pokemon.new(Data, "FIXMON_A", 20), Pokemon.new(Data, "FIXMON_B", 5) }
  local stack = { states = {} }
  function stack:push(s) self.states[#self.states + 1] = s end
  function stack:pop() return table.remove(self.states) end
  function stack:top() return self.states[#self.states] end
  return { data = Data, save = save, stack = stack,
           input = { wasPressed = function() return false end,
                     isDown = function() return false end } }
end

local function snapshot(battle)
  local rows, strings = 0, {}
  local realRow, realDraw = battle.drawBallRow, Font.draw
  battle.drawBallRow = function() rows = rows + 1 end
  Font.draw = function(text) strings[#strings + 1] = tostring(text) return 0 end
  local ok, err = pcall(battle.drawHUDs, battle, 0)
  battle.drawBallRow, Font.draw = realRow, realDraw
  local enemyHud = false
  for _, s in ipairs(strings) do
    if s:find(battle.enemy.name, 1, true) then enemyHud = true end
  end
  return ok, err, rows, enemyHud
end

local function run(label, battle)
  battle.onFinish = function() end
  battle:enter()
  T.check(battle.introBalls ~= true, label .. ": no ball window at enter")
  local frames, soundOverlap = {}, false
  local ballsAt, textAt, sawRows
  for f = 1, 400 do
    if soundLeft > 0 then soundLeft = soundLeft - 1 end
    battle:update(1 / 60)
    local cur = battle.current and battle.current.text
    local atText = cur == battle.introText
    if atText and not textAt then textAt = f end
    if battle.introBalls == true and not ballsAt then
      ballsAt = f
      if soundLeft > 0 then soundOverlap = true end
    end
    local ok, err, rows, hud = snapshot(battle)
    T.check(ok, label .. ": drawHUDs runs on frame " .. f .. (ok and "" or (": " .. tostring(err))))
    frames[f] = { balls = battle.introBalls == true, rows = rows, hud = hud,
                  landed = (battle.introSlide or 0) == 0 }
    if atText and rows > 0 then sawRows = true end
    if textAt then break end
  end
  local early, earlyRows, earlyHud = false, false, false
  for f, fr in ipairs(frames) do
    if textAt and f < textAt - 1 then
      if fr.balls then early = true end
      if fr.rows > 0 then earlyRows = true end
    end
    if textAt and f < textAt and fr.landed and fr.hud then earlyHud = true end
  end
  return { early = early, earlyRows = earlyRows, earlyHud = earlyHud,
           overlap = soundOverlap, ballsAt = ballsAt, textAt = textAt,
           sawRows = sawRows }
end

GameVersion.set("red")

do
  local r = run("wild", BattleState.newWild(makeGame(), "FIXMON_C", 5))
  T.check(r.textAt ~= nil, "wild: the intro text comes up")
  T.check(not r.early, "wild: the ball window stays shut until the intro text")
  T.check(not r.overlap, "wild: the ball window opens after the cry has finished")
  T.eq(r.ballsAt, r.textAt and r.textAt - 1, "wild: balls go up right before the intro text")
  T.check(not r.earlyRows, "wild: no ball row is drawn during the cry")
  T.check(not r.earlyHud, "wild: no enemy HUD is drawn during the cry")
  T.check(r.sawRows, "wild: the ball row is drawn with the intro text")
end

do
  local r = run("trainer", BattleState.newTrainer(makeGame(), "OPP_FIX_YOUNGSTER", 1))
  T.check(r.textAt ~= nil, "trainer: the intro text comes up")
  T.check(not r.early, "trainer: the ball window stays shut through the sfx and gap")
  T.check(not r.overlap, "trainer: the ball window opens after the sfx has finished")
  T.eq(r.ballsAt, r.textAt and r.textAt - 1, "trainer: balls go up right before the intro text")
  T.check(not r.earlyRows, "trainer: no ball rows during the sfx and gap")
  T.check(r.sawRows, "trainer: the ball rows are drawn with the intro text")
end

do
  local ghost = BattleState.newWild(makeGame(), "FIXMON_C", 5)
  ghost:makeGhost()
  local r = run("ghost", ghost)
  T.check(r.ballsAt == nil and not r.sawRows, "ghost: DrawAllPokeballs never runs")
  T.check(not r.earlyHud, "ghost: no enemy HUD under the intro text")
  local nextText = ghost.queue[1] and ghost.queue[1].text
  T.check(type(nextText) == "string" and nextText:find("ID'd", 1, true) ~= nil,
          "ghost: GhostCantBeIDdText follows the intro text")
end

do
  local soul = BattleState.newWild(makeGame(), "FIXMON_C", 5)
  soul:makeUnveiledGhost()
  local r = run("unveiled", soul)
  T.check(r.ballsAt == nil and not r.sawRows, "unveiled ghost: DrawAllPokeballs never runs")
end

do
  local demo = BattleState.newWild(makeGame(), "FIXMON_C", 5)
  demo:makeOldManDemo()
  local r = run("red demo", demo)
  T.check(r.sawRows, "red old man demo: DrawAllPokeballs runs (no wBattleType check)")
end

GameVersion.set("yellow")
do
  local demo = BattleState.newWild(makeGame(), "FIXMON_C", 5)
  demo:makeOldManDemo()
  local r = run("yellow demo", demo)
  T.check(r.ballsAt == nil and not r.sawRows, "yellow old man demo: wBattleType skips DrawAllPokeballs")
end
GameVersion.set("red")

for k, v in pairs(real) do Sound[k] = v end
Music.playBattle, Music.play = realMusic.playBattle, realMusic.play

T.finish()
