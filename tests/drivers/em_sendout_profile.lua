local U = require("tests.drivers.util")

return function(game)
  local fails = 0
  local function result(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then fails = fails + 1 end
  end
  local function finish()
    print(string.format("[driver] em_sendout_profile: %d failure(s)", fails))
    love.event.quit(fails == 0 and 0 or 1)
    U.wait(10)
  end

  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "NICK", gender = 0 })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local BattleBridge = require("src.core.game3.battle_bridge")
  local Battle = require("src.core.game3.battle")
  local Ui = require("src.core.game3.battle.ui")
  local Map = require("src.core.game3.map")
  local C = require("src.core.game3.constants").of("emerald")
  local session = Runtime.getSession()
  if not session then result(false, "field session"); return finish() end

  local ok = pcall(function() Map.load(nil, game, "EM_ROUTE101", { x = 7, y = 13, facing = "down" }) end)
  result(ok, "Route 101 loads")
  U.wait(120)
  session.party = {}
  -- pokeemerald/src/battle_setup.c:923
  Party.giveMon(session, C.species.byName.SPECIES_TREECKO, 5, "TREECKO")
  print("SENDOUT_MARK battle_start")
  local started = BattleBridge.startFirstBattle(Runtime._mod, game, { done = function() end })
  result(started == true, "first battle started")
  if not started then return finish() end

  local lastTap, f = 0, 0
  for _ = 1, 4000 do
    if Battle.isActive() and Battle._phase == "command" and Ui._mode == "menu" then break end
    f = f + 1
    if Ui.dialogPending and Ui.dialogPending() and f - lastTap >= 14 then
      lastTap = f
      U.tap(game, "a")
    else
      U.wait(1)
    end
  end
  result(Battle._phase == "command" and Ui._mode == "menu", "reached the action menu after send-out")
  U.wait(30)
  finish()
end
