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

local session = { version = "ruby", map = "RU_OLDALE_TOWN_POKEMON_CENTER_2F", x = 2, y = 2, party = {} }
package.loaded["src.core.game3.runtime"] = { getSession = function() return session end, isActive = function() return true end }

local Plaza = require("src.core.game3.link.union_plaza_map")
local UnionRs = require("src.core.game3.rse.union_rs")
local Union = require("src.core.game3.link.union_room")

print("[test] RS map ids")
eq(Plaza.KIND, "rs", "Ruby builds the RS room")
eq(Plaza.SOURCE_ID, nil, "Ruby has no cart Union Room to redirect")
eq(Plaza.TILE_SOURCE_ID, "RU_RECORD_CORNER", "tiles come from Ruby's own Record Corner")
eq(Plaza.MAP_ID, "RU_UNION_ROOM", "the added room id")
check(Union.isUnionMap("RU_UNION_ROOM"), "the RS room is a Union Room map")
check(not Union.isUnionMap("RU_RECORD_CORNER"), "the Record Corner is not")

print("[test] RS role grid")
local roles, source, blocked = Plaza.tables("rs")
eq(#roles, 25, "25 rows")
local bad
for y, row in ipairs(roles) do
  if #row ~= 25 then bad = y end
  for i = 1, #row do if not source[row:sub(i, i)] then bad = y end end
end
check(bad == nil, "every row is 25 wide with known roles: " .. tostring(bad))
for slot = 1, Plaza.CAP do
  local x, y = Plaza.cellFor(slot)
  local r = Plaza.roleAt(x, y, "rs")
  if r ~= "." then check(false, "slot " .. slot .. " is on floor") end
end
local ex, ey = Plaza.entry()
eq(Plaza.roleAt(ex, ey, "rs"), "p", "entry is an exit pad")
eq(#Plaza.EXITS, 3, "three exit pads")
local function key(x, y) return y * 64 + x end
local cells = {}
for _, c in ipairs(Plaza.CELLS) do cells[key(c.x, c.y)] = true end
local function walk(x, y)
  local r = Plaza.roleAt(x, y, "rs")
  return r ~= nil and not blocked[r] and not cells[key(x, y)]
end
local reach, queue, head = { [key(ex, ey)] = true }, { { ex, ey } }, 1
while queue[head] do
  local p = queue[head]
  head = head + 1
  for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
    local nx, ny = p[1] + d[1], p[2] + d[2]
    if walk(nx, ny) and not reach[key(nx, ny)] then
      reach[key(nx, ny)] = true
      queue[#queue + 1] = { nx, ny }
    end
  end
end
local sides = true
for _, c in ipairs(Plaza.CELLS) do
  for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
    if not reach[key(c.x + d[1], c.y + d[2])] then sides = false end
  end
end
check(sides, "every member cell is reachable from all four sides with the room full")

print("[test] 2F discovery and the added door")
local LayoutNative = require("src.core.game3.layout_native")
local function grid(w, h, fill)
  local cells2 = {}
  for i = 1, w * h do cells2[i] = { mid = fill, coll = 0, elev = 3 } end
  return cells2
end
local twoF = grid(14, 9, 0x202)
twoF[0 * 14 + 5 + 1] = { mid = 0x25c, coll = 1, elev = 0 }
twoF[1 * 14 + 5 + 1] = { mid = 0x264, coll = 1, elev = 0 }
twoF[1 * 14 + 2 + 1] = { mid = 0x004, coll = 1, elev = 0 }
local maps = {
  RU_OLDALE_TOWN_POKEMON_CENTER_2F = {
    warps = { { x = 1, y = 5, destMap = "RU_OLDALE_TOWN_POKEMON_CENTER_1F", destWarp = 3 },
              { x = 5, y = 1, destMap = "RU_SINGLE_BATTLE_COLOSSEUM", destWarp = 1 } },
    objects = { { x = 4, y = 2, graphicsId = 85 } },
    midLayout = LayoutNative.fromDecoded({ width = 14, height = 9, cells = twoF }, "RU_OLDALE_TOWN_POKEMON_CENTER_2F", "p"),
  },
  RU_OLDALE_TOWN_POKEMON_CENTER_1F = {
    warps = { { x = 1, y = 6, destMap = "RU_OLDALE_TOWN_POKEMON_CENTER_2F", destWarp = 1 } },
    objects = { { x = 7, y = 2, graphicsId = 58 } },
    midLayout = LayoutNative.fromDecoded({ width = 14, height = 9, cells = grid(14, 9, 0x202) }, "RU_OLDALE_TOWN_POKEMON_CENTER_1F", "p"),
  },
  RU_SINGLE_BATTLE_COLOSSEUM = { warps = {} },
  RU_TRADE_CENTER = { warps = { { x = 5, y = 8, destMap = "RU_OLDALE_TOWN_POKEMON_CENTER_2F" } } },
}
maps.RU_OLDALE_TOWN_POKEMON_CENTER_1F.midLayout.cells[3 * 14 + 7 + 1].coll = 1
local found = UnionRs.discover(maps)
check(found.RU_OLDALE_TOWN_POKEMON_CENTER_2F ~= nil, "the 2F with a Colosseum bay is found")
eq(found.RU_OLDALE_TOWN_POKEMON_CENTER_1F, nil, "the 1F is not")
eq(found.RU_OLDALE_TOWN_POKEMON_CENTER_2F and found.RU_OLDALE_TOWN_POKEMON_CENTER_2F.oneF,
  "RU_OLDALE_TOWN_POKEMON_CENTER_1F", "its origin is the 1F the stairs lead to")
local def = maps.RU_OLDALE_TOWN_POKEMON_CENTER_2F
local before = def.midLayout
UnionRs.patchLayout(def, "RU_OLDALE_TOWN_POKEMON_CENTER_2F")
check(def.midLayout ~= before, "the patch builds a fresh layout copy")
eq(before:midAt(2, 1), 0x004, "the cached layout is untouched")
eq(def.midLayout:midAt(2, 1), 0x264, "the added door copies the bay door")
eq(def.midLayout:midAt(2, 0), 0x25c, "with the wall above it")
eq(def.midLayout:midAt(4, 4), 0x202, "the rest of the floor is the same")
local again = def.midLayout
UnionRs.patchLayout(def, "RU_OLDALE_TOWN_POKEMON_CENTER_2F")
eq(def.midLayout, again, "patching twice is a no-op")
UnionRs._game = { data = { maps = maps } }
UnionRs.centers = found
eq(UnionRs.attendantGfx("RU_OLDALE_TOWN_POKEMON_CENTER_2F"), 85, "the attendant wears the bay attendant's graphics")
local o = UnionRs.originFor("RU_OLDALE_TOWN_POKEMON_CENTER_2F")
check(o and o.map == "RU_OLDALE_TOWN_POKEMON_CENTER_1F" and o.x == 7 and o.y == 4 and o.facing == "up",
  "the origin is the cell in front of the 1F nurse desk")
eq(UnionRs.countMons({ party = { { species = 1 }, { species = 412, isEgg = true }, { species = 4 } } }), 2,
  "eggs do not count toward entry")

print("[test] saves in the added room land in front of the nurse")
local Rules = require("src.core.game3.rse.union_rs_rules")
local Origin = require("src.online.union.Origin")
local s = { version = "ruby", map = "RU_UNION_ROOM", x = 12, y = 20, specialSaveWarpFlags = 0 }
Origin.record(s, { gen = 3, version = "ruby", map = o.map, x = o.x, y = o.y, facing = "up" })
local flags, warp = Rules.saveWarpFields(s)
eq(flags, 1, "a save in the room sets the continue warp")
check(warp and warp.map == o.map and warp.x == 7 and warp.y == 4, "pointing at the nurse front")
local m, x, y, f = Rules.saveLocation(s)
check(m == o.map and x == 7 and y == 4 and f == "up", "the saved location is the nurse front")
local s2 = { version = "ruby", map = "RU_OLDALE_TOWN", x = 5, y = 5, specialSaveWarpFlags = 0 }
local f2 = Rules.saveWarpFields(s2)
eq(f2, 0, "saves elsewhere keep the cart rules")
eq(Rules.saveLocation(s2), nil, "and their own location")
local loaded = { version = "ruby", map = "RU_UNION_ROOM", x = 12, y = 20, healMap = o.map }
Rules.useContinueGameWarp(loaded)
check(loaded.map == o.map and loaded.x == 7 and loaded.y == 4 and loaded.facing == "up",
  "a save inside the room without a continue warp still loads at the nurse front")
local cont = { version = "ruby", map = "RU_UNION_ROOM", x = 12, y = 20, specialSaveWarpFlags = 1,
  continueGameWarp = { map = o.map, x = 7, y = 4 } }
Rules.useContinueGameWarp(cont)
check(cont.map == o.map and cont.x == 7 and cont.y == 4 and cont.facing == "up", "the continue warp path faces the desk")

if failed > 0 then
  print(("[FAIL] %d check(s) failed"):format(failed))
  os.exit(1)
end
print("[PASS] union rs")
