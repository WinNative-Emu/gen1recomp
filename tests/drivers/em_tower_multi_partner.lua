local U = require("tests.drivers.util")
local S = require("tests.drivers.em_story_util")
local L = require("tests.drivers.em_battle_loop")

return function(game)
  local d = S.new("em_tower_multi_partner", "/tmp/em_tower_multi_partner")
  local check, note = d.check, d.note
  local function shot(name) d.shot(game, name) end
  local function finish() return d.finish() end

  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  if not check(game.boot ~= nil, "boot reached") then return finish() end
  game:_handleBootAction({ action = "new_game", name = "BRENDAN", gender = 0 })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Battle = require("src.core.game3.battle")
  local Anim = require("src.core.game3.battle.anim")
  local Util = require("src.core.game3.rse.frontier.util")
  local D = require("src.core.game3.rse.frontier.trainers")
  local Tower = require("src.core.game3.rse.frontier.tower")
  local Natives = require("src.core.game3.scripting.natives")
  local Rse = require("src.core.game3.rse.init")

  local session = Runtime.getSession()
  if not check(session and session.version == "emerald", "Emerald session") then return finish() end
  Natives.ensureBound(session)
  require("src.core.game3.encounters").onStep = function() return nil end

  local function tough(name, moves)
    local m = D.createMon(S.species(name), 50, 31, 0, tonumber(session.trainerId) or 0,
      { otName = session.name, moves = {} })
    local ms = {}
    for i, mv in ipairs(moves) do ms[i] = S.move(mv) end
    D.setMoves(m, ms)
    D.setEvs(m, { 252, 252, 6, 0, 0, 0 })
    m.otId, m.otName, m.ot = session.trainerId, session.name, session.name
    return m
  end
  session.party = {
    tough("SPECIES_METAGROSS", { "MOVE_METEOR_MASH", "MOVE_EARTHQUAKE", "MOVE_PSYCHIC", "MOVE_BRICK_BREAK" }),
    tough("SPECIES_SALAMENCE", { "MOVE_DRAGON_CLAW", "MOVE_EARTHQUAKE", "MOVE_FLAMETHROWER", "MOVE_AERIAL_ACE" }),
  }

  local ok, err = pcall(function()
    Map.load(nil, game, "EM_BATTLE_FRONTIER_BATTLE_TOWER_MULTI_BATTLE_ROOM", { x = 7, y = 6, facing = "up" })
  end)
  if not check(ok, "multi battle room loads " .. tostring(err or "")) then return finish() end
  U.wait(30)
  S.settle(game)

  Rse.setVar("VAR_FRONTIER_FACILITY", D.FACILITY.TOWER)
  Rse.setVar("VAR_FRONTIER_BATTLE_MODE", D.MODE.MULTIS)
  local f = Util.frontier(session)
  f.lvlMode = D.LVL.L50
  local partnerId = 120
  f.trainerIds[18], f.trainerIds[19], f.trainerIds[20] = partnerId, 300, 400
  session.frontierOpponentA, session.frontierOpponentB = 10, 30

  local ctx = {}
  local started, startErr = pcall(Tower.doTowerBattle, ctx, nil, session)
  if not check(started, "doTowerBattle in MULTIS starts " .. tostring(startErr or "")) then return finish() end
  for _ = 1, 600 do
    if Battle.isActive() then break end
    U.wait(2)
  end
  if not check(Battle.isActive(), "tower multi battle is active") then return finish() end

  local st = Battle._st
  local wantClass = D.className(session, D.opponentClass(session, partnerId, D.FACILITY.TOWER))
  local wantName = D.trainerName(session, partnerId, D.FACILITY.TOWER)
  check(st.kinds.partner and st.double and st.kinds.twoOpponents, "double, partner and two opponents")
  check(st.partner and st.partner.className == wantClass and wantClass ~= "",
    "partner class is the frontier trainer's class (" .. tostring(st.partner and st.partner.className) .. ")")
  check(st.partner and st.partner.name == wantName and wantName ~= "",
    "partner name is the frontier trainer's name (" .. tostring(st.partner and st.partner.name) .. ")")
  check(st.partner and st.partner.backPic == nil, "no Steven back pic for a frontier partner")
  check(st.partner and st.partner.frontPic == D.frontSpriteId(session, partnerId, D.FACILITY.TOWER),
    "partner draws its frontier front pic")

  local shots = {}
  local done, why = L.run(game, {
    turnCap = 40,
    onFrame = function(_, phase)
      local stage = Anim.stage()
      if phase == "intro" and not shots.intro and stage.trainer.player.visible and stage.trainer.player.fronts
          and (stage.trainer.player.ox or 0) == 0 then
        shots.intro = true
        U.wait(2)
        shot("01_intro_partner_and_player_front_pics")
      end
    end,
  })
  check(shots.intro, "intro reached with both front pics on the player side")
  check(done, "battle finished " .. tostring(why or ""))
  local sent = L.logIndex(wantClass .. " " .. wantName) ~= nil
  check(sent, "intro prints the partner's class and name (sText_InGamePartnerSentOutZGoN)")
  if not sent then L.dumpLog("[log]") end
  note("result " .. tostring(st.result))
  return finish()
end
