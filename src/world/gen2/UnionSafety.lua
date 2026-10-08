local Origin = require("src.online.union.Origin")
local Map = require("src.world.gen2.Map")
local Permissions = require("src.world.gen2.Permissions")
local Center = require("src.world.gen2.UnionCenter2F")

local Safety = {}

local function tilesetOf(data, def)
  return data.gen2Tilesets and data.gen2Tilesets[def.tileset]
end

function Safety.vanillaWidthCells(maps)
  local def = maps[Center.MAP_ID]
  if not def then return 0 end
  return (def.width - (maps[Center.ROOM_ID] and 2 or 0)) * 2
end

function Safety.isAdded(data, pos)
  if type(pos) ~= "table" then return false end
  local maps = data.gen2Maps
  if pos.map == Center.ROOM_ID then return true end
  if pos.map ~= Center.MAP_ID then return false end
  local def = maps[Center.MAP_ID]
  if not def then return true end
  local x, y = pos.x or -1, pos.y or -1
  return x < 0 or y < 0 or x >= Safety.vanillaWidthCells(maps) or y >= def.height * 2
end

local function stairsWarp(def)
  for i, w in ipairs(def.warps or {}) do
    if w.destMap == Center.MAP_ID then return i end
  end
  return nil
end

function Safety.nurseFront(data, mapId)
  local def = mapId and data.gen2Maps[mapId]
  if not (def and stairsWarp(def)) then return nil end
  local nurse
  for _, o in ipairs(def.objects or {}) do
    if o.sprite == "SPRITE_NURSE" then nurse = o end
  end
  local tileset = nurse and tilesetOf(data, def)
  if not tileset then return nil end
  local map = Map.new(def, tileset)
  local y = nurse.y + 1
  while map:inBounds(nurse.x, y) and Permissions.isCounter(map:cellCollision(nurse.x, y)) do
    y = y + 1
  end
  if y == nurse.y + 1 or not map:isWalkable(nurse.x, y) then return nil end
  return nurse.x, y, "up"
end

local function healCenter(save, data)
  local spawns = data.gen2Landmarks and data.gen2Landmarks.spawns
  local s = spawns and spawns[save.spawn]
  if not (s and s.map) then return nil, s end
  local ids = {}
  for id, def in pairs(data.gen2Maps) do
    if type(def) == "table" and stairsWarp(def) then
      for _, w in ipairs(def.warps) do
        if w.destMap == s.map then ids[#ids + 1] = id break end
      end
    end
  end
  table.sort(ids)
  return ids[1], s
end

function Safety.target(save, data)
  local origin = Origin.get(save)
  local candidates = {}
  if origin and origin.gen == 2 then candidates[#candidates + 1] = origin.map end
  if type(save.backupWarp) == "table" then candidates[#candidates + 1] = save.backupWarp.map end
  local heal, spawn = healCenter(save, data)
  candidates[#candidates + 1] = heal
  for _, id in ipairs(candidates) do
    local x, y, facing = Safety.nurseFront(data, id)
    if x then return id, x, y, facing, id end
  end
  if spawn and spawn.map and data.gen2Maps[spawn.map] then
    return spawn.map, spawn.x, spawn.y, "down", nil
  end
  return nil
end

local function cleanScenes(scenes, maps)
  if type(scenes) ~= "table" then return scenes end
  local out = {}
  for k, v in pairs(scenes) do out[k] = v end
  out[Center.ROOM_ID] = nil
  local def = maps[Center.MAP_ID]
  local scene = out[Center.MAP_ID]
  local row = def and scene and def.sceneScripts and def.sceneScripts[scene]
  if scene and (not row or row.scriptKey == Center.LEFT_KEY) then
    out[Center.MAP_ID] = 0
  end
  return out
end

local function relocate(save, data)
  local mapId, x, y, facing, center = Safety.target(save, data)
  save.mapScenes = cleanScenes(save.mapScenes, data.gen2Maps)
  if not mapId then
    save.position = nil
    return "spawn"
  end
  save.position = { map = mapId, x = x, y = y, facing = facing }
  if center then
    save.backupWarp = { map = center, warp = stairsWarp(data.gen2Maps[center]) }
  end
  if type(save.mapObjectMasks) == "table" and save.mapObjectMasks.map ~= mapId then
    save.mapObjectMasks = nil
  end
  return mapId
end

function Safety.seal(save, data)
  if not (type(save) == "table" and data and data.gen2Maps) then return nil end
  if not Safety.isAdded(data, save.position) then return nil end
  return relocate(save, data)
end

function Safety.settle(save, data)
  if not (type(save) == "table" and data and data.gen2Maps) then return nil end
  if not data.gen2Maps[Center.ROOM_ID] then
    save.mapScenes = cleanScenes(save.mapScenes, data.gen2Maps)
  end
  if not Safety.isAdded(data, save.position) then return nil end
  local where = relocate(save, data)
  Origin.clear(save)
  return where
end

return Safety
