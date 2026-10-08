local Family = require("src.core.game3.link.family")

local function rsActive()
  return Family.isRubySapphire(Family.activeVersion())
end

local function enginePrefix()
  local row = require("src.core.game3.profile").of(Family.activeVersion())
  return row and row.map and row.map.enginePrefix or "FR_"
end

local Plaza = setmetatable({}, {
  __index = function(t, k)
    if k == "KIND" then return rsActive() and "rs" or "cart" end
    if k == "SOURCE_ID" then
      if rsActive() then return nil end
      return Family.mapId(nil, "unionRoom")
    end
    if k == "TILE_SOURCE_ID" then
      if rsActive() then return Family.mapId(nil, "recordCorner") end
      return Family.mapId(nil, "unionRoom")
    end
    if k == "MAP_ID" then
      if rsActive() then return enginePrefix() .. "UNION_ROOM" end
      return Family.mapId(nil, "unionRoom") .. "_PLAZA"
    end
    if k == "EXITS" then
      if rsActive() then return rawget(t, "RS").EXITS end
      local ex = rawget(t, "FAMILY_EXITS")
      return ex[Family.of()] or ex.frlg
    end
    return nil
  end,
})
Plaza.CAP = 40
Plaza.WIDTH = 25
Plaza.HEIGHT = 25
Plaza.EXIT_X, Plaza.EXIT_Y = 12, 24
Plaza.ATTENDANT_LOCAL_ID = 1

Plaza.FAMILY_EXITS = {
  -- pokefirered/data/maps/UnionRoom/map.json warp_events
  frlg = { { x = 12, y = 24, source = 1 } },
  -- pokeemerald/data/maps/UnionRoom/map.json warp_events
  rse = { { x = 12, y = 24, source = 1 }, { x = 13, y = 24, source = 2 } },
}

Plaza.ROLES = {
  "ABCDTTTTTTTTTTTTTTTTTTTTE",
  "abcdtttttttttttttttttttte",
  "FGHHHHHHHHHHHHHHHHHHHHHIJ",
  "fg.....................ij",
  "L.......................R",
  "L.......................R",
  "L.......................R",
  "L.......................R",
  "L.......................R",
  "L.......................R",
  "L..........123..........R",
  "L..........456..........R",
  "L..........789..........R",
  "L.......................R",
  "L.......................R",
  "L.......................R",
  "L.......................R",
  "L.......................R",
  "L.......................R",
  "L.......................R",
  "L.......................R",
  "L.......................R",
  "L.......................R",
  "Kk_________mno_________pq",
  "###########xXz###########",
}

Plaza.SOURCE = {
  A = { 0, 0 }, B = { 1, 0 }, C = { 2, 0 }, D = { 3, 0 }, T = { 4, 0 }, E = { 14, 0 },
  a = { 0, 1 }, b = { 1, 1 }, c = { 2, 1 }, d = { 3, 1 }, t = { 4, 1 }, e = { 14, 1 },
  F = { 0, 2 }, G = { 1, 2 }, H = { 2, 2 }, I = { 13, 2 }, J = { 14, 2 },
  f = { 0, 3 }, g = { 1, 3 }, ["."] = { 2, 3 }, i = { 13, 3 }, j = { 14, 3 },
  L = { 0, 4 }, R = { 14, 4 },
  ["1"] = { 6, 5 }, ["2"] = { 7, 5 }, ["3"] = { 8, 5 },
  ["4"] = { 6, 6 }, ["5"] = { 7, 6 }, ["6"] = { 8, 6 },
  ["7"] = { 6, 7 }, ["8"] = { 7, 7 }, ["9"] = { 8, 7 },
  K = { 0, 10 }, k = { 1, 10 }, _ = { 2, 10 }, m = { 6, 10 }, n = { 7, 10 }, o = { 8, 10 },
  p = { 13, 10 }, q = { 14, 10 },
  ["#"] = { 0, 11 }, x = { 6, 11 }, X = { 7, 11 }, z = { 8, 11 },
}

Plaza.BLOCKED = {
  A = true, B = true, C = true, D = true, T = true, E = true,
  a = true, b = true, c = true, d = true, t = true, e = true,
  ["#"] = true,
}

Plaza.RS = {
  -- pokeruby/data/maps/RecordCorner/map.json warp_events
  EXITS = { { x = 11, y = 24, source = 1 }, { x = 12, y = 24, source = 2 }, { x = 13, y = 24, source = 3 } },
  ROLES = {
    "ABTTTTTTTTTEFFGTTTTTTTTHI",
    "abttttttttteffgtttttttthi",
    "JKLLLLLLLLLMNNOLLLLLLLLPQ",
    "RS.....................UV",
    "RS.....................UV",
    "RS.....................UV",
    "RS.....................UV",
    "RS.....................UV",
    "RS.....................UV",
    "RS.....................UV",
    "RS.....................UV",
    "RS.....................UV",
    "RS.....................UV",
    "RS.....................UV",
    "RS.....................UV",
    "RS.....................UV",
    "RS.....................UV",
    "RS.....................UV",
    "RS.....................UV",
    "RS.....................UV",
    "RS.....................UV",
    "RS.....................UV",
    "RS.....................UV",
    "WX.....................YZ",
    "###########ppp###########",
  },
  -- pokeruby/data/layouts/RecordCorner/map.bin
  SOURCE = {
    A = { 3, 0 }, B = { 4, 0 }, T = { 5, 0 }, E = { 8, 0 }, F = { 9, 0 }, G = { 11, 0 }, H = { 15, 0 }, I = { 16, 0 },
    a = { 3, 1 }, b = { 4, 1 }, t = { 5, 1 }, e = { 8, 1 }, f = { 9, 1 }, g = { 11, 1 }, h = { 15, 1 }, i = { 16, 1 },
    J = { 3, 2 }, K = { 4, 2 }, L = { 5, 2 }, M = { 8, 2 }, N = { 9, 2 }, O = { 11, 2 }, P = { 15, 2 }, Q = { 16, 2 },
    R = { 3, 3 }, S = { 4, 3 }, ["."] = { 5, 3 }, U = { 15, 3 }, V = { 16, 3 },
    W = { 3, 8 }, X = { 4, 8 }, Y = { 15, 8 }, Z = { 16, 8 },
    ["#"] = { 0, 9 }, p = { 8, 9 },
  },
  BLOCKED = {
    A = true, B = true, T = true, E = true, F = true, G = true, H = true, I = true,
    a = true, b = true, t = true, e = true, f = true, g = true, h = true, i = true,
    J = true, Q = true, R = true, V = true, W = true, Z = true, ["#"] = true,
  },
}

function Plaza.tables(kind)
  if (kind or Plaza.KIND) == "rs" then return Plaza.RS.ROLES, Plaza.RS.SOURCE, Plaza.RS.BLOCKED end
  return Plaza.ROLES, Plaza.SOURCE, Plaza.BLOCKED
end

local CELL_XS = { 3, 6, 9, 12, 15, 18, 21 }
local CELL_YS = { 5, 8, 11, 14, 17, 20 }
local DOOR_X, DOOR_Y = 12, 23

local cells, bySlot, byKey = {}, {}, {}
for _, y in ipairs(CELL_YS) do
  for _, x in ipairs(CELL_XS) do
    if not (x == DOOR_X and y == 20) then
      cells[#cells + 1] = { x = x, y = y }
    end
  end
end
table.sort(cells, function(p, q)
  local dp = math.abs(p.x - DOOR_X) + math.abs(p.y - DOOR_Y)
  local dq = math.abs(q.x - DOOR_X) + math.abs(q.y - DOOR_Y)
  if dp ~= dq then return dp < dq end
  local ap, aq = math.abs(p.x - DOOR_X), math.abs(q.x - DOOR_X)
  if ap ~= aq then return ap < aq end
  if p.x ~= q.x then return p.x < q.x end
  return p.y > q.y
end)
for i, c in ipairs(cells) do
  if i <= Plaza.CAP then
    bySlot[i] = c
    byKey[c.y * 64 + c.x] = i
  end
end
Plaza.CELLS = cells

function Plaza.cellFor(slot)
  local c = bySlot[tonumber(slot) or -1]
  if not c then return nil end
  return c.x, c.y, "down"
end

function Plaza.slotAt(x, y)
  x, y = tonumber(x), tonumber(y)
  if not (x and y) then return nil end
  return byKey[y * 64 + x]
end

function Plaza.entry()
  return Plaza.EXIT_X, Plaza.EXIT_Y, "up"
end

function Plaza.roleAt(x, y, kind)
  local roles = Plaza.tables(kind)
  local row = roles[y + 1]
  if not row or x < 0 or x >= #row then return nil end
  return row:sub(x + 1, x + 1)
end

local function copyRow(row)
  local out = {}
  for k, v in pairs(row) do out[k] = v end
  return out
end

function Plaza.buildDecoded(src, kind)
  local _, source = Plaza.tables(kind)
  local cellsOut = {}
  for y = 0, Plaza.HEIGHT - 1 do
    for x = 0, Plaza.WIDTH - 1 do
      local s = source[Plaza.roleAt(x, y, kind)]
      if s[1] >= (src.trueWidth or src.width or 0) or s[2] >= (src.trueHeight or src.height or 0) then
        error(("union plaza: %s layout has no cell %d,%d; re-import the ROM"):format(Plaza.TILE_SOURCE_ID, s[1], s[2]))
      end
      local c = src:cellAt(s[1], s[2])
      cellsOut[y * Plaza.WIDTH + x + 1] = { mid = c.mid, coll = c.coll, elev = c.elev }
    end
  end
  local border = {}
  for i, m in ipairs(src.borderMids or { 0 }) do border[i] = m end
  return {
    width = Plaza.WIDTH,
    height = Plaza.HEIGHT,
    trueWidth = Plaza.WIDTH,
    trueHeight = Plaza.HEIGHT,
    borderWidth = src.borderWidth or 1,
    borderHeight = src.borderHeight or 1,
    borderMids = border,
    cells = cellsOut,
  }
end

local function buildEvents(ev)
  if type(ev) ~= "table" then return nil end
  local out = {}
  for k, v in pairs(ev) do out[k] = v end
  local objs = {}
  for _, row in ipairs(ev.objects or ev.objectEvents or {}) do
    if tonumber(row.localId) == Plaza.ATTENDANT_LOCAL_ID then
      objs[#objs + 1] = copyRow(row)
    end
  end
  out.objects = objs
  out.objectEvents = nil
  out.bgEvents = {}
  out.coordEvents = {}
  return out
end

function Plaza.ensure(game)
  local maps = game and game.data and game.data.maps
  if type(maps) ~= "table" then error("union plaza: no map table to build " .. Plaza.MAP_ID .. " into", 2) end
  local kind = Plaza.KIND
  local sourceId = Plaza.TILE_SOURCE_ID
  local srcDef = maps[sourceId]
  if not srcDef then
    error("union plaza: " .. sourceId .. " is missing from the cache; re-import the ROM", 2)
  end
  if not srcDef.midLayout then
    local okM, Map = pcall(require, "src.core.game3.map")
    if okM and Map and Map.ensureMidLayout then Map.ensureMidLayout(game, sourceId, srcDef) end
  end
  local src = srcDef.midLayout
  if not src then
    error("union plaza: " .. sourceId .. " has no layout in the cache; re-import the ROM", 2)
  end

  local mapId = Plaza.MAP_ID
  local def = maps[mapId]
  if not (def and def._plazaSource == src) then
    local LayoutNative = require("src.core.game3.layout_native")
    local pair = src.pair or srcDef.pair
    def = {}
    for k, v in pairs(srcDef) do def[k] = v end
    def.id = mapId
    def.name = mapId
    def.width = Plaza.WIDTH
    def.height = Plaza.HEIGHT
    def.connections = {}
    def.midLayout = LayoutNative.fromDecoded(Plaza.buildDecoded(src, kind), mapId, pair)
    def.pair = pair
    def.warps = {}
    for i, exit in ipairs(Plaza.EXITS) do
      local srcWarps = srcDef.warps or {}
      local warp = copyRow(srcWarps[exit.source] or srcWarps[1] or {})
      warp.x, warp.y = exit.x, exit.y
      def.warps[i] = warp
    end
    def.objects = kind == "rs" and {} or nil
    def.objectEvents = nil
    def.bgEvents = {}
    def.coordEvents = {}
    if kind == "rs" then def.mapScripts = nil end
    def._plazaSource = src
    maps[mapId] = def
  end

  if kind == "rs" then
    require("src.core.game3.rse.union_rs").install(game)
    return def
  end

  local Space = package.loaded["src.core.game3.scripting.space"]
  local bundle = Space and Space.bundle
  local events = bundle and bundle.events
  if type(events) == "table" and events[sourceId]
      and events[mapId] == nil then
    events[mapId] = buildEvents(events[sourceId])
  end
  local ev = events and events[mapId]
  if ev and def.objects == nil and Space.attachEventsToMaps then
    Space.attachEventsToMaps({ [mapId] = def }, bundle)
  end
  return def
end

return Plaza
