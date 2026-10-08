local U = require("tests.drivers.util")
local G = require("tests.drivers.union_gen3_util")

local CENTER = {
  firered = "FR_VIRIDIAN_CITY_POKEMON_CENTER_2F", leafgreen = "FR_VIRIDIAN_CITY_POKEMON_CENTER_2F",
  emerald = "EM_OLDALE_TOWN_POKEMON_CENTER_2F", ruby = "RU_OLDALE_TOWN_POKEMON_CENTER_2F",
  sapphire = "SA_OLDALE_TOWN_POKEMON_CENTER_2F",
}

return function(game)
  local version = G.version()
  local tag = os.getenv("UNION_SHOT_TAG") or "mixed"
  local d = G.start("union_gen3_mixed_" .. version)
  local session = G.boot(d, game, 0)
  if not session then return d.finish() end
  local Space = require("src.core.game3.scripting.space")
  local Map = require("src.core.game3.map")
  local Union = require("src.core.game3.link.union_room")
  local Plaza = require("src.core.game3.link.union_plaza_map")
  local Family = require("src.core.game3.link.family")
  local Flags = require("src.core.game3.scripting.flags")
  local Warp = require("src.core.game3.warp")
  local e = G.env(d, game, "ME")
  if not d.check(e.connect(), "online on the fake relay") then return d.finish() end
  if version == "emerald" then
    -- pokeemerald/data/scripts/cable_club.inc:104
    Flags.setVar(Space.store, nil, Family.var("emerald", "VAR_CABLE_CLUB_TUTORIAL_STATE"), 2)
  end
  local rs = Family.isRubySapphire(version)
  G.loadMap(game, CENTER[version], rs and 1 or 6, rs and 3 or 4, "up")
  e.wait(30)
  U.tap(game, "a")
  local entered = e.drive(function()
    return Map.current == Plaza.MAP_ID and Union.state == "main" and not Warp.isBusy()
  end, 40)
  if not d.check(entered, "entered the Union Room") then return d.finish() end
  e.peer("b0000001", "RED", "red", 1, 11, 0)
  e.peer("b0000002", "KRIS", "crystal", 2, 22, 1)
  e.peer("b0000003", "MAY", "emerald", 3, 44, 1, "g3:4")
  d.check(e.waitFor(function() return Union.playerCount() == 3 end, 8, 200), "three members appear")
  e.wait(60)
  local slot
  for s = 1, Plaza.CAP do
    local p = Union.players[s]
    if p and p.name == "RED" then slot = s end
  end
  local foreign = 0
  for s = 1, Plaza.CAP do
    local v = Union.vobj(s)
    if v and v.foreign then foreign = foreign + 1 end
  end
  d.note("members drawn from other games' caches: " .. foreign)
  local cx, cy = Plaza.cellFor(slot or 1)
  e.place(cx + 1, cy, "left")
  e.wait(30)
  d.still(game, version .. "_" .. tag .. "_room.png")
  G.resize(240, 160)
  d.still(game, version .. "_" .. tag .. "_native.png")
  G.resize(844, 390)
  d.still(game, version .. "_" .. tag .. "_phone.png")
  G.resize(960, 640)
  e.close()
  return d.finish()
end
