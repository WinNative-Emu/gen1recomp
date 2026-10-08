local U = require("tests.drivers.util")
local D = require("tests.support.union_trade_driver")
local GameVersion = require("src.core.GameVersion")

return function(game)
  io.stdout:setvbuf("line")
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "LEAF", gender = 1 })
  U.wait(240)
  local version = GameVersion.get()
  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local C = require("src.core.game3.constants").of(version)
  local session = Runtime.getSession()
  if not session then
    print("FAIL " .. version .. " field session exists")
    love.event.quit(1)
    return
  end
  local S = C.species.byName
  session.party = {}
  Party.giveMon(session, S.SPECIES_MACHOKE, 30, "")
  Party.giveMon(session, S.SPECIES_PIDGEY, 5, "")
  return D.run(game, {
    peerVersion = "gold",
    peerGame = function() return D.peerGame("gold", 152, 10, { 33, 45 }) end,
    mine = function() return session.party[1] and session.party[1].species end,
    expectMoveFix = true,
  })
end
