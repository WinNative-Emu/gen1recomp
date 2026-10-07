#!/usr/bin/env luajit
package.path = "./?.lua;./?/init.lua;" .. package.path

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

local store = { flags = {}, vars = {} }
local session = {
  version = "ruby", store = store, map = "RS_OLDALE_TOWN_POKEMON_CENTER_2F", x = 5, y = 3,
  name = "BRENDAN", gender = 0, trainerId = 0x2222,
  party = { { species = 280, level = 12 }, { species = 283, level = 9 } },
  bag = { pockets = { items = {} } },
}
local input = { pressed = {} }
function input:wasPressed(k) return self.pressed[k] == true end
function input:isDown(k) return self.pressed[k] == true end
local game = { data = { maps = {} }, session = session, input = input, save = { player = { name = "BRENDAN" } } }

package.loaded["src.core.game3.runtime"] = {
  getSession = function() return session end,
  isActive = function() return true end,
  _game = game,
}
package.loaded["src.core.game3.player"] = { cellX = 5, cellY = 3, facing = "up" }
package.loaded["src.core.game3.map"] = { load = function() end }
package.loaded["src.core.game3.rom_text"] = {
  plain = function(key) return key end, box = function(key) return key end,
  ascii = function(key) return key end, has = function() return true end,
  ir = function(key) return { { t = "text", s = key } } end,
  translate = function(ir) return ir end,
  key = function(n, i, j) return j and (n .. "[" .. i .. "][" .. j .. "]") or (n .. "[" .. i .. "]") end,
  at = function(n, i, j) return j and (n .. "[" .. i .. "][" .. j .. "]") or (n .. "[" .. i .. "]") end,
  count = function() return 0 end, list = function() return {} end,
  lazy = function(map) return setmetatable({}, { __index = function(_, k) return map[k] end }) end,
}

local ctx = { specialVars = {}, stringVars = {} }
local adapters = { log = function() end, playSe = function() end }
package.loaded["src.core.game3.scripting.space"] = {
  store = store, mapId = session.map, vm = { ctx = ctx, adapters = adapters },
  ensureBundle = function() return nil end,
}

local LIVE = { engine = 3, engineVersion = "1.0.0", fingerprint = "f00dcafe", kind = "vanilla" }
package.loaded["src.online.ArenaData"] = {
  liveProfile3 = function(_, rulesetId)
    local p = { version = session.version }
    for k, v in pairs(LIVE) do p[k] = v end
    p.rulesetId = rulesetId
    return p
  end,
}
local Client = FakeRelay.client({ state = "online", id = "0000beef" })
package.loaded["src.online.Client"] = Client

local Link = require("src.core.game3.link")
local LB = require("src.core.game3.link.battle")
local Union = require("src.core.game3.link.union_room")
local Flags = require("src.core.game3.scripting.flags")
local Lobby = require("src.ui.game3.rs.cable_lobby")
local Game3Link = require("src.link.Game3Link")
local NativesLinkRs = require("src.core.game3.scripting.natives_link_rs")

local function getVar(id) return tonumber(Flags.getVar(store, ctx, id)) or 0 end
local function setVar(id, v) Flags.setVar(store, ctx, id, v) end
local function fresh()
  ctx.specialVars = {}
  ctx.nativePoll, ctx.mode, ctx.status = nil, nil, nil
  Client.clear()
  Client._group, Client._groups, Client._directEntries = nil, {}, {}
  Client._room, Client._seat = nil, nil
  Lobby.reset()
  Link.reset()
  Link._live = nil
end
local function rowIds()
  local out = {}
  for i, row in ipairs(Lobby.rows()) do out[i] = row.id end
  return out
end
local function pick(id)
  for _, row in ipairs(Lobby.rows()) do
    if row.id == id then return Lobby.opts.select(row) end
  end
  error("no row " .. tostring(id))
end
local function poll(n)
  local r
  for _ = 1, n or 1 do
    r = ctx.nativePoll()
    if r then break end
  end
  return r
end
local function me(id) return { id = id or "0000beef", name = "BRENDAN", avatar = { name = "BRENDAN" } } end
local function peerOn(room, seat, version, linkType)
  local hello = Game3Link.hello(game, linkType, { version = version, name = version:upper(), trainerId = 0x1000 + seat })
  return Game3Link.attach(FakeRelay.transport(room, seat), {
    game = game, linkType = linkType, seat = seat, seats = room.seats, hello = hello,
  })
end
local function pump(peers)
  for _ = 1, 4 do
    for _, p in ipairs(peers) do p:update(0) end
    Link.update(0)
  end
end

print("[test] 1. a Ruby cable leader auto-accepts and starts a two-seat group")
fresh()
setVar(0x8004, 1)
local yielded = NativesLinkRs.BY_NAME.sub_808347C(ctx, adapters)
check(yielded, "sub_808347C parks the script")
check(Lobby.isOpen(), "the cable lobby is up")
eq(table.concat(rowIds(), ","), "leader,join", "CREATE GROUP / JOIN GROUP")
pick("leader")
local og = Client.last("openGroup")
eq(og and og[1], "battle_single", "the leader opens a battle_single group")
eq(og and og[2] and og[2].rulesetId, "g3_single", "with the battle ruleset profile")
Client._group = { leader = "0000beef", min = 2, max = 2, members = { me() },
  pending = { { id = "00e00001", name = "MAY", avatar = { name = "MAY" } } } }
poll()
local acc = Client.last("acceptGroup")
eq(acc and acc[1], "00e00001", "the first group_request is accepted without a prompt")
eq(acc and acc[2], true, "with ok = true")
Client._group = { leader = "0000beef", min = 2, max = 2, members = { me(), { id = "00e00001", name = "MAY" } }, pending = {} }
poll()
eq(Client.count("startGroup"), 1, "a full two-seat group starts by itself")

print("[test] 2. an Emerald wireless peer seated into the group links up with no linkup message")
local room = FakeRelay.room({ seats = 2 })
Client.bindRoom(room, 0)
local peer = peerOn(room, 1, "emerald", Game3Link.LINKTYPE.BATTLE)
check(poll() == false, "the match opens the relay link")
check(Link.link ~= nil, "Link.openRelay ran")
pump({ peer })
check(Link.link and Link.link:isReady(), "the hellos agree")
local done = poll(LB.LINKUP_TICKS + 5)
check(done == true, "the linkup finishes")
eq(getVar(Link.VAR_RESULT), Link.LINKUP.SUCCESS, "Ruby vs an Emerald wireless player is LINKUP_SUCCESS")
eq(LB.state, "seat", "and the colosseum seat wait begins")
eq(Link.link and Link.link.linkType, 0x2233, "the link runs as LINKTYPE_SINGLE_BATTLE")
check(not Lobby.isOpen(), "the lobby closed")

print("[test] 3. a Ruby joiner sees Direct Corner hosts next to cable groups")
fresh()
setVar(0x8004, 2)
NativesLinkRs.BY_NAME.sub_808347C(ctx, adapters)
pick("join")
eq(Client.last("groupList") and Client.last("groupList")[1], "battle_double", "it watches battle_double groups")
eq(Client.last("directList") and Client.last("directList")[1], "battle_double", "and the Direct Corner list")
Client._groups = { { leader = "00c00001", name = "RED", avatar = { name = "RED" }, joined = 1, max = 2 } }
Client._directEntries.battle_double = {
  { kind = "room", room = "r00000000000000aa", host = "00d00001", name = "LEAF", avatar = { name = "LEAF" } },
  { kind = "room", room = "r00000000000000bb", host = "00d00002", name = "PIN", locked = true },
  { kind = "player", id = "00d00003", name = "AUTO" },
}
local rows = Lobby.rows()
eq(#rows, 3, "one group and two hosted rooms (queued players are not joinable)")
eq(rows[2].kind, "room", "the Direct Corner host is listed")
eq(rows[3].disabled, true, "a PIN room is not joinable from the cable")
pick("r00000000000000aa")
local jr = Client.last("joinRoom")
eq(jr and jr[1], "r00000000000000aa", "room_join to the Direct Corner host")
eq(jr and jr[2], "player", "as a player")
Lobby.opts.cancel()
eq(Client.count("leaveRoom"), 1, "B while joining leaves the room")
check(Lobby.isOpen(), "and goes back to the list")

print("[test] 4. FireRed's cable counter falls back to the relay instead of timing out")
fresh()
session.version = "firered"
local NativesLink = require("src.core.game3.scripting.natives_link")
setVar(0x8004, Link.USING.TRADE_CENTER)
yielded = NativesLink.BY_NAME.TryTradeLinkup(ctx, adapters)
check(yielded, "TryTradeLinkup parks the script")
check(Lobby.isOpen(), "with the cable lobby, not a dead wait")
for _ = 1, LB.LINKUP_TICKS + 5 do ctx.nativePoll() end
eq(getVar(Link.VAR_RESULT), Link.LINKUP.ONGOING, "and it does not time out to CONNECTION_ERROR")
pick("leader")
eq(Client.last("openGroup") and Client.last("openGroup")[1], "trade", "the trade group")
Lobby.opts.cancel()
eq(getVar(Link.VAR_RESULT), Link.LINKUP.FAILED, "B is LINKUP_FAILED")
eq(Client.count("leaveGroup"), 1, "and leaves the group")

print("[test] 5. Emerald's cable counters pick the matching relay activity")
session.version = "emerald"
local cases = {
  { "TryBattleLinkup", Link.USING.SINGLE_BATTLE, "battle_single" },
  { "TryBattleLinkup", Link.USING.MULTI_BATTLE, "battle_multi" },
  { "TryBattleLinkup", Link.USING.BATTLE_TOWER, "battle_tower" },
  { "TryRecordMixLinkup", 0, "record_corner" },
}
local NativesLinkRse = require("src.core.game3.scripting.natives_link_rse")
for _, c in ipairs(cases) do
  fresh()
  setVar(0x8004, c[2])
  NativesLinkRse.BY_NAME[c[1]](ctx, adapters)
  pick("leader")
  eq(Client.last("openGroup") and Client.last("openGroup")[1], c[3], c[1] .. " " .. c[2] .. " opens " .. c[3])
end
fresh()
NativesLinkRse.BY_NAME.TryBerryBlenderLinkup(ctx, adapters)
pick("leader")
eq(Client.last("openGroup") and Client.last("openGroup")[1], "berry_blender", "TryBerryBlenderLinkup opens berry_blender")
fresh()
setVar(0x8011, 2)
local NativesContest = require("src.core.game3.scripting.natives_contest")
NativesContest.BY_NAME.TryContestEModeLinkup(ctx, adapters)
pick("leader")
eq(Client.last("openGroup") and Client.last("openGroup")[1], "contest_cute", "a CUTE link contest opens contest_cute")
eq(LB.towerSpec().linkType, 0x2266, "a level 50 tower challenge links as LINKTYPE_BATTLE_TOWER_50")

print("[test] 6. a 2..4 group still asks the leader")
fresh()
setVar(0x8004, 0)
NativesLinkRse.BY_NAME.TryRecordMixLinkup(ctx, adapters)
pick("leader")
Client._group = { leader = "0000beef", min = 2, max = 4, members = { me() },
  pending = { { id = "00e00002", name = "WALLY", avatar = { name = "WALLY" } } } }
poll()
eq(table.concat(rowIds(), ","), "yes,no", "ADD WALLY? YES / NO")
eq(Client.count("acceptGroup"), 0, "nothing accepted yet")
pick("yes")
eq(Client.last("acceptGroup") and Client.last("acceptGroup")[2], true, "YES accepts")

print("[test] 7. the activity names follow each game's sLinkGroupActivityNameTexts")
session.version = "emerald"
eq(Union.ACTIVITY_NAMES[15], "sLinkGroupActivityNameTexts[15]", "Emerald RECORD CORNER")
eq(Union.ACTIVITY_NAMES[23], "sLinkGroupActivityNameTexts[23]", "Emerald COOL CONTEST")
eq(Union.ACTIVITY_NAMES[28], "sLinkGroupActivityNameTexts[28]", "Emerald BATTLE TOWER LV. 50")
eq(Union.ACTIVITY_NAMES[13], nil, "Emerald SPIN TRADE is an empty string")
eq(Union.ACTIVITY_NAMES[3], "sLinkGroupActivityNameTexts[3]", "MULTI BATTLE")
session.version = "firered"
eq(Union.ACTIVITY_NAMES[13], "sLinkGroupActivityNameTexts[13]", "FireRed SPIN TRADE")
eq(Union.ACTIVITY_NAMES[15], nil, "FireRed has no RECORD CORNER name")
eq(Union.ACTIVITY_NAMES[10], "sLinkGroupActivityNameTexts[10]", "BERRY CRUSH")

print("[test] 8. the Direct Corner CHOOSE list shows open cable groups")
Client._directEntries.trade = {
  { kind = "group", leader = "00f00001", name = "BRENDAN", avatar = { name = "BRENDAN", version = "ruby" }, joined = 1, max = 2 },
  { kind = "group", leader = "00f00002", name = "FULL", avatar = { name = "FULL" }, joined = 2, max = 2 },
}
local drows = Union.directRows("trade")
eq(#drows, 1, "the open group is listed, the full one is not")
eq(drows[1] and drows[1].kind, "group", "as a group row")
eq(drows[1] and drows[1].leader, "00f00001", "with its leader id")
eq(drows[1] and drows[1].version, "ruby", "and the Ruby version for the trade check")

print("[test] 9. record mixing packs byte runs so a full Emerald packet fits the relay cap")
local RecordMix = require("src.core.game3.link.record_mix")
local Json = require("src.link.Json")
local Wire = require("src.link.Wire")
local raw = {}
for i = 1, 160 do raw[i] = (i * 37) % 256 end
local packet = { secretBases = { { trainerName = "MAY", _recordMixNativeBytes = raw } }, tvShows = { [0] = { kind = 1 } } }
local msg = Wire.sanitize(Json.decode(Json.encode({ type = RecordMix.MSG.PACKET, spot = 1, packet = RecordMix.toWire(packet) })))
local back = RecordMix.fromWire(msg.packet)
local same = true
for i = 1, 160 do if back.secretBases[1]._recordMixNativeBytes[i] ~= raw[i] then same = false end end
check(same, "160 native bytes survive the wire")
eq(back.tvShows[0].kind, 1, "zero-indexed rows still round trip")
check(#Json.encode(RecordMix.toWire(packet)) < 700, "and the byte run travels as one hex string")

print("[test] 10. a contest with a Ruby player is flagged and skips the wireless standby")
local CL = require("src.core.game3.link.contest_link")
local fakeLink = {
  isOpen = function() return true end,
  players = function() return { { seat = 0, version = "emerald" }, { seat = 1, version = "ruby" } } end,
  send = function(self, m) self.sent = (self.sent or 0) + 1 end,
  take = function() return nil end,
  getSeat = function() return 0 end,
}
local flags = CL.flagsFor(fakeLink, true)
eq(flags, CL.FLAG.IS_LINK + CL.FLAG.IS_WIRELESS + CL.FLAG.HAS_RS_PLAYER, "IS_LINK | IS_WIRELESS | HAS_RS_PLAYER")
local s = CL.newSession(fakeLink, { flags = flags })
eq(s:standby(), true, "LinkContest_TryLinkStandby skips the standby with an RS player")
eq(fakeLink.sent, nil, "without sending a standby block")
CL.active = s
NativesContest.linkFlags = flags
eq(select(2, NativesContest.BY_NAME.IsContestWithRSPlayer()), 1, "IsContestWithRSPlayer answers TRUE")
eq(select(1, NativesContest.linkContestWaitForConnection(ctx, adapters)), false,
  "LinkContestWaitForConnection does not park the script for an RS contest")
eq(CL.flagsFor({ players = function() return { { seat = 0, version = "emerald" } } end }, false), CL.FLAG.IS_LINK,
  "an all-Emerald cable contest is just IS_LINK")
CL.reset()
NativesContest.linkFlags = 0

Link.reset()
Lobby.reset()
print(string.format("%s game3_link_rs_entry_test", failed == 0 and "PASS" or ("FAIL " .. failed)))
os.exit(failed == 0 and 0 or 1)
