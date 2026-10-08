local U = require("tests.drivers.util")
local G = require("tests.drivers.union_gen3_util")

local CENTERS = {
  firered = {
    { "FR_VIRIDIAN_CITY_POKEMON_CENTER_2F", "FR_VIRIDIAN_CITY_POKEMON_CENTER_1F" },
    { "FR_INDIGO_PLATEAU_POKEMON_CENTER_2F", "FR_INDIGO_PLATEAU_POKEMON_CENTER_1F" },
    { "SEVII_ONE_ISLAND_POKECENTER_2F", "SEVII_ONE_ISLAND_POKECENTER" },
    { "FR_SEVEN_ISLAND_POKEMON_CENTER_2F", "FR_SEVEN_ISLAND_POKEMON_CENTER_1F" },
  },
  leafgreen = {
    { "FR_CERULEAN_CITY_POKEMON_CENTER_2F", "FR_CERULEAN_CITY_POKEMON_CENTER_1F" },
    { "FR_INDIGO_PLATEAU_POKEMON_CENTER_2F", "FR_INDIGO_PLATEAU_POKEMON_CENTER_1F" },
    { "SEVII_ONE_ISLAND_POKECENTER_2F", "SEVII_ONE_ISLAND_POKECENTER" },
    { "FR_ROUTE_4_POKEMON_CENTER_2F", "FR_ROUTE_4_POKEMON_CENTER_1F" },
  },
  emerald = {
    { "EM_OLDALE_TOWN_POKEMON_CENTER_2F", "EM_OLDALE_TOWN_POKEMON_CENTER_1F" },
    { "EM_BATTLE_FRONTIER_POKEMON_CENTER_2F", "EM_BATTLE_FRONTIER_POKEMON_CENTER_1F" },
    { "EM_EVER_GRANDE_CITY_POKEMON_LEAGUE_2F", "EM_EVER_GRANDE_CITY_POKEMON_LEAGUE_1F" },
  },
}

return function(game)
  local version = G.version()
  local d = G.start("union_gen3_centers_" .. version)
  local session = G.boot(d, game, version == "leafgreen" and 1 or 0)
  if not session then return d.finish() end
  local Space = require("src.core.game3.scripting.space")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Message = require("src.ui.game3.message")
  local Union = require("src.core.game3.link.union_room")
  local Plaza = require("src.core.game3.link.union_plaza_map")
  local Client = require("src.online.Client")
  local Family = require("src.core.game3.link.family")
  local Flags = require("src.core.game3.scripting.flags")
  local e = G.env(d, game, "ME")
  if not d.check(e.connect(), "online on the fake relay") then return d.finish() end
  if version == "emerald" then
    -- pokeemerald/data/scripts/cable_club.inc:104
    Flags.setVar(Space.store, nil, Family.var("emerald", "VAR_CABLE_CLUB_TUTORIAL_STATE"), 2)
  end
  local peered = false
  for i, row in ipairs(CENTERS[version] or CENTERS.firered) do
    local twoF, oneF = row[1], row[2]
    local name = twoF
    if not d.check(game.data.maps[twoF] ~= nil, twoF .. " exists") then return d.finish() end
    G.loadMap(game, twoF, 6, 4, "up")
    e.wait(30)
    U.tap(game, "a")
    local entered = e.drive(function() return Space.mapId == Plaza.MAP_ID and Union.state == "main" end, 30)
    d.note(name .. " map=" .. tostring(Space.mapId) .. " union=" .. tostring(Union.state))
    if not d.check(entered, name .. ": the attendant walks the player into the Union Room") then
      d.shot(game, i .. "_" .. name .. "_enter_failed.png")
      return d.finish()
    end
    d.check(e.waitFor(function() return Client.plaza() ~= nil end, 5, 60), name .. ": joined the plaza")
    if not peered then
      e.peer("b0000001", "RED", "red", 1, 11, 0)
      e.peer("b0000002", "KRIS", "crystal", 2, 22, 1)
      e.peer("b0000003", "MAY", "emerald", 3, 44, 1, "g3:4")
      peered = true
    end
    d.check(e.waitFor(function() return Union.playerCount() == 3 end, 8, 200), name .. ": three cross-gen members appear")
    e.wait(40)
    e.place(12, 19, "up")
    e.wait(20)
    d.still(game, i .. "_" .. name .. "_room.png")
    e.place(12, 23, "down")
    e.wait(10)
    for _ = 1, 30 do
      if Map.current == twoF then break end
      U.hold(game, "down", 8)
      e.relay:pump()
    end
    local back = e.waitFor(function() return Map.current == twoF and not require("src.core.game3.warp").isBusy() end, 8, 300)
    d.check(back, name .. ": the exit pad returns to " .. twoF .. " (" .. tostring(Map.current) .. ")")
    G.settleText(game)
    e.wait(20)
    d.check(Union.state == "off", name .. ": leaving stops the Union Room")
    d.still(game, i .. "_" .. name .. "_back_2f.png")
    G.loadMap(game, twoF, 10, 4, "up")
    d.check(G.talksOpen(game), name .. ": the direct corner attendant still talks")
    G.settleText(game)
    if game.data.maps[oneF] then
      local nurse
      for _, o in ipairs(game.data.maps[oneF].objects or {}) do
        local nid = require("src.core.game3.constants").of(version):require("event_objects", "OBJ_EVENT_GFX_NURSE")
        if tonumber(o.graphicsId or o.graphics) == nid then nurse = o end
      end
      if nurse then
        G.loadMap(game, oneF, nurse.x, nurse.y + 2, "up")
        d.check(G.talksOpen(game), name .. ": the 1F nurse still talks")
        G.settleText(game, 2000)
      end
    end
  end

  local twoF = (CENTERS[version] or CENTERS.firered)[1][1]
  G.loadMap(game, twoF, 6, 4, "up")
  e.wait(30)
  U.tap(game, "a")
  e.drive(function() return Space.mapId == Plaza.MAP_ID and Union.state == "main" end, 30)
  e.wait(30)
  e.place(10, 12, "down")
  d.check(game:saveGame() ~= false, "saving in the plaza writes the slot")
  local SaveData = require("src.core.SaveData")
  local Schema = require("src.core.game3.save_schema_firered")
  local raw = love.filesystem.read(SaveData.saveFilename and SaveData.saveFilename() or ("saves/" .. version .. "/slot1.lua"))
  local saved = raw and SaveData.decode(raw)
  local cont = saved and Schema.fromSaveTable(saved)
  d.note("saved map=" .. tostring(saved and saved.map) .. " continue -> " .. tostring(cont and cont.map)
    .. " " .. tostring(cont and cont.x) .. "," .. tostring(cont and cont.y))
  d.check(cont and cont.map == twoF, "continue after a plaza save resolves to the PC 2F (cart continue warp)")
  e.close()
  return d.finish()
end
