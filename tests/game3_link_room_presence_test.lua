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

local session = { name = "RED", gender = 0, trainerId = 0x1234, version = "firered" }
package.loaded["src.core.game3.runtime"] = {
  getSession = function() return session end,
  _game = { session = session, data = { maps = {} } },
}
local Player = { cellX = 1, cellY = 22, facing = "up" }
package.loaded["src.core.game3.player"] = Player

local Plaza = require("src.core.game3.link.union_plaza_map")
package.loaded["src.core.game3.scripting.space"] = { mapId = Plaza.MAP_ID }
package.loaded["src.core.game3.collision"] = {
  _mapId = Plaza.MAP_ID,
  inBounds = function(x, y) return x >= 0 and y >= 0 and x < Plaza.WIDTH and y < Plaza.HEIGHT end,
  isWater = function() return false end,
  canEnter = function(_, x, y) return Plaza.roleAt(x, y) == "." end,
}
local VirtualObjects = require("src.core.game3.virtual_objects")
package.loaded["src.core.game3.objects"] = {
  blocks = function(x, y)
    for _, vo in ipairs(VirtualObjects.list()) do
      if vo.solid and ((vo.x == x and vo.y == y) or (vo.prevX == x and vo.prevY == y)) then return true end
    end
    return false
  end,
}

local Wander = require("src.core.game3.link.plaza_wander")

do
  local function trace(seed)
    local w = Wander.new(seed, 5, 5)
    local env = { canWander = true, free = function() return true end }
    local out = {}
    for i = 1, 3000 do
      Wander.tick(w, env)
      out[i] = w.x * 100 + w.y
    end
    return out, w
  end
  local a = trace(42)
  local b = trace(42)
  local same, left, far = true, false, 0
  for i = 1, #a do
    if a[i] ~= b[i] then same = false end
    local x, y = math.floor(a[i] / 100), a[i] % 100
    if x ~= 5 or y ~= 5 then left = true end
    far = math.max(far, math.abs(x - 5), math.abs(y - 5))
  end
  check(same, "the same seed walks the same path")
  check(left, "an idle avatar leaves its cell now and then")
  check(far <= Wander.RADIUS, "and never strays past its radius (" .. far .. ")")

  local w = Wander.new(7, 5, 5)
  local env = { canWander = true, free = function() return true end }
  local guard = 0
  while Wander.atHome(w) and guard < 5000 do Wander.tick(w, env); guard = guard + 1 end
  check(not Wander.atHome(w), "the avatar starts a walk")
  env.canWander = false
  for _ = 1, 400 do Wander.tick(w, env) end
  check(Wander.atHome(w), "and walks back home when it may not wander")
  local still = Wander.new(9, 5, 5)
  for _ = 1, 3000 do Wander.tick(still, { canWander = false, free = function() return true end }) end
  check(Wander.atHome(still), "a busy avatar never moves")
end

local Union = require("src.core.game3.link.union_room")
Union.graphicsIdFor = function() return 1 end
Union._avatars = { opposite_facing = { 0, 2, 1, 4, 3 }, member_facing = { 1, 3, 1, 4, 2 } }
Union.state = "main"
Union._vobjs = {}
Union.players = {
  [1] = { id = "b", name = "BLUE", gender = 0, trainerId = 2, status = "idle", activity = Union.ACTIVITY.NONE + Union.IN_UNION_ROOM },
  [2] = { id = "g", name = "GREEN", gender = 1, trainerId = 3, status = "chatting", activity = Union.ACTIVITY.CHAT + Union.IN_UNION_ROOM },
  [3] = { id = "y", name = "YELLOW", gender = 1, trainerId = 4, status = "trading", activity = Union.ACTIVITY.TRADE + Union.IN_UNION_ROOM },
  [4] = { id = "p", name = "PINK", gender = 1, trainerId = 5, status = "battling", activity = Union.ACTIVITY.BATTLE_SINGLE + Union.IN_UNION_ROOM },
}
Union.refreshPlaza()

eq(Union.memberStatusKind(Union.players[1]), nil, "an idle member shows no status")
eq(Union.memberStatusKind(Union.players[2]), "chat", "chatting shows the chat icon")
eq(Union.memberStatusKind(Union.players[3]), "trade", "trading shows the trade icon")
eq(Union.memberStatusKind(Union.players[4]), "battle", "battling shows the battle icon")
eq(Union.memberStatusKind({ activity = Union.ACTIVITY.CARD + Union.IN_UNION_ROOM }), "chat",
  "with no relay status the activity decides")

local hx, hy = Union.cellFor(1)
local bx, by = Union.cellFor(2)
local leftHome, moved2, maxOff = false, false, 0
local awayAt
for _ = 1, 4000 do
  Union.animateAll()
  local rec = VirtualObjects.get(Union.vobjId(1))
  if rec and (rec.x ~= hx or rec.y ~= hy) then
    leftHome = true
    maxOff = math.max(maxOff, math.abs(rec.x - hx), math.abs(rec.y - hy))
    if not rec.moving and not awayAt then awayAt = { rec.x, rec.y } end
  end
  local rec2 = VirtualObjects.get(Union.vobjId(2))
  if rec2 and (rec2.x ~= bx or rec2.y ~= by) then moved2 = true end
  if awayAt then break end
end
check(leftHome, "an idle plaza avatar wanders off its cell")
check(maxOff <= 1, "inside its own 3x3 box")
check(not moved2, "a chatting avatar stays put")

if awayAt then
  Player.cellX, Player.cellY, Player.facing, Player.moving = awayAt[1], awayAt[2] + 1, "up", false
  if Plaza.roleAt(Player.cellX, Player.cellY) ~= "." then
    Player.cellY, Player.facing = awayAt[2] - 1, "down"
  end
  eq(Union.tryInteractWithMember(), 1, "talking reaches the avatar where it stands now")
  for _ = 1, 200 do Union.animateAll() end
  local rec = VirtualObjects.get(Union.vobjId(1))
  check(rec and rec.x == awayAt[1] and rec.y == awayAt[2], "and it holds still while talked to")
  Union.updateMemberFacing(1)
  Player.cellX, Player.cellY = 1, 22
  local home = false
  for _ = 1, 4000 do
    Union.animateAll()
    local r = VirtualObjects.get(Union.vobjId(1))
    if r and r.x == hx and r.y == hy and not r.moving then home = true break end
  end
  check(home, "after the talk it walks back to its own cell")
else
  check(false, "the idle avatar never stopped away from home")
end

local LinkTags = require("src.ui.game3.link_tags")
local src = LinkTags.sources()
check(src ~= nil, "the Union Room has tags")
local t1 = src and src.byVobj[Union.vobjId(1)]
eq(t1 and t1.name, "BLUE", "the badge carries the relay avatar name")
eq(t1 and t1.kind, nil, "idle has no icon")
eq(src and src.byVobj[Union.vobjId(2)] and src.byVobj[Union.vobjId(2)].kind, "chat", "chatting badge")
eq(src and src.player and src.player.name, "RED", "the local player gets a badge too")
eq(LinkTags.tagFor(src, { kind = "player" }), src and src.player, "the player actor maps to its badge")
eq(LinkTags.tagFor(src, { kind = "npc", eventObject = { virtualId = Union.vobjId(3) } }), src and src.byVobj[Union.vobjId(3)],
  "a plaza avatar maps to its badge")

local measure = function(name) return #name * 6 end
local left = LinkTags.layout({ name = "LONGNAME", kind = "trade" }, 0, 40, 240, measure)
check(left.x >= LinkTags.EDGE, "a badge at the left edge stays on screen")
local right = LinkTags.layout({ name = "LONGNAME", kind = "battle" }, 240, 40, 240, measure)
check(right.x + right.w <= 240 - LinkTags.EDGE, "a badge at the right edge stays on screen")
local plain = LinkTags.layout({ name = "WALLACEMORE" }, 120, 40, 240, function() return 999 end)
eq(plain.textW, LinkTags.MAX_TEXT_W, "long names are clipped to the badge width")
for kind in pairs(LinkTags.ICONS) do
  local w, h = LinkTags.iconSize(kind)
  check(h <= LinkTags.PLATE_H and w > 0, kind .. " icon fits the badge")
end

local LP = require("src.core.game3.link.link_players")
LP._mapId = "tradeCenter"
LP._remotes[1] = { busy = true, name = "GREEN", x = 4, y = 5 }
LP._remotes[2] = { busy = false, name = "GOLD", x = 7, y = 5 }
eq(LP.statusKind(1), "trade", "a busy player in the Trade Center is trading")
eq(LP.statusKind(2), nil, "an idle one has no icon")
LP._mapId = "colosseum2P"
eq(LP.statusKind(1), "battle", "a busy player in the Colosseum is battling")
src = LinkTags.sources()
eq(src and src.byVobj[LP.VOBJ_BASE + 1] and src.byVobj[LP.VOBJ_BASE + 1].name, "GREEN", "link room avatars get badges")
LP._remotes, LP._mapId = {}, nil

if failed > 0 then
  print(("FAIL game3_link_room_presence_test (%d)"):format(failed))
  os.exit(1)
end
print("PASS game3_link_room_presence_test")
