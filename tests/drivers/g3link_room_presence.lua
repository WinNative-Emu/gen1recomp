local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/g3link_presence"

local VERSION = os.getenv("POKEPORT_VERSION") or "firered"
local PER = {
  firered = { center = "FR_VIRIDIAN_CITY_POKEMON_CENTER_2F", trade = "FR_TRADE_CENTER" },
  leafgreen = { center = "FR_VIRIDIAN_CITY_POKEMON_CENTER_2F", trade = "FR_TRADE_CENTER" },
  emerald = { center = "EM_OLDALE_TOWN_POKEMON_CENTER_2F", trade = "EM_TRADE_CENTER" },
}
local CENTER_2F = PER[VERSION].center
local Plaza = require("src.core.game3.link.union_plaza_map")

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
  if failures == 0 then
    print("PASS g3link_room_presence")
    love.event.quit(0)
  else
    print("FAIL g3link_room_presence failures=" .. failures)
    love.event.quit(1)
  end
end

local function now() return love.timer.getTime() end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "RED" })
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
  local Link = require("src.core.game3.link")
  local Union = require("src.core.game3.link.union_room")
  local Client = require("src.online.Client")
  local Relay = require("tests.support.fake_relay")
  local VirtualObjects = require("src.core.game3.virtual_objects")
  local Family = require("src.core.game3.link.family")
  local UNION_ROOM = Plaza.MAP_ID

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end
  Party.giveMon(session, 25, 12)
  Party.giveMon(session, 1, 10)

  local relay = Relay.new({ clock = function() return now() end })
  local me = relay:seat("a0000001", "RED")
  Client.configure({ relayAddress = "fake:1", connect = function() return me.transport end })

  local function ctx() return Space.vm and Space.vm.ctx end
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
  local function drive(cond, seconds)
    local t0 = now()
    while not cond() and now() - t0 < (seconds or 10) do
      if Choice.active or SaveMenu.isOpen() or Message.isOpen() then U.tap(game, "a") end
      wait(6)
    end
    return cond()
  end

  local live = Link.liveProfile()
  if not result(live ~= nil, "the live g3 profile computes") then return finish() end
  local function peer(id, name, trainerId, gender, version, status)
    local s = relay:seat(id, name)
    relay:handle(s, { type = "lobby_hello", protocol = 3, name = name, profiles = { live },
      presence = { where = "launcher", status = status or "idle", version = version } })
    s.avatar = { name = name, trainerId = trainerId, gender = gender, version = version }
    relay:handle(s, { type = "plaza_join", kind = "union", cap = 40, xgen = 1, profile = live, avatar = s.avatar })
    return s
  end

  Link.connect()
  result(waitFor(function() return Client.state() == "online" end, 5, 120), "online on the relay")
  result(Link.adapterConnected(), "the adapter reads connected")
  Map.load(nil, game, CENTER_2F, { x = 6, y = 4, facing = "up" })
  wait(60)
  Flags.setFlag(Space.store, ctx(), Family.flag(VERSION, "FLAG_SYS_POKEDEX_GET"), true)
  if VERSION == "emerald" then
    -- pokeemerald/data/scripts/cable_club.inc:104
    Flags.setVar(Space.store, ctx(), Family.var(VERSION, "VAR_CABLE_CLUB_TUTORIAL_STATE"), 2)
  end
  place(6, 4, "up")
  wait(12)
  U.tap(game, "a")
  local entered = drive(function() return Space.mapId == UNION_ROOM and Union.state == "main" end, 25)
  if not result(entered, "the attendant walks the player into the Union Room") then
    print("[driver] map=" .. tostring(Space.mapId) .. " union=" .. tostring(Union.state))
    U.shot(game, DIR .. "/" .. VERSION .. "_presence_enter_failed.png")
    return finish()
  end

  local statuses = { "chatting", "trading", "battling", "idle", "idle", "idle", "idle", "idle", "idle", "idle", "idle", "idle" }
  local names = { "BLUE", "GREEN", "GOLD", "SILVER", "MAY", "LEAF", "WALLY", "BRENDAN", "KRIS", "ETHAN", "LYRA", "DAWN" }
  local versions = { "firered", "leafgreen", "emerald", "ruby", "sapphire" }
  local crowd = {}
  for i, name in ipairs(names) do
    crowd[i] = peer(string.format("c%07x", i), name, 0x100 + i * 13, i % 2, versions[(i - 1) % #versions + 1], statuses[i])
  end
  result(waitFor(function() return Union.playerCount() == #names end, 10, 120), "the peers appear in the plaza")
  result(waitFor(function() return VirtualObjects.count() == #names end, 5, 60), "as avatars")
  wait(40)

  local LinkTags = package.loaded["src.ui.game3.link_tags"]
  result(LinkTags ~= nil, "the badge layer is loaded in the Union Room")
  local src = LinkTags and LinkTags.sources()
  local kinds, named = {}, 0
  for slot = 1, Plaza.CAP do
    local p = Union.players[slot]
    local tag = p and src and src.byVobj[Union.vobjId(slot)]
    if tag then
      if tag.name == p.name then named = named + 1 end
      if tag.kind then kinds[tag.kind] = true end
    end
  end
  result(named == #names, "every avatar carries its relay name (" .. named .. ")")
  result(kinds.chat and kinds.trade and kinds.battle, "chatting, trading and battling each get an icon")
  result(src and src.player and src.player.name == "RED", "the player's own badge reads RED")

  place(12, 15, "up")
  wait(10)
  U.still(game, DIR .. "/" .. VERSION .. "_presence_01_badges_and_icons.png")

  local homes = {}
  for slot = 1, Plaza.CAP do
    if Union.players[slot] then homes[slot] = { Union.cellFor(slot) } end
  end
  place(1, 22, "up")
  local moved, stepping, busyMoved = {}, false, false
  for _ = 1, 1500 do
    wait(1)
    for slot, h in pairs(homes) do
      local rec = VirtualObjects.get(Union.vobjId(slot))
      if rec and (rec.x ~= h[1] or rec.y ~= h[2]) then
        moved[slot] = true
        if Union.memberStatusKind(Union.players[slot]) then busyMoved = true end
        if rec.moving and not stepping then
          stepping = true
          place(12, 15, "up")
          wait(8)
          U.still(game, DIR .. "/" .. VERSION .. "_presence_02_wander_mid_step.png")
          place(1, 22, "up")
        end
      end
    end
  end
  local n = 0
  for _ in pairs(moved) do n = n + 1 end
  result(n >= 3, "idle avatars wander off their cells (" .. n .. ")")
  result(not busyMoved, "chatting, trading and battling avatars stay put")

  place(12, 15, "up")
  wait(30)
  U.still(game, DIR .. "/" .. VERSION .. "_presence_03_after_wander.png")

  place(12, 22, "down")
  wait(10)
  for _ = 1, 20 do
    if Map.current == CENTER_2F then break end
    U.hold(game, "down", 8)
    relay:pump()
  end
  result(waitFor(function() return Map.current == CENTER_2F end, 8, 300), "the exit warps back to the 2F")
  wait(20)
  result(LinkTags.sources() == nil, "no badges outside the link rooms")

  local LinkPlayers = require("src.core.game3.link.link_players")
  local inbox = {}
  local fake = {
    role = "host",
    update = function() end,
    isOpen = function() return true end,
    isReady = function() return true end,
    getSeat = function() return 0 end,
    send = function() return true end,
    take = function(_, kind)
      for i, m in ipairs(inbox) do
        if m.type == kind then return table.remove(inbox, i) end
      end
      return nil
    end,
    players = function()
      return { { seat = 0, name = "RED", gender = 0, version = "firered" },
               { seat = 1, name = "MAY", gender = 1, version = "emerald" } }
    end,
  }
  Client.disconnect()
  Map.load(nil, game, PER[VERSION].trade, { x = 4, y = 5, facing = "right" })
  place(4, 5, "right")
  wait(30)
  Link.link = fake
  Link.startPump()
  inbox[#inbox + 1] = { type = LinkPlayers.MSG, seat = 1, map = "tradeCenter", x = 7, y = 5, facing = "left", busy = true }
  wait(30)
  local tc = LinkTags.sources()
  local mayTag = tc and tc.byVobj[LinkPlayers.VOBJ_BASE + 1]
  result(mayTag and mayTag.name == "MAY", "the Trade Center partner wears her name")
  result(mayTag and mayTag.kind == "trade", "and a trade icon while she is busy at the table")
  result(tc and tc.player and tc.player.name == "RED", "and the player keeps his badge in the link room")
  U.still(game, DIR .. "/" .. VERSION .. "_presence_04_trade_center.png")
  Link.link = nil
  wait(4)
  finish()
end
