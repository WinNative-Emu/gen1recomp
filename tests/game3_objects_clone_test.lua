#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path
local G3 = require("tests.game3_cache")
local root = G3.rootOrSkip("game3_objects_clone_test", "scripts/events.lua")
local bundle = assert(G3.bundle("scripts/events.lua"), "events bundle")

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local OBJ_KIND_CLONE = 255
local EXPECT = {
  { map = "3_3", index = 10, localId = 10, target = { 10, 3, 27 } },
  { map = "3_6", index = 13, localId = 13, target = { 7, 3, 34 } },
  { map = "3_16", index = 3, localId = 3, target = { 4, 3, 56 } },
  { map = "3_20", index = 7, localId = 7, target = { 8, 3, 1 } },
  { map = "3_22", index = 7, localId = 7, target = { 12, 3, 3 } },
  { map = "3_25", index = 1, localId = 1, target = { 10, 3, 6 } },
  { map = "3_33", index = 14, localId = 14, target = { 13, 3, 32 } },
  { map = "3_39", index = 6, localId = 6, target = { 2, 3, 0 } },
  { map = "3_63", index = 7, localId = 7, target = { 1, 3, 17 } },
}

local json = require("src.link.Json")
for _, e in ipairs(EXPECT) do
  local f = io.open(root .. "/map_tree/maps/" .. e.map .. "/events.json", "rb")
  check(f ~= nil, e.map .. " events.json present")
  if f then
    local ev = json.decode(f:read("*a"))
    f:close()
    local o = ev.objects[e.index]
    check(o and o.kind == OBJ_KIND_CLONE, e.map .. " object " .. (e.index - 1) .. " is a clone")
    check(o and o.targetLocalId == e.target[1] and o.targetMapGroup == e.target[2]
      and o.targetMapNum == e.target[3],
      string.format("%s clone targets local %d on %d:%d", e.map, e.target[1], e.target[2], e.target[3]))
    check(o and o.elevation == nil and o.movementType == nil, e.map .. " clone carries no normal-union fields")
  end
end

require("src.import.gba.map_catalog").rebuildIndex()
local Objects = require("src.core.game3.objects")
Objects.reset()

local cerulean = bundle.events.FR_CERULEAN_CITY
local cloneDef
for _, def in ipairs(cerulean.objects) do
  if def.kind == OBJ_KIND_CLONE then cloneDef = def end
end
check(cloneDef ~= nil, "Cerulean City has a clone object")
local tpl = bundle.events.FR_ROUTE_9.objects[cloneDef.cloneTarget.localId]
check(Objects.cloneTemplate(cloneDef) == tpl, "clone resolves to Route 9 objectEvents[targetLocalId - 1]")

local saved = cloneDef.cloneTarget.mapId
cloneDef.cloneTarget.mapId = nil
check(Objects.cloneTemplate(cloneDef) == tpl, "clone resolves by group/num without a baked mapId")
cloneDef.cloneTarget.mapId = saved

Objects.loadMap(nil, "FR_CERULEAN_CITY", { objects = cerulean.objects })
local eo = Objects.find(cloneDef.localId)
check(eo ~= nil, "clone spawned under its own local id")
if eo then
  check(eo.cellX == cloneDef.x and eo.cellY == cloneDef.y, "clone keeps its own position")
  check(eo.graphicsId == tpl.graphicsId, "clone uses the target's graphics")
  check(eo.movementType == tpl.movementType, "clone uses the target's movement type")
  check(eo.currentElevation == tpl.elevation, "clone uses the target's elevation")
  check(eo.flag == tpl.flag and eo.flag ~= 0, "clone uses the target's hide flag")
  check(eo.scriptKey == tpl.scriptKey, "clone uses the target's script")
end
check(cloneDef.elevation == 0 and cloneDef.movementType == 0, "bundle template left untouched")

local pool = Objects.spawnFromDefs(cerulean.objects, nil, "FR_CERULEAN_CITY")
local ghost = pool.byId[cloneDef.localId]
check(ghost and ghost.graphicsId == tpl.graphicsId and ghost.flag == tpl.flag, "neighbor pools resolve clones too")

if failed > 0 then
  print(string.format("FAIL: %d check(s) failed", failed))
  os.exit(1)
end
print("PASS game3_objects_clone_test")
