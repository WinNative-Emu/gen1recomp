package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")
local T = require("tests.harness")
local FakeRelay = require("tests.support.fake_relay")
local Data = require("tests.modkit.fixtures").fresh()
require("src.render.Font").load(Data)

local Avatars = require("src.online.union.Avatars")
local ChoiceBox = require("src.ui.ChoiceBox")
local NPC = require("src.world.gen2.Npc")
local Participant = require("src.online.union.Participant")
local Player = require("src.world.gen2.Player")
local Presence = require("src.world.gen2.UnionRoomPresence")
local Room = require("src.online.union.Room")
local RoomMap = require("src.world.gen2.UnionRoomMap")
local ScriptMenu = require("src.ui.gen2.ScriptMenu")
local Sound = require("src.core.Sound")
local TextBox = require("src.render.TextBox")
local Activity = require("src.ui.gen2.union.Activity")
Activity.installed = true
local Text = require("src.ui.gen2.union.Text")

Sound.play = function() end
Sound.playPress = function() end

local CLOCK = 0
love.timer.getTime = function() return CLOCK end

Data.text = Data.text or {}
Data.text._MysteryGiftCanceledText = "The link has been\ncancelled.{PROMPT}"

local pushedText = {}
local realNew = TextBox.new
TextBox.new = function(game, text, onDone, opts)
  pushedText[#pushedText + 1] = text
  return realNew(game, text, onDone, opts)
end

local reads = 0
Avatars.setReader(function()
  reads = reads + 1
  return nil
end)

local function pid(n) return ("%08x"):format(n) end

local FP = { red = "1111111111111111", gold = "3333333333333333", crystal = "4444444444444444",
             firered = "5555555555555555", ruby = "7777777777777777", silver = "3333333333333333" }

local function ctxFor(version, name, tid, gender, style)
  local gen = Participant.genOf(version)
  return { version = version, name = name, trainerId = tid, gender = gender or 0, style = style,
           profile = { engine = gen, version = version, engineVersion = "0.0.0-dev", apiVersion = 2,
                       fingerprint = FP[version], rulesetId = gen == 3 and "g3_single" or "union",
                       kind = "vanilla" },
           vanillaFingerprint = FP[version], gameplayMods = false }
end

local function newStack()
  local stack = { states = {} }
  function stack:push(s) self.states[#self.states + 1] = s end
  function stack:pop()
    local t = self.states[#self.states]
    self.states[#self.states] = nil
    return t
  end
  function stack:top() return self.states[#self.states] end
  function stack:update(dt)
    local t = self:top()
    if t and t.update then t:update(dt) end
  end
  return stack
end

local MAP = {}
function MAP:inBounds(x, y) return x >= 0 and y >= 0 and x < RoomMap.WIDTH and y < RoomMap.HEIGHT end
function MAP:isWalkable(x, y) return self:inBounds(x, y) and y >= 2 end

local function newWorld()
  local w = { npcs = {}, entities = {}, map = MAP }
  MAP.id = RoomMap.ID
  w.player = Player.new(12, 24, "up")
  w.entities[1] = w.player
  function w:busy() return false end
  function w:npcAt(x, y)
    for _, n in ipairs(self.npcs) do
      if NPC.covers(n, x, y) then return n end
    end
    return nil
  end
  return w
end

local Env = {}
Env.__index = Env

local function env(opts)
  opts = opts or {}
  local e = setmetatable({ relay = FakeRelay.new({ clock = function() return CLOCK end, legacy = opts.legacy }),
                           clients = {}, rooms = {}, seats = {}, pressed = {} }, Env)
  e.stack = newStack()
  e.game = { data = Data, stack = e.stack, save = { options = { textSpeed = 1 }, player = { name = "GOLD", id = 1 } },
             input = { wasPressed = function(_, k) return e.pressed[k] or false end,
                       isDown = function() return false end } }
  e.world = newWorld()
  return e
end

function Env:client(n, name)
  local seat = self.relay:seat(pid(n), name)
  package.loaded["src.online.Client"] = nil
  local C = require("src.online.Client")
  C.reset()
  C.configure({ relayAddress = "fake:3", connect = function() return seat.transport end })
  C.connect({ name = name, profiles = {} })
  self.clients[#self.clients + 1] = C
  self.seats[n] = seat
  return C, seat
end

function Env:add(n, version, name, gender, style)
  local C = self:client(n, name)
  self:pump(2)
  local r = Room.new({ client = C })
  r:join(ctxFor(version, name, n, gender, style))
  self.rooms[n] = r
  return r, C
end

function Env:me(version)
  local C, seat = self:client(1, "ME")
  self.mine, self.mySeat = C, seat
  self:pump(2)
  self.session = Presence.new(self.game, self.world, {
    client = C, room = Room.new({ client = C }), ctx = ctxFor(version or "gold", "ME", 1),
  })
  return self.session
end

function Env:pump(rounds)
  for _ = 1, rounds or 4 do
    self.relay:pump()
    for _, C in ipairs(self.clients) do C.update(0) end
    for _, r in pairs(self.rooms) do r:poll() end
    if self.session then self.session:update() end
    self.stack:update(1 / 60)
  end
end

function Env:press(key, rounds)
  self.pressed = { [key] = true }
  self:pump(1)
  self.pressed = {}
  self:pump(rounds or 1)
end

function Env:mash(key, cond, n)
  for _ = 1, n or 400 do
    if cond() then return true end
    self:press(key)
  end
  return cond()
end

function Env:wait(cond, n)
  for _ = 1, n or 400 do
    if cond() then return true end
    self:pump(1)
  end
  return cond()
end

local function topMt(e) return getmetatable(e.stack:top()) end

local function checkMirror(e, label)
  local s = e.session
  local members = s.room:members()
  local ok = true
  for _, p in ipairs(members) do
    local ent = s.bySlot[p.slot]
    local pend = s.pending[p.slot]
    if not ((ent and ent.participant.id == p.id) or (pend and pend.id == p.id)) then ok = false end
  end
  local count = 0
  for slot, ent in pairs(s.bySlot) do
    count = count + 1
    local m = s.room:member(slot)
    if not m or m.id ~= ent.participant.id then ok = false end
    local x, y = RoomMap.cellFor(slot)
    if ent.cellX ~= x or ent.cellY ~= y then ok = false end
  end
  local inNpcs, inEntities = 0, 0
  for _, n in ipairs(e.world.npcs) do if n.session == s then inNpcs = inNpcs + 1 end end
  for _, n in ipairs(e.world.entities) do if n.session == s then inEntities = inEntities + 1 end end
  T.check(ok and inNpcs == count and inEntities == count, label)
end

do
  local e = env()
  e:add(2, "red", "RED", 0)
  e:add(3, "crystal", "KRIS", 1)
  e:add(4, "firered", "LEAF", 1, "g3:3")
  local s = e:me("gold")
  e:pump(6)
  T.eq(s.state, "joined", "the presence joins once the client is online")
  T.eq(#s:entities(), 3, "three others are spawned")
  checkMirror(e, "entities mirror the plaza by slot")
  local ent = s:entity(e.rooms[3]:self().slot)
  T.eq(ent.participant.gender, 1, "the Crystal member keeps her gender")
  T.eq(ent.participant.gen, 2, "the Crystal member reads gen 2")
  T.eq(s:entity(e.rooms[4]:self().slot).participant.style, "g3:3", "the FRLG class style rides the entity")
  T.check(ent.avatar.standin, "a member whose source game has no cache is a stand-in")
  T.eq(#e.world.entities, 4, "the player plus three entities")

  e.rooms[3]:leave()
  e:pump(4)
  T.eq(#s:entities(), 2, "a leaver despawns")
  checkMirror(e, "the mirror holds after a leave")
  e:add(5, "silver", "SILV", 0)
  e:pump(4)
  T.eq(#s:entities(), 3, "a newcomer spawns")
  checkMirror(e, "the newcomer takes the freed slot")

  local rng = 12345
  local function rand(n)
    rng = (rng * 1103515245 + 12345) % 2147483648
    return rng % n + 1
  end
  local versions = { "red", "gold", "crystal", "firered", "ruby" }
  local mirrored = true
  for i = 1, 60 do
    local n = 10 + rand(12)
    if e.rooms[n] and e.rooms[n].state ~= "left" then
      e.rooms[n]:leave()
    else
      if e.rooms[n] then
        e.rooms[n]:join(ctxFor(versions[rand(#versions)], "T" .. n, n))
      else
        e:add(n, versions[rand(#versions)], "T" .. n)
      end
    end
    e:pump(2)
    local before = T.failures
    checkMirror(e, "churn step " .. i .. " keeps the mirror")
    if T.failures ~= before then mirrored = false break end
  end
  T.check(mirrored, "sixty churn steps keep entities equal to the plaza")
  T.check(s.spawned > 10 and s.despawned > 5, "churn really spawned and despawned")
end

do
  local e = env()
  local s = e:me("crystal")
  e:pump(4)
  local slot = 2
  local x, y = RoomMap.cellFor(slot)
  e.world.player.cellX, e.world.player.cellY = x, y
  e:add(2, "red", "RED")
  e:pump(4)
  T.check(s:entity(slot) == nil and s.pending[slot] ~= nil, "a member joining onto the player's cell waits")
  e.world.player.cellX, e.world.player.cellY = x, y + 1
  e:pump(2)
  T.check(s:entity(slot) ~= nil and s.pending[slot] == nil, "the member appears once the player steps off")

  e.world.player.facing = "up"
  e.world.player.turnTimer = 0
  local r = e.world.player:tryMove("up", MAP, e.world.entities)
  T.eq(r, "blocked", "a member blocks the player's step")
  T.eq(e.world:npcAt(x, y), s:entity(slot), "the member is found where it stands")
  T.check(not s:entity(slot).passable, "members are not passable")
end

do
  local e = env()
  local s = e:me("gold")
  e:pump(4)
  for i = 2, 40 do
    e:add(i, ({ "red", "crystal", "firered", "ruby" })[i % 4 + 1], "T" .. i)
    e:pump(1)
  end
  e:pump(6)
  T.eq(#s:entities(), 39, "39 others fill the room with me")
  local seen, distinct = {}, true
  for _, ent in ipairs(s:entities()) do
    local key = ent.cellY * 64 + ent.cellX
    if seen[key] then distinct = false end
    seen[key] = true
  end
  T.check(distinct, "every member stands on its own cell")
  local ex, ey = RoomMap.entry()
  local reach, queue = { [ey * 64 + ex] = true }, { { ex, ey } }
  while #queue > 0 do
    local c = table.remove(queue, 1)
    for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
      local nx, ny = c[1] + d[1], c[2] + d[2]
      local key = ny * 64 + nx
      if MAP:isWalkable(nx, ny) and not seen[key] and not reach[key] then
        reach[key] = true
        queue[#queue + 1] = { nx, ny }
      end
    end
  end
  local talkable = true
  for _, ent in ipairs(s:entities()) do
    local any = false
    for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
      if reach[(ent.cellY + d[2]) * 64 + ent.cellX + d[1]] then any = true end
    end
    if not any then talkable = false end
  end
  T.check(talkable, "every member has a reachable cell to be talked to from")

  local r0, s0 = Avatars.stats().resolves, reads
  for _ = 1, 120 do
    e:pump(1)
    for _, ent in ipairs(s:entities()) do ent:draw(0, 0, 2) end
  end
  T.eq(reads, s0, "no cache reads while the room runs and draws")
  T.eq(Avatars.stats().resolves, r0, "no avatar resolves per frame")
end

do
  local e = env()
  local rb = e:add(2, "red", "RED")
  local s = e:me("gold")
  e:pump(6)
  local ent = s:entity(rb:self().slot)
  e.world.player.cellX, e.world.player.cellY, e.world.player.facing = ent.cellX, ent.cellY + 1, "up"
  e:pump(1)
  T.eq(s.tagged, ent, "the faced member carries the name tag")
  T.check(ent:onTalk(e.world), "talking to a member is claimed")
  T.eq(ent.facing, "down", "the member turns to the player")
  T.check(e:mash("a", function() return topMt(e) == ScriptMenu end), "the BATTLE / TRADE / CANCEL menu opens")
  T.eq(#e.stack:top().items, 3, "the menu has three rows")
  e:press("a")
  T.check(e:wait(function() return #rb:incoming() == 1 end), "a battle invite reaches the member")
  T.eq(rb:incoming()[1].mode, "battle", "the invite is a battle")
  rb:reply(rb:incoming()[1].id, false)
  T.check(e:wait(function()
    return pushedText[#pushedText] == Text.closed("declined", "RED")
  end), "a decline shows its line")
  T.check(e:mash("a", function() return s.ui == nil and e.stack:top() == nil end), "the decline line closes")
  T.eq(ent.facing, "down", "the member faces its default way after the talk")

  local screenCalled
  Activity.screens.battle = function(act) screenCalled = act end
  ent:onTalk(e.world)
  e:mash("a", function() return topMt(e) == ScriptMenu end)
  e:press("a")
  T.check(e:wait(function() return #rb:incoming() == 1 end), "a second invite arrives")
  rb:reply(rb:incoming()[1].id, true)
  T.check(e:wait(function() return s.activity ~= nil end), "an accepted invite begins the activity")
  T.check(e:wait(function() return screenCalled ~= nil end), "the activity hands over once prep rules are in")
  T.eq(screenCalled.mode, "battle", "the hand-over carries the mode")
  T.eq(screenCalled.peer.name, "RED", "the hand-over names the peer")
  T.eq(screenCalled.prep.rules and screenCalled.prep.rules.ruleset, "g3u", "Gen 2 vs Gen 1 is a g3u battle")
  screenCalled:cancel("cancel")
  local pb = rb:prep()
  T.check(e:wait(function() pb:poll() return pb.state == "closed" end), "cancel closes the peer's prep")
  T.check(e:mash("a", function() return s.activity == nil and s.ui == nil and e.stack:top() == nil end),
    "the activity ends cleanly")
  Activity.screens.battle = nil

  ent:onTalk(e.world)
  e:mash("a", function() return topMt(e) == ScriptMenu end)
  e:press("a")
  e:wait(function() return #rb:incoming() == 1 end)
  T.check(e:wait(function() local t = e.stack:top() return t and t.tick ~= nil end), "the waiting line is up")
  e:press("b")
  T.check(e:wait(function() return pushedText[#pushedText] == Text.cancelled(e.game) end),
    "B while waiting cancels with the cart line")
  rb:reply(rb:incoming()[1].id, true)
  e:pump(6)
  T.check(s.activity == nil, "an invite accepted after cancelling never opens an activity")
  e:mash("a", function() return e.stack:top() == nil end)
  T.check(e:wait(function() return e.mine.room() == nil end), "the late room is left")
end

do
  local e = env()
  local rb = e:add(2, "firered", "LEAF", 1, "g3:3")
  local s = e:me("crystal")
  e:pump(6)
  local ent = s:entity(rb:self().slot)
  local h = rb:invite(pid(1), "xg_trade")
  T.check(e:wait(function() return topMt(e) == TextBox end), "an incoming request opens a prompt")
  T.eq(pushedText[#pushedText], Text.say("askTrade", "LEAF"), "the prompt names the requester and trade")
  T.eq(ent.facing, "down", "the requester turns toward the player")
  T.check(e:mash("a", function() return topMt(e) == ChoiceBox end), "YES / NO comes up")
  e:press("down")
  e:press("a")
  T.check(e:wait(function() return s.ui == nil and e.stack:top() == nil end), "NO closes the prompt")
  T.check(e:wait(function() return h.state == "closed" and h.why == "declined" end), "the requester sees the decline")

  rb:invite(pid(1), "xg_battle")
  e:wait(function() return topMt(e) == TextBox end)
  T.eq(pushedText[#pushedText], Text.say("askBattle", "LEAF"), "a battle request names battle")
  e:mash("a", function() return topMt(e) == ChoiceBox end)
  e:press("a")
  T.check(e:wait(function() return s.activity ~= nil end), "YES begins the activity")
  local pb = rb:prep()
  T.check(e:mash("a", function() return s.activity and s.activity.waiter and s.activity.waiter:shown() end),
    "the getting-ready line is up")
  e:press("b")
  T.check(e:wait(function() return pushedText[#pushedText] == Text.cancelled(e.game) end),
    "B on the getting-ready line cancels with the cart line")
  T.check(e:wait(function() pb:poll() return pb.state == "closed" end), "the requester's prep closes")
  e:mash("a", function() return s.activity == nil and e.stack:top() == nil end)
  T.check(s.activity == nil, "the activity is gone after the cancel line")

  rb:invite(pid(1), "xg_battle")
  e:wait(function() return topMt(e) == TextBox end)
  e:mash("a", function() return topMt(e) == ChoiceBox end)
  e:press("a")
  e:wait(function() return s.activity ~= nil end)
  e:mash("a", function() return s.activity and s.activity.waiter and s.activity.waiter:shown() end)
  local pr = rb:prep()
  pr:cancel("cancel")
  T.check(e:wait(function() return pushedText[#pushedText] == Text.say("peerCancel", "LEAF") end),
    "a peer cancel shows the peer's line")
end

do
  local e = env({ legacy = true })
  local s = e:me("gold")
  e:pump(8)
  T.eq(s.state, "offline", "an old relay leaves the presence offline")
  T.eq(s.err, "server_outdated", "the error is server_outdated")
  T.check(e:wait(function() return pushedText[#pushedText] == Text.error("server_outdated") end),
    "the server_outdated line is shown")
  T.eq(#s:entities(), 0, "the room stays empty")
  T.check(Text.error("server_outdated") ~= Text.error("client_outdated"), "outdated texts differ per side")
end

do
  local e = env()
  local rb = e:add(2, "red", "RED")
  local s = e:me("gold")
  e:pump(6)
  local ent = s:entity(rb:self().slot)
  for _ = 1, 40 do e:pump(1) end
  T.eq(ent.alpha, 1, "members are fully shown while linked")
  e.relay:drop(e.mySeat)
  e:pump(2)
  T.check(s.lost, "a dropped link is noticed")
  for _ = 1, 30 do e:pump(1) end
  T.eq(ent.alpha, Presence.FADE, "members fade while reconnecting")
  T.check(e:wait(function() return pushedText[#pushedText] == Text.S.lost end), "the reconnecting line shows")
  e.relay:reconnect(e.mySeat)
  CLOCK = CLOCK + 2
  T.check(e:wait(function() return not s.lost end), "the link comes back")
  for _ = 1, 30 do e:pump(1) end
  T.eq(ent.alpha, 1, "members come back")
  T.eq(s:entity(rb:self().slot), ent, "the same entity stands in the same slot after the resume")
  T.check(e:wait(function() return e.stack:top() == nil and s.ui == nil end), "the reconnecting line closes itself")
end

do
  local e = env()
  package.loaded["src.online.Client"] = nil
  local C = require("src.online.Client")
  C.reset()
  C.configure({ relayAddress = "fake:3", connect = function() return nil, "no route" end })
  local Connect = {
    start = function() return C.connect({ name = "ME", profiles = {} }) end,
  }
  local s = Presence.new(e.game, e.world, { client = C, room = Room.new({ client = C }),
                                            ctx = ctxFor("gold", "ME", 1), connect = Connect })
  e.session = s
  e:pump(2)
  T.eq(s.state, "offline", "no network leaves the room offline")
  T.check(e:wait(function() return pushedText[#pushedText] == Text.error("offline") end),
    "the no-network line is shown")
  e:mash("a", function() return e.stack:top() == nil end)
  T.check(s:idle(), "the room works as an empty room afterwards")
end

TextBox.new = realNew
T.finish("union_gen2_presence")
