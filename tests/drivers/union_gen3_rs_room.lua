local U = require("tests.drivers.util")
local G = require("tests.drivers.union_gen3_util")

local CENTERS = { "OLDALE_TOWN", "MAUVILLE_CITY", "EVER_GRANDE_CITY", "PACIFIDLOG_TOWN" }

return function(game)
  local version = G.version()
  local d = G.start("union_gen3_rs_room_" .. version)
  local session = G.boot(d, game, version == "sapphire" and 1 or 0)
  if not session then return d.finish() end
  local Space = require("src.core.game3.scripting.space")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Message = require("src.ui.game3.message")
  local Union = require("src.core.game3.link.union_room")
  local Plaza = require("src.core.game3.link.union_plaza_map")
  local UnionRs = require("src.core.game3.rse.union_rs")
  local Screen = require("src.ui.game3.union_room")
  local Client = require("src.online.Client")
  local Warp = require("src.core.game3.warp")
  local prefix = G.prefix()
  local ROOM = prefix .. "UNION_ROOM"
  d.check(Plaza.MAP_ID == ROOM, "the added room id is " .. ROOM)
  d.check(game.data.maps[ROOM] ~= nil, "the RS Union Room map is built at load")
  local e = G.env(d, game, "ME")
  if not d.check(e.connect(), "online on the fake relay") then return d.finish() end

  local function enter(name, idx)
    local twoF = prefix .. name .. "_POKEMON_CENTER_2F"
    local def = game.data.maps[twoF]
    if not d.check(def ~= nil and UnionRs.isCenter(twoF), name .. ": 2F has the added entrance") then return false end
    d.check(def.midLayout:midAt(2, 1) == def.midLayout:midAt(5, 1), name .. ": the added door uses the bay door tile")
    G.loadMap(game, twoF, 1, 3, "up")
    e.wait(20)
    d.check(require("src.core.game3.virtual_objects").get(UnionRs.VOBJ_ID) ~= nil, name .. ": the attendant stands by the door")
    if idx == 1 then d.still(game, "rs_" .. idx .. "_" .. name .. "_2f_attendant.png") end
    U.tap(game, "a")
    local sawWelcome = false
    local entered = e.drive(function()
      if Message.isOpen() and Message.currentPage():find("UNION ROOM", 1, true) then sawWelcome = true end
      return Map.current == ROOM and Union.state == "main" and not Warp.isBusy()
    end, 40)
    d.check(sawWelcome, name .. ": the attendant greets with the UNION ROOM text")
    d.note(name .. " map=" .. tostring(Map.current) .. " union=" .. tostring(Union.state) .. " at "
      .. tostring(Player.cellX) .. "," .. tostring(Player.cellY))
    if not d.check(entered, name .. ": the attendant saves and walks the player in") then
      d.shot(game, "rs_" .. idx .. "_" .. name .. "_enter_failed.png")
      return false
    end
    d.check(e.waitFor(function() return Client.plaza() ~= nil end, 5, 60), name .. ": joined the relay plaza")
    local join = Client.plazaJoinInfo and Client.plazaJoinInfo("union")
    d.check(join and join.avatar and join.avatar.style == "player" and join.opts and join.opts.xgen ~= nil,
      name .. ": RS joins with style player over xgen")
    return true, twoF
  end

  local function leave(name, twoF)
    e.place(12, 23, "down")
    e.wait(10)
    for _ = 1, 30 do
      if Map.current == twoF then break end
      U.hold(game, "down", 8)
      e.relay:pump()
    end
    local back = e.waitFor(function() return Map.current == twoF and not Warp.isBusy() end, 8, 300)
    d.check(back, name .. ": the exit pads return to the same 2F")
    e.wait(30)
    d.check(Player.cellX == UnionRs.FRONT.x and Player.cellY == UnionRs.FRONT.y,
      name .. ": the player steps out of the added door (" .. tostring(Player.cellX) .. "," .. tostring(Player.cellY) .. ")")
    d.check(Union.state == "off", name .. ": leaving stops the Union Room")
  end

  local ok, twoF = enter(CENTERS[1], 1)
  if not ok then return d.finish() end
  e.peer("b0000001", "RED", "red", 1, 11, 0)
  e.peer("b0000002", "KRIS", "crystal", 2, 22, 1)
  e.peer("b0000003", "MAY", "emerald", 3, 44, 1, "g3:4")
  d.check(e.waitFor(function() return Union.playerCount() == 3 end, 8, 200), "three cross-gen members appear in the RS room")
  e.wait(40)
  e.place(12, 19, "up")
  e.wait(20)
  d.still(game, "rs_room_mixed.png")
  G.resize(240, 160)
  d.still(game, "rs_room_mixed_native.png")
  G.resize(844, 390)
  d.still(game, "rs_room_mixed_phone.png")
  G.resize(960, 640)
  local slot
  for s = 1, Plaza.CAP do
    local p = Union.players[s]
    if p and p.name == "RED" then slot = s end
  end
  local cx, cy = Plaza.cellFor(slot or 1)
  e.place(cx, cy + 1, "up")
  e.wait(10)
  U.tap(game, "a")
  local menu = false
  for _ = 1, 400 do
    if Screen.isOpen() then menu = true break end
    if Message.isOpen() and Message.isWaiting() and not Message._stay then U.tap(game, "a") end
    e.wait(1)
  end
  d.check(menu, "talking to a Gen 1 member opens BATTLE / TRADE")
  d.still(game, "rs_room_xg_menu.png")
  U.tap(game, "b")
  G.settleText(game)
  e.wait(10)
  leave(CENTERS[1], twoF)
  G.loadMap(game, twoF, 4, 4, "up")
  d.check(G.talksOpen(game), "the Colosseum attendant still talks")
  G.settleText(game)
  local oneF = UnionRs.centers[twoF].oneF
  local origin = UnionRs.originFor(twoF)
  d.check(origin ~= nil, "the origin nurse front resolves")
  G.loadMap(game, oneF, origin.x, origin.y, "up")
  d.check(G.talksOpen(game), "the 1F nurse still talks")
  G.settleText(game, 2000)

  for i = 2, #CENTERS do
    local okI, tf = enter(CENTERS[i], i)
    if okI then leave(CENTERS[i], tf) end
  end

  local okS, saveCenter = enter(CENTERS[3], 9)
  if okS then
    e.place(10, 12, "down")
    e.wait(10)
    local o = UnionRs.originFor(saveCenter)
    d.check(game:saveGame() ~= false, "saving inside the added room writes the slot")
    local SaveData = require("src.core.SaveData")
    local Schema = require("src.core.game3.save_schema_firered")
    local saved = SaveData.decode(love.filesystem.read(SaveData.saveFilename()))
    d.note("saved " .. tostring(saved.map) .. " " .. tostring(saved.x) .. "," .. tostring(saved.y) .. " flags="
      .. tostring(saved.specialSaveWarpFlags))
    d.check(saved.map == o.map and saved.x == o.x and saved.y == o.y,
      "the slot records the player in front of the origin nurse desk")
    e.close()
    e.wait(10)
    local cont = Schema.fromSaveTable(saved)
    require("src.core.game3.options").bind(cont, game.options)
    game:adoptSave(cont, true)
    game:_enterField(cont, "continue")
    U.wait(60)
    G.settleText(game)
    U.wait(30)
    d.still(game, "rs_continue_nurse_front.png")
    d.check(Map.current == o.map and Player.cellX == o.x and Player.cellY == o.y and Player.facing == "up",
      "reload lands facing the nurse (" .. tostring(Map.current) .. " " .. tostring(Player.cellX) .. ","
      .. tostring(Player.cellY) .. " " .. tostring(Player.facing) .. ")")
  end
  e.close()
  return d.finish()
end
