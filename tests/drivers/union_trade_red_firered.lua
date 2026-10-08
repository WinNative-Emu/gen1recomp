local U = require("tests.drivers.util")
local D = require("tests.support.union_trade_driver")
local Pokemon = require("src.pokemon.Pokemon")

return function(game)
  U.wait(30)
  if not D.installGen3("firered") then
    print("FAIL red<->firered needs an imported FireRed identity")
    love.event.quit(1)
    return
  end
  U.teleport(game, "VIRIDIAN_POKECENTER", 4, 4, "down")
  U.wait(30)
  local save = game.save
  save.party = { Pokemon.new(game.data, "PIKACHU", 25), Pokemon.new(game.data, "BULBASAUR", 12) }
  local stamp = require("src.battle.BattleState").stampOT
  for _, mon in ipairs(save.party) do stamp(save, mon) end
  return D.run(game, {
    peerVersion = "firered",
    peerGame = function() return D.peerGame("firered", 4, 10, { 10, 45 }) end,
    mine = function() return save.party[1] and save.party[1].species end,
    expectReceived = "CHARMANDER",
  })
end
