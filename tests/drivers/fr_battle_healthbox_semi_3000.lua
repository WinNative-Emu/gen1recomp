local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/fr_battle_healthbox_semi_3000"

local MOVE_TACKLE, MOVE_ROAR, MOVE_THUNDER_WAVE, MOVE_DIG, MOVE_SPLASH = 33, 46, 86, 91, 150

return function(game)
  local fails = 0
  local function result(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then fails = fails + 1 end
    return ok
  end
  local function finish()
    local UiL = package.loaded["src.core.game3.battle.ui"]
    if fails > 0 and UiL and UiL.log then
      for _, t in ipairs(UiL.log()) do print("  log: " .. (tostring(t):gsub("\n", " "))) end
    end
    print(string.format("fr battle healthbox/semi driver: %d failure(s)", fails))
    love.event.quit(fails == 0 and 0 or 1)
  end

  for _ = 1, 600 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(180)

  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local BattleBridge = require("src.core.game3.battle_bridge")
  local Battle = require("src.core.game3.battle")
  local Anim = require("src.core.game3.battle.anim")
  local AnimSeq = require("src.core.game3.battle.anim_seq")
  local Healthbox = require("src.core.game3.battle.healthbox")
  local Experience = require("src.core.game3.battle.experience")
  local SummaryData = require("src.core.game3.summary_data")
  local Ui = require("src.core.game3.battle.ui")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the field") then return finish() end
  session.party = {}
  Party.giveMon(session, 28, 40)
  Party.giveMon(session, 16, 40)
  local lead, bench = session.party[1], session.party[2]
  lead.moves, lead.pp = { MOVE_DIG, MOVE_THUNDER_WAVE, MOVE_SPLASH, MOVE_TACKLE }, { 10, 20, 40, 35 }
  bench.moves, bench.pp = { MOVE_TACKLE, 0, 0, 0 }, { 35, 0, 0, 0 }
  lead.exp = SummaryData.expForLevel(Experience.growthRate(lead), 41) - 1
  bench.exp = SummaryData.expForLevel(Experience.growthRate(bench), 40)

  local ok, err = BattleBridge.start(Runtime._mod, game,
    { trainerId = 326, party = { { species = 19, level = 40 } } },
    { wild = false, trainerId = 326, fade = false })
  if not result(ok == true, "trainer battle started " .. tostring(err or "")) then return finish() end

  local f, lastTap = 0, 0
  local watcher = nil
  local function at_command()
    return Battle.isActive() and Battle._phase == "command" and Ui._mode == "menu"
  end
  local function cur_step()
    local steps = AnimSeq._steps
    return steps and steps[AnimSeq._i], steps, AnimSeq._i
  end
  local function pump(stop, limit)
    for _ = 1, limit or 6000 do
      f = f + 1
      if watcher then watcher() end
      if stop() then return true end
      if Ui.choiceActive and Ui.choiceActive() then
        U.wait(8)
        U.tap(game, "b")
        U.wait(8)
      elseif (Ui.dialogPending and Ui.dialogPending() and f - lastTap >= 14)
          or (not Battle.isActive() or Battle._phase ~= "command") and f - lastTap >= 90 then
        lastTap = f
        U.tap(game, "a")
      else
        U.wait(1)
      end
    end
    return stop()
  end
  local function command(move, slot)
    Ui._pendingCommand = { kind = "move", move = move, slot = slot, user = "player" }
    Ui._mode = "none"
  end

  if not result(pump(at_command), "reached the command menu") then return finish() end
  local st = Battle.getState()
  local foe = st.enemy
  foe.mon.moves, foe.mon.pp = { MOVE_TACKLE, 0, 0, 0 }, { 35, 0, 0, 0 }
  foe.mon.maxHp, foe.mon.hp = 300, 300
  foe.mon.speed, foe.speed = 1, 1
  st.player.mon.maxHp, st.player.mon.hp = 300, 300
  Anim.syncDisplayFromState(st)

  local forcePara = nil
  local base = st.rng or function(lo, hi) return math.random(lo, hi) end
  st.rng = function(lo, hi)
    if lo == 0 and hi == 3 and forcePara ~= nil then return forcePara end
    if lo == 1 and hi == 100 then return 1 end
    return base(lo, hi)
  end

  local hpBefore = st.player.mon.hp
  local dug, missed, foeMissShot = false, false, false
  local sawPara, hitShot, hpAtPara = false, false, nil
  watcher = function()
    local s = cur_step()
    if not s then return end
    if not dug and s.kind == "msg" and (s.data.text or ""):find("dug a hole", 1, true) then
      dug = st.player.semiInvulnerable == "UNDERGROUND"
      st.player.status, st.player.mon.status = "PAR", "PAR"
      Anim.syncDisplayFromState(st)
      forcePara = 0
    elseif dug and not foeMissShot and s.kind == "msg" and (s.data.text or ""):find("missed", 1, true) then
      foeMissShot = true
      missed = st.player.mon.hp == hpBefore
      U.wait(30)
      U.still(game, DIR .. "/3000_01_dig_underground_foe_misses.png")
    elseif s.kind == "msg" and (s.data.text or ""):find("is paralyzed", 1, true) and not sawPara then
      sawPara = true
      hpAtPara = st.player.mon.hp
      U.wait(30)
      U.still(game, DIR .. "/3000_02_fully_paralyzed.png")
    elseif sawPara and not hitShot and s.kind == "hp" and (s.data.battler == 0 or s.data.side == "player") then
      hitShot = true
      U.wait(24)
      U.still(game, DIR .. "/3000_03_foe_tackle_hits_surfaced_mon.png")
    end
  end
  command(MOVE_DIG, 1)
  result(pump(function() return sawPara and at_command() end), "Dig turn 2 was fully paralyzed")
  result(dug, "Dig turn 1 went underground")
  result(missed and foeMissShot, "foe Tackle missed the underground mon")
  watcher = nil
  result(st.player.semiInvulnerable == nil and st.player.underground == nil, "paralysis cleared UNDERGROUND")
  result(st.player.twoTurnMove == nil and st.player.expLockedMove == nil, "paralysis dropped the Dig charge")
  result(hitShot and hpAtPara and st.player.mon.hp < hpAtPara, "foe Tackle hit the surfaced mon")
  local pp = Anim.present("player")
  result(pp and pp.visible ~= false, "player sprite is visible again")

  forcePara = 3
  result(foe.status == nil and foe.mon.status == nil, "foe has no status before Thunder Wave")
  local foeP = Anim.present("enemy")
  local seen = {}
  local after_watch
  watcher = function()
    if after_watch then after_watch() end
    local s, _, i = cur_step()
    if not s then return end
    if s.kind == "move" and tonumber(s.data.moveId) == MOVE_THUNDER_WAVE and not seen.move then
      seen.move = Healthbox.shownAilment(foeP, foe)
      U.wait(6)
      U.still(game, DIR .. "/2999_01_thunder_wave_anim_no_icon.png")
    elseif s.kind == "msg" and seen.move and not seen.msg and (s.data.text or ""):find("paralyzed", 1, true) then
      seen.msg = Healthbox.shownAilment(foeP, foe)
      seen.msgIdx = i
      U.wait(40)
      U.still(game, DIR .. "/2999_02_paralysis_message_no_icon.png")
    end
  end
  after_watch = function()
    if seen.msg ~= nil and seen.after == nil and (not AnimSeq._steps or AnimSeq._i > seen.msgIdx) then
      seen.after = Healthbox.shownAilment(foeP, foe)
      U.wait(4)
      U.still(game, DIR .. "/2999_03_icon_after_message.png")
    end
  end
  command(MOVE_THUNDER_WAVE, 2)
  result(pump(function() return seen.after ~= nil and at_command() end), "Thunder Wave turn played")
  watcher = nil
  result(seen.move == 0, "no PAR icon during the Thunder Wave animation (got " .. tostring(seen.move) .. ")")
  result(seen.msg == 0, "no PAR icon while the paralysis message prints (got " .. tostring(seen.msg) .. ")")
  result(seen.after == 2, "PAR icon after the message (got " .. tostring(seen.after) .. ")")

  foe.mon.moves, foe.mon.pp = { MOVE_ROAR, 0, 0, 0 }, { 20, 0, 0, 0 }
  local dragShot = false
  watcher = function()
    local s = cur_step()
    if s and s.kind == "msg" and (s.data.text or ""):find("dragged out", 1, true) and not dragShot then
      dragShot = true
    end
  end
  command(MOVE_SPLASH, 3)
  result(pump(function() return dragShot and at_command() end), "Roar dragged out the bench mon")
  watcher = nil
  U.wait(10)
  U.still(game, DIR .. "/3003_01_roar_dragged_out_exp_bar.png")
  local want = Experience.progress(st.player.mon).progressPercent
  pp = Anim.present("player")
  result(st.player.partyIndex == 2, "bench mon is now in battle")
  result(pp and math.abs((pp.displayExp or -1) - want) < 1e-6,
    ("EXP bar shows the dragged-out mon (shown %s, want %s)"):format(tostring(pp and pp.displayExp), tostring(want)))

  foe.mon.moves, foe.mon.pp = { MOVE_SPLASH, 0, 0, 0 }, { 40, 0, 0, 0 }
  foe.mon.hp = 1
  foeP.displayHp = 1
  local koSeen = {}
  watcher = function()
    local s = cur_step()
    if not s then return end
    if s.kind == "hp" and (s.data.battler == 1 or s.data.side == "enemy") and not koSeen.hp then
      koSeen.hp = Healthbox.shownAilment(foeP, foe)
      U.wait(2)
      U.still(game, DIR .. "/2999_04_ko_hit_icon_still_shown.png")
    elseif s.kind == "faint" and not koSeen.cry then
      koSeen.cry = Healthbox.shownAilment(foeP, foe)
      U.wait(2)
      U.still(game, DIR .. "/2999_05_faint_anim_icon_still_shown.png")
    end
  end
  command(MOVE_TACKLE, 1)
  result(pump(function() return not Battle.isActive() end, 12000), "battle ended after the KO")
  watcher = nil
  result(koSeen.hp == 2, "PAR icon still shown while the KO hit drains HP (got " .. tostring(koSeen.hp) .. ")")
  result(koSeen.cry == 2, "PAR icon still shown as the faint animation starts (got " .. tostring(koSeen.cry) .. ")")
  finish()
end
