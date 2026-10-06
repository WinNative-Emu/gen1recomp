-- engine/battle/move_effects/recoil.asm:65
-- engine/battle/core.asm:3226
local U = require("tests.drivers.util")
local Battle = require("src.battle.BattleState")
local Pokemon = require("src.pokemon.Pokemon")
local SaveData = require("src.core.SaveData")
local Version = require("src.core.GameVersion")

return function(game)
  local deadline = love.timer.getTime() + 25
  local old = {}
  for _, k in ipairs({ "writeSave", "writeOptions", "persistOptions" }) do old[k] = rawget(game, k) end
  local keys = { "save", "saveOptions", "saveLiveOptions", "writeSlot", "writeCartSlot" }
  local writers = {}
  for _, k in ipairs(keys) do writers[k] = SaveData[k] end
  local volume = love.audio.getVolume()
  local fails = 0
  local function check(label, ok)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then fails = fails + 1 end
    return ok
  end

  local ok, err = xpcall(function()
    assert(Version.generation() == 1, "Gen1 required")
    local out = assert(os.getenv("POKEPORT_SHOT_DIR"), "shot directory required")
    local function forbidden() error("#2653 unexpected persistent write") end
    for _, k in ipairs({ "writeSave", "writeOptions", "persistOptions" }) do game[k] = forbidden end
    for _, k in ipairs(keys) do SaveData[k] = forbidden end
    love.audio.setVolume(0)

    local function wait(n)
      for _ = 1, n do
        assert(love.timer.getTime() < deadline, "#2653 deadline")
        U.wait(1)
      end
    end
    local function fullyTyped(b)
      local row = b.shown and b.shown[#b.shown]
      return b.current and row and b.codes and #row == #b.codes and b.lineIndex == #b.lines
        and b.total and b.total > 0 and b.charIndex >= b.total and not b.scrollPx and not b.msgWaiting
    end
    local function move(id)
      local def = assert(game.data.moves[id], "required imported move " .. id)
      return { id = id, pp = def.pp, maxPp = def.pp }
    end

    game:startNewGame({ intro = false })
    game.save.options.animations = false
    game.save.options.textSpeed = 1
    U.teleport(game, "PALLET_TOWN", 9, 7, "down")

    local function runTurn(pauseAt)
      game.save.party = { Pokemon.new(game.data, "TAUROS", 40) }
      game.save.party[1].moves = { move("TAKE_DOWN") }
      local battle = Battle.newWild(game, "SNORLAX", 50)
      battle.enemy.mon.moves = { move("SPLASH") }
      battle.enemy.curMoves = battle.enemy.mon.moves
      battle.rng = function(a) return a or 0 end

      local r = { step = 0 }
      local update = battle.update
      battle.update = function(self, ...)
        if r.paused then return end
        if r.armed then
          r.step = r.step + 1
          local p, e = self.player, self.enemy
          if e.shownHP ~= r.lastEnemy then
            r.enemyLastMove = r.step
            r.lastEnemy = e.shownHP
          end
          if not r.playerFirstMove and p.shownHP < r.pStart then r.playerFirstMove = r.step end
          if not r.eEnd and e.mon.hp < r.eStart then r.eEnd = e.mon.hp end
          if not r.midStep and r.eEnd and e.shownHP <= math.floor((r.eStart + r.eEnd) / 2) then
            r.midStep = r.step
            r.midPlayerHP = p.shownHP
          end
          local row = self.current
          if row and row.text and row.text:find("recoil", 1, true) and not r.recoilStep then
            r.recoilStep = r.step
            r.recoilPlayerHP = p.shownHP
          end
          if pauseAt and r.midStep == r.step then r.paused = true end
        end
        update(self, ...)
      end
      game.stack:push(battle)

      local function advanceUntil(fn, label)
        for _ = 1, 3000 do
          if fn() then return true end
          if not r.paused and battle.current and not battle.current.auto and fullyTyped(battle) then
            U.tap(game, "a")
          end
          wait(1)
        end
        error(label)
      end

      advanceUntil(function() return battle.phase == "menu" end, "menu did not settle")
      r.pStart, r.eStart = battle.player.mon.hp, battle.enemy.mon.hp
      r.lastEnemy = battle.enemy.shownHP
      U.tap(game, "a")
      advanceUntil(function() return battle.phase == "moveSelect" end, "move list missing")
      r.armed = true
      U.tap(game, "a")
      advanceUntil(function() return battle.player.mon.hp < r.pStart end, "recoil never applied")
      r.eEnd, r.pEnd = r.eEnd or battle.enemy.mon.hp, battle.player.mon.hp
      if pauseAt then
        advanceUntil(function() return r.paused end, "never reached the counted mid-drain step")
        r.shotOk = U.still(game, out .. "/2653_01_target_draining_user_bar_full.png")
        r.shotPlayerHP, r.shotEnemyHP = battle.player.shownHP, battle.enemy.shownHP
        r.paused = false
      end
      advanceUntil(function()
        return battle.current and battle.current.text
          and battle.current.text:find("recoil", 1, true) and fullyTyped(battle)
      end, "recoil text never settled")
      if pauseAt then
        r.textShotOk = U.still(game, out .. "/2653_02_recoil_text_after_user_bar.png")
        r.textPlayerHP = battle.player.shownHP
      end
      advanceUntil(function() return battle.phase == "menu" end, "turn did not finish")
      game.stack:pop()
      return r
    end

    local count = runTurn(nil)
    check("#2653 the hit and the recoil both landed", count.eEnd < count.eStart and count.pEnd < count.pStart)
    check("#2653 user bar holds full through the target's drain",
          count.playerFirstMove and count.enemyLastMove and count.playerFirstMove > count.enemyLastMove)
    check("#2653 user bar still full at mid target drain", count.midStep ~= nil and count.midPlayerHP == count.pStart)
    check("#2653 user bar finished before the recoil text",
          count.recoilStep ~= nil and count.recoilPlayerHP == count.pEnd)

    local shoot = runTurn(count.midStep ~= nil)
    print(("#2653 mid target drain at logic step %s (count pass) / %s (shot pass)"):format(
      tostring(count.midStep), tostring(shoot.midStep)))
    check("#2653 mid-drain shot captured", shoot.shotOk == true)
    check("#2653 shot frame: target mid-drain, user bar full",
          shoot.shotPlayerHP == shoot.pStart and shoot.shotEnemyHP and shoot.shotEnemyHP < shoot.eStart
          and shoot.shotEnemyHP > shoot.eEnd)
    check("#2653 recoil text shot captured with the user bar down",
          shoot.textShotOk == true and shoot.textPlayerHP == shoot.pEnd)

    U.teleport(game, "PALLET_TOWN", 9, 7, "down")
  end, debug.traceback)
  for _, k in ipairs({ "writeSave", "writeOptions", "persistOptions" }) do game[k] = old[k] end
  for _, k in ipairs(keys) do SaveData[k] = writers[k] end
  love.audio.setVolume(volume)
  if not ok then print("FAIL #2653 " .. tostring(err)) end
  love.event.quit((ok and fails == 0) and 0 or 1)
end
