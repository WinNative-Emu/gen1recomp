local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/g3link_south_exit"

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  local Link = package.loaded["src.core.game3.link"]
  if Link then pcall(Link.reset) end
  local Client = package.loaded["src.online.Client"]
  if Client then pcall(Client.disconnect) end
  print((failures == 0 and "PASS" or "FAIL") .. " g3link_south_exit failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
  U.wait(10)
end

local function now() return love.timer.getTime() end

local PER = {
  firered = {
    center = "FR_VIRIDIAN_CITY_POKEMON_CENTER_2F", room = "FR_TRADE_CENTER",
    attendant = { 10, 4 }, prompt = "Text_TerminateLinkIfYouLeaveRoom", script = "TradeCenter_ConfirmLeaveRoom",
    newGame = { action = "new_game", name = "RED" },
  },
  emerald = {
    center = "EM_OLDALE_TOWN_POKEMON_CENTER_2F", room = "EM_TRADE_CENTER",
    attendant = { 10, 3 }, prompt = "Text_TerminateLinkConfirmation", script = "EventScript_ConfirmLeaveCableClubRoom",
    newGame = { action = "new_game", name = "MAY", gender = 1 },
  },
}

return function(game)
  print("PASS driver_started")
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  local version = os.getenv("POKEPORT_VERSION") or "firered"
  local P = PER[version] or PER.firered
  game:_handleBootAction(P.newGame)
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local Player = require("src.core.game3.player")
  local Message = require("src.ui.game3.message")
  local Choice = require("src.ui.game3.choice")
  local SaveMenu = require("src.ui.game3.save_menu")
  local Party = require("src.core.game3.party")
  local RomText = require("src.core.game3.rom_text")
  local Link = require("src.core.game3.link")
  local Family = require("src.core.game3.link.family")
  local Client = require("src.online.Client")
  local Relay = require("tests.support.fake_relay")
  local SaveData = require("src.core.SaveData")
  local Schema = require("src.core.game3.save_schema_firered")

  local session = Runtime.getSession()
  if not result(session ~= nil, version .. " new game reached the field") then return finish() end
  while #(session.party or {}) < 2 do Party.giveMon(session, 25, 12) end

  local relay = Relay.new({ clock = function() return now() end })
  local me = relay:seat("a0000001", "ME")
  Client.configure({ relayAddress = "fake:1", connect = function() return me.transport end })

  local function ctx() return Space.vm and Space.vm.ctx end
  local cableVar = Family.var(version, "VAR_CABLE_CLUB_STATE")
  local function cableState() return tonumber(Flags.getVar(Space.store, ctx(), cableVar)) or 0 end
  local function place(x, y, facing)
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing
    game.session.x, game.session.y, game.session.facing = x, y, facing
  end
  local function wait(n)
    for _ = 1, n do
      relay:pump()
      U.wait(1)
    end
  end
  local function waitFor(cond, seconds, frames)
    local t0, n = now(), 0
    while not cond() do
      relay:pump()
      U.wait(1)
      n = n + 1
      if now() - t0 > (seconds or 5) and n > (frames or 60) then return false end
    end
    return true
  end
  local function pageHas(text)
    local page = Message.isOpen() and Message.currentPage() or ""
    return page:find(text, 1, true) ~= nil
  end
  local okWait, waitPlain = pcall(RomText.plain, "CableClub_Text_PleaseWaitBCancel")
  local waitText = okWait and waitPlain:match("^[^\n]+") or "\0"
  local function drive(cond, seconds)
    local t0 = now()
    while not cond() and now() - t0 < (seconds or 10) do
      if Choice.active or SaveMenu.isOpen() or (Message.isOpen() and not pageHas(waitText)) then
        U.tap(game, "a")
      end
      wait(6)
    end
    return cond()
  end

  local live = Link.liveProfile()
  if not result(live ~= nil, "the live g3 profile computes") then return finish() end
  Link.connect()
  result(waitFor(function() return Client.state() == "online" end, 5, 120), "the Client is online on the relay")

  if version == "emerald" then
    Flags.setVar(Space.store, ctx(), Family.var("emerald", "VAR_CABLE_CLUB_TUTORIAL_STATE"), 2)
  end
  Map.load(nil, game, P.center, { x = P.attendant[1], y = P.attendant[2], facing = "up" })
  wait(60)
  Flags.setFlag(Space.store, ctx(), Family.flag(version, "FLAG_SYS_POKEDEX_GET"), true)
  place(P.attendant[1], P.attendant[2], "up")
  wait(12)
  U.tap(game, "a")
  local queued = drive(function() return relay.queue["a0000001"] ~= nil end, 25)
  if not result(queued, "TRADE CENTER > JOIN queues at the Direct Corner") then
    U.shot(game, DIR .. "/" .. version .. "_queue_failed.png")
    return finish()
  end

  local blue = relay:seat("b0000002", "BLUE")
  relay:handle(blue, { type = "lobby_hello", protocol = 3, name = "BLUE", profiles = { live } })
  relay:handle(blue, { type = "direct_queue", activity = "trade", ruleset = "g3_link", auto = true,
    profile = live, avatar = { name = "BLUE", trainerId = 0x2222, gender = 0, version = version },
    preview = { 4 } })
  result(waitFor(function() return Link.link ~= nil end, 5, 120), "the link attaches")
  local hello = {}
  for k, v in pairs(Link.link.myHello) do hello[k] = v end
  hello.name = "BLUE"
  hello.game3 = { cacheVersion = Link.link.myHello.game3.cacheVersion,
    nativeVersion = Link.link.myHello.game3.nativeVersion, linkType = Link.link.linkType,
    trainerId = 0x2222, gender = 0, seat = 1 }
  relay:handle(blue, { type = "room_msg", seq = 1, msg = hello })

  local warped = drive(function() return Space.mapId == P.room and not (Space.vm and Space.vm:isRunning()) end, 30)
  if not result(warped, "the attendant walks the player into the trade center") then
    U.shot(game, DIR .. "/" .. version .. "_no_room.png")
    return finish()
  end
  result(cableState() == Link.USING.TRADE_CENTER, "VAR_CABLE_CLUB_STATE = USING_TRADE_CENTER")
  result(waitFor(function() return Link.link and Link.link:isReady() end, 5, 120), "the link handshake completed")
  wait(30)
  print("[driver] room pos " .. Player.cellX .. "," .. Player.cellY .. " facing " .. tostring(Player.facing))
  U.shot(game, DIR .. "/" .. version .. "_01_room.png")

  local promptText = RomText.plain(P.prompt):match("^[^\n]+")
  local function walkToExit()
    local t0 = now()
    while now() - t0 < 10 and not (Choice.active and pageHas(promptText)) do
      if Message.isOpen() and not Choice.active and not pageHas(promptText) then U.tap(game, "a") end
      if not Message.isOpen() and not (Space.vm and Space.vm:isRunning()) then U.hold(game, "down", 8) end
      wait(4)
    end
    return Choice.active and pageHas(promptText)
  end

  local prompted = walkToExit()
  print("[driver] exit pos " .. Player.cellX .. "," .. Player.cellY .. " map " .. tostring(Space.mapId))
  result(prompted, P.script .. " asks to terminate the link at the south exit")
  waitFor(function() return not Message.isTyping() end, 3, 120)
  U.shot(game, DIR .. "/" .. version .. "_02_prompt.png")
  if not prompted then return finish() end

  result(Choice.cursor == nil or Choice.cursor == 1, "the cursor starts on YES")
  U.tap(game, "down")
  wait(6)
  U.tap(game, "a")
  result(waitFor(function() return not Choice.active and not Message.isOpen()
    and not (Space.vm and Space.vm:isRunning()) end, 5, 120), "NO closes the prompt and releases the player")
  wait(20)
  result(Space.mapId == P.room, "NO keeps the player in the room")
  result(Link.link ~= nil and Link.link:isOpen(), "NO keeps the link open")
  result(cableState() == Link.USING.TRADE_CENTER, "NO keeps VAR_CABLE_CLUB_STATE")
  U.shot(game, DIR .. "/" .. version .. "_03_after_no.png")

  prompted = walkToExit()
  result(prompted, "the prompt comes back on the next DOWN")
  if not prompted then return finish() end
  U.tap(game, "a")
  local exitSent
  local function leaving() return Link.exitQueued or Space.mapId == P.center end
  if version == "emerald" then
    exitSent = waitFor(leaving, 5, 600)
  else
    exitSent = drive(leaving, 10)
  end
  result(exitSent, "YES runs ExitLinkRoom without waiting on the partner")
  U.shot(game, DIR .. "/" .. version .. "_04_please_wait.png")
  local left = waitFor(function() return Space.mapId == P.center and not (Space.vm and Space.vm:isRunning()) end, 15, 600)
  print("[driver] after yes map " .. tostring(Space.mapId) .. " pos " .. Player.cellX .. "," .. Player.cellY)
  result(left, "YES returns the player to the 2F")
  wait(30)
  result(Link.link == nil, "the link is closed")
  result(Client.room() == nil, "the relay room is left")
  result(cableState() == 0, "VAR_CABLE_CLUB_STATE is cleared")
  U.shot(game, DIR .. "/" .. version .. "_05_back_on_2f.png")

  pcall(Client.disconnect)
  wait(10)
  local savedX, savedY = Player.cellX, Player.cellY
  result(game:saveGame() ~= false, "saving after leaving writes the slot")
  local raw = love.filesystem.read("saves/" .. version .. "/slot1.lua")
    or love.filesystem.read("save_" .. version .. ".lua")
  if not result(type(raw) == "string", "the slot is on disk") then return finish() end
  local cont = Schema.fromSaveTable(SaveData.decode(raw))
  require("src.core.game3.options").bind(cont, game.options)
  game:adoptSave(cont, true)
  game:_enterField(cont, "continue")
  local t0 = now()
  while now() - t0 < 10 and (Space.mapId ~= P.center or (Space.vm and Space.vm:isRunning()) or Message.isOpen()) do
    if Message.isOpen() then U.tap(game, "a") end
    U.wait(6)
  end
  U.wait(30)
  print("[driver] continue map " .. tostring(Map.current) .. " pos " .. Player.cellX .. "," .. Player.cellY)
  result(Map.current == P.center and Player.cellX == savedX and Player.cellY == savedY, "CONTINUE resumes on the 2F")
  result(cableState() == 0 and Link.link == nil, "CONTINUE has no link state left over")
  U.shot(game, DIR .. "/" .. version .. "_06_continue.png")
  finish()
end
