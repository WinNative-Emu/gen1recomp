local Spot = {}

local DOOR = { x = 2, y = 1 }
-- pokeruby/data/maps/OldaleTown_PokemonCenter_2F/map.json:63
local BAY_DOOR = { x = 5, y = 1 }

local function profileOf(version)
  return require("src.core.game3.profile").of(version)
end

local function isRs(version)
  return require("src.core.game3.link.family").isRubySapphire(version)
end

function Spot.prefix(version)
  local row = profileOf(version)
  return row and row.map and row.map.enginePrefix or "FR_"
end

function Spot.roomId(version)
  if isRs(version) then return Spot.prefix(version) .. "UNION_ROOM" end
  return require("src.core.game3.link.family").mapId(version, "unionRoom") .. "_PLAZA"
end

function Spot.colosseumId(version)
  return require("src.core.game3.link.family").mapId(version, "colosseum2P")
end

function Spot.nurseGfx(version)
  return require("src.core.game3.constants").of(version):require("event_objects", "OBJ_EVENT_GFX_NURSE")
end

function Spot.isRsCenter(def, colosseum)
  for _, w in ipairs(type(def) == "table" and def.warps or {}) do
    if tonumber(w.x) == BAY_DOOR.x and tonumber(w.y) == BAY_DOOR.y and w.destMap == colosseum then return true end
  end
  return false
end

function Spot.isAdded(version, lookup, map, x, y)
  if type(map) ~= "string" then return false end
  if map == Spot.roomId(version) then return true end
  if not isRs(version) or tonumber(x) ~= DOOR.x or tonumber(y) ~= DOOR.y then return false end
  return Spot.isRsCenter(lookup(map), Spot.colosseumId(version))
end

-- pokefirered/data/maps/ViridianCity_PokemonCenter_1F/map.json:21
function Spot.nurseFront(def, nurse)
  if type(def) ~= "table" or type(def.collAt) ~= "function" then return nil end
  for _, o in ipairs(def.objects or {}) do
    if tonumber(o.graphicsId or o.graphics) == nurse then
      local x, y = tonumber(o.x), tonumber(o.y)
      for dy = 1, 3 do
        if def.collAt(x, y + dy) == 0 then return x, y + dy end
      end
    end
  end
  return nil
end

function Spot.oneFOf(lookup, twoF, nurse)
  local def = lookup(twoF)
  for _, w in ipairs(type(def) == "table" and def.warps or {}) do
    local dest = type(w.destMap) == "string" and lookup(w.destMap) or nil
    if dest and Spot.nurseFront(dest, nurse) then
      for _, back in ipairs(dest.warps or {}) do
        if back.destMap == twoF then return w.destMap end
      end
    end
  end
  return nil
end

function Spot.resolve(version, lookup, save)
  if type(save) ~= "table" or not Spot.isAdded(version, lookup, save.map, save.x, save.y) then return nil end
  local nurse = Spot.nurseGfx(version)
  local tries = {}
  if save.map ~= Spot.roomId(version) then tries[#tries + 1] = save.map end
  local dw = save.dynamicWarp
  if type(dw) == "table" and type(dw.map) == "string" then tries[#tries + 1] = dw.map end
  for _, twoF in ipairs(tries) do
    local oneF = Spot.oneFOf(lookup, twoF, nurse)
    local x, y
    if oneF then x, y = Spot.nurseFront(lookup(oneF), nurse) end
    if x then return { map = oneF, x = x, y = y, facing = "up" } end
  end
  local heal = type(save.healMap) == "string" and save.healMap or nil
  local x, y = Spot.nurseFront(heal and lookup(heal), nurse)
  if x then return { map = heal, x = x, y = y, facing = "up" } end
  return nil
end

function Spot.liveLookup(game)
  local maps = game and game.data and game.data.maps or {}
  local memo = {}
  return function(mapId)
    if memo[mapId] ~= nil then return memo[mapId] or nil end
    local def = maps[mapId]
    if type(def) ~= "table" then
      memo[mapId] = false
      return nil
    end
    if not def.midLayout then
      local okM, Map = pcall(require, "src.core.game3.map")
      if okM and Map and Map.ensureMidLayout then pcall(Map.ensureMidLayout, game, mapId, def) end
    end
    local objects = def.objects
    if objects == nil then
      local Space = package.loaded["src.core.game3.scripting.space"]
      local ev = Space and Space.bundle and Space.bundle.events and Space.bundle.events[mapId]
      objects = ev and (ev.objects or ev.objectEvents) or {}
    end
    local L = def.midLayout
    local row = {
      warps = def.warps or {}, objects = objects,
      collAt = L and function(x, y) return L:collAt(x, y) end or nil,
    }
    memo[mapId] = row
    return row
  end
end

function Spot.live(session, game)
  if type(session) ~= "table" then return nil end
  local version = session.version or require("src.core.game3.link.family").activeVersion()
  if not game then
    local rt = package.loaded["src.core.game3.runtime"]
    game = rt and rt._game or nil
  end
  if not (game and game.data and game.data.maps) then return nil end
  return Spot.resolve(version, Spot.liveLookup(game), session)
end

local function u16(s, i)
  local a, b = s:byte(i, i + 1)
  if not b then return nil end
  return a + b * 256
end

-- pokefirered/include/global.fieldmap.h:8
local COLLISION_SHIFT, COLLISION_MASK = 10, 3

function Spot.cacheLookup(read, slotOf, mapOf)
  local Json = require("src.link.Json")
  local memo = {}
  return function(mapId)
    if memo[mapId] ~= nil then return memo[mapId] or nil end
    memo[mapId] = false
    local slot = slotOf(mapId)
    local header = slot and read("map_tree/maps/" .. slot .. "/header.json")
    local events = slot and read("map_tree/maps/" .. slot .. "/events.json")
    local grid = slot and read("map_tree/maps/" .. slot .. "/grid.bin")
    if not (header and events and grid) then return nil end
    local okH, h = pcall(Json.decode, header)
    local okE, e = pcall(Json.decode, events)
    if not (okH and okE and type(h) == "table" and type(e) == "table") then return nil end
    local w, hgt = tonumber(h.width) or 0, tonumber(h.height) or 0
    local warps = {}
    for i, wp in ipairs(e.warps or {}) do
      warps[i] = { x = wp.x, y = wp.y, destMap = mapOf(wp.mapGroup, wp.mapNum) }
    end
    local row = {
      warps = warps, objects = e.objects or {},
      collAt = function(x, y)
        if x < 0 or y < 0 or x >= w or y >= hgt then return 1 end
        local v = u16(grid, (y * w + x) * 2 + 1)
        return v and math.floor(v / 2 ^ COLLISION_SHIFT) % (COLLISION_MASK + 1) or 1
      end,
    }
    memo[mapId] = row
    return row
  end
end

return Spot
