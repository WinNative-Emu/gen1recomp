package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")
local T = require("tests.harness")
local FakeRelay = require("tests.support.fake_relay")
local GameVersion = require("src.core.GameVersion")
local Participant = require("src.online.union.Participant")
local Room = require("src.online.union.Room")
local Avatars = require("src.online.union.Avatars")
local Collision = require("src.world.Collision")
local StateStack = require("src.core.StateStack")
local UnionRoomMap = require("src.world.gen1.UnionRoomMap")
local Presence = require("src.world.gen1.UnionRoomPresence")
local Text = require("src.ui.union.gen1.Text")
require("src.ui.union.gen1.Activity").installed = true
local Font = require("src.render.Font")

local CLOCK = 0
love.timer.getTime = function() return CLOCK end

GameVersion.set("red")

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

local reads = 0
Avatars.setReader(function() reads = reads + 1 return nil end)

local Input = {}
Input.__index = Input
function Input:wasPressed(k) return self.pressed[k] == true end
function Input:isDown() return false end
function Input:press(k) self.pressed[k] = true end
function Input:clear() self.pressed = {} end

local function newGame()
  local stack = setmetatable({}, { __index = StateStack })
  stack:init()
  local player = { cellX = 12, cellY = 25, px = 12 * 16, py = 25 * 16, facing = "up" }
  local ow = {
    isOverworld = true, map = { id = UnionRoomMap.MAP_ID }, player = player,
    npcs = {}, entities = { player }, scriptMoves = {},
    runner = { isRunning = function() return false end },
  }
  local game = {
    stack = stack, overworld = ow,
    input = setmetatable({ pressed = {} }, Input),
    data = { sprites = {}, field = {}, audio = { sfx = {} },
             text = { _CableClubNPCPleaseWaitText = "Please wait.{DONE}" } },
    save = { player = { name = "RED", id = 4321 }, options = {}, flags = {} },
  }
  stack:push(ow)
  return game, ow
end

local World = {}
World.__index = World

local function newWorld()
  return setmetatable({ relay = FakeRelay.new({ clock = function() return CLOCK end }),
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

local function presenceFor(w, game, opts)
  opts = opts or {}
  local room, C, seat = w:add(1, "RED")
  w:pump()
  local p = Presence.new(game, {
    room = room,
    connect = opts.connect or function() return true end,
    ctx = { profile = profileFor("red"), vanillaFingerprint = FP.red, gameplayMods = false },
  })
  game.unionPresence = p
  p:start()
  return p, room, C, seat
end

local function step(w, game, n)
  for _ = 1, n or 1 do
    w:pump(1)
    game.stack:update(1 / 60)
    if game.unionPresence then game.unionPresence:tick() end
    game.input:clear()
  end
end

local function topText(game)
  local top = game.stack:top()
  if not (top and top.pages) then return nil end
  local out = {}
  for _, page in ipairs(top.pages) do
    for _, line in ipairs(page) do out[#out + 1] = type(line) == "table" and (line.text or "") or tostring(line) end
  end
  return table.concat(out, " ")
end

local function until_(w, game, cond, n)
  for _ = 1, n or 600 do
    if cond() then return true end
    step(w, game, 1)
  end
  return cond()
end

local function mashUntil(w, game, cond, n)
  for i = 1, n or 600 do
    if cond() then return true end
    local top = game.stack:top()
    if top and top.pages and (top.waiting or (top.done and not top.stay and not top.choice)) and i % 2 == 0 then game.input:press("a") end
    step(w, game, 1)
  end
  return cond()
end

local function count(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

local function has(list, item)
  for _, v in ipairs(list) do if v == item then return true end end
  return false
end

do
  local long = "ABCDEFGHIJ"
  for key in pairs(Text.S) do
    local s = Text.say(key, long, long, long)
    for line in (s:gsub("[\f\v]", "\n") .. "\n"):gmatch("(.-)\n") do
      T.check(Font.glyphCount(line) <= 18, ("Gen 1 line fits 18 columns: %s %q"):format(key, line))
    end
  end
  for _, code in ipairs({ "server_outdated", "client_outdated", "offline", "lost", "bad_avatar" }) do
    T.check(type(Text.error(code)) == "string" and #Text.error(code) > 0, "error text for " .. code)
  end
  T.check(Text.error("server_outdated") ~= Text.error("offline"), "server_outdated has its own line")
  local b = Text.blocked("policy_mismatch")
  T.check(b == b:upper(), "blocked text is uppercase in the Gen 1 register")
  for line in (b:gsub("\f", "\n") .. "\n"):gmatch("(.-)\n") do
    T.check(#line <= 18, "blocked line fits 18 columns: " .. line)
  end
  T.eq(Text.closed("declined", "GOLD"), Text.say("declined", "GOLD"), "declined invite text")
  T.eq(Text.closed("busy", "GOLD"), Text.say("busy", "GOLD"), "busy invite text")
  T.eq(Text.closed("target_left", "GOLD"), Text.say("gone", "GOLD"), "left invite text")
  T.eq(Text.closed("weird", "GOLD"), Text.say("refused", "GOLD"), "unknown invite close text")
  T.check(Text.standin({ name = "MAY", game = "ruby" }, { need = { "ruby", "sapphire" } }):find("RUBY", 1, true) ~= nil,
    "stand-in text names the import")
end

do
  local w = newWorld()
  local game, ow = newGame()
  local p, room = presenceFor(w, game)
  T.eq(p.state, "joining", "online client joins right away")
  local others = {
    { 2, "BLUE", "blue", 0, nil }, { 3, "KRIS", "crystal", 1, nil },
    { 4, "LEAF", "leafgreen", 1, "g3:3" }, { 5, "MAY", "ruby", 1, "player" },
  }
  local rooms = {}
  for i, o in ipairs(others) do
    rooms[i] = w:add(o[1], o[2])
  end
  w:pump()
  for i, o in ipairs(others) do rooms[i]:join(ctxFor(o[3], o[2], o[1], o[4], o[5])) end
  step(w, game, 4)
  T.eq(p.state, "joined", "presence reaches joined")
  T.eq(count(p.members), 4, "four participants spawn")
  for _, m in pairs(p.members) do
    local cell = Presence.cellFor(m.p.slot)
    T.eq(m.cellX .. "," .. m.cellY, cell.x .. "," .. cell.y, "member stands on its slot cell " .. m.p.slot)
    T.check(has(ow.npcs, m) and has(ow.entities, m), "member is in npcs and entities")
    T.eq(Collision.occupied(ow.entities, cell.x, cell.y), m, "member blocks its cell")
  end
  T.check(has(ow.entities, p.overlay), "the tag overlay rides the draw list")
  T.check(p.overlay.passable, "the overlay never blocks")
  local kris = p:memberById(pid(3))
  T.eq(kris.p.gen, 2, "Crystal member is Gen 2")
  T.eq(kris.digit, 2, "Crystal member badge digit 2")
  T.check(kris.entry.standin, "Crystal not imported here reads as a stand-in")
  T.eq(p:memberById(pid(4)).p.style, "g3:3", "FRLG class style is kept")

  local readsBefore = reads
  local resolves = Avatars.stats().resolves
  for _ = 1, 120 do
    step(w, game, 1)
    for _, m in pairs(p.members) do m:draw(0, 0) end
    p.overlay:draw(0, 0)
  end
  T.eq(reads, readsBefore, "no cache reads while ticking and drawing")
  T.eq(Avatars.stats().resolves, resolves, "no avatar resolves while ticking and drawing")

  rooms[2]:leave()
  step(w, game, 3)
  T.eq(p:memberById(pid(3)), nil, "a leaver despawns")
  T.check(not has(ow.npcs, kris) and not has(ow.entities, kris), "the leaver is gone from npcs and entities")
  local slot = kris.p.slot
  local rs = w:add(6, "SILV")
  w:pump()
  rs:join(ctxFor("silver", "SILV", 6, 0))
  step(w, game, 3)
  local silv = p:memberById(pid(6))
  T.check(silv ~= nil and silv.p.slot == slot, "a newcomer takes the freed slot")
  local n = 0
  for _, e in ipairs(ow.entities) do if e.unionMember then n = n + 1 end end
  T.eq(n, 4, "no stale entities after churn")
  rs:setStatus("busy")
  step(w, game, 3)
  T.eq(silv.p.status, "busy", "status change reaches the member")

  ow.npcs, ow.entities = {}, { ow.player }
  step(w, game, 1)
  T.eq(#ow.npcs, 4, "members rebind after the world rebuilds its lists")

  ow.map = { id = "POKECENTER_2F" }
  step(w, game, 2)
  T.eq(game.unionPresence, nil, "leaving the map drops the presence")
  T.eq(#ow.npcs, 0, "leaving removes every member")
  T.eq(#w.relay:sent(w.seats[1], "plaza_leave"), 1, "leaving sends plaza_leave")
end

do
  local w = newWorld()
  local game, ow = newGame()
  local p = presenceFor(w, game)
  local rooms = {}
  for i = 1, 39 do
    rooms[i] = w:add(100 + i, "T" .. i)
  end
  w:pump()
  for i = 1, 39 do
    local v = ({ "red", "gold", "firered", "crystal", "emerald" })[(i % 5) + 1]
    rooms[i]:join(ctxFor(v, "T" .. i, i, i % 2))
    w:pump(1)
  end
  step(w, game, 4)
  T.eq(count(p.members), 39, "39 others spawn in a full room")
  local seen = {}
  local distinct = true
  for _, m in pairs(p.members) do
    local key = m.cellX .. "," .. m.cellY
    if seen[key] then distinct = false end
    seen[key] = true
    for _, e in ipairs(UnionRoomMap.EXITS) do
      T.check(not (e.x == m.cellX and e.y == m.cellY), "no member on an exit cell")
    end
    T.check(m.cellX >= 0 and m.cellX < UnionRoomMap.WIDTH * 2 and m.cellY >= 2 and m.cellY < UnionRoomMap.HEIGHT * 2,
      "member cell inside the room floor")
  end
  T.check(distinct, "40 trainers stand on distinct cells")
  local map = { inBounds = function() return true end, isWalkableCell = function() return true end,
                cellTile = function() return 0 end, def = {} }
  local m = p.members[2]
  ow.player.cellX, ow.player.cellY = m.cellX, m.cellY + 1
  local ok, why = Collision.canMove(map, ow.entities, ow.player, "up")
  T.check(not ok and why == "entity", "the player can't walk into a member")
  ow.player.facing = "up"
  step(w, game, 1)
  T.eq(p.focus, m, "the faced member gets the name tag")
  T.eq(p.overlay.py, m.py + 0.5, "the tag draws right after its member")
  p:leave()
end

do
  local w = newWorld()
  local game, ow = newGame()
  local p = presenceFor(w, game)
  local cell = Presence.cellFor(2)
  ow.player.cellX, ow.player.cellY = cell.x, cell.y
  local rb = w:add(2, "GOLD")
  w:pump()
  rb:join(ctxFor("gold", "GOLD", 2, 0))
  step(w, game, 4)
  T.eq(p.members[2], nil, "a member does not spawn on the player")
  T.check(p.pending[2] ~= nil, "the member waits for its cell")
  ow.player.cellX, ow.player.cellY = cell.x + 1, cell.y
  step(w, game, 1)
  T.check(p.members[2] ~= nil, "the member spawns once the cell is free")
  p:leave()
end

do
  local w = newWorld()
  local game, ow = newGame()
  local p = presenceFor(w, game)
  local rb = w:add(2, "MAY")
  w:pump()
  rb:join(ctxFor("emerald", "MAY", 2, 1, "g3:2"))
  step(w, game, 4)
  local m = p.members[2]
  Presence.talk(game, ow, m, function() end)
  T.check(mashUntil(w, game, function() return getmetatable(game.stack:top()) == require("src.ui.Menu") end, 300),
    "talking opens the BATTLE/TRADE/CANCEL menu")
  local menu = game.stack:top()
  T.eq(#menu.items, 3, "three choices")
  T.eq(menu.items[1].label, "BATTLE", "BATTLE first")
  T.eq(menu.items[3].label, "CANCEL", "CANCEL last")
  T.check(p.busy, "the presence is busy while the menu is open")
  step(w, game, 2)
  rb:poll()
  T.eq(rb:member(pid(1)).status, "busy", "others see us busy while talking")
  game.input:press("a")
  step(w, game, 1)
  T.check(until_(w, game, function() return #rb:incoming() == 1 end, 60), "BATTLE sends an invite")
  T.eq(rb:incoming()[1].mode, "battle", "the invite is a battle")
  rb:reply(rb:incoming()[1].id, true)
  T.check(until_(w, game, function() return p.room:xgRoom() ~= nil end, 60), "the accept opens an xg room")
  T.check(until_(w, game, function()
    local t = topText(game) or ""
    return t:find("Getting ready", 1, true) ~= nil
  end, 600), "accepted invite shows the getting ready line")
  local prep = p.room:prep()
  T.eq(prep.state, "prep", "the prep reached the point prep screens start")
  local peer = rb:prep()
  peer:poll()
  T.check(until_(w, game, function() return game.stack:top() and game.stack:top().tick ~= nil end, 120),
    "the waiter is up")
  game.input:press("b")
  step(w, game, 2)
  w:pump()
  peer:poll()
  T.eq(peer.state, "closed", "B cancels the prep for the peer")
  T.eq(p.room.prepObj, nil, "the prep is dropped")
  T.check((topText(game) or ""):find("canceled", 1, true) ~= nil, "cancel line shown")
  p:leave()
end

do
  local w = newWorld()
  local game, ow = newGame()
  local p = presenceFor(w, game)
  local rb = w:add(2, "GOLD")
  w:pump()
  rb:join(ctxFor("gold", "GOLD", 2, 0))
  step(w, game, 4)
  rb:setStatus("busy")
  step(w, game, 3)
  Presence.talk(game, ow, p.members[2], function() end)
  T.check((topText(game) or ""):find("busy", 1, true) ~= nil, "a busy member gives the busy line")
  T.check(not p.busy, "a busy line does not hold our status")
  game.stack:pop()
  rb:setStatus("idle")
  step(w, game, 3)

  local h = require("src.ui.union.gen1.Talk").invite(game, p, p.members[2].p, "xg_trade", function() end)
  step(w, game, 2)
  T.eq(rb:incoming()[1].mode, "trade", "TRADE sends a trade invite")
  rb:reply(rb:incoming()[1].id, false)
  T.check(until_(w, game, function() return h.state == "closed" end, 60), "the decline closes the invite")
  T.check(until_(w, game, function() return (topText(game) or ""):find("said no", 1, true) ~= nil end, 300),
    "the decline line shows")
  game.stack:pop()
  step(w, game, 2)

  local h2 = require("src.ui.union.gen1.Talk").invite(game, p, p.members[2].p, "xg_battle", function() end)
  until_(w, game, function() return game.stack:top() and game.stack:top().tick ~= nil end, 300)
  game.input:press("b")
  step(w, game, 2)
  T.check(p.abandoned[h2], "B while waiting abandons the invite")
  rb:reply(rb:incoming()[1].id, true)
  T.check(until_(w, game, function() return next(p.abandoned) == nil end, 60), "the abandoned handle is swept")
  w:pump()
  T.eq(rb:xgRoom(), nil, "a late accept of an abandoned invite is cancelled for the peer")
  T.eq(p.room:xgRoom(), nil, "and we are out of the xg room")
  p:leave()
end

do
  local w = newWorld()
  local game, ow = newGame()
  local p = presenceFor(w, game)
  local rb = w:add(2, "LEAF")
  w:pump()
  rb:join(ctxFor("firered", "LEAF", 2, 1))
  step(w, game, 4)
  rb:poll()
  rb:invite(pid(1), "xg_battle")
  step(w, game, 3)
  local top = game.stack:top()
  T.check(top and top.choice ~= nil, "an incoming invite opens a yes/no prompt")
  T.check((topText(game) or ""):find("BATTLE", 1, true) ~= nil, "the prompt names the battle")
  T.eq(p.members[2].facing, "down", "the inviter turns toward the player")
  T.eq(p.focus, p.members[2], "the inviter wears the name tag while asking")
  local ChoiceBox = require("src.ui.ChoiceBox")
  T.check(mashUntil(w, game, function() return getmetatable(game.stack:top()) == ChoiceBox end, 600),
    "the YES/NO box comes up")
  game.input:press("a")
  T.check(until_(w, game, function() return rb:xgRoom() ~= nil end, 120), "accepting opens the xg room for the inviter")
  T.check(until_(w, game, function() return (topText(game) or ""):find("Getting ready", 1, true) ~= nil end, 600),
    "accepting an invite reaches the getting ready line")
  p:leave()

  local w2 = newWorld()
  local game2 = newGame()
  local p2 = presenceFor(w2, game2)
  local rc = w2:add(2, "LEAF")
  w2:pump()
  rc:join(ctxFor("firered", "LEAF", 2, 1))
  step(w2, game2, 4)
  rc:poll()
  local hc = rc:invite(pid(1), "xg_trade")
  step(w2, game2, 3)
  mashUntil(w2, game2, function() return getmetatable(game2.stack:top()) == ChoiceBox end, 600)
  game2.input:press("b")
  until_(w2, game2, function() return hc.state == "closed" end, 120)
  T.eq(hc.state, "closed", "declining closes the inviter's handle")
  T.eq(hc.why, "declined", "the inviter hears declined")
  T.check(not p2.busy, "declining frees the presence")
  p2:leave()
end

do
  local w = newWorld()
  local game = newGame()
  local offline = { state = function() return "offline" end }
  local p = Presence.new(game, {
    room = Room.new({ client = offline }),
    connect = function() return false, "no route" end,
    ctx = { profile = profileFor("red"), vanillaFingerprint = FP.red, gameplayMods = false },
  })
  game.unionPresence = p
  p:start()
  T.eq(p.state, "offline", "a failed connect leaves the room empty")
  step(w, game, 1)
  T.check((topText(game) or ""):find("No other", 1, true) ~= nil, "offline line reads as empty room")
  T.eq(count(p.members), 0, "offline has no members")
  p:leave()
end

do
  local w = newWorld()
  local game = newGame()
  local p, room, C, seat = presenceFor(w, game)
  local rb = w:add(2, "GOLD")
  w:pump()
  rb:join(ctxFor("gold", "GOLD", 2, 0))
  step(w, game, 4)
  local before = p.members[2]
  w.relay:drop(seat)
  step(w, game, 2)
  T.eq(p.state, "reconnecting", "a dropped link is reconnecting")
  for _ = 1, Presence.LOST_SHOW_FRAMES + 2 do
    p:tick()
  end
  T.check((topText(game) or ""):find("Reconnecting", 1, true) ~= nil, "the reconnecting line shows")
  T.eq(p.members[2], before, "members stay while reconnecting")
  w.relay:reconnect(seat)
  CLOCK = CLOCK + 2
  step(w, game, 8)
  T.eq(C.state(), "online", "the client resumes")
  T.eq(p.state, "joined", "the presence resumes")
  T.eq(p.members[2], before, "the member object survives the resume")
  T.check(game.stack:top() == game.overworld, "the reconnecting box closes")
  p:leave()
end

do
  local w = newWorld()
  local game = newGame()
  local p = presenceFor(w, game)
  local rb = w:add(2, "GOLD")
  w:pump()
  local ctx = ctxFor("gold", "GOLD", 2, 0)
  ctx.caps = { proto = 1, policy = 99, gens = { ["2"] = { { version = "gold", fp = FP.gold } } } }
  rb:join(ctx)
  step(w, game, 4)
  local Talk = require("src.ui.union.gen1.Talk")
  Talk.invite(game, p, p.members[2].p, "xg_trade", function() end)
  step(w, game, 2)
  rb:reply(rb:incoming()[1].id, true)
  T.check(mashUntil(w, game, function()
    local t = topText(game) or ""
    return t:find("VERSION", 1, true) ~= nil
  end, 900), "a policy mismatch shows the blocked line in Gen 1 caps")
  T.eq(p.activity and p.activity.why, "blocked", "the activity finished as blocked")
  w:pump(4)
  T.eq(p.room:xgRoom(), nil, "the blocked prep room is left")
  p:leave()

  local w2 = newWorld()
  local game2 = newGame()
  local p2 = presenceFor(w2, game2)
  local rc = w2:add(2, "MAY")
  w2:pump()
  rc:join(ctxFor("ruby", "MAY", 2, 1))
  step(w2, game2, 4)
  Talk.invite(game2, p2, p2.members[2].p, "xg_trade", function() end)
  step(w2, game2, 2)
  rc:reply(rc:incoming()[1].id, true)
  T.check(until_(w2, game2, function() return p2.activity and p2.activity.state == "ready" end, 900),
    "a trade reaches the ready stage")
  T.check((topText(game2) or ""):find("TRADE", 1, true) ~= nil, "ready trade line")
  local peer = rc:prep()
  peer:poll()
  peer:cancel("cancel")
  T.check(until_(w2, game2, function()
    return (topText(game2) or ""):find("canceled", 1, true) ~= nil
  end, 600), "the peer cancelling shows a line")
  T.check(mashUntil(w2, game2, function() return p2.activity == nil end, 600), "and ends the activity")
  T.check(not p2.busy, "the presence is free after the peer cancels")
  p2:leave()
end

local function cacheText(version)
  local home = os.getenv("HOME")
  if not home or home == "" then return nil end
  for _, base in ipairs({ home .. "/Library/Application Support/LOVE", home .. "/.local/share/love" }) do
    for _, id in ipairs({ "g1r-" .. version, "pokeport-test-caches" }) do
      local f = io.open(base .. "/" .. id .. "/" .. version .. "/data/generated/text.lua", "rb")
      if f then
        local body = f:read("*a")
        f:close()
        local chunk = load(body, "@text", "t", {})
        local ok, mod = pcall(chunk)
        if ok then return mod end
      end
    end
  end
  return nil
end

for _, version in ipairs({ "red", "blue", "yellow" }) do
  local text = cacheText(version)
  if text then
    local line = Text.pleaseWait({ data = { text = text } })
    T.check(line:find("Please wait.", 1, true) == 1, version .. " cache carries the cable club wait line")
  else
    print("[skip] no " .. version .. " cache for the cart wait line")
  end
end

T.finish()
