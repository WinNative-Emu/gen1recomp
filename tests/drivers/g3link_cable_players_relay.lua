local U = require("tests.drivers.util")

local SEAT = tonumber(os.getenv("G3LP_SEAT") or "0") or 0
local ROOMFILE = os.getenv("G3LP_ROOMFILE")
  or ((os.getenv("TMPDIR") or "/tmp"):gsub("/+$", "") .. "/g3lp_room.txt")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/g3lp"
local VERSION = os.getenv("POKEPORT_VERSION") or "firered"
local TAG = "g3lp_" .. VERSION .. "_seat" .. SEAT
local PEER = 1 - SEAT
local CHAIRS = { [0] = { 4, 5, "right" }, [1] = { 7, 5, "left" } }
local PER = {
  firered = { room = "FR_TRADE_CENTER", center = "FR_VIRIDIAN_CITY_POKEMON_CENTER_2F", gfx = { [0] = "OBJ_EVENT_GFX_RED_NORMAL", [1] = "OBJ_EVENT_GFX_GREEN_NORMAL" } },
  leafgreen = { room = "FR_TRADE_CENTER", center = "FR_VIRIDIAN_CITY_POKEMON_CENTER_2F", gfx = { [0] = "OBJ_EVENT_GFX_RED_NORMAL", [1] = "OBJ_EVENT_GFX_GREEN_NORMAL" } },
  emerald = { room = "EM_TRADE_CENTER", center = "EM_OLDALE_TOWN_POKEMON_CENTER_2F", gfx = { [0] = "OBJ_EVENT_GFX_RIVAL_BRENDAN_NORMAL", [1] = "OBJ_EVENT_GFX_RIVAL_MAY_NORMAL" } },
}

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. TAG .. " " .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function now() return love.timer.getTime() end

return function(game)
  print("PASS " .. TAG .. " driver_started")
  local Link, Client
  local function finish()
    if Link then pcall(Link.closeLink, "driver_done") end
    if Client then pcall(Client.disconnect) end
    print((failures == 0 and "PASS " or "FAIL ") .. TAG .. " cable_players failures=" .. failures)
    love.event.quit(failures == 0 and 0 or 1)
    U.wait(10)
  end
  local P = PER[VERSION]
  if not result(P ~= nil, "version has a Trade Center") then return finish() end

  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = SEAT == 0 and "AAA" or "BBB", gender = SEAT })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Objects = require("src.core.game3.objects")
  local VO = require("src.core.game3.virtual_objects")
  local LP = require("src.core.game3.link.link_players")
  local Game3Link = require("src.link.Game3Link")
  local RelayTransport = require("src.core.game3.link.relay_transport")
  local ArenaData = require("src.online.ArenaData")
  local C = require("src.core.game3.constants").of(VERSION)
  Link = require("src.core.game3.link")
  Client = require("src.online.Client")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end
  local g3 = Runtime._game or game
  session.name = SEAT == 0 and "AAA" or "BBB"

  local peer = { tiles = {}, moving = false, sub = false }
  local function observe()
    local r = LP.remotes()[PEER]
    if not r then return end
    local function push(x, y)
      local k = x .. "," .. y
      if peer.tiles[#peer.tiles] ~= k then peer.tiles[#peer.tiles + 1] = k end
    end
    if #peer.tiles == 0 then push(r.prevX, r.prevY) end
    if not r.moving then push(r.x, r.y) end
    if r.moving then peer.moving = true end
    local vo = VO.get(LP.VOBJ_BASE + PEER)
    if vo and ((vo.px and vo.px % 16 ~= 0) or (vo.py and vo.py % 16 ~= 0)) then peer.sub = true end
  end
  local function waitUntil(pred, seconds)
    local deadline = now() + (seconds or 10)
    while not pred() do
      if now() > deadline then return false end
      U.wait(1)
      observe()
    end
    return true
  end

  local profile, why = ArenaData.liveProfile3(g3, "g3_link")
  if not result(profile ~= nil, "live Gen 3 profile (" .. tostring(why) .. ")") then return finish() end
  local okC, errC = Client.connect({ name = session.name, profiles = { profile },
    presence = { where = "game", status = "busy" } })
  result(okC, "Client.connect to " .. tostring(os.getenv("POKEPORT_RELAY_ADDR")) .. " " .. tostring(errC))
  if not result(waitUntil(function() return Client.state() == "online" end, 10), "online on the relay") then
    return finish()
  end
  if SEAT == 0 then
    os.remove(ROOMFILE)
    Client.createRoom({ intent = "trade", profile = profile, seats = 2 })
    if not result(waitUntil(function() return Client.room() ~= nil end, 10), "seat 0 opened a room") then
      return finish()
    end
    local fh = io.open(ROOMFILE, "w")
    if fh then fh:write(tostring(Client.room().room)); fh:close() end
  else
    local roomId
    waitUntil(function()
      local fh = io.open(ROOMFILE, "r")
      if fh then roomId = fh:read("*l"); fh:close() end
      return roomId ~= nil and roomId ~= ""
    end, 15)
    if not result(roomId ~= nil, "seat 1 found the room id") then return finish() end
    Client.joinRoom(roomId, "player", profile)
  end
  local paired = waitUntil(function()
    local room = Client.room()
    return room and Client.seat() ~= nil and #(room.players or {}) == 2 and room.match ~= nil
  end, 15)
  if not result(paired, "both seats paired") then return finish() end
  result(Client.seat() == SEAT, "this process holds seat " .. SEAT)
  local live = Game3Link.attach(RelayTransport.new(Client.roomSession()), {
    seat = Client.seat(), seats = 2, game = g3, linkType = Game3Link.LINKTYPE.TRADE,
  })
  Link.attach(live)
  if not result(waitUntil(function() return live:isReady() end, 10), "Game3Link handshake is full") then
    return finish()
  end

  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local Message = require("src.ui.game3.message")
  local Choice = require("src.ui.game3.choice")
  local Stack = require("src.ui.game3.stack")
  local function cableState() return Link.getVar(Space.vm and Space.vm.ctx, Link.VAR_CABLE_CLUB_STATE) end
  local door = { x = 5, y = 4 }
  for _, w in ipairs((Link.mapDef(P.center) or {}).warps or {}) do
    if w.destMap == P.room or w.map == P.room then door = { x = w.x, y = w.y } end
  end
  session.dynamicWarp = { map = P.center, warpId = -1, x = door.x, y = door.y }
  session.warpDestination = nil

  -- pokefirered/src/overworld.c:2194
  local ax, ay = 5 + SEAT, 8
  Map.load(nil, g3, P.room, { x = ax, y = ay, facing = "up" })
  Player.cellX, Player.cellY, Player.facing = ax, ay, "up"
  Player.px, Player.py = ax * 16, ay * 16
  Player.targetX, Player.targetY = ax, ay
  if not result(waitUntil(function() return LP.remotes()[PEER] ~= nil end, 10), "peer link player spawned") then
    return finish()
  end
  Link.setVar(Space.vm and Space.vm.ctx, Link.VAR_CABLE_CLUB_STATE, Link.USING.TRADE_CENTER)
  waitUntil(function() return false end, 1)

  local function pageHas(sub) return tostring(Message.currentPage() or ""):find(sub, 1, true) ~= nil end
  local function vmBusy() return Space.vm and Space.vm:isRunning() end
  local function cardOpen() local top = Stack.top(); return top and top.id == "trainer" end
  local function mash(pred, seconds, btn)
    local deadline = now() + (seconds or 10)
    while not pred() do
      if now() > deadline then return false end
      U.tap(game, btn or "a"); U.wait(5); observe()
    end
    return true
  end
  local function face(dir)
    for _ = 1, 20 do
      if Player.facing == dir and not Player.moving then break end
      table.insert(game.input.pressQueue, dir); game.input.state[dir] = true
      U.wait(1)
    end
    game.input.state[dir] = false
    U.wait(10)
  end
  -- pokeemerald/src/overworld.c:2745
  local peerName = SEAT == 0 and "BBB" or "AAA"
  if SEAT == 0 then
    face("right")
    result(Player.facing == "right", "seat 0 faces the partner")
    local calm = 0
    waitUntil(function()
      local r = LP.remotes()[PEER]
      calm = (r and r.busy ~= true and not vmBusy()) and calm + 1 or 0
      return calm >= 90
    end, 15)
    U.tap(game, "a")
    result(vmBusy(), "A on the link player runs a native script")
    result(waitUntil(function() return pageHas(peerName) end, 8), "read-trainer-card text names " .. peerName)
    print("INFO " .. TAG .. " card text " .. tostring(Message.currentPage()))
    result(mash(cardOpen, 15), "the partner's trainer card opens")
    local TC = package.loaded["src.ui.game3.trainer_card"]
    result(TC and TC._session and tostring(TC._session.name) == peerName,
      "the card shown is the partner's " .. tostring(TC and TC._session and TC._session.name))
    U.wait(20)
    U.shot(game, DIR .. "/" .. TAG .. "_partner_card.png")
    waitUntil(function() return false end, 5)
    result(mash(function() return not cardOpen() and not vmBusy() end, 15, "b"), "the card closes back to the room")
  else
    local busyFor = 0
    waitUntil(function()
      local r = LP.remotes()[PEER]
      busyFor = (r and r.busy == true) and busyFor + 1 or 0
      return busyFor >= 120
    end, 20)
    face("left")
    U.tap(game, "a")
    result(waitUntil(function() return pageHas("busy") end, 8), "a busy partner gets the native too-busy text")
    print("INFO " .. TAG .. " busy text " .. tostring(Message.currentPage()))
    mash(function() return not vmBusy() and not Message.isOpen() end, 10)
    waitUntil(function() local r = LP.remotes()[PEER]; return r and r.busy ~= true end, 20)
  end
  waitUntil(function() return false end, 1)
  peer.tiles, peer.moving, peer.sub = {}, false, false

  local function stepTo(dir)
    local sx, sy = Player.cellX, Player.cellY
    local deadline = now() + 8
    while Player.cellX == sx and Player.cellY == sy and not Player.moving do
      if now() > deadline then return false end
      table.insert(game.input.pressQueue, dir)
      game.input.state[dir] = true
      U.wait(1); observe()
    end
    game.input.state[dir] = false
    waitUntil(function() return not Player.moving end, 8)
    return true
  end
  local chair = CHAIRS[SEAT]
  local path = SEAT == 0 and { "up", "up", "left", "up" } or { "up", "up", "right", "up" }
  local shotMid = false
  for _, dir in ipairs(path) do
    if not stepTo(dir) then break end
    if not shotMid and peer.moving then
      shotMid = true
      U.shot(game, DIR .. "/" .. TAG .. "_peer_walking.png")
    end
    local r, pc = LP.remotes()[PEER], CHAIRS[PEER]
    if not peer.shotSeated and r and r.x == pc[1] and r.y == pc[2] and not r.moving and r.facing == pc[3] then
      peer.shotSeated = true
      U.shot(game, DIR .. "/" .. TAG .. "_peer_seated.png")
    end
  end
  result(Player.cellX == chair[1] and Player.cellY == chair[2], "walked onto own chair " .. Player.cellX .. "," .. Player.cellY)
  result(Player.facing == chair[3], "own chair forces facing " .. tostring(Player.facing))

  local pc = CHAIRS[PEER]
  local seated = waitUntil(function()
    local r = LP.remotes()[PEER]
    return r and r.x == pc[1] and r.y == pc[2] and not r.moving and r.facing == pc[3]
  end, 20)
  local r = LP.remotes()[PEER] or {}
  print("INFO " .. TAG .. " peer tiles " .. table.concat(peer.tiles, " ") .. " facing=" .. tostring(r.facing))
  result(seated, "peer seated at " .. pc[1] .. "," .. pc[2] .. " facing " .. pc[3])
  result(peer.tiles[1] == (5 + PEER) .. ",8", "peer started at arrival x+seat " .. tostring(peer.tiles[1]))
  result(peer.moving and peer.sub and #peer.tiles >= 4, "peer walked with sub-tile motion")
  local vo = VO.get(LP.VOBJ_BASE + PEER)
  local want = C:require("event_objects", P.gfx[PEER])
  result(vo ~= nil and vo.graphicsId == want, "peer drawn as " .. P.gfx[PEER] .. " (" .. tostring(vo and vo.graphicsId) .. ")")
  result(Objects.blocks(pc[1], pc[2]) == true, "peer blocks its chair")
  local drawn = false
  for _, eo in ipairs(Objects.forDraw()) do
    if eo.virtualId == LP.VOBJ_BASE + PEER and eo.cellX == pc[1] and eo.cellY == pc[2] then drawn = true end
  end
  result(drawn, "peer is in the field draw list")
  U.shot(game, DIR .. "/" .. TAG .. "_both_seated.png")

  local Menu = require("src.ui.game3.link_trade_menu")
  local function where()
    return "map=" .. tostring(Link.currentMap()) .. " xy=" .. Player.cellX .. "," .. Player.cellY .. " facing=" .. tostring(Player.facing)
      .. " vm=" .. tostring(vmBusy()) .. " choice=" .. tostring(Choice.active) .. " msg=" .. tostring(Message.currentPage())
      .. " menu=" .. tostring(Menu.isOpen() and Menu.cb) .. " top=" .. tostring(Stack.top() and Stack.top().id)
  end
  if waitUntil(function() return Menu.isOpen() and Menu.cb == "main" and (Menu.fadeDir or 0) == 0 end, 20) then
    for _ = 1, 20 do
      if Menu.pos == 12 then break end
      U.tap(game, "down"); U.wait(3)
    end
    U.tap(game, "a")
    waitUntil(function() return Menu.cb == "cancel_prompt" end, 10)
    U.wait(10)
    U.tap(game, "a")
    result(mash(function() return not Menu.isOpen() and not vmBusy() and not Message.isOpen() end, 30),
      "both cancel out of the trade menu")
  end
  print("INFO " .. TAG .. " before walk out " .. where())
  local function walkOut()
    local route = SEAT == 0 and { "down", "right", "down", "down" } or { "down", "left", "down", "down" }
    for _, dir in ipairs(route) do stepTo(dir) end
    local deadline = now() + 10
    while not Choice.active do
      if now() > deadline then print("INFO " .. TAG .. " no prompt " .. where()); return false end
      if not vmBusy() then U.hold(game, "down", 8) end
      U.wait(4); observe()
    end
    U.wait(20)
    U.tap(game, "a")
    -- pokefirered/data/scripts/cable_club.inc:1394
    local ok = mash(function() return Link.currentMap() == P.center and not vmBusy() end, 20)
    print("INFO " .. TAG .. " walk out " .. where())
    return ok
  end
  local function afterLeaving(label)
    result(Link.currentMap() == P.center, label .. " back on the 2F")
    result(Link.link == nil, label .. " link closed")
    result(cableState() == 0 or cableState() == Link.USING.TRADE_CENTER, label .. " cable state " .. tostring(cableState()))
    result(game:saveGame() ~= false, label .. " saving after leaving writes the slot")
  end
  if SEAT == 1 then
    local ok = walkOut()
    result(ok, "seat 1 confirms leave at the south exit and warps out")
    afterLeaving("leaver")
  else
    local gone = waitUntil(function() return LP.remotes()[PEER] == nil end, 40)
    result(gone, "the departed partner's link player is removed")
    waitUntil(function() return false end, 1)
    result(Link.currentMap() == P.room, "seat 0 stays in the room after the partner leaves")
    result(Link.link ~= nil and Link.link:isOpen(), "seat 0 keeps its link open")
    result(Link.link and #Link.link:players() == 1, "the departed seat is gone from the link players")
    result(VO.get(LP.VOBJ_BASE + PEER) == nil and not Objects.blocks(pc[1], pc[2]), "the partner's sprite is gone and its chair is free")
    U.shot(game, DIR .. "/" .. TAG .. "_partner_left.png")
    local ok = walkOut()
    result(ok, "seat 0 leaves on its own afterwards")
    afterLeaving("last player")
  end
  return finish()
end
