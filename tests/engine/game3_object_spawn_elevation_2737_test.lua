-- pokeemerald/src/event_object_movement.c:7737, pokeemerald/src/event_object_movement.c:4931

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local GameVersion = require("src.core.GameVersion")
GameVersion.set("emerald")
local Collision = require("src.core.game3.collision")
local Objects = require("src.core.game3.objects")
local FieldView = require("src.core.game3.field_view")

local W, H = 19, 9
local elev = {}
for y = 0, H - 1 do
  for x = 0, W - 1 do elev[y * W + x] = 3 end
end
elev[5 * W + 17] = 4
elev[5 * W + 2] = 15
elev[6 * W + 4] = 0
local layout = { width = W, height = H, pair = "spawn_elev_test" }
function layout:elevAt(x, y) return elev[y * W + x] end
function layout:collAt() return 0 end
function layout:midAt() return 0x200 end
function layout:collArray()
  local c = {}
  for i = 1, W * H do c[i] = 0 end
  return c
end
local mapDef = { midLayout = layout, pair = layout.pair, warps = {} }
Collision.bindMap({ save = { position = {} } }, "SPAWN_ELEV_TEST", mapDef)

local defs = {
  { localId = 1, x = 17, y = 5, elevation = 3, graphicsId = 7, movementType = 0x0A },
  { localId = 2, x = 2, y = 5, elevation = 3, graphicsId = 7, movementType = 0x0A },
  { localId = 3, x = 4, y = 6, elevation = 3, graphicsId = 7, movementType = 0x0A },
}
local pool = Objects.spawnFromDefs(defs, mapDef, nil)
local stone, multi, trans = pool.byId[1], pool.byId[2], pool.byId[3]
check(stone and multi and trans, "objects spawned")
eq(stone.elevation, 3, "template elevation before first update")

local savedById, savedOrder, savedTracks = Objects._byId, Objects._order, Objects._tracks
Objects._byId, Objects._order, Objects._tracks = pool.byId, pool.order, {}
Objects.update({ save = { position = {} } })

eq(stone.elevation, 4, "spawn_elevation_follows_metatile")
eq(stone.currentElevation, 4, "spawn current elevation follows metatile")
eq(multi.elevation, 3, "multi-level tile keeps template elevation")
eq(trans.elevation, 3, "transition tile keeps previous elevation")
eq(trans.currentElevation, 0, "transition tile sets current elevation 0")
check(not stone.spawnElevation, "spawn update runs once")

local under, over = FieldView.applyDrawOrder({
  { kind = "npc", eventObject = stone, elevation = stone.elevation, y = 5 * 16 },
}, {}, {}, 0)
eq(#over, 1, "mr_stone_draws_over_bg1")
eq(#under, 0, "mr stone not under top layer")

local savedMapId, savedDefs = Objects._mapId, Objects._defs
Objects._mapId, Objects._defs = "SPAWN_ELEV_TEST", defs
local snap = Objects.snapshot()
eq(#snap.list, 0, "snapshot has no row for a spawn-resolved elevation")
Objects._mapId, Objects._defs = savedMapId, savedDefs
Objects._byId, Objects._order, Objects._tracks = savedById, savedOrder, savedTracks

local NW, NH = 5, 5
local nelev = {}
for y = 0, NH - 1 do
  for x = 0, NW - 1 do nelev[y * NW + x] = 3 end
end
nelev[1 * NW + 1] = 4
local nlayout = { width = NW, height = NH, pair = "spawn_elev_neighbor" }
function nlayout:elevAt(x, y) return nelev[y * NW + x] end
function nlayout:collAt() return 0 end
function nlayout:midAt() return 0x200 end
function nlayout:collArray()
  local c = {}
  for i = 1, NW * NH do c[i] = 0 end
  return c
end
local nmapDef = { midLayout = nlayout, pair = nlayout.pair, warps = {} }
local npool = Objects.spawnFromDefs({
  { localId = 1, x = 1, y = 1, elevation = 3, graphicsId = 7, movementType = 0x0A },
  { localId = 2, x = 3, y = 3, elevation = 3, graphicsId = 7, movementType = 0x0A },
}, nmapDef, nil)
local raised, flat = npool.byId[1], npool.byId[2]
eq(raised.elevation, 3, "neighbor template elevation before first tick")
eq(layout:elevAt(1, 1), 3, "active map cell under the neighbor NPC is elevation 3")
Objects.tickPool(npool, { save = { position = {} } }, nil)
eq(raised.elevation, 4, "neighbor_pool_spawn_elevation_follows_own_metatile")
eq(raised.currentElevation, 4, "neighbor pool current elevation follows own metatile")
eq(flat.elevation, 3, "neighbor pool flat tile keeps template elevation")
check(not raised.spawnElevation, "neighbor pool spawn update runs once")
GameVersion.set("firered")
T.finish("game3_object_spawn_elevation_2737_test")
