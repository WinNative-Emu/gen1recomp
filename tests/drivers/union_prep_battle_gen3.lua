local U = require("tests.drivers.util")
local D = require("tests.support.union_prep_driver")
local GameVersion = require("src.core.GameVersion")

return function(game)
  io.stdout:setvbuf("line")
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "MAY", gender = 1 })
  U.wait(240)
  local version = GameVersion.get()
  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local Storage = require("src.core.game3.storage")
  local Stack = require("src.ui.game3.stack")
  local C = require("src.core.game3.constants").of(version)
  local session = Runtime.getSession()
  if not session then
    print("FAIL " .. version .. " field session exists")
    love.event.quit(1)
    return
  end
  local S = C.species.byName
  session.party = {}
  Party.giveMon(session, S.SPECIES_TREECKO, 10, "")
  Party.giveMon(session, S.SPECIES_PIKACHU, 20, "")
  Party.giveMon(session, S.SPECIES_BULBASAUR, 12, "")
  Party.giveMon(session, S.SPECIES_IVYSAUR, 15, "")
  local ivy = table.remove(session.party)
  Storage.ensure(session)
  session.storage.boxes[1].mons[1] = ivy
  local pika = session.party[2]
  pika.moves[4], pika.pp[4], pika.maxPp[4] = 57, 15, 15
  return D.run(game, {
    version = version,
    snapshot = function() return { party = session.party, storage = session.storage, overlay = session.move_overlay } end,
    rules = { ruleset = "g3u", dexMax = 151, moveMax = 165, moveGen = 1, gens = { 1, 3 } },
    opponent = { name = "RED", version = "red", gen = 1 },
    rentalCount = 15,
    problems = { "TREECKO can't join", "can't learn SURF" },
    substitute = { owned = "IVYSAUR", id = "swap_rental", label = "VENUSAUR" },
    pickMove = true,
    peerSize = 2,
    sitOut = "BULBASAUR",
    expectRental = true,
    closed = function() return not Stack.has("union_battle_prep") end,
  })
end
