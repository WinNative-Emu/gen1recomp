local U = require("tests.drivers.util")
local D = require("tests.support.union_trade_driver")
local Mon = require("src.battle.gen2.Mon")

return function(game)
  U.wait(60)
  local save = game.save
  local bulba = Mon.new(game.data, "BULBASAUR", 14)
  bulba.moves[#bulba.moves + 1] = { id = "SWEET_SCENT", pp = 20, maxPp = 20 }
  while #bulba.moves > 4 do table.remove(bulba.moves, 1) end
  save.party = { bulba, Mon.new(game.data, "SENTRET", 6) }
  for _, mon in ipairs(save.party) do Mon.stampOT(save, mon) end
  return D.run(game, {
    peerVersion = "red",
    peerGame = function() return D.peerGame("red", 7, 12, { 33, 39 }) end,
    mine = function() return save.party[1] and save.party[1].species end,
    expectReceived = "SQUIRTLE",
    expectMoveFix = true,
  })
end
