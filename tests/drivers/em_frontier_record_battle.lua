local U = require("tests.drivers.util")
local S = require("tests.drivers.em_story_util")
local F = require("tests.drivers.em_frontier_f2_util")
local M = require("tests.drivers.em_misc_util")

return function(game)
  local d = S.new("em_frontier_record_battle", "/tmp/em_frontier_record_battle")
  local check, note = d.check, d.note
  local function finish() return d.finish() end

  local session = M.boot(game, d)
  if not session then return finish() end
  S.setFlag("FLAG_SYS_GAME_CLEAR", true)
  require("src.core.game3.scripting.natives").ensureBound(session)
  session.repelSteps = 0
  require("src.core.game3.encounters").onStep = function() return nil end
  local Util = require("src.core.game3.rse.frontier.util")
  local Message = require("src.ui.game3.message")

  -- pokeemerald/include/constants/pokemon.h:47
  local ADAMANT, MODEST, JOLLY, BOLD = 3, 15, 13, 5
  session.party = {
    F.mon(session, "SPECIES_METAGROSS", { "MOVE_METEOR_MASH", "MOVE_EARTHQUAKE", "MOVE_PSYCHIC", "MOVE_BRICK_BREAK" }, ADAMANT),
    F.mon(session, "SPECIES_SALAMENCE", { "MOVE_DRAGON_CLAW", "MOVE_EARTHQUAKE", "MOVE_FLAMETHROWER", "MOVE_AERIAL_ACE" }, JOLLY),
    F.mon(session, "SPECIES_SWAMPERT", { "MOVE_SURF", "MOVE_EARTHQUAKE", "MOVE_ICE_BEAM", "MOVE_BRICK_BREAK" }, MODEST),
    F.mon(session, "SPECIES_LATIOS", { "MOVE_PSYCHIC", "MOVE_DRAGON_CLAW", "MOVE_THUNDERBOLT", "MOVE_ICE_BEAM" }, BOLD),
  }

  if not check(F.teleport(game, d, "EM_BATTLE_FRONTIER_OUTSIDE_EAST", 45, 58, "up"), "Battle Frontier east loads") then
    return finish()
  end
  S.travel(game, { "EM_BATTLE_FRONTIER_BATTLE_PALACE_LOBBY" }, { repel = false, settle = { limit = 20000 } })
  if not check(S.mapNow() == "EM_BATTLE_FRONTIER_BATTLE_PALACE_LOBBY", "walked into the Battle Palace lobby") then
    return finish()
  end
  U.wait(10)

  local f = Util.frontier(session)
  local picker = F.partyPicker(d, game, { 1, 2, 3 }, "01_choose_three")
  local attendant = S.objectByScript("BattleFrontier_BattlePalaceLobby_EventScript_SinglesAttendant")
  if not check(attendant ~= nil, "singles attendant present") then return finish() end
  local battles, retired, askedRecord, shotSaved = 0, false, false, false
  S.talkTo(game, attendant)
  S.settle(game, {
    limit = 400000,
    until_ = function()
      return retired and S.mapNow() == "EM_BATTLE_FRONTIER_BATTLE_PALACE_LOBBY" and not S.busy()
        and tonumber(f.challengeStatus) == 0
    end,
    watch = function()
      if not shotSaved and Message.isOpen() and not Message.isTyping()
          and (M.saw("battle was recorded") or M.saw("could not be saved")) then
        shotSaved = true
        d.shot(game, "02_record_result_message")
      end
    end,
    choice = function(ch)
      local r = F.pick(ch, "RETIRE")
      if r then
        retired = true
        return r
      end
      if retired and M.saw("like to record") then
        askedRecord = true
        return F.pick(ch, "YES")
      end
      return F.yesNo(ch) or "yes"
    end,
    onIdleUi = picker.idle,
    onBattleStart = function() battles = battles + 1 end,
    onBattleEnd = function(result) note("battle " .. battles .. " -> " .. tostring(result)) end,
  })
  check(battles == 1, "one palace battle fought (" .. battles .. ")")
  check(retired, "retired after the first win")
  check(askedRecord, "the lobby attendant asked to record the last battle")
  check(not M.saw("error of some sort"), "no record-save error message")
  check(M.saw("battle was recorded"), "the battle was recorded on the FRONTIER PASS")
  check(type(session.recordedBattle) == "table", "the recorded battle block is in the session save")
  check(tonumber(f.disableRecordBattle) == 1, "a second record of the same battle is disabled")
  for i = math.max(1, #M.msgs - 4), #M.msgs do note("msg " .. i .. ": " .. M.msgs[i]:gsub("\n", " ")) end
  finish()
end
