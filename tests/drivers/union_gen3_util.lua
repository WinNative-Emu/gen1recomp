local U = require("tests.drivers.util")
local X = require("tests.drivers.em_xa_util")

local G = {}

local function now() return love.timer.getTime() end

function G.version()
  return os.getenv("POKEPORT_VERSION") or "firered"
end

function G.prefix()
  local v = G.version()
  if v == "emerald" then return "EM_" end
  if v == "ruby" then return "RU_" end
  if v == "sapphire" then return "SA_" end
  return "FR_"
end

function G.start(name)
  local d = X.new(name, "/tmp/" .. name)
  return d
end

function G.boot(d, game, gender)
  local session = X.newGame(d, game, gender or 0)
  if not session then return nil end
  X.settle(game)
  U.wait(30)
  local Party = require("src.core.game3.party")
  local Runtime = require("src.core.game3.runtime")
  session = Runtime.getSession()
  local species = G.version() == "ruby" or G.version() == "sapphire" or G.version() == "emerald"
  while #(session.party or {}) < 2 do Party.giveMon(session, species and 280 or 25, 12) end
  local Flags = require("src.core.game3.scripting.flags")
  local Space = require("src.core.game3.scripting.space")
  local flags = require("src.ui.game3.screens").flags(session).IDS
  if flags.SYS_POKEDEX_GET then Flags.setFlag(Space.store, nil, flags.SYS_POKEDEX_GET, true) end
  if flags.SYS_POKEMON_GET then Flags.setFlag(Space.store, nil, flags.SYS_POKEMON_GET, true) end
  return session
end

function G.env(d, game, myName)
  local Client = require("src.online.Client")
  local Relay = require("tests.support.fake_relay")
  local Link = require("src.core.game3.link")
  local Player = require("src.core.game3.player")
  local Message = require("src.ui.game3.message")
  local Choice = require("src.ui.game3.choice")
  local SaveMenu = require("src.ui.game3.save_menu")
  local e = {}
  e.relay = Relay.new({ clock = now })
  e.me = e.relay:seat("a0000001", myName or "ME")
  Client.configure({ relayAddress = "fake:1", connect = function() return e.me.transport end })
  function e.wait(n)
    for _ = 1, n do
      e.relay:pump()
      U.wait(1)
    end
  end
  function e.waitFor(cond, seconds, frames)
    local t0, n = now(), 0
    while not cond() do
      e.relay:pump()
      U.wait(1)
      n = n + 1
      if now() - t0 > (seconds or 5) and n > (frames or 60) then return false end
    end
    return true
  end
  function e.drive(cond, seconds)
    local t0 = now()
    while not cond() and now() - t0 < (seconds or 10) do
      if Choice.active or SaveMenu.isOpen() or Message.isOpen() then U.tap(game, "a") end
      e.wait(6)
    end
    return cond()
  end
  function e.place(x, y, facing)
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing
    game.session.x, game.session.y, game.session.facing = x, y, facing
  end
  function e.connect()
    Link.connect()
    return e.waitFor(function() return Client.state() == "online" end, 5, 120)
  end
  function e.live() return Link.liveProfile() end
  function e.peer(id, name, version, gen, trainerId, gender, style)
    local live = Link.liveProfile()
    local s = e.relay:seat(id, name)
    local profile = { engine = gen, version = version, engineVersion = live.engineVersion,
      apiVersion = live.apiVersion, fingerprint = live.fingerprint, rulesetId = gen == 3 and live.rulesetId or "union",
      kind = "vanilla" }
    if gen == 3 then
      profile = {}
      for k, v in pairs(live) do profile[k] = v end
      profile.version = version
    end
    e.relay:handle(s, { type = "lobby_hello", protocol = 3, name = name, profiles = { profile }, xgen = 1,
      presence = { where = "union", status = "idle", version = version } })
    s.avatar = { name = name, trainerId = trainerId or 7, gender = gender or 0, version = version,
      style = style or "player" }
    e.relay:handle(s, { type = "plaza_join", kind = "union", cap = 40, xgen = 1, profile = profile, avatar = s.avatar })
    return s
  end
  function e.walk(dir, axis, target)
    for _ = 1, 600 do
      local v = axis == "x" and Player.cellX or Player.cellY
      if v == target and not Player.moving then return true end
      if Player.moving then e.wait(1) else U.hold(game, dir, 1) end
    end
    return false
  end
  function e.close()
    pcall(Link.reset)
    pcall(Client.disconnect)
  end
  return e
end

function G.loadMap(game, mapId, x, y, facing)
  local Map = require("src.core.game3.map")
  X.settle(game)
  Map.load(nil, game, mapId, { x = x, y = y, facing = facing })
  local Player = require("src.core.game3.player")
  local s = require("src.core.game3.runtime").getSession()
  if s then s.x, s.y, s.facing = x, y, facing end
  Player.cellX, Player.cellY = x, y
  Player.px, Player.py = x * 16, y * 16
  Player.targetX, Player.targetY = x, y
  Player.facing = facing
  U.wait(40)
end

function G.settleText(game, frames)
  local Message = require("src.ui.game3.message")
  local Choice = require("src.ui.game3.choice")
  local Space = require("src.core.game3.scripting.space")
  for _ = 1, frames or 900 do
    local busy = Message.isOpen() or Choice.active or (Space.vm and Space.vm:isRunning())
    if not busy then return true end
    U.tap(game, "a")
    U.wait(4)
  end
  return false
end

function G.talksOpen(game, frames)
  local Message = require("src.ui.game3.message")
  local Choice = require("src.ui.game3.choice")
  U.tap(game, "a")
  for _ = 1, frames or 120 do
    if Message.isOpen() or Choice.active then return true end
    U.wait(1)
  end
  return false
end

function G.resize(w, h)
  love.window.setMode(w, h, { resizable = true })
  if love.resize then love.resize(w, h) end
  U.wait(8)
end

return G
