local U = require("tests.drivers.util")
local D = require("tests.support.union_prep_driver")
local Pokemon = require("src.pokemon.Pokemon")
local Boxes = require("src.pokemon.Boxes")
local GameVersion = require("src.core.GameVersion")

return function(game)
  U.wait(30)
  local save = game.save
  local pika = Pokemon.new(game.data, "PIKACHU", 25)
  pika.moves[4] = { id = "SURF", pp = 15 }
  save.party = { pika, Pokemon.new(game.data, "BULBASAUR", 12), Pokemon.new(game.data, "RATTATA", 10) }
  Boxes.ensure(save)[1] = { Pokemon.new(game.data, "CHARMANDER", 8) }
  return D.run(game, {
    version = GameVersion.get(),
    snapshot = function() return { party = save.party, boxes = save.boxes } end,
    rules = { ruleset = "g3u", dexMax = 151, moveMax = 165, moveGen = 1, gens = { 1, 2 } },
    opponent = { name = "KRIS", version = "gold", gen = 2 },
    rentalCount = 15,
    problems = { "can't learn SURF" },
    move = nil,
    pickMove = true,
    peerSize = 2,
    sitOut = "RATTATA",
    expectRental = false,
    closed = function(screen) return game.stack:top() ~= screen end,
  })
end
