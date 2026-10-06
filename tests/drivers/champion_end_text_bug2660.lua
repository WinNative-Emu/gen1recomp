-- scripts/ChampionsRoom.asm:65
--   tools/run_driver.sh red <identity> tests/drivers/champion_end_text_bug2660.lua <shotdir>
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local BattleState = require("src.battle.BattleState")

  local DIR = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR") or "/tmp/shots"
  local failures = 0
  local function check(label, ok)
    if not ok then failures = failures + 1 end
    print((ok and "PASS " or "FAIL ") .. label)
    return ok
  end
  local function oneline(s)
    return (tostring(s):gsub("[\n\v\f]", " / "))
  end
  local function finish()
    U.log("done:", failures, "failure(s)")
    love.event.quit(failures == 0 and 0 or 1)
    while true do coroutine.yield() end
  end

  local expected = game.data.text and game.data.text._RivalDefeatedText
  check("cache carries _RivalDefeatedText", type(expected) == "string")

  local mon = Pokemon.new(game.data, "MEWTWO", 100)
  mon.moves = { { id = "PSYCHIC_M", pp = 10, ppUps = 0 } }
  if not game.data.moves.PSYCHIC_M then
    mon.moves = { { id = "PSYCHIC", pp = 10, ppUps = 0 } }
  end
  game.save.party = { mon }
  game.save.player.name = "RED"
  game.save.player.rival = "BLUE"
  game.save.flags = game.save.flags or {}
  game.save.flags.EVENT_BEAT_CHAMPION_RIVAL_THIS_RUN = nil
  game.save.flags.EVENT_BEAT_CHAMPION_RIVAL = nil

  U.teleport(game, "CHAMPIONS_ROOM", 4, 7, "up")

  local battle, armed
  local sawDefeated, sawLoss, sawMoney
  local lossText, lossShot, headShot, lastText = nil, false, false, nil
  for _ = 1, 20000 do
    local top = game.stack:top()
    if getmetatable(top) == BattleState then
      if not battle then
        battle = top
        armed = top.endBattleText
        U.log("battle pushed; endBattleText:", oneline(armed))
        for _, m in ipairs(top.enemyParty or {}) do m.hp = 1 end
        if top.enemy and top.enemy.mon then top.enemy.mon.hp = 1 end
      end
      local cur = top.current
      local text = cur and cur.text
      if text and text ~= lastText then
        lastText = text
        if text:find("defeated", 1, true) then sawDefeated = sawDefeated or U.frame() end
        if text:find("NO!", 1, true) and text:find("That can't be!", 1, true) then
          sawLoss = sawLoss or U.frame()
          lossText = text
        end
        if text:find("for winning", 1, true) then sawMoney = sawMoney or U.frame() end
      end
      local typingLoss = lossText and text == lossText
      if typingLoss and not headShot then
        if top.lineIndex == 2 and top.msgWaiting
           and (top.frame or 0) % 60 < 30 then
          headShot = U.still(game, DIR .. "/2660_01_rival_loss_first_page.png")
        end
      end
      if typingLoss and not lossShot
         and top.charIndex and top.total and top.charIndex >= top.total then
        lossShot = U.still(game, DIR .. "/2660_02_rival_loss_scrolled.png")
      end
      if sawMoney then break end
      if typingLoss and not headShot then
        U.wait(1)
      else
        U.tap(game, "a")
        U.wait(3)
      end
    elseif battle then
      break
    else
      U.tap(game, "a")
      U.wait(3)
    end
  end

  check("champion battle pushed", battle ~= nil)
  check("battle armed with _RivalDefeatedText",
        type(armed) == "string" and armed:find("That can't be!", 1, true) ~= nil)
  check("defeated line printed", sawDefeated ~= nil)
  check("rival loss line printed on the battle screen", sawLoss ~= nil)
  if lossText then
    U.log("loss line:", oneline(lossText))
    check("loss line opens with the rival name tag", lossText:sub(1, 6) == "BLUE: ")
  end
  check("money line printed", sawMoney ~= nil)
  check("loss line sits between defeated and money",
        sawDefeated ~= nil and sawLoss ~= nil and sawMoney ~= nil
        and sawDefeated < sawLoss and sawLoss < sawMoney)
  check("loss line first page screenshotted", headShot)
  check("loss line screenshotted", lossShot)
  finish()
end
