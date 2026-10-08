local UnionCenters = require("src.world.gen1.UnionCenters")
local Origin = require("src.online.union.Origin")

local UnionSafety = {}

UnionSafety.ADDED = {
  [UnionCenters.FLOOR_2F] = true,
  [UnionCenters.UNION_ROOM] = true,
}

local function known(data, id)
  return type(id) == "string" and data.maps and data.maps[id] ~= nil
end

local function centerPlan(data, mapId)
  return UnionCenters.planFor(data, mapId) or (UnionCenters.plan(data, mapId))
end

function UnionSafety.nurseFront(data, mapId)
  local def = known(data, mapId) and data.maps[mapId]
  if not def then return nil end
  local entries = data.text_pointers and data.text_pointers[def.label]
  for _, o in ipairs(def.objects or {}) do
    local entry = entries and entries[o.text]
    if o.sprite == "SPRITE_NURSE" and (entry == nil or entry.nurse) then
      return { map = mapId, x = o.x, y = o.y + 2, facing = "up" }
    end
  end
  return nil
end

function UnionSafety.townOf(data, centerId)
  for id, def in pairs(data.maps or {}) do
    if type(def) == "table" and id ~= centerId then
      for _, w in ipairs(def.warps or {}) do
        if w.destMap == centerId then return id, w end
      end
    end
  end
  return nil
end

function UnionSafety.centerOfTown(data, town)
  local def = known(data, town) and data.maps[town]
  for _, w in ipairs(def and def.warps or {}) do
    if centerPlan(data, w.destMap) then return w.destMap end
  end
  return nil
end

function UnionSafety.offVanilla(save, data)
  local p = type(save) == "table" and save.player
  if type(p) ~= "table" then return false end
  if UnionSafety.ADDED[p.map] then return true end
  local plan = type(p.map) == "string" and centerPlan(data, p.map)
  if not (plan and p.x and p.y) then return false end
  local bx, by = plan.desk.bx, plan.desk.by
  return p.x >= bx * 2 and p.x <= bx * 2 + 3 and p.y >= by * 2 - 1 and p.y <= by * 2
end

function UnionSafety.target(save, data)
  local o = Origin.get(save)
  local center = o and o.gen == 1 and known(data, o.map) and centerPlan(data, o.map) and o.map
  local here = save.player and save.player.map
  if not center and type(here) == "string" and centerPlan(data, here) then center = here end
  local heal = save.lastHeal
  if not (type(heal) == "table" and known(data, heal.map)) then
    heal = require("src.core.SaveData").defaultHeal(data.field and data.field.boot)
  end
  center = center or UnionSafety.centerOfTown(data, heal.map)
  local spot = center and UnionSafety.nurseFront(data, center)
  if spot then
    local town, w = UnionSafety.townOf(data, center)
    spot.town = town and { id = town, x = w.x, y = w.y } or nil
    return spot
  end
  return { map = heal.map, x = heal.x, y = heal.y, facing = "down", heal = true }
end

local function relocate(save, t)
  local p = {}
  for k, v in pairs(save.player) do p[k] = v end
  p.map, p.x, p.y, p.facing = t.map, t.x, t.y, t.facing
  save.player = p
  local last = save.lastOutdoor
  if t.town and not (type(last) == "table" and last.id == t.town.id) then
    save.lastOutdoor = { id = t.town.id, x = t.town.x, y = t.town.y }
  end
  Origin.clear(save)
end

function UnionSafety.settle(save, data)
  if type(save) ~= "table" or type(data) ~= "table" or not UnionSafety.offVanilla(save, data) then
    return nil
  end
  local t = UnionSafety.target(save, data)
  relocate(save, t)
  return t
end

function UnionSafety.forWrite(save, data)
  if type(save) ~= "table" or type(data) ~= "table" or not UnionSafety.offVanilla(save, data) then
    return save
  end
  local out = {}
  for k, v in pairs(save) do out[k] = v end
  relocate(out, UnionSafety.target(save, data))
  return out
end

local REWRITTEN = { player = true, lastOutdoor = true, [Origin.KEY] = true }

function UnionSafety.write(save, data, writer)
  local out = UnionSafety.forWrite(save, data)
  local ok = writer(out)
  if out ~= save then
    for k, v in pairs(out) do
      if not REWRITTEN[k] then save[k] = v end
    end
  end
  return ok
end

return UnionSafety
