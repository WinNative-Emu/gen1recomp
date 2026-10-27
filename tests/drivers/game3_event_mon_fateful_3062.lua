local U = require("tests.drivers.util")
local F = require("tests.drivers.em_fa_util")
local S = F.new("game3_event_mon_fateful_3062", os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_event_mon_fateful_3062")

local NAVEL_ROCK_BASE = "FR_NAVEL_ROCK_BASE"
local LUGIA_XY = { 10, 15 }
local FATEFUL = 2147483648

return function(game)
  if not F.boot(game, S) then return S.finish() end
  local Runtime = require("src.core.game3.runtime")
  local Battle = require("src.core.game3.battle")
  local Ui = require("src.core.game3.battle.ui")
  local Party = require("src.core.game3.party")
  local Bag = require("src.core.game3.bag")
  local Message = require("src.ui.game3.message")
  local Encounters = require("src.core.game3.encounters")
  local Gen3Save = require("src.save_convert.Gen3Save")
  local session = Runtime.getSession()
  local C = require("src.core.game3.constants").of(session.version)
  local lugia = C:require("species", "SPECIES_LUGIA")
  local master = C:require("items", "ITEM_MASTER_BALL")

  session.party = {}
  Party.giveMon(session, C:require("species", "SPECIES_MEWTWO"), 100)
  Bag.add(session.bag, master, 1)

  -- pokefirered/data/maps/NavelRock_Base/scripts.inc:15
  F.setFlag("FLAG_FOUGHT_LUGIA", false)
  F.setFlag("FLAG_LUGIA_FLEW_AWAY", false)
  S.check(F.goTo(game, NAVEL_ROCK_BASE, LUGIA_XY[1], LUGIA_XY[2] + 1, "up"), "Navel Rock Base loaded")

  Encounters.takePendingWild()
  U.tap(game, "a")
  U.wait(30)
  for _ = 1, 600 do
    if Battle.isActive() then break end
    if Message.isOpen() then U.tap(game, "a") end
    U.wait(6)
  end
  if not S.check(Battle.isActive(), "talking to Lugia ran seteventmon and started the battle") then
    return S.finish()
  end

  local thrown, atMenu = false, false
  for frame = 1, 9000 do
    if not Battle.isActive() then break end
    if Battle._phase == "command" and Ui._mode == "menu" and not thrown then
      atMenu = true
      local st = Battle.getState()
      local foe = st and st.enemy and st.enemy.mon
      S.check(foe and tonumber(foe.species) == lugia and tonumber(foe.level) == 70, "the event mon is Lugia Lv70")
      S.check(foe and foe.modernFatefulEncounter == true, "battle Lugia carries modernFatefulEncounter")
      S.check(S.still(game, "3062_01_navel_rock_lugia_battle.png"), "Lugia battle shot")
      thrown = true
      Ui._pendingCommand = { kind = "bag", itemId = master, user = "player" }
      Ui._mode = "none"
    elseif Battle._phase == "catch_nickname_prompt" then
      U.tap(game, "b")
      U.wait(12)
    elseif Ui.dialogPending and Ui.dialogPending() then
      U.tap(game, "a")
      U.wait(8)
    elseif frame % 16 == 0 then
      U.tap(game, "a")
      U.wait(4)
    else
      U.wait(1)
    end
  end
  S.check(atMenu, "the Lugia battle reached the command menu")
  F.settle(game, 600)
  S.check(not Battle.isActive(), "the battle ended")
  local Fade = require("src.ui.game3.fade")
  for _ = 1, 600 do
    if not Fade.isActive() and (Fade.t or 0) <= 0 then break end
    U.wait(1)
  end
  U.wait(20)

  local caught
  for i = #session.party, 1, -1 do
    if tonumber(session.party[i].species) == lugia then caught = session.party[i] break end
  end
  if not S.check(caught ~= nil, "Lugia was caught into the party") then return S.finish() end
  S.check(caught.modernFatefulEncounter == true, "caught Lugia keeps modernFatefulEncounter")
  local ribbons = tonumber(Gen3Save.fromPortMon(caught, {}, true).ribbons) or 0
  S.check(math.floor(ribbons / FATEFUL) % 2 == 1, "exported ribbons word has bit 31 set")
  S.check(S.still(game, "3062_02_lugia_caught_field.png"), "post-catch field shot")
  S.finish()
end
