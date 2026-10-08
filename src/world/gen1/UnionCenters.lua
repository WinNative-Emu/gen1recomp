local Assets = require("src.render.Assets")
local Logger = require("src.core.Logger")
local UnionRoomMap = require("src.world.gen1.UnionRoomMap")

local UnionCenters = {}

UnionCenters.FLOOR_2F = "POKECENTER_2F"
UnionCenters.LABEL_2F = "Pokecenter2F"
UnionCenters.UNION_ROOM = UnionRoomMap.MAP_ID
UnionCenters.IMAGE = "assets/composed/pokecenter_union.png"
UnionCenters.STAIR_TILESET = "REDS_HOUSE_1"
UnionCenters.STAIR_SOURCE_TILES = { 10, 11, 12, 13, 26, 27, 28, 29 }
UnionCenters.TEXT_LINK = "TEXT_POKECENTER2F_LINK_RECEPTIONIST"
UnionCenters.TEXT_UNION = "TEXT_POKECENTER2F_UNION_RECEPTIONIST"
UnionCenters.LINK_RECEPTIONIST = 1
UnionCenters.UNION_RECEPTIONIST = 2
UnionCenters.STAIRS_2F = { x = 13, y = 1 }
UnionCenters.DOOR_2F = { x = 6, y = 1 }
UnionCenters.DOOR_WARP_2F = 2
UnionCenters.GATE_2F = { bx = 3, by = 1 }

UnionCenters.EXPECTED = {
  "VIRIDIAN_POKECENTER", "PEWTER_POKECENTER", "CERULEAN_POKECENTER",
  "MT_MOON_POKECENTER", "ROCK_TUNNEL_POKECENTER", "VERMILION_POKECENTER",
  "CELADON_POKECENTER", "LAVENDER_POKECENTER", "FUCHSIA_POKECENTER",
  "CINNABAR_POKECENTER", "SAFFRON_POKECENTER", "INDIGO_PLATEAU_LOBBY",
}

local TILESETS = { POKECENTER = true, MART = true }
local DESK_LEFT, DESK_RIGHT, DESK_DOOR, COUNTER = 34, 35, 13, 7
local SRC = {
  floor = { 15, 0 }, wall = { 12, 0 }, pillar = { 1, 1 }, cap = { 5, 1 },
  counter = { 7, 0 }, gate = { 34, 0 }, pc = { 35, 3 },
}
local COUNTER_LEFT_END = 6

local registry = setmetatable({}, { __mode = "k" })

local function copy(t)
  if type(t) ~= "table" then return t end
  local out = {}
  for k, v in pairs(t) do out[k] = copy(v) end
  return out
end

local function shallow(t)
  local out = {}
  for k, v in pairs(t or {}) do out[k] = v end
  return out
end

local function inList(list, v)
  for _, x in ipairs(list or {}) do
    if x == v then return true end
  end
  return false
end

local function blockAt(def, bx, by)
  if bx < 0 or by < 0 or bx >= def.width or by >= def.height then return nil end
  return def.blocks[by * def.width + bx + 1]
end

local function setBlock(def, bx, by, id)
  def.blocks[by * def.width + bx + 1] = id
end

local function quadOf(ts, block, cell)
  local b = ts.blocks[block + 1]
  if not b then return nil end
  local ox, oy = (cell % 2) * 2, math.floor(cell / 2) * 2
  local function at(x, y) return b[(oy + y) * 4 + ox + x + 1] end
  return { at(0, 0), at(1, 0), at(0, 1), at(1, 1) }
end

local function assemble(tl, tr, bl, br)
  return {
    tl[1], tl[2], tr[1], tr[2],
    tl[3], tl[4], tr[3], tr[4],
    bl[1], bl[2], br[1], br[2],
    bl[3], bl[4], br[3], br[4],
  }
end

function UnionCenters.findReceptionist(def, pointers)
  if type(def) ~= "table" or type(def.objects) ~= "table" then return nil end
  local entries = type(pointers) == "table" and pointers[def.label] or nil
  for i, o in ipairs(def.objects) do
    local entry = entries and entries[o.text]
    if o.sprite == "SPRITE_LINK_RECEPTIONIST" and type(entry) == "table" and entry.cableClub then
      return o, i, entry
    end
  end
  return nil
end

local function pcTileAt(data, mapId, x, y)
  local extras = data.field and data.field.hiddenExtras
  for _, h in ipairs(extras and extras.pcTiles and extras.pcTiles[mapId] or {}) do
    if h.x == x and h.y == y then return true end
  end
  return false
end

function UnionCenters.plan(data, mapId)
  local def = data.maps and data.maps[mapId]
  if type(def) ~= "table" then return nil, "map missing" end
  if not TILESETS[def.tileset] then return nil, "tileset " .. tostring(def.tileset) end
  local ts = data.tilesets and data.tilesets[def.tileset]
  if not ts then return nil, "tileset data missing" end
  local obj, objIndex = UnionCenters.findReceptionist(def, data.text_pointers)
  if not obj then return nil, "no cable club receptionist" end
  local bc, br = math.floor(obj.x / 2), math.floor(obj.y / 2)
  if obj.x % 2 ~= 1 or obj.y % 2 ~= 0 then
    return nil, ("receptionist at %d,%d is not the desk gap"):format(obj.x, obj.y)
  end
  local want = {
    { bc, br, DESK_LEFT }, { bc + 1, br, DESK_RIGHT },
    { bc, br - 1, DESK_DOOR }, { bc + 1, br - 1, DESK_DOOR },
    { bc - 1, br, COUNTER },
  }
  for _, w in ipairs(want) do
    local got = blockAt(def, w[1], w[2])
    if got ~= w[3] then
      return nil, ("block %d,%d is %s, expected %d"):format(w[1], w[2], tostring(got), w[3])
    end
  end
  local pcX, pcY = bc * 2 + 3, br * 2 + 1
  if not pcTileAt(data, mapId, pcX, pcY) then
    return nil, ("no PC hidden tile at %d,%d"):format(pcX, pcY)
  end
  local ax0, ax1, ay0, ay1 = bc * 2 + 1, bc * 2 + 3, br * 2 - 1, br * 2 + 1
  for _, o in ipairs(def.objects) do
    if o ~= obj and o.x >= ax0 and o.x <= ax1 and o.y >= ay0 and o.y <= ay1 then
      return nil, ("object %s stands in the stairs area"):format(tostring(o.name))
    end
  end
  for _, w in ipairs(def.warps or {}) do
    if w.x >= ax0 and w.x <= ax1 and w.y >= ay0 and w.y <= ay1 then
      return nil, ("warp at %d,%d overlaps the stairs area"):format(w.x, w.y)
    end
  end
  return {
    map = mapId, label = def.label, tileset = def.tileset,
    receptionist = { index = obj.index, objIndex = objIndex, x = obj.x, y = obj.y,
                     text = obj.text, name = obj.name },
    front = { x = obj.x, y = obj.y + 1 },
    desk = { bx = bc, by = br },
    changes = {
      { bx = bc, by = br - 1, from = DESK_DOOR, to = "pillarWall" },
      { bx = bc + 1, by = br - 1, from = DESK_DOOR, to = "upStairs" },
      { bx = bc, by = br, from = DESK_LEFT, to = "capFloor" },
      { bx = bc + 1, by = br, from = DESK_RIGHT, to = "pcCorner" },
    },
    stairs = { x = bc * 2 + 3, y = br * 2 - 1 },
    pc = { x = pcX, y = pcY },
  }
end

function UnionCenters.candidates(data)
  local seen, out = {}, {}
  for _, id in ipairs(UnionCenters.EXPECTED) do
    if data.maps and data.maps[id] then seen[id] = true out[#out + 1] = id end
  end
  local extra = {}
  for id, def in pairs(data.maps or {}) do
    if not seen[id] and type(def) == "table" and TILESETS[def.tileset]
       and UnionCenters.findReceptionist(def, data.text_pointers) then
      extra[#extra + 1] = id
    end
  end
  table.sort(extra)
  for _, id in ipairs(extra) do out[#out + 1] = id end
  return out
end

local function composeImage(base, source, perRow, srcPerRow, first)
  return function()
    local baseData = Assets.imageData(base)
    local srcData = Assets.imageData(source)
    local w, h = baseData:getDimensions()
    local tiles = UnionCenters.STAIR_SOURCE_TILES
    local rows = math.ceil(#tiles / perRow)
    local out = love.image.newImageData(w, h + rows * 8)
    out:paste(baseData, 0, 0, 0, 0, w, h)
    for i, t in ipairs(tiles) do
      local d = first + i - 1
      out:paste(srcData, (d % perRow) * 8, math.floor(d / perRow) * 8,
                (t % srcPerRow) * 8, math.floor(t / srcPerRow) * 8, 8, 8)
    end
    return out
  end
end

local function patchTileset(ts)
  local perRow = ts.tilesPerRow
  local first = (ts.imageWidth / 8) * (ts.imageHeight / 8)
  local q = {}
  for k, s in pairs(SRC) do
    q[k] = quadOf(ts, s[1], s[2])
    if not q[k] then return nil, "block " .. s[1] .. " missing" end
  end
  if not (inList(ts.walkable, q.floor[3]) and not inList(ts.walkable, q.pillar[3])
          and not inList(ts.walkable, q.cap[3]) and inList(ts.counterTiles, q.counter[3])) then
    return nil, "tileset collision does not match the vanilla center"
  end
  q.up = { first + 2, first + 3, first + 6, first + 7 }
  q.down = { first + 0, first + 1, first + 4, first + 5 }
  ts.image = UnionCenters.IMAGE
  ts.imageHeight = ts.imageHeight + math.ceil(#UnionCenters.STAIR_SOURCE_TILES / perRow) * 8
  ts.tileSources = ts.tileSources or {}
  for i, t in ipairs(UnionCenters.STAIR_SOURCE_TILES) do
    ts.tileSources[first + i - 1] = { tileset = UnionCenters.STAIR_TILESET, tile = t }
  end
  ts.walkable = ts.walkable or {}
  ts.warpTiles = ts.warpTiles or {}
  for _, t in ipairs({ q.up[3], q.down[3] }) do
    ts.walkable[#ts.walkable + 1] = t
    ts.warpTiles[#ts.warpTiles + 1] = t
  end
  local ids = {}
  local function add(name, b)
    ts.blocks[#ts.blocks + 1] = b
    ids[name] = #ts.blocks - 1
  end
  add("pillarWall", assemble(q.pillar, q.wall, q.pillar, q.floor))
  add("upStairs", assemble(q.wall, q.wall, q.floor, q.up))
  add("capFloor", assemble(q.cap, q.floor, q.floor, q.floor))
  add("pcCorner", assemble(q.floor, q.floor, q.floor, q.pc))
  add("downStairs", assemble(q.pillar, q.wall, q.pillar, q.down))
  add("gateClosed", assemble(q.gate, q.counter, q.floor, q.floor))
  add("gateOpen", assemble(q.floor, q.counter, q.floor, q.floor))
  ids.counterEnd = ids.capFloor
  ids.firstTile = first
  ids.upTile, ids.downTile = q.up[3], q.down[3]
  return ids
end

local function build2F(ids, borderBlock, home)
  local W, D, F = 12, DESK_DOOR, 15
  local function receptionist(index, x, text, name)
    return { index = index, movement = "STAY", range = "DOWN",
             sprite = "SPRITE_LINK_RECEPTIONIST", x = x, y = 1,
             name = name, text = text }
  end
  return {
    id = UnionCenters.FLOOR_2F, label = UnionCenters.LABEL_2F, tileset = "POKECENTER",
    width = 7, height = 4, borderBlock = borderBlock,
    blocks = {
      W, W, W, D, W, D, ids.downStairs,
      COUNTER_LEFT_END, COUNTER, COUNTER, ids.gateClosed, COUNTER, ids.gateClosed, ids.counterEnd,
      F, F, F, F, F, F, F,
      14, F, F, F, F, F, 14,
    },
    warps = {
      { x = UnionCenters.STAIRS_2F.x, y = UnionCenters.STAIRS_2F.y,
        destMap = home.map, destWarp = home.warp },
      { x = UnionCenters.DOOR_2F.x, y = UnionCenters.DOOR_2F.y,
        destMap = UnionCenters.UNION_ROOM, destWarp = 1 },
    },
    objects = {
      receptionist(UnionCenters.LINK_RECEPTIONIST, 11, UnionCenters.TEXT_LINK,
                   "POKECENTER2F_LINK_RECEPTIONIST"),
      receptionist(UnionCenters.UNION_RECEPTIONIST, 7, UnionCenters.TEXT_UNION,
                   "POKECENTER2F_UNION_RECEPTIONIST"),
    },
    signs = {}, connections = {},
  }
end

local function verify(def, plan, ids)
  for _, c in ipairs(plan.changes) do
    if blockAt(def, c.bx, c.by) ~= ids[c.to] then return false end
  end
  local w = def.warps[plan.warp]
  if not (w and w.x == plan.stairs.x and w.y == plan.stairs.y
          and w.destMap == UnionCenters.FLOOR_2F) then
    return false
  end
  for _, o in ipairs(def.objects) do
    if o.sprite == "SPRITE_LINK_RECEPTIONIST" and o.text == plan.receptionist.text then
      return false
    end
  end
  return true
end

function UnionCenters.forData(data)
  return data and registry[data] or nil
end

function UnionCenters.planFor(data, mapId)
  local r = UnionCenters.forData(data)
  return r and r.plans[mapId] or nil
end

function UnionCenters.apply(data)
  local maps, tilesets = data.maps, data.tilesets
  if not (maps and tilesets) then return nil, "no map data" end
  if maps[UnionCenters.FLOOR_2F] then return registry[data], "already applied" end
  local stairs, club = tilesets[UnionCenters.STAIR_TILESET], tilesets[UnionRoomMap.TILESET]
  if not (stairs and club and tilesets.POKECENTER) then return nil, "tilesets missing" end
  local result = { plans = {}, order = {}, refused = {}, blocks = {} }
  local ok = {}
  for _, id in ipairs(UnionCenters.candidates(data)) do
    local plan, why = UnionCenters.plan(data, id)
    if plan then
      ok[#ok + 1] = plan
    else
      result.refused[id] = why
    end
  end
  if #ok == 0 then return nil, "no center matched" end

  data.maps = shallow(maps)
  data.tilesets = shallow(tilesets)
  maps, tilesets = data.maps, data.tilesets
  local baseImage = tilesets.POKECENTER.image
  local patched = {}
  local function tilesetIds(name)
    if patched[name] ~= nil then return patched[name] end
    local ts = copy(tilesets[name])
    local ids, why = patchTileset(ts)
    if ids then
      tilesets[name] = ts
      result.blocks[name] = ids
    else
      Logger.warn("union room: tileset %s not patched: %s", name, why)
    end
    patched[name] = ids or false
    return ids
  end
  local pcIds = tilesetIds("POKECENTER")
  if not pcIds then return nil, "POKECENTER tileset did not match" end
  Assets.compose(UnionCenters.IMAGE,
    composeImage(baseImage, stairs.image, tilesets.POKECENTER.tilesPerRow,
                 stairs.tilesPerRow, pcIds.firstTile))

  for _, plan in ipairs(ok) do
    local ids = tilesetIds(plan.tileset)
    if not ids then
      result.refused[plan.map] = "tileset " .. plan.tileset .. " did not match"
    else
      local def = copy(maps[plan.map])
      for _, c in ipairs(plan.changes) do
        c.toId = ids[c.to]
        setBlock(def, c.bx, c.by, c.toId)
      end
      table.remove(def.objects, plan.receptionist.objIndex)
      def.warps[#def.warps + 1] = { x = plan.stairs.x, y = plan.stairs.y,
                                    destMap = UnionCenters.FLOOR_2F, destWarp = 1 }
      plan.warp = #def.warps
      plan.verified = verify(def, plan, ids)
      maps[plan.map] = def
      result.plans[plan.map] = plan
      result.order[#result.order + 1] = plan.map
    end
  end
  local home = result.plans[result.order[1]]
  local floor2 = build2F(pcIds, maps[home.map].borderBlock, home)
  maps[UnionCenters.FLOOR_2F] = floor2
  maps[UnionCenters.UNION_ROOM] = UnionRoomMap.build(
    maps.TRADE_CENTER and maps.TRADE_CENTER.borderBlock or 0,
    UnionCenters.FLOOR_2F, UnionCenters.DOOR_WARP_2F)
  result.gateClosed, result.gateOpen = pcIds.gateClosed, pcIds.gateOpen

  local pointers = data.text_pointers
  local entry = pointers and pointers[home.label]
  entry = entry and entry[home.receptionist.text]
  if pointers then
    data.text_pointers = shallow(pointers)
    data.text_pointers[UnionCenters.LABEL_2F] = { [UnionCenters.TEXT_LINK] = copy(entry) }
  end
  local songs = data.audio and data.audio.mapSongs
  if songs then
    data.audio = shallow(data.audio)
    songs = shallow(songs)
    data.audio.mapSongs = songs
    songs[UnionCenters.FLOOR_2F] = songs[home.map]
    songs[UnionCenters.UNION_ROOM] = songs.TRADE_CENTER
  end

  registry[data] = result
  local refused = {}
  for id, why in pairs(result.refused) do refused[#refused + 1] = id .. " (" .. why .. ")" end
  table.sort(refused)
  Logger.info("union room: %d centers patched%s", #result.order,
              #refused > 0 and (", refused: " .. table.concat(refused, ", ")) or "")
  return result
end

function UnionCenters.seed(data, opts)
  local Setting = require("src.online.union.Setting")
  if not Setting.patchesOn(1, opts) then return nil, "setting off" end
  return UnionCenters.apply(data)
end

return UnionCenters
