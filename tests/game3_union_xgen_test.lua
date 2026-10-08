#!/usr/bin/env luajit
package.path = "./?.lua;./?/init.lua;" .. package.path
require("tests.fixture_data.game3_items").install()

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end
local function eq(a, b, msg)
  check(a == b, string.format("%s (%s == %s)", msg, tostring(a), tostring(b)))
end

local FakeRelay = require("tests.g3link_fake_relay")
local Plaza = require("src.core.game3.link.union_plaza_map")
local UNION_MAP = Plaza.MAP_ID

local store = { flags = {}, vars = {} }
local session = {
  store = store, map = UNION_MAP, x = 12, y = 24, name = "LEAF", gender = 1, trainerId = 0x1235,
  party = { { species = 1, level = 12 }, { species = 4, level = 9 } },
  bag = { pockets = { items = {} } }, version = "firered",
}
local input = { pressed = {} }
function input:wasPressed(k) return self.pressed[k] == true end
local game = { data = { maps = { [UNION_MAP] = { warps = {} } } }, session = session, input = input,
  save = { player = { name = "LEAF" }, options = {} } }
package.loaded["src.core.game3.runtime"] = {
  getSession = function() return session end,
  isActive = function() return true end,
  _game = game,
}
local Player = { cellX = 12, cellY = 23, facing = "down" }
package.loaded["src.core.game3.player"] = Player
package.loaded["src.core.game3.map"] = { load = function() end }
package.loaded["src.core.game3.objects"] = {
  addObject = function() return true end, removeObject = function() return true end,
  find = function() return nil end, refreshGraphics = function() return 0 end,
}
local VirtualObjects = require("src.core.game3.virtual_objects")

local romBundle = require("tests.game3_cache").bundle()
if not romBundle then
  package.loaded["src.core.game3.rom_text"] = {
    plain = function(key) return key end, box = function(key) return key end,
    ascii = function(key) return key end, has = function() return true end,
    ir = function(key) return { { t = "text", s = key } } end,
    key = function(n, i, j) return j and (n .. "[" .. i .. "][" .. j .. "]") or (n .. "[" .. i .. "]") end,
    at = function(n, i, j) return j and (n .. "[" .. i .. "][" .. j .. "]") or (n .. "[" .. i .. "]") end,
    count = function() return 0 end, list = function() return {} end,
    lazy = function(map) return setmetatable({}, { __index = function(_, k) return map[k] end }) end,
  }
end

local ctx = { specialVars = {}, stringVars = {} }
local adapters = { log = function() end, playSe = function() end }
package.loaded["src.core.game3.scripting.space"] = {
  store = store, mapId = UNION_MAP, vm = { ctx = ctx, adapters = adapters },
  ensureBundle = function() return romBundle end,
}

local LIVE = { engine = 3, engineVersion = "1.0.0", fingerprint = "f00dcafe", kind = "vanilla", version = "firered" }
package.loaded["src.online.ArenaData"] = {
  liveProfile3 = function(_, rulesetId)
    local p = {}
    for k, v in pairs(LIVE) do p[k] = v end
    p.rulesetId = rulesetId
    return p
  end,
  onlineBlockers3 = function() return {} end,
}
local Client = FakeRelay.client({ state = "online", id = "0000beef" })
Client._profiles = { LIVE }
local joinOpts
function Client.joinPlaza(kind, profile, avatar, cap, opts)
  Client.calls[#Client.calls + 1] = { name = "joinPlaza", args = { kind, profile, avatar, cap, opts } }
  joinOpts = opts
end
package.loaded["src.online.Client"] = Client

local Natives = require("src.core.game3.scripting.natives")
local NativesLink = require("src.core.game3.scripting.natives_link")
local Link = require("src.core.game3.link")
local Union = require("src.core.game3.link.union_room")
local Screen = require("src.ui.game3.union_room")
local Message = require("src.ui.game3.message")
local Choice = require("src.ui.game3.choice")
local Avatars = require("src.online.union.Avatars")
Union._avatars = FakeRelay.avatars()
Avatars.setReader(function() return nil end)

local function run(n)
  for _ = 1, n or 1 do
    if Message.isOpen() and not Message.isWaiting() then Message.skipReveal() end
    Message.tick()
    Link.update(1 / 60)
  end
end
local function page() return Message.isOpen() and Message.currentPage() or "" end
local function member(id, slot, name, version, gen, tid, gender, status)
  return { id = id, name = name, slot = slot, online = true, status = status or "idle",
    avatar = { name = name, trainerId = tid or 1, gender = gender or 0, version = version, gen = gen,
               style = gen == 3 and ("g3:" .. ((tid or 1) % 8)) or "player" } }
end

print("[test] 1. the Gen 3 room joins the cross-gen plaza")
Link.reset()
Natives.special(ctx, NativesLink.SPECIAL.RunUnionRoom, adapters)
local join = Client.last("joinPlaza")
check(join ~= nil, "joinPlaza sent")
eq(joinOpts and joinOpts.xgen, require("src.online.Protocol2").XGEN, "with xgen")
check(joinOpts and type(joinOpts.caps) == "table" and joinOpts.caps.proto ~= nil, "and presence caps")
eq(join and join[3] and join[3].style, "g3:" .. (0x1235 % 8), "FRLG avatars send their class style")
eq(join and join[3] and join[3].version, "firered", "and the version")

print("[test] 2. Gen 1 and Gen 2 members get a foreign avatar, Gen 3 keeps its class sprite")
Client._plaza = { kind = "union", instance = 1, cap = 40, rev = 1, you = 3, members = {
  member("aaaa0001", 1, "RED", "red", 1, 11),
  member("aaaa0002", 2, "KRIS", "crystal", 2, 22, 1),
  member("0000beef", 3, "LEAF", "firered", 3, 0x1235, 1),
  member("aaaa0004", 4, "MAY", "emerald", 3, 44, 1),
} }
run(2)
eq(Union.playerCount(), 3, "three other members")
eq(Union.players[1].sourceGen, 1, "RED is Gen 1")
eq(Union.players[2].sourceGen, 2, "KRIS is Gen 2")
eq(Union.players[4].sourceGen, 3, "MAY is Gen 3")
local v1 = Union.vobj(1)
check(v1 and v1.foreign and v1.foreign.game == "red" and v1.gfx == nil and v1.foreign.host.version == "firered",
  "RED draws through Avatars with this game as the stand-in host")
check(Union.vobj(4).foreign == nil and Union.vobj(4).gfx == Union.graphicsIdFor(1, 44), "MAY keeps her class graphics")
local realResolve = Avatars.resolve
Avatars.resolve = function(p)
  if p.game == "crystal" then return { key = "k", layout = "gb", w = 16, h = 16, frames = 6, gen = 2 } end
  return realResolve(p)
end
Union.hideAvatar(2)
run(Union.FLY_HEIGHT / Union.FLY_STEP + 2)
Client._plaza.rev = 2
Union.players[2] = nil
run(2)
local v2 = Union.vobj(2)
check(v2 and v2.foreign and v2.foreign.game == "crystal" and v2.gfx == nil, "KRIS with Crystal imported draws her real sprite")
run(30)
local rec2 = VirtualObjects.get(Union.vobjId(2))
check(rec2 and rec2.foreign and rec2.foreign.gen == 2 and rec2.solid == true, "the foreign record blocks like any avatar")
Avatars.resolve = realResolve
eq(Union._serverOutdated, nil, "a new server does not trip the update notice")

print("[test] 3. talking to a Gen 1 member names the import and offers BATTLE / TRADE")
local cx, cy = Plaza.cellFor(1)
Player.cellX, Player.cellY, Player.facing = cx, cy + 1, "up"
input.pressed.a = true
run(1)
input.pressed.a = false
eq(Union.vobj(1).dir, Union.DIR.SOUTH, "RED turns toward the player")
local sawStandin = false
for _ = 1, 400 do
  if page():find("RED, BLUE or YELLOW", 1, true) then sawStandin = true end
  if Screen.isOpen() then break end
  if Message.isOpen() and Message.isWaiting() and not Message._stay then Message.advance() end
  run(1)
end
check(sawStandin, "the stand-in line names the Gen 1 imports")
check(Screen.isOpen(), "the Gen 3 activity menu opens")
eq(#Screen.items, 3, "three entries")
eq(Screen.items[1].wire, "xg_battle", "BATTLE sends a cross-gen battle invite")
eq(Screen.items[2].wire, "xg_trade", "TRADE sends a cross-gen trade invite")
Screen.confirm()
local inv = Client.last("invite")
eq(inv and inv[1], "aaaa0001", "the invite goes to RED")
eq(inv and inv[2], "xg_battle", "as xg_battle")
eq(Union.state, "send_activity_request", "waiting for the answer")

print("[test] 4. an accepted invite opens prep through beginXg, and no screen means a clean cancel")
local sent = {}
Union.xgInstalled = true
Union.xgScreens.battle, Union.xgScreens.trade = nil, nil
local snapshot = { mode = "battle", rev = 1, rosters = {}, sizeReq = {}, offers = {}, ready = {}, caps = {} }
local xgRoom = { room = "r1", intent = "xg", mode = "battle", stage = "prep", xg = snapshot,
  players = { { seat = 0, id = "0000beef", gen = 3, avatar = { name = "LEAF", version = "firered" } },
              { seat = 1, id = "aaaa0001", gen = 1, avatar = { name = "RED", version = "red" } } } }
local rs = { closed = false, left = false }
function rs:send(msg) sent[#sent + 1] = msg end
function rs:takeWhere() return nil end
function rs:close() self.left = true end
Client.room = function() return xgRoom end
Client.roomSession = function() return rs end
Client.seat = function() return 0 end
Client.handles[#Client.handles].state = "accepted"
Client.handles[#Client.handles].room = "r1"
run(2)
local act = Union._xgSession
check(act ~= nil and act.prep ~= nil, "beginXg built the activity with a prep session")
eq(act and act.mode, "battle", "battle mode")
eq(act and act.peer and act.peer.name, "RED", "the peer comes from the room")
eq(act and act.peer and act.peer.gen, 1, "with its generation")
check(page():find("Getting ready to battle RED", 1, true) ~= nil, "a preparing line shows")
for _ = 1, 120 do run(1) end
eq(sent[#sent] and sent[#sent].type, "xg_cancel", "the prep is canceled when no screen exists")
check(rs.left, "and the room is left")
check(act.done and act.why == "unavailable", "the activity ends as unavailable")
for _ = 1, 400 do
  if not Message.isOpen() and Union.state == "main" then break end
  if Message.isOpen() and Message.isWaiting() then Message.advance() end
  run(1)
end
eq(Union.state, "main", "back to the room")

print("[test] 5. a registered screen is called once prep is live")
local called = 0
Union.xgScreens.battle = function(a)
  called = called + 1
  a:finish("done")
end
sent, rs.left = {}, false
xgRoom.room = "r2"
local act2 = Union.beginXg(xgRoom, "battle")
act2.prep.state = "prep"
act2.prep.rules = { ruleset = "g3u" }
for _ = 1, 10 do run(1) end
eq(called, 1, "the battle screen ran once")
check(act2.done and act2.why == "done", "the screen finished the activity")
Union.xgScreens.battle = nil

print("[test] 6. an incoming cross-gen trade asks in Gen 3 style and accepts")
Union.toMain()
xgRoom.room = "r3"
Client._invites = { { id = "inv9", activity = "xg_trade", from = { id = "aaaa0002", name = "KRIS",
  avatar = { name = "KRIS", version = "crystal", gen = 2 } } } }
run(2)
local asked = false
for _ = 1, 400 do
  if page():find("KRIS from POKéMON CRYSTAL", 1, true) then asked = true end
  if Choice.isOpen() then break end
  if Message.isOpen() and Message.isWaiting() and (Message._page or 1) < #(Message._pages or {}) then
    Message.advance()
  end
  run(1)
end
check(asked, "the trade request names KRIS and CRYSTAL")
check(Choice.isOpen(), "YES/NO is offered")
Choice.cursor = 1
Choice.confirm()
local reply = Client.last("replyInvite")
eq(reply and reply[1], "inv9", "the invite is answered")
eq(reply and reply[2], true, "with yes")
run(3)
check(Union._xgSession ~= nil and Union._xgSession.mode == "trade", "prep opens in trade mode")
Union.endXg(nil, "test")

print("[test] 7. a legacy shard row trips the server update notice")
Union.toMain()
Client._plaza = { kind = "union", instance = 2, cap = 40, rev = 9, you = 3, members = {
  { id = "0000beef", name = "LEAF", slot = 3, online = true, status = "idle",
    avatar = { name = "LEAF", trainerId = 1, gender = 1, version = "firered" } },
} }
Union._upgradeShown = nil
run(3)
eq(Union._serverOutdated, "legacy_shard", "an own row without a gen means the server is old")
check(page():find("UNION ROOM server", 1, true) ~= nil, "the update notice shows: " .. page())

print("[test] 8. badges ride on the name tags")
local LinkTags = require("src.ui.game3.link_tags")
local plain = LinkTags.layout({ name = "RED" }, 100, 50, 240, function() return 18 end, {})
local tagged = LinkTags.layout({ name = "RED", badge = 1 }, 100, 50, 240, function() return 18 end, {})
eq(tagged.w - plain.w, require("src.online.union.Badge").SIZE + LinkTags.BADGE_GAP, "a badge widens the plate")
check(tagged.badgeX and tagged.badgeX >= tagged.textX + 18, "the badge sits after the name")

local Badge = require("src.online.union.Badge")
local near = LinkTags.unionLayout({ name = "RED", badge = 1, near = true }, 100, 50, 240, function() return 18 end, {})
check(near.plate and near.badgeX + Badge.SIZE == near.x + near.w - 1, "a nearby member's badge sits at the plate's right edge")
check(near.y + near.h < 50, "the plate stays clear of the head")
check(near.x == math.floor(near.x) and near.badgeY == math.floor(near.badgeY), "integer pixel positions")
local far = LinkTags.unionLayout({ name = "RED", badge = 1, near = false }, 100, 50, 240, function() return 18 end, {})
check(not far.plate and far.w == Badge.SIZE, "a distant member shows only the badge")

pcall(Link.reset)
if failed > 0 then
  print(("[FAIL] %d check(s) failed"):format(failed))
  os.exit(1)
end
print("[PASS] union xgen")
