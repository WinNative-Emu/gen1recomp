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

local Objects = require("src.core.game3.objects")
local GfxIds = require("src.core.game3.scripting.gfx_ids")
local Flags = require("src.core.game3.scripting.flags")
local Space = require("src.core.game3.scripting.space")

print("[test] 1. OBJ_EVENT_GFX_SEAGALLOP (108) / OBJ_EVENT_GFX_SS_ANNE (151) come from the ROM")
check(GfxIds.TO_SPRITE[108] == nil, "108 has no host sprite fallback")
check(GfxIds.TO_SPRITE[109] == nil, "109 has no host sprite fallback")
check(GfxIds.TO_SPRITE[151] == nil, "151 has no host sprite fallback")

local FR_ROOT = os.getenv("POKEFIRERED") or "../pokefirered"
local f = io.open(FR_ROOT .. "/pokefirered.gba", "rb")
if f then
  local data = f:read("*a")
  f:close()
  local GV = require("src.core.GameVersion")
  local Rom = require("src.import.gba.rom")
  local OwExtract = require("src.import.gba.ow_extract")
  local sha = GV.VERSIONS.firered.sha1
  local rom = assert(Rom.open({
    info = function() return { size = #data, md5 = sha } end,
    read = function(_, _, off, len) return data:sub(off + 1, off + len) end,
  }, GV.forSha1(sha)))
  local pals = OwExtract.loadPaletteTable(rom, {})
  -- src/data/object_events/object_event_graphics_info.h:2889
  local boat = assert(OwExtract.extractOne(rom, 108, pals, {}))
  check(boat.width == 64 and boat.height == 64, "Seagallop is a 64x64 sheet")
  check(boat.paletteTag == 0x1114 and boat.paletteSlot == 10, "Seagallop uses OBJ_EVENT_PAL_TAG_SEAGALLOP in PALSLOT_NPC_SPECIAL")
  check(boat.drawOffX == 0 and boat.drawOffY == 0, "Seagallop 64x64 subsprite is centered")
  check(pals[0x1114] ~= nil, "Seagallop palette loaded from sObjectEventSpritePalettes")
  local ext = OwExtract.decodeMeta(OwExtract.encodeMeta(boat))
  check(ext.width == 64 and ext.drawOffX == 0, "Seagallop meta round-trips")
  -- src/data/object_events/object_event_graphics_info.h:2908
  local anne = assert(OwExtract.extractOne(rom, 151, pals, {}))
  check(anne.width == 128 and anne.height == 64, "SS Anne is a 128x64 sheet")
  check(anne.paletteTag == 0x1115 and anne.paletteSlot == 10, "SS Anne uses OBJ_EVENT_PAL_TAG_SS_ANNE in PALSLOT_NPC_SPECIAL")
  -- src/data/object_events/object_event_subsprites.h:999
  check(anne.drawOffX == 32 and anne.drawOffY == 16, "SS Anne draws +32,+16 off center (got "
    .. tostring(anne.drawOffX) .. "," .. tostring(anne.drawOffY) .. ")")
  local meta = OwExtract.decodeMeta(OwExtract.encodeMeta(anne))
  check(meta.drawOffX == 32 and meta.drawOffY == 16, "SS Anne draw offset round-trips through the meta")
  local player = assert(OwExtract.extractOne(rom, 0, pals, {}))
  check(player.drawOffX == 0 and player.drawOffY == 0, "16x32 player subsprite stays centered")
else
  print("[skip] pokefirered.gba not found, ROM sprite checks skipped")
end

print("[test] 2. offMap bounds checking")
local bounds = { w = 24, h = 20 }
check(not Objects.offMap(bounds, { cellX = 10, cellY = 12 }), "x=10 is on-map")
check(not Objects.offMap(bounds, { cellX = 0, cellY = 0 }), "x=0, y=0 is on-map")
check(Objects.offMap(bounds, { cellX = 24, cellY = 12 }), "x=24 is off-map on 24x20 map")
check(Objects.offMap(bounds, { cellX = -1, cellY = 12 }), "x=-1 is off-map")

print("[test] 3. Cinnabar Island Seagallop spawn & arrival movement")
local cinnabarMapDef = {
  midLayout = { width = 24, height = 20 },
  objects = {
    { localId = 1, graphicsId = 23, x = 14, y = 6, movementType = 5, flag = 0 },
    { localId = 2, graphicsId = 32, x = 11, y = 11, movementType = 1, flag = 0 },
    { localId = 3, graphicsId = 73, x = 20, y = 7, movementType = 10, flag = 0x27 }, -- Bill
    { localId = 4, graphicsId = 108, x = 23, y = 7, elevation = 1, movementType = 9, flag = 0x28 }, -- Seagallop
  }
}

local store = Flags.newStore()
Flags.setFlag(store, nil, 0x28, true) -- FLAG_HIDE_CINNABAR_SEAGALLOP = true
Space.store = store
Space.mapId = "CinnabarIsland"

Objects.clear()
Objects.loadMap(nil, "CinnabarIsland", cinnabarMapDef)

-- Initially Seagallop is hidden by flag 0x28
local drawList = Objects.forDraw()
local foundSeagallop = false
for _, eo in ipairs(drawList) do
  if eo.localId == 4 then foundSeagallop = true end
end
check(not foundSeagallop, "Seagallop is initially hidden before addobject")

-- Script runs: setobjectxyperm 4, 30, 12 then addobject 4
Objects.setObjectXY(4, 30, 12)
Objects.addObject(4)
local boatEo = Objects.find(4)
check(boatEo and boatEo.cellX == 30 and boatEo.cellY == 12, "Seagallop coordinates set to (30, 12)")

-- Script runs: applymovement 4, CinnabarIsland_Movement_BoatArrive (5 steps left: 30 -> 25)
local arriveBytes = {
  0x1B, -- delay_16
  0x1B, -- delay_16
  0x1F, -- walk_fast_left
  0x1F, -- walk_fast_left
  0x12, -- walk_left
  0x0A, -- walk_slower_left
  0x0A, -- walk_slower_left
  0xFE  -- step_end
}

local movementFinished = false
Objects.applyMovement(4, arriveBytes, function()
  movementFinished = true
end)

drawList = Objects.forDraw()
foundSeagallop = false
for _, eo in ipairs(drawList) do
  if eo.localId == 4 then foundSeagallop = true end
end
check(foundSeagallop, "Seagallop moving from off-map (30, 12) is included in forDraw() while tracked")

-- Step through frames until movement completes
local maxFrames = 300
local frames = 0
while not movementFinished and frames < maxFrames do
  Objects.update(nil)
  frames = frames + 1
end

check(movementFinished, "Boat arrival movement completed in " .. frames .. " frames")
check(boatEo and boatEo.cellX == 25 and boatEo.cellY == 12,
  "Boat arrived at shoreline (25, 12), got (" .. tostring(boatEo and boatEo.cellX) .. ", " .. tostring(boatEo and boatEo.cellY) .. ")")

drawList = Objects.forDraw()
foundSeagallop = false
for _, eo in ipairs(drawList) do
  if eo.localId == 4 then foundSeagallop = true end
end
check(foundSeagallop, "Seagallop at (25, 12) is visible and drawn at shoreline")

if failed > 0 then
  print("\nFAIL: " .. failed .. " assertions failed")
  os.exit(1)
else
  print("\nPASS: all Cinnabar Seagallop tests passed")
end
