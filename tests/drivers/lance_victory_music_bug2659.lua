-- POKEPORT_DRIVER=tests/drivers/lance_victory_music_bug2659.lua POKEPORT_SHOT_DIR=/tmp/shots love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/shots"
  local Pokemon = require("src.pokemon.Pokemon")
  local Music = require("src.core.Music")
  local BattleState = require("src.battle.BattleState")
  local Timing = require("src.core.Timing")
  os.execute('mkdir -p "' .. DIR .. '" 2>/dev/null')

  local failed = false
  local function check(label, ok)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then failed = true end
    return ok
  end

  local played = {}
  local realPlayBattle = Music.playBattle
  Music.playBattle = function(data, kind, trainerId, song)
    played[#played + 1] = { call = "battle", kind = kind }
    return realPlayBattle(data, kind, trainerId, song)
  end
  local realPlayVictory = Music.playVictory
  Music.playVictory = function(data, kind, trainerId)
    played[#played + 1] = { call = "victory", kind = kind }
    return realPlayVictory(data, kind, trainerId)
  end
  local function lastKind(call)
    local k
    for _, p in ipairs(played) do
      if p.call == call then k = p.kind end
    end
    return k
  end

  U.newGame(game)
  local mon = Pokemon.new(game.data, "MEWTWO", 100)
  mon.moves = { { id = "SWIFT", pp = 20, maxPp = 20, ppUps = 0 } }
  game.save.party = { mon }
  game.save.player.name = "RED"
  U.teleport(game, "LANCES_ROOM", 5, 3, "up")
  U.wait(20)
  local ow = game.overworld
  check("overworld up in LANCES_ROOM", ow ~= nil)
  if not ow then love.event.quit(1) return end

  local battle = BattleState.newTrainer(game, "OPP_LANCE", 1)
  battle.onFinish = function() end
  for i, m in ipairs(battle.enemyParty) do
    m.hp = (i == 1) and 1 or 0
  end
  battle.enemy.shownHP = 1
  battle.enemy.shownPx = Timing.hpBarPixels(1, math.max(1, battle.enemy.mon.stats.hp))
  ow:pushBattle(battle)

  for _ = 1, 900 do
    if game.stack:top() == battle and battle.musicKind then break end
    U.wait(1)
  end
  check("lance battle on screen", game.stack:top() == battle)
  check("lance battle theme is gym (play_battle_music.asm)",
        battle.musicKind == "gym" and lastKind("battle") == "gym")
  check("lance is not a wGymLeaderNo fight", not battle.isGymLeader)

  local won = false
  for _ = 1, 3000 do
    if lastKind("victory") then won = true break end
    U.tap(game, "a")
    U.wait(6)
  end
  check("lance defeated, victory theme requested", won)
  check("lance victory theme is trainer (TrainerBattleVictory)",
        lastKind("victory") == "trainer")
  local b = game.data.audio and game.data.audio.battle
  check("MUSIC_DEFEATED_TRAINER is playing",
        b ~= nil and Music.current() == b.trainerWin
        and b.trainerWin ~= b.gymWin)

  U.wait(40)
  U.shot(game, DIR .. "/2659_01_lance_defeated_trainer_theme.png")

  Music.playBattle, Music.playVictory = realPlayBattle, realPlayVictory
  love.event.quit(failed and 1 or 0)
end
