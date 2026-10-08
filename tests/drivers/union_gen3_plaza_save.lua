local U = require("tests.drivers.util")
local G = require("tests.drivers.union_gen3_util")

local CENTER = {
  firered = { "FR_CERULEAN_CITY_POKEMON_CENTER_2F", "FR_CERULEAN_CITY_POKEMON_CENTER_1F" },
  leafgreen = { "FR_CERULEAN_CITY_POKEMON_CENTER_2F", "FR_CERULEAN_CITY_POKEMON_CENTER_1F" },
  emerald = { "EM_LAVARIDGE_TOWN_POKEMON_CENTER_2F", "EM_LAVARIDGE_TOWN_POKEMON_CENTER_1F" },
}

return function(game)
  local version = G.version()
  local d = G.start("union_gen3_plaza_save_" .. version)
  local session = G.boot(d, game, 0)
  if not session then return d.finish() end
  local Space = require("src.core.game3.scripting.space")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Union = require("src.core.game3.link.union_room")
  local Plaza = require("src.core.game3.link.union_plaza_map")
  local Family = require("src.core.game3.link.family")
  local Flags = require("src.core.game3.scripting.flags")
  local Warp = require("src.core.game3.warp")
  local Spot = require("src.core.game3.link.union_save_spot")
  local e = G.env(d, game, "ME")
  if not d.check(e.connect(), "online on the fake relay") then return d.finish() end
  if version == "emerald" then
    -- pokeemerald/data/scripts/cable_club.inc:104
    Flags.setVar(Space.store, nil, Family.var("emerald", "VAR_CABLE_CLUB_TUTORIAL_STATE"), 2)
  end
  local twoF, oneF = CENTER[version][1], CENTER[version][2]
  G.loadMap(game, twoF, 6, 4, "up")
  e.wait(30)
  U.tap(game, "a")
  local entered = e.drive(function()
    return Map.current == Plaza.MAP_ID and Union.state == "main" and not Warp.isBusy()
  end, 40)
  if not d.check(entered, "entered the Union Room from " .. twoF) then return d.finish() end
  e.place(10, 12, "down")
  e.wait(10)
  local o = Spot.live(require("src.core.game3.runtime").getSession(), game)
  d.check(o ~= nil and o.map == oneF, "the origin is the center's 1F (" .. tostring(o and o.map) .. ")")
  d.check(game:saveGame() ~= false, "saving inside the plaza writes the slot")
  local SaveData = require("src.core.SaveData")
  local Schema = require("src.core.game3.save_schema_firered")
  local saved = SaveData.decode(love.filesystem.read(SaveData.saveFilename()))
  d.note("saved " .. tostring(saved.map) .. " " .. tostring(saved.x) .. "," .. tostring(saved.y) .. " "
    .. tostring(saved.facing) .. " flags=" .. tostring(saved.specialSaveWarpFlags))
  d.check(o ~= nil and saved.map == o.map and saved.x == o.x and saved.y == o.y and saved.facing == "up",
    "the slot records the player facing the origin nurse desk")
  d.check(require("bit").band(tonumber(saved.specialSaveWarpFlags) or 0, 1) == 0, "no continue warp to the 2F door")
  d.check(Map.current == Plaza.MAP_ID, "the live player stays in the plaza")
  local bytes, err = require("src.save_convert.SaveConvert").exportSav(saved, version, nil)
  d.check(bytes ~= nil, "the slot exports as a cartridge save (" .. tostring(err) .. ")")
  e.close()
  e.wait(10)
  local cont = Schema.fromSaveTable(saved)
  require("src.core.game3.options").bind(cont, game.options)
  game:adoptSave(cont, true)
  game:_enterField(cont, "continue")
  U.wait(60)
  G.settleText(game)
  U.wait(30)
  d.still(game, version .. "_plaza_continue_nurse_front.png")
  d.check(o ~= nil and Map.current == o.map and Player.cellX == o.x and Player.cellY == o.y and Player.facing == "up",
    "reload lands facing the nurse (" .. tostring(Map.current) .. " " .. tostring(Player.cellX) .. ","
    .. tostring(Player.cellY) .. " " .. tostring(Player.facing) .. ")")
  return d.finish()
end
