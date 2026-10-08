local U = require("tests.drivers.util")
local G = require("tests.drivers.union_gen3_util")

return function(game)
  local version = G.version()
  local d = G.start("rs_link_records_machine_" .. version)
  local session = G.boot(d, game, 0)
  if not session then return d.finish() end
  local Map = require("src.core.game3.map")
  local twoF = G.prefix() .. "OLDALE_TOWN_POKEMON_CENTER_2F"
  G.loadMap(game, twoF, 7, 4, "up")
  U.wait(30)
  d.check(Map.current == twoF, "standing on the Oldale 2F")
  local Records = require("src.ui.game3.rs.link_records")
  -- pokeruby/data/scripts/cable_club.inc:597
  require("src.core.game3.scripting.natives_link_rs").BY_NAME.ShowLinkBattleRecords()
  local Space = require("src.core.game3.scripting.space")
  Records.owner = Space.vm
  local ok = pcall(function() U.wait(20) end)
  d.check(ok and Records.isVisible(), "the link battle records window draws over the field")
  d.still(game, "rs_link_records_window.png")
  Records.eraseBox(0, 0, 29, 19)
  U.wait(10)
  d.check(not Records.isVisible(), "erasebox closes the records window")
  return d.finish()
end
