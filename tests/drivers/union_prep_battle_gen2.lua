local U = require("tests.drivers.util")
local D = require("tests.support.union_prep_driver")
local Mon = require("src.battle.gen2.Mon")
local GameVersion = require("src.core.GameVersion")

return function(game)
  U.wait(60)
  local save = game.save
  local pika = Mon.new(game.data, "PIKACHU", 20)
  pika.moves[#pika.moves] = { id = "CRUNCH", pp = 15, maxPp = 15 }
  save.party = { Mon.new(game.data, "CHIKORITA", 15), pika, Mon.new(game.data, "GEODUDE", 12) }
  save.boxes = save.boxes or {}
  save.boxes[1] = { Mon.new(game.data, "BULBASAUR", 14) }
  return D.run(game, {
    version = GameVersion.get(),
    snapshot = function() return { party = save.party, boxes = save.boxes } end,
    rules = { ruleset = "g3u", dexMax = 151, moveMax = 165, moveGen = 1, gens = { 1, 2 } },
    opponent = { name = "RED", version = "red", gen = 1 },
    rentalCount = 15,
    problems = { "CHIKORITA can't join", "CRUNCH isn't used" },
    substitute = { owned = "BULBASAUR", id = "swap_rental", label = "VENUSAUR" },
    pickMove = true,
    peerSize = 2,
    sitOut = "GEODUDE",
    expectRental = true,
    closed = function(screen) return game.stack:top() ~= screen end,
  })
end
