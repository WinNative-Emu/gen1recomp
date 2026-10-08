package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")
local T = require("tests.harness")
local FakeRelay = require("tests.support.fake_relay")
local Participant = require("src.online.union.Participant")
local Caps = require("src.online.union.Caps")
local Room = require("src.online.union.Room")
local Wire = require("src.link.Wire")
local Protocol2 = require("src.online.Protocol2")

local CLOCK = 0
love.timer.getTime = function() return CLOCK end

local function pid(n) return ("%08x"):format(n) end

local FP = { red = "1111111111111111", blue = "1111111111111111", yellow = "2222222222222222",
             gold = "3333333333333333", silver = "3333333333333333", crystal = "4444444444444444",
             firered = "5555555555555555", leafgreen = "5555555555555555",
             emerald = "6666666666666666", ruby = "7777777777777777", sapphire = "7777777777777777" }

local function profileFor(version)
  local gen = Participant.genOf(version)
  return { engine = gen, version = version, engineVersion = "0.0.0-dev", apiVersion = 2,
           fingerprint = FP[version], rulesetId = gen == 3 and "g3_single" or "union",
           kind = "vanilla" }
end

local function ctxFor(version, name, tid, gender, style)
  return { version = version, name = name, trainerId = tid, gender = gender or 0,
           style = style, profile = profileFor(version),
           vanillaFingerprint = FP[version], gameplayMods = false }
end

local World = {}
World.__index = World

local function newWorld(opts)
  return setmetatable({ relay = FakeRelay.new({ clock = function() return CLOCK end,
                                                legacy = opts and opts.legacy }),
                        clients = {}, rooms = {}, seats = {} }, World)
end

function World:add(n, name)
  local seat = self.relay:seat(pid(n), name)
  package.loaded["src.online.Client"] = nil
  local C = require("src.online.Client")
  C.reset()
  C.configure({ relayAddress = "fake:3", connect = function() return seat.transport end })
  C.connect({ name = name, profiles = {} })
  self.clients[#self.clients + 1] = C
  self.seats[#self.seats + 1] = seat
  local room = Room.new({ client = C })
  self.rooms[#self.rooms + 1] = room
  return room, C, seat
end

function World:pump(rounds)
  for _ = 1, rounds or 4 do
    self.relay:pump()
    for _, C in ipairs(self.clients) do C.update(0) end
  end
end

local function slots(list)
  local out = {}
  for _, p in ipairs(list) do out[#out + 1] = p.slot end
  return table.concat(out, ",")
end

local function ids(list)
  local out = {}
  for _, p in ipairs(list) do out[#out + 1] = p.id end
  return table.concat(out, ",")
end

do
  local row = Wire.member({ id = pid(7), name = "ACC", slot = 3, status = "idle",
    avatar = { name = "ASH", trainerId = 70000, gender = 1, version = "crystal", style = "player", gen = 2 },
    caps = { proto = 1, policy = 1, gens = { ["2"] = { { version = "crystal", fp = "ABCDEF0123456789" } } } } })
  local p = Participant.fromMember(row)
  T.check(p ~= nil, "a Gen 2 xgen row parses")
  T.eq(p.gen, 2, "the row's relay gen is kept")
  T.eq(p.game, "crystal", "the participant's game is the avatar version")
  T.eq(p.gender, 1, "gender comes from the avatar")
  T.eq(p.trainerId, 65535, "trainer id clamps to 16 bits on the wire")
  T.eq(p.legacy, false, "a row with avatar.gen is not legacy")
  T.eq(p.caps.gens["2"][1].fp, "abcdef0123456789", "caps fingerprints are lowercased")
  T.eq(Participant.badgeDigit(p), 2, "the badge digit is the source gen")

  local legacy = Participant.fromMember(Wire.member({ id = pid(8), slot = 4,
    avatar = { name = "LEAF", trainerId = 5, gender = 1, version = "leafgreen" } }))
  T.eq(legacy.legacy, true, "a row without avatar.gen is legacy")
  T.eq(legacy.gen, 3, "a legacy row's gen comes from the version family")
  T.eq(legacy.style, "player", "a legacy row defaults to the player style")

  T.eq(Participant.fromMember(Wire.member({ id = pid(9), slot = 5,
    avatar = { name = "X", version = "emerald", gen = 1 } })), nil,
    "a row whose gen disagrees with its version family is refused")
  T.eq(Participant.fromMember(Wire.member({ id = pid(10), slot = 6, avatar = { name = "X" } })), nil,
    "a row without a version is refused")
  T.eq(Participant.fromMember(Wire.member({ id = pid(11), avatar = { version = "red", gen = 1 } })), nil,
    "a row without a slot is refused")
  T.eq(Participant.fromMember(Wire.member({ id = pid(12), slot = 1, avatar = { version = "zelda", gen = 1 } })), nil,
    "a row with an unknown version is refused")
  T.eq(Wire.avatar({ name = "A", version = "red", style = "BAD STYLE" }).style, nil,
    "a malformed style token is dropped on the wire")
  local av = Participant.wireAvatar({ name = "ABCDEFGHIJKLMN", trainerId = 70001, gender = "female",
                                      version = "red" })
  T.eq(av.name, "ABCDEFGHIJ", "the wire avatar name is cut to 10 characters")
  T.eq(av.trainerId, 70001 % 65536, "the wire avatar trainer id is 16 bits")
  T.eq(av.style, "player", "the wire avatar style defaults to player")

  local caps = Caps.compute({ version = "yellow", vanillaFingerprint = FP.yellow, gameplayMods = false })
  T.eq(caps.gens["1"][1].version, "yellow", "caps list only the active game's own version")
  T.eq(caps.gens["2"], nil, "caps never list another gen")
  T.check(Caps.empty(Caps.compute({ version = "yellow", vanillaFingerprint = FP.yellow,
                                    gameplayMods = true })),
    "gameplay mods omit the gen entry")
end

do
  local hello = Protocol2.lobbyHello({ name = "X", xgen = 1 })
  T.eq(hello.xgen, 1, "lobby_hello carries xgen")
  local join = Protocol2.plazaJoin("union", profileFor("red"), { name = "A", version = "red", style = "player" },
    40, { xgen = 1, caps = Caps.compute({ version = "red", vanillaFingerprint = FP.red, gameplayMods = false }) })
  T.eq(join.xgen, 1, "plaza_join carries xgen")
  T.eq(join.avatar.style, "player", "plaza_join keeps the avatar style")
  T.eq(join.caps.gens["1"][1].fp, FP.red, "plaza_join carries caps")
  local legacyJoin = Protocol2.plazaJoin("union", profileFor("firered"), { name = "A", version = "firered" }, 40)
  T.eq(legacyJoin.xgen, nil, "a plain plaza_join stays without xgen")
  T.eq(legacyJoin.caps, nil, "a plain plaza_join stays without caps")
  T.check(Protocol2.CLIENT_TYPES.set_caps, "set_caps is a client type")
  local nack = Wire.sanitize({ type = "room_msg", seq = nil, seat = -1, relay = true,
    msg = { type = "xg_nack", of = "xg_roster", why = "stale_rev", rev = 1, current = 3 } })
  T.eq(nack.msg.of, "xg_roster", "xg_nack keeps of")
  T.eq(nack.msg.current, 3, "xg_nack keeps current")
  local st = Wire.sanitize({ type = "room_state", room = "r0000000000003001", intent = "xg", mode = "battle",
    stage = "prep", players = { { id = pid(1), seat = 0, gen = 1, avatar = { name = "A", version = "red", gen = 1 } } },
    xg = { mode = "battle", rev = 4, gens = { 1, 3 }, rules = { mode = "battle", ruleset = "g3u", dexMax = 151 },
           caps = { true, false }, rosters = { { size = 3, digest16 = "00112233445566ff" } },
           sizeReq = {}, offers = {}, ready = { false, true } } })
  T.eq(st.mode, "battle", "room_state keeps the xg mode")
  T.eq(st.xg.rev, 4, "room_state keeps the xg snapshot rev")
  T.eq(st.xg.rules.dexMax, 151, "the snapshot keeps the rules")
  T.eq(st.xg.rosters[1].size, 3, "the snapshot keeps seat rosters")
  T.eq(st.xg.ready[2], true, "the snapshot keeps ready flags")
  T.eq(st.players[1].gen, 1, "room_state player rows keep gen")
  T.eq(st.players[1].avatar.version, "red", "room_state player rows keep the avatar")
end

do
  local w = newWorld()
  local ra, ca = w:add(1, "RED")
  local rb = w:add(2, "GOLD")
  local rc = w:add(3, "MAY")
  w:pump()
  T.check(ra:join(ctxFor("red", "RED", 100, 0)), "a Gen 1 game joins")
  T.check(rb:join(ctxFor("gold", "GOLD", 200, 0)), "a Gen 2 game joins")
  T.check(rc:join(ctxFor("emerald", "MAY", 300, 1, "g3:2")), "a Gen 3 game joins")
  w:pump()
  local sent = w.relay:sent(w.seats[1], "plaza_join")[1]
  T.eq(sent.xgen, 1, "the room join sends xgen")
  T.eq(sent.profile.rulesetId, "union", "a Gen 1 profile carries rulesetId union")
  T.eq(sent.caps.gens["1"][1].version, "red", "the join sends the active game's caps")
  local hello = w.relay:sent(w.seats[1], "lobby_hello")[1]
  T.eq(hello.xgen, 1, "the client hello advertises xgen")
  local da, dc = ra:poll(), rc:poll()
  T.eq(#da.joined, 2, "Gen 1 sees two others join")
  T.eq(slots(da.joined), "2,3", "joined rows come by slot")
  T.eq(da.joined[1].gen, 2, "Gen 1 sees the Gen 2 member's gen")
  T.eq(da.joined[2].gen, 3, "Gen 1 sees the Gen 3 member's gen")
  T.eq(da.joined[2].style, "g3:2", "the Gen 3 style token rides the row")
  T.eq(dc.joined[1].gen, 1, "Gen 3 sees the Gen 1 member's gen")
  T.eq(ra:self().slot, 1, "Gen 1 holds slot 1")
  T.eq(ra:count(), 3, "the room counts three trainers")
  local again = ra:poll()
  T.eq(#again.joined + #again.left + #again.changed, 0, "an unchanged plaza produces no diff")
  local builds = ra.builds
  for _ = 1, 30 do ra:poll() end
  T.eq(ra.builds, builds, "polling an unchanged plaza never rebuilds")

  rc:leave()
  w:pump()
  local d1 = ra:poll()
  T.eq(#d1.left, 1, "a leaver shows in left")
  T.eq(d1.left[1].slot, 3, "the leaver's slot is reported")
  local rd = w:add(4, "SILV")
  w:pump()
  rd:join(ctxFor("silver", "SILV", 400, 0))
  w:pump()
  local d2 = ra:poll()
  T.eq(#d2.joined, 1, "a newcomer shows in joined")
  T.eq(d2.joined[1].slot, 3, "the newcomer takes the lowest free slot")
  T.eq(d2.joined[1].id, pid(4), "the slot now holds the newcomer")

  rb:setStatus("busy")
  w:pump()
  local d3 = ra:poll()
  T.eq(#d3.changed, 1, "a status change is a changed row")
  T.eq(d3.changed[1].status, "busy", "the changed row carries the new status")
  T.check(ra:busy(ra:member(pid(2))), "a busy member reads busy")
  rb:setStatus("idle")
  w:pump()
  ra:poll()

  w.relay:drop(w.seats[1])
  w:pump()
  w.relay:reconnect(w.seats[1])
  CLOCK = CLOCK + 2
  w:pump(6)
  T.eq(ca.state(), "online", "the client resumes")
  local d4 = ra:poll()
  T.eq(#d4.joined + #d4.left + #d4.changed, 0, "a resume keeps every slot stable")
  T.eq(ids(ra:members()), pid(2) .. "," .. pid(4), "members are unchanged after the resume")
end

do
  local w = newWorld()
  local rooms = {}
  for i = 1, 41 do
    local r = w:add(100 + i, "T" .. i)
    rooms[i] = r
  end
  w:pump()
  for i = 1, 41 do
    local v = ({ "red", "gold", "firered" })[(i % 3) + 1]
    rooms[i]:join(ctxFor(v, "T" .. i, i, 0))
    w:pump(1)
  end
  w:pump()
  rooms[1]:poll()
  rooms[41]:poll()
  T.eq(rooms[1]:count(), 40, "an instance holds 40 trainers")
  T.eq(#rooms[1]:members(), 39, "a full instance shows 39 others")
  T.eq(rooms[41]:count(), 1, "the 41st trainer opens a new instance")
  local maxSlot = 0
  for _, p in ipairs(rooms[1]:members()) do maxSlot = math.max(maxSlot, p.slot) end
  T.eq(maxSlot, 40, "slots run 1..40")
  local sent = w.relay:sent(w.seats[1], "plaza_join")[1]
  T.eq(sent.cap, 40, "the join asks for cap 40")
end

do
  local w = newWorld()
  local ra, ca = w:add(1, "RED")
  local rb, cb = w:add(2, "MAY")
  local rc, cc = w:add(3, "GOLD")
  w:pump()
  ra:join(ctxFor("red", "RED", 1, 0))
  rb:join(ctxFor("emerald", "MAY", 2, 1))
  rc:join(ctxFor("gold", "GOLD", 3, 0))
  w:pump()
  ra:poll(); rb:poll(); rc:poll()
  local h = ra:invite(rb:self(), "xg_battle")
  T.check(h ~= nil, "an xg_battle invite goes out")
  w:pump()
  local inc = rb:incoming()
  T.eq(#inc, 1, "the invitee sees one xg invite")
  T.eq(inc[1].mode, "battle", "the invite reads as a battle")
  T.eq(inc[1].from.gen, 1, "the invite names a Gen 1 sender")
  T.eq(rb:incoming()[1].from.id, pid(1), "the invite resolves the sender's participant")
  rb:reply(inc[1].id, true)
  w:pump()
  T.eq(h.state, "accepted", "the sender sees the invite accepted")
  local room = ra:xgRoom()
  T.check(room ~= nil, "the sender sits in an xg room")
  T.eq(room.stage, "prep", "the xg room starts in prep")
  T.eq(room.xg.gens[1], 1, "the snapshot carries the seat gens")
  T.eq(room.players[2].gen, 3, "player rows carry gens")
  T.eq(cb.room().mode, "battle", "the invitee's room carries the mode")
  ra:poll(); rc:poll()
  T.eq(rc:member(pid(1)).status, "battling", "plaza rows show the pair battling")
  local hc = rc:invite(pid(1), "xg_trade")
  w:pump()
  T.eq(hc.state, "closed", "an invite to a battling trainer closes")
  T.eq(hc.why, "busy", "an invite to a battling trainer is busy")
  T.check(cc.room() == nil, "the refused sender has no room")
  T.check(ca.room() ~= nil and cb.room() ~= nil, "the pair keeps its room")
end

do
  local w = newWorld({ legacy = true })
  local ra = w:add(1, "RED")
  local rb, cb = w:add(2, "LEAF")
  w:pump()
  ra:join(ctxFor("red", "RED", 1, 0))
  rb:join(ctxFor("leafgreen", "LEAF", 2, 1))
  w:pump()
  local da = ra:poll()
  T.eq(da.error and da.error.error, "server_outdated", "a Gen 1 join on an old relay is server_outdated")
  T.eq(ra:poll().error, nil, "the error is reported once")
  T.eq(ra:error().error, "server_outdated", "the error stays readable")
  local db = rb:poll()
  T.eq(db.error and db.error.error, "server_outdated", "a Gen 3 join landing in a legacy shard is server_outdated")
  w:pump()
  T.eq(#w.relay:sent(w.seats[2], "plaza_leave"), 1, "the client leaves the legacy shard")
  T.check(cb.plaza() == nil, "the legacy plaza is dropped")
end

do
  local w = newWorld()
  local ra, ca = w:add(1, "RED")
  w:pump()
  local saved = FakeRelay.PLAZA_CAP
  FakeRelay.PLAZA_CAP = 60
  ra:join(ctxFor("red", "RED", 1, 0))
  w:pump()
  FakeRelay.PLAZA_CAP = saved
  local d = ra:poll()
  T.eq(d.error and d.error.error, "client_outdated", "plaza_cap upgrade_required is client_outdated")
  T.check(ca.upgradeRequired() ~= nil, "the client latched the upgrade")
end

do
  local w = newWorld()
  local ra = w:add(1, "RED")
  local rb = w:add(2, "MAY")
  w:pump()
  local bad = ctxFor("red", "RED", 1, 0)
  bad.profile.rulesetId = "gen1_faithful"
  ra:join(bad)
  w:pump()
  local d = ra:poll()
  T.eq(d.error and d.error.error, "server_outdated", "a refused Gen 1 profile reads as server_outdated")
  local badAv = ctxFor("emerald", "MAY", 2, 1)
  badAv.version = "emerald"
  badAv.profile.version = "emerald"
  rb:join(badAv)
  rb.avatar.version = "red"
  w.clients[2].joinPlaza("union", badAv.profile, rb.avatar, 40, { xgen = 1, caps = rb.caps })
  w:pump()
  local db = rb:poll()
  T.eq(db.error and db.error.error, "bad_avatar", "an avatar outside the profile family is bad_avatar")
end

T.finish()
