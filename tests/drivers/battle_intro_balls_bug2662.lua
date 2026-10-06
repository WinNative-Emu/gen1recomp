-- engine/battle/common_text.asm:10
-- engine/battle/common_text.asm:43
local U = require("tests.drivers.util")
local BattleState = require("src.battle.BattleState")
local Pokemon = require("src.pokemon.Pokemon")
local Version = require("src.core.GameVersion")
local Font = require("src.render.Font")

return function(game)
  local deadline = love.timer.getTime() + 60
  local fails = 0
  local function check(label, ok)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then fails = fails + 1 end
    return ok
  end

  local ok, err = xpcall(function()
    assert(Version.generation() == 1, "Gen1 required")
    local out = assert(os.getenv("POKEPORT_SHOT_DIR"), "shot directory required")

    local function wait(n)
      for _ = 1, n do
        assert(love.timer.getTime() < deadline, "#2662 deadline")
        U.wait(1)
      end
    end

    local function snapshot(battle)
      local rows, strings = 0, {}
      local realRow, realFont, realDraw = battle.drawBallRow, Font.draw, love.graphics.draw
      battle.drawBallRow = function() rows = rows + 1 end
      Font.draw = function(text) strings[#strings + 1] = tostring(text) return 0 end
      love.graphics.draw = function() end
      pcall(battle.drawHUDs, battle, 0)
      battle.drawBallRow, Font.draw, love.graphics.draw = realRow, realFont, realDraw
      local hud = false
      for _, s in ipairs(strings) do
        if s:find(battle.enemy.name, 1, true) then hud = true end
      end
      return rows, hud
    end

    game:startNewGame({ intro = false })
    game.save.options.textSpeed = 1

    local function freshParty()
      game.save.party = { Pokemon.new(game.data, "BULBASAUR", 12),
                          Pokemon.new(game.data, "PIDGEY", 9) }
    end

    local function introText(b)
      local cur = b.current and b.current.text
      if cur == b.introText then return true end
      return b.current == nil and b.queue[1] ~= nil and b.queue[1].text == b.introText
    end

    local function watch(label, battle, holdShot)
      U.teleport(game, "PALLET_TOWN", 9, 7, "down")
      wait(5)
      battle.onFinish = function() end
      game.overworld:pushBattle(battle)
      local r = { early = false, during = false, hudEarly = false, rowsEarly = false,
                  heldFrames = 0, holdShot = false }
      local update = battle.update
      battle.update = function(self, ...)
        update(self, ...)
        if (self.introSlide or 0) ~= 0 or game.stack:top() ~= self then return end
        local atText = introText(self)
        if self.introBalls == true and not atText then r.early = true end
        if self.introBalls == true and self.waitingSound then r.during = true end
        if not atText and not r.reachedText then
          local rows, hud = snapshot(self)
          if rows > 0 then r.rowsEarly = true end
          if hud then r.hudEarly = true end
          if self.waitingSound or (self.waitFrames or 0) > 0 then
            r.heldFrames = r.heldFrames + 1
          end
        end
        if atText then r.reachedText = true end
      end
      local shotHeld = false
      for _ = 1, 3000 do
        wait(1)
        if game.stack:top() == battle and (battle.introSlide or 0) == 0
           and not shotHeld and (battle.waitingSound or (battle.waitFrames or 0) > 0)
           and not introText(battle) then
          shotHeld = U.still(game, out .. "/" .. holdShot)
          r.holdShot = shotHeld and battle.introBalls ~= true
        end
        if battle.current and battle.current.text == battle.introText then break end
      end
      return r
    end

    local function waitPrompt(b)
      for _ = 1, 600 do
        if b.msgPrompt then return true end
        wait(1)
      end
      return false
    end

    freshParty()
    local wild = BattleState.newWild(game, "RATTATA", 3)
    local r = watch("wild", wild, "2662_01_wild_cry_no_balls.png")
    check("wild: the cry held the queue after the slide landed", r.heldFrames > 0)
    check("wild: captured the cry frame with no ball window", r.holdShot)
    check("wild: no ball window before the intro text", not r.early)
    check("wild: no ball window while the cry sounds", not r.during)
    check("wild: no ball row drawn during the cry", not r.rowsEarly)
    check("wild: no enemy HUD drawn during the cry", not r.hudEarly)
    check("wild: the ball window is open with the intro text", wild.introBalls == true)
    waitPrompt(wild)
    check("wild: balls and text shot", U.still(game, out .. "/2662_02_wild_balls_with_text.png"))

    freshParty()
    local tr = BattleState.newTrainer(game, "OPP_YOUNGSTER", 1)
    r = watch("trainer", tr, "2662_03_trainer_sfx_no_balls.png")
    check("trainer: the sfx and gap held the queue", r.heldFrames > 0)
    check("trainer: captured the sfx frame with no ball window", r.holdShot)
    check("trainer: no ball window before the intro text", not r.early)
    check("trainer: no ball window while the sfx sounds", not r.during)
    check("trainer: no ball rows drawn during the sfx and gap", not r.rowsEarly)
    check("trainer: the ball window is open with the intro text", tr.introBalls == true)
    waitPrompt(tr)
    check("trainer: balls and text shot", U.still(game, out .. "/2662_04_trainer_balls_with_text.png"))

    freshParty()
    local ghost = BattleState.newWild(game, "GASTLY", 20)
    ghost:makeGhost()
    U.teleport(game, "PALLET_TOWN", 9, 7, "down")
    wait(5)
    ghost.onFinish = function() end
    game.overworld:pushBattle(ghost)
    local ghostBalls, sawDarn = false, false
    for _ = 1, 3000 do
      wait(1)
      if ghost.introBalls == true then ghostBalls = true end
      local cur = ghost.current and ghost.current.text
      if cur and cur:find("ID'd", 1, true) then sawDarn = true end
      if ghost.msgPrompt then
        if sawDarn then break end
        wait(8)
        U.tap(game, "a")
      end
    end
    check("ghost: GhostCantBeIDdText follows the intro text", sawDarn)
    check("ghost: DrawAllPokeballs never runs", not ghostBalls)
    if sawDarn then
      check("ghost: cant be IDd shot", U.still(game, out .. "/2662_05_ghost_cant_be_idd.png"))
    end
  end, debug.traceback)
  if not ok then print("FAIL #2662 driver error: " .. tostring(err)) fails = fails + 1 end
  love.event.quit(fails == 0 and 0 or 1)
end
