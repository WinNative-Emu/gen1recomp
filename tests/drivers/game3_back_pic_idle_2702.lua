local U = require("tests.drivers.util")
local F = require("tests.drivers.em_fa_util")
local S = F.new("game3_back_pic_idle_2702", os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_back_pic_idle_2702")

return function(game)
  if not F.boot(game, S) then return S.finish() end
  local Runtime = require("src.core.game3.runtime")
  local Battle = require("src.core.game3.battle")
  local Bridge = require("src.core.game3.battle_bridge")
  local IntroSeq = require("src.core.game3.battle.intro_seq")
  local Anim = require("src.core.game3.battle.anim")
  local Party = require("src.core.game3.party")
  local TrainerPic = require("src.core.game3.trainer_pic")
  local session = Runtime.getSession()
  local version = session.version
  local rse = version == "emerald" or version == "ruby" or version == "sapphire"
  local C = require("src.core.game3.constants").of(version)
  local function species(name) return C:require("species", "SPECIES_" .. name) end
  session.party = {}
  Party.giveMon(session, species(rse and "MUDKIP" or "SQUIRTLE"), 10)

  local wantIdle = rse and 3 or 0
  local wantThrow = rse and { 0, 1, 2 } or { 1, 2, 3, 4 }
  S.check(TrainerPic.backIdleFrame(0) == wantIdle, version .. " cache idle frame for back pic 0 is " .. wantIdle)

  if not S.check(Bridge.startWild(Runtime._mod, game, { species = species(rse and "WURMPLE" or "PIDGEY"), level = 3 },
      { fade = false }) == true, version .. " wild battle started") then return S.finish() end

  local idleBad, idleSeen, throwSeen = 0, 0, {}
  local slideShot, appearedShot, throwShot = false, false, false
  for _ = 1, 4000 do
    local steps = IntroSeq._steps
    if not steps then
      if idleSeen > 0 then break end
    else
      local step = steps[IntroSeq._i]
      local tp = Anim.stage().trainer.player
      local kind = step and step.kind
      if kind == "player_throw" then
        if tp.visible and throwSeen[#throwSeen] ~= tp.frame then throwSeen[#throwSeen + 1] = tp.frame end
        if not throwShot and tp.visible and tp.frame == wantThrow[2] then
          throwShot = true
          S.check(U.still(game, S.dir .. "/2702_03_" .. version .. "_throw_second_pose.png"), version .. " throw pose shot")
        end
      elseif tp.visible and #throwSeen == 0 and (kind == "bgslide" or kind == "msg") then
        idleSeen = idleSeen + 1
        if tp.frame ~= wantIdle then idleBad = idleBad + 1 end
        if kind == "bgslide" and not slideShot and (tp.ox or 0) < 120 and (tp.ox or 0) > 40 then
          slideShot = true
          S.check(U.still(game, S.dir .. "/2702_01_" .. version .. "_slide_in_idle.png"), version .. " slide shot")
        elseif kind == "msg" and not appearedShot then
          appearedShot = true
          U.wait(20)
          S.check(U.still(game, S.dir .. "/2702_02_" .. version .. "_wild_appeared_idle.png"), version .. " appeared shot")
        elseif kind == "msg" and idleSeen % 30 == 0 then
          U.tap(game, "a")
        end
      end
    end
    if Battle._phase == "command" then break end
    U.wait(1)
  end

  S.check(idleSeen > 0 and idleBad == 0, version .. " back pic idles on frame " .. wantIdle
    .. " (" .. idleSeen .. " frames, " .. idleBad .. " wrong)")
  if throwSeen[1] == wantIdle then table.remove(throwSeen, 1) end
  local same = #throwSeen == #wantThrow
  for i, f in ipairs(wantThrow) do same = same and throwSeen[i] == f end
  S.check(same, version .. " throw shows frames " .. table.concat(wantThrow, ",") .. " (saw "
    .. table.concat(throwSeen, ",") .. ")")
  S.finish()
end
