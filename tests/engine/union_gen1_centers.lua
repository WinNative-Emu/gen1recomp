package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local Map = require("src.world.Map")
local UnionCenters = require("src.world.gen1.UnionCenters")
local UnionRoomMap = require("src.world.gen1.UnionRoomMap")
local UnionSafety = require("src.world.gen1.UnionSafety")
local Origin = require("src.online.union.Origin")

local function deepCopy(t)
  if type(t) ~= "table" then return t end
  local out = {}
  for k, v in pairs(t) do out[k] = deepCopy(v) end
  return out
end

local function deepEq(a, b, path)
  path = path or "data"
  if type(a) ~= type(b) then return false, path end
  if type(a) ~= "table" then return a == b, path end
  for k, v in pairs(a) do
    local ok, at = deepEq(v, b[k], path .. "." .. tostring(k))
    if not ok then return false, at end
  end
  for k in pairs(b) do
    if a[k] == nil then return false, path .. "." .. tostring(k) end
  end
  return true
end

local QUADS = {
  floor = { 1, 2, 3, 4 }, wall = { 5, 5, 5, 5 }, pillar = { 6, 7, 6, 7 },
  cap = { 8, 9, 10, 11 }, counter = { 12, 12, 13, 14 }, gate = { 15, 16, 17, 18 },
  pc = { 19, 20, 21, 22 }, door = { 23, 24, 25, 26 }, other = { 27, 28, 29, 30 },
}

local function blockOf(tl, tr, bl, br)
  return {
    tl[1], tl[2], tr[1], tr[2], tl[3], tl[4], tr[3], tr[4],
    bl[1], bl[2], br[1], br[2], bl[3], bl[4], br[3], br[4],
  }
end

local function centerTileset(id)
  local q = QUADS
  local blocks = {}
  for i = 0, 36 do blocks[i + 1] = blockOf(q.other, q.other, q.floor, q.floor) end
  blocks[1 + 1] = blockOf(q.wall, q.pillar, q.floor, q.pillar)
  blocks[5 + 1] = blockOf(q.counter, q.cap, q.floor, q.floor)
  blocks[6 + 1] = blockOf(q.counter, q.counter, q.floor, q.floor)
  blocks[7 + 1] = blockOf(q.counter, q.counter, q.floor, q.floor)
  blocks[12 + 1] = blockOf(q.wall, q.wall, q.floor, q.floor)
  blocks[13 + 1] = blockOf(q.door, q.wall, q.floor, q.floor)
  blocks[14 + 1] = blockOf(q.other, q.other, q.other, q.other)
  blocks[15 + 1] = blockOf(q.floor, q.floor, q.floor, q.floor)
  blocks[34 + 1] = blockOf(q.gate, q.floor, q.floor, q.floor)
  blocks[35 + 1] = blockOf(q.gate, q.counter, q.floor, q.pc)
  return {
    id = id, image = "assets/generated/tilesets/pokecenter.png",
    imageWidth = 128, imageHeight = 48, tilesPerRow = 16,
    blocks = blocks, walkable = { 3, 25 }, warpTiles = { 25 },
    counterTiles = { 13, 17 },
  }
end

local function clubTileset()
  local blocks = {}
  for i = 0, 35 do
    local b = {}
    for j = 1, 16 do b[j] = 40 end
    blocks[i + 1] = b
  end
  for _, id in ipairs({ 3, 19, 23, 27 }) do
    for j = 1, 8 do blocks[id + 1][j] = 6 end
  end
  return { id = "CLUB", image = "assets/generated/tilesets/club.png", tilesPerRow = 16,
           imageWidth = 128, imageHeight = 40, blocks = blocks, walkable = { 40 } }
end

local function center(id, label, extra)
  local def = {
    id = id, label = label, tileset = "POKECENTER", width = 7, height = 4, borderBlock = 0,
    blocks = { 32, 16, 1, 2, 12, 13, 13, 33, 4, 5, 7, 7, 34, 35,
               8, 15, 15, 15, 15, 15, 27, 14, 10, 11, 14, 15, 15, 14 },
    warps = { { x = 3, y = 7, destMap = "LAST_MAP", destWarp = 1 },
              { x = 4, y = 7, destMap = "LAST_MAP", destWarp = 1 } },
    objects = {
      { index = 1, sprite = "SPRITE_NURSE", x = 3, y = 1, name = label .. "_NURSE",
        text = "TEXT_" .. label:upper() .. "_NURSE" },
      { index = 2, sprite = "SPRITE_GENTLEMAN", x = 10, y = 5, name = label .. "_GENTLEMAN",
        text = "TEXT_" .. label:upper() .. "_GENTLEMAN" },
      { index = 3, sprite = "SPRITE_LINK_RECEPTIONIST", x = 11, y = 2, name = label .. "_LINK",
        text = "TEXT_" .. label:upper() .. "_LINK_RECEPTIONIST" },
    },
  }
  for k, v in pairs(extra or {}) do def[k] = v end
  return def
end

local function indigo()
  return {
    id = "INDIGO_PLATEAU_LOBBY", label = "IndigoPlateauLobby", tileset = "MART",
    width = 8, height = 6, borderBlock = 0,
    blocks = { 19, 18, 12, 12, 13, 0, 0, 0,
               22, 15, 30, 31, 31, 36, 36, 36,
               24, 15, 32, 16, 1, 2, 13, 13,
               23, 15, 33, 4, 5, 7, 34, 35,
               29, 29, 15, 15, 15, 15, 15, 27,
               25, 15, 15, 10, 11, 15, 14, 14 },
    warps = { { x = 7, y = 11, destMap = "LAST_MAP", destWarp = 1 },
              { x = 8, y = 11, destMap = "LAST_MAP", destWarp = 2 },
              { x = 8, y = 0, destMap = "LORELEIS_ROOM", destWarp = 1 } },
    objects = {
      { index = 1, sprite = "SPRITE_NURSE", x = 7, y = 5, name = "INDIGO_NURSE",
        text = "TEXT_INDIGOPLATEAULOBBY_NURSE" },
      { index = 5, sprite = "SPRITE_LINK_RECEPTIONIST", x = 13, y = 6, name = "INDIGO_LINK",
        text = "TEXT_INDIGOPLATEAULOBBY_LINK_RECEPTIONIST" },
    },
  }
end

local function source()
  local mart = centerTileset("MART")
  return {
    maps = {
      VIRIDIAN_POKECENTER = center("VIRIDIAN_POKECENTER", "ViridianPokecenter"),
      MT_MOON_POKECENTER = center("MT_MOON_POKECENTER", "MtMoonPokecenter"),
      INDIGO_PLATEAU_LOBBY = indigo(),
      TRADE_CENTER = { id = "TRADE_CENTER", borderBlock = 14 },
      VIRIDIAN_CITY = { id = "VIRIDIAN_CITY", tileset = "OVERWORLD", width = 1, height = 1, blocks = { 0 },
                        warps = { { x = 23, y = 25, destMap = "VIRIDIAN_POKECENTER", destWarp = 1 } } },
      ROUTE_4 = { id = "ROUTE_4", tileset = "OVERWORLD", width = 1, height = 1, blocks = { 0 },
                  warps = { { x = 11, y = 5, destMap = "MT_MOON_POKECENTER", destWarp = 1 } } },
      INDIGO_PLATEAU = { id = "INDIGO_PLATEAU", tileset = "PLATEAU", width = 1, height = 1, blocks = { 0 },
                         warps = { { x = 9, y = 5, destMap = "INDIGO_PLATEAU_LOBBY", destWarp = 1 } } },
    },
    tilesets = {
      POKECENTER = centerTileset("POKECENTER"), MART = mart,
      REDS_HOUSE_1 = { id = "REDS_HOUSE_1", image = "assets/generated/tilesets/reds_house.png", tilesPerRow = 16 },
      CLUB = clubTileset(),
    },
    text_pointers = {
      ViridianPokecenter = { TEXT_VIRIDIANPOKECENTER_LINK_RECEPTIONIST = { cableClub = true, label = "L" } },
      MtMoonPokecenter = { TEXT_MTMOONPOKECENTER_LINK_RECEPTIONIST = { cableClub = true, label = "M" } },
      IndigoPlateauLobby = { TEXT_INDIGOPLATEAULOBBY_LINK_RECEPTIONIST = { cableClub = true, label = "I" } },
    },
    field = { hiddenExtras = { pcTiles = {
      VIRIDIAN_POKECENTER = { { x = 13, y = 3, facing = "up" } },
      MT_MOON_POKECENTER = { { x = 13, y = 3, facing = "up" } },
      INDIGO_PLATEAU_LOBBY = { { x = 15, y = 7, facing = "up" } },
    } }, boot = { startMap = "VIRIDIAN_CITY", startX = 0, startY = 0 } },
    audio = { mapSongs = { VIRIDIAN_POKECENTER = "Music_Pokecenter", TRADE_CENTER = "Music_Celadon" } },
  }
end

local function load(src)
  local data = {}
  for k, v in pairs(src) do data[k] = v end
  return data
end

local src = source()
local pristine = deepCopy(src)
local plan, why = UnionCenters.plan(src, "VIRIDIAN_POKECENTER")
check(plan ~= nil, "Viridian plan: " .. tostring(why))
eq(plan and plan.stairs.x .. "," .. plan.stairs.y, "13,1", "Viridian stairs cell")
eq(plan and plan.front.x .. "," .. plan.front.y, "11,3", "Viridian front of the desk")
eq(plan and plan.desk.bx .. "," .. plan.desk.by, "5,1", "Viridian desk block")
local ip = UnionCenters.plan(src, "INDIGO_PLATEAU_LOBBY")
check(ip ~= nil, "Indigo Plateau gets its own plan")
eq(ip and ip.stairs.x .. "," .. ip.stairs.y, "15,5", "Indigo stairs cell")
eq(ip and ip.front.x .. "," .. ip.front.y, "13,7", "Indigo front of the desk")
eq(ip and ip.desk.bx .. "," .. ip.desk.by, "6,3", "Indigo desk block")
eq(ip and ip.tileset, "MART", "Indigo plan keeps the MART tileset")

local edited = source()
edited.maps.MT_MOON_POKECENTER.blocks[13] = 15
local _, reason = UnionCenters.plan(edited, "MT_MOON_POKECENTER")
check(reason and reason:find("expected 34", 1, true), "a non-vanilla desk is refused with a reason: " .. tostring(reason))
local blocked = source()
table.insert(blocked.maps.VIRIDIAN_POKECENTER.objects, { index = 9, sprite = "SPRITE_GIRL", x = 12, y = 1, name = "IN_THE_WAY" })
local _, reason2 = UnionCenters.plan(blocked, "VIRIDIAN_POKECENTER")
check(reason2 and reason2:find("IN_THE_WAY", 1, true), "an object in the stairs area refuses the plan")

local data = load(src)
local r = UnionCenters.apply(data)
check(r ~= nil, "apply patches the fixture")
eq(#r.order, 3, "three fixture centers patched")
check(deepEq(src, pristine), "apply never writes into the source tables")
local maps, pc = data.maps, data.tilesets.POKECENTER
local floor1, floor2, room = maps.VIRIDIAN_POKECENTER, maps[UnionCenters.FLOOR_2F], maps[UnionCenters.UNION_ROOM]
check(floor2 and room, "2F and the union room are registered")
eq(#floor2.blocks, floor2.width * floor2.height, "2F block count")
eq(#room.blocks, room.width * room.height, "union room block count")
for _, id in ipairs({ "VIRIDIAN_POKECENTER", "MT_MOON_POKECENTER", "INDIGO_PLATEAU_LOBBY" }) do
  local p = r.plans[id]
  check(p and p.verified, id .. " patched layout verified")
  for _, o in ipairs(maps[id].objects) do
    check(o.sprite ~= "SPRITE_LINK_RECEPTIONIST", id .. " no longer has the link receptionist")
  end
  local w = maps[id].warps[p.warp]
  eq(w and w.destMap, UnionCenters.FLOOR_2F, id .. " stairs warp leads to the 2F")
  eq(#maps[id].warps, #pristine.maps[id].warps + 1, id .. " gains exactly one warp")
end
eq(r.plans.VIRIDIAN_POKECENTER.warp, 3, "center stairs warp index")
eq(r.plans.INDIGO_PLATEAU_LOBBY.warp, 4, "Indigo stairs warp index")

local m1 = Map.new(floor1, pc)
check(m1:isWarpTileCell(13, 1) and m1:isWalkableCell(13, 1), "1F stair cell is a walkable warp tile")
check(not m1:isWalkableCell(10, 1), "1F pillar seals the nurse side")
check(not m1:isWalkableCell(10, 2), "1F counter ends in a cap under the pillar")
eq(m1:blockAt(4, 1), 7, "1F counter block next to the cap stays the vanilla counter")
eq(m1:tileAt(20, 4), QUADS.cap[1], "cap tile sits right under the pillar column")
eq(m1:tileAt(20, 2), QUADS.pillar[1], "pillar tile above the cap")
check(m1:isWalkableCell(11, 1) and m1:isWalkableCell(12, 1) and m1:isWalkableCell(11, 2), "stairs alcove walkable")
check(not m1:isWalkableCell(13, 3), "PC cell stays solid")
eq(m1:tileAt(26, 7), QUADS.pc[3], "PC graphic stays at 13,3")

local mi = Map.new(maps.INDIGO_PLATEAU_LOBBY, data.tilesets.MART)
check(mi:isWarpTileCell(15, 5) and mi:isWalkableCell(15, 5), "Indigo stair cell is a walkable warp tile")
check(not mi:isWalkableCell(12, 5) and not mi:isWalkableCell(12, 6), "Indigo nurse side sealed")
local lorelei = maps.INDIGO_PLATEAU_LOBBY.warps[3]
eq(lorelei.destMap .. "@" .. lorelei.x .. "," .. lorelei.y, "LORELEIS_ROOM@8,0", "Lorelei warp untouched")

local m2 = Map.new(floor2, pc)
check(m2:isWarpTileCell(13, 1) and m2:isWalkableCell(13, 1), "2F stair cell is a walkable warp tile")
check(not m2:isWalkableCell(6, 2), "2F union gate starts closed")
check(m2:isCounterCell(7, 2) and m2:isCounterCell(11, 2), "both 2F receptionists are reachable across the counter")
check(not m2:isWalkableCell(12, 1), "2F pillar seals the area behind the counter")
eq(m2:blockAt(UnionCenters.GATE_2F.bx, UnionCenters.GATE_2F.by), r.gateClosed, "gate block id is exported")
local sprites = {}
for _, o in ipairs(floor2.objects) do sprites[o.x .. "," .. o.y] = o.text end
eq(sprites["11,1"], UnionCenters.TEXT_LINK, "cable club receptionist on the 2F")
eq(sprites["7,1"], UnionCenters.TEXT_UNION, "union receptionist on the 2F")
eq(#floor2.objects, 2, "2F has only the two receptionists")
check(data.text_pointers[UnionCenters.LABEL_2F][UnionCenters.TEXT_LINK].cableClub,
      "2F cable desk keeps the cable club text entry")
eq(floor2.warps[2].destMap, UnionCenters.UNION_ROOM, "2F door leads to the union room")
eq(room.warps[1].destMap .. "#" .. room.warps[1].destWarp, UnionCenters.FLOOR_2F .. "#2", "room exit leads to the 2F door")
eq(data.audio.mapSongs[UnionCenters.FLOOR_2F], "Music_Pokecenter", "2F plays the center music")
eq(data.audio.mapSongs[UnionCenters.UNION_ROOM], "Music_Celadon", "room plays the link room music")
check(pristine.audio.mapSongs[UnionCenters.FLOOR_2F] == nil and src.audio.mapSongs[UnionCenters.FLOOR_2F] == nil,
      "source song table untouched")

for id = 96, 103 do
  check(pc.tileSources[id] and pc.tileSources[id].tileset == "REDS_HOUSE_1",
        ("tile %d is sourced from Red's house"):format(id))
end
eq(pc.imageHeight, 56, "composed atlas grows by one tile row")
eq(pc.image, UnionCenters.IMAGE, "POKECENTER draws from the composed atlas")
eq(data.tilesets.MART.image, UnionCenters.IMAGE, "MART draws from the composed atlas for Indigo")

local snapshot = deepCopy(data)
local again, note = UnionCenters.apply(data)
eq(note, "already applied", "a second apply reports a no-op")
check(again == r, "a second apply returns the first registry")
local same, where = deepEq(snapshot, data)
check(same, "a second apply changes nothing: " .. tostring(where))

local onA = load(src)
check(UnionCenters.seed(onA, { unionRoom = true }) ~= nil, "seed applies with the setting on")
local off = load(src)
local none, offWhy = UnionCenters.seed(off, { unionRoom = false })
check(none == nil and offWhy == "setting off", "seed skips with the setting off")
local vanilla, at = deepEq(off, pristine)
check(vanilla, "setting off leaves vanilla data: " .. tostring(at))
check(UnionCenters.forData(off) == nil, "no registry with the setting off")
local onB = load(src)
UnionCenters.seed(onB, { unionRoom = true })
local equal, diff = deepEq(onA, onB)
check(equal, "ON/OFF/ON reloads give identical map tables: " .. tostring(diff))
local receptionists = 0
for _, o in ipairs(onB.maps[UnionCenters.FLOOR_2F].objects) do
  if o.sprite == "SPRITE_LINK_RECEPTIONIST" then receptionists = receptionists + 1 end
end
eq(receptionists, 2, "no duplicate 2F NPCs after reloads")
eq(#onB.maps.VIRIDIAN_POKECENTER.warps, 3, "no duplicate stairs warps after reloads")
eq(#onB.tilesets.POKECENTER.blocks, 37 + 7, "no duplicate appended blocks after reloads")

local Plaza = require("src.core.game3.link.union_plaza_map")
local seen = {}
local mr = Map.new(room, data.tilesets.CLUB)
local gridOk, distinct = true, true
for slot = 1, UnionRoomMap.CAP do
  local x, y = UnionRoomMap.cellFor(slot)
  local px, py = Plaza.cellFor(slot)
  if not (x == px and y == py) then gridOk = false end
  check(x and mr:isWalkableCell(x, y), ("slot %d cell %s,%s walkable"):format(slot, tostring(x), tostring(y)))
  eq(UnionRoomMap.slotAt(x, y), slot, ("slotAt inverts cellFor for slot %d"):format(slot))
  local key = tostring(x) .. "," .. tostring(y)
  if seen[key] then distinct = false end
  seen[key] = true
  for _, e in ipairs(UnionRoomMap.EXITS) do
    check(not (e.x == x and e.y == y), ("slot %d is not an exit cell"):format(slot))
  end
end
check(gridOk, "Gen 1 slot N is the Gen 3 plaza slot N cell")
check(distinct, "40 participant cells never overlap")
check(UnionRoomMap.cellFor(41) == nil, "no slot 41")
for _, e in ipairs(UnionRoomMap.EXITS) do
  check(mr:isWalkableCell(e.x, e.y) and e.y == mr.heightCells - 1, "exit carpet on the bottom edge")
end

local scripts = require("data.scripts.pokecenter_upstairs")[UnionCenters.FLOOR_2F]
local function fakeGame(save)
  return { data = data, save = save }
end
local function fakeOw(mapDef)
  local ow = { calls = {}, map = Map.new(mapDef, pc) }
  function ow:takeWarp(w) self.calls[#self.calls + 1] = { "takeWarp", w } end
  function ow:warpToHealPoint() self.calls[#self.calls + 1] = { "heal" } end
  function ow:replaceBlock(bx, by, b) self.map:setBlock(bx, by, b) self.calls[#self.calls + 1] = { "block", b } end
  function ow:queueScript(s) self.calls[#self.calls + 1] = { "queue", s } end
  return ow
end
local outdoor = { id = "VIRIDIAN_CITY", x = 23, y = 26 }
local save = { flags = {}, lastOutdoor = outdoor }
local ow = fakeOw(deepCopy(floor2))
scripts.onEnter(fakeGame(save), ow, "MT_MOON_POKECENTER")
local o = Origin.get(save)
check(o and o.gen == 1 and o.map == "MT_MOON_POKECENTER", "entering the 2F records the origin center")
eq(o and o.warp, r.plans.MT_MOON_POKECENTER.warp, "origin keeps the 1F stairs warp index")
eq(o and (o.x .. "," .. o.y), "13,1", "origin keeps the 1F stairs cell")
check(save.lastOutdoor == outdoor and save.lastOutdoor.id == "VIRIDIAN_CITY", "origin record leaves lastOutdoor alone")
scripts.onEnter(fakeGame(save), ow, UnionCenters.UNION_ROOM)
eq((Origin.get(save) or {}).map, "MT_MOON_POKECENTER", "returning from the room keeps the origin")
check(ow.calls[#ow.calls][1] == "queue", "returning from the room queues the walk-out")
eq(ow.map:blockAt(UnionCenters.GATE_2F.bx, UnionCenters.GATE_2F.by), r.gateOpen, "gate opens for the walk-out")
scripts.onEnter(fakeGame(save), ow, nil)
eq(ow.map:blockAt(UnionCenters.GATE_2F.bx, UnionCenters.GATE_2F.by), r.gateClosed, "a plain entry closes the gate")
eq((Origin.get(save) or {}).map, "MT_MOON_POKECENTER", "a boot entry keeps the origin")
check(scripts.onStep(fakeGame(save), ow, 12, 2) == false, "other 2F cells are plain steps")
ow.calls = {}
check(scripts.onStep(fakeGame(save), ow, 13, 1) == true, "the 2F stairs consume the step")
local call = ow.calls[1]
check(call and call[1] == "takeWarp" and call[2].destMap == "MT_MOON_POKECENTER"
      and call[2].destWarp == r.plans.MT_MOON_POKECENTER.warp, "2F stairs return to the origin center")
local land = maps[call[2].destMap].warps[call[2].destWarp]
eq(land.x .. "," .. land.y, "13,1", "the return lands on that center's stairs")
check(Origin.get(save) == nil, "origin cleared once the player is back")
ow.calls = {}
Origin.record(save, { gen = 1, version = "red", map = "NOWHERE", warp = 3, x = 1, y = 1 })
scripts.onStep(fakeGame(save), ow, 13, 1)
eq(ow.calls[1] and ow.calls[1][1], "heal", "an invalid origin falls back to the heal point")
ow.calls = {}
scripts.onStep(fakeGame({ flags = {} }), ow, 13, 1)
eq(ow.calls[1] and ow.calls[1][1], "heal", "no origin falls back to the heal point")

local function savedOn(map, origin, x, y)
  local s = { player = { map = map, x = x or 13, y = y or 2, facing = "left", name = "RED" },
              lastHeal = { map = "VIRIDIAN_CITY", x = 23, y = 26 }, flags = {},
              lastOutdoor = { id = "PALLET_TOWN", x = 5, y = 6 } }
  if origin then Origin.record(s, origin) end
  return s
end
local function spot(s) return s.player.map .. "@" .. s.player.x .. "," .. s.player.y .. ":" .. s.player.facing end
local mtMoon = { gen = 1, version = "red", map = "MT_MOON_POKECENTER", warp = 3, x = 13, y = 1 }
local offData = load(src)
for _, case in ipairs({ { "off", offData }, { "on", data } }) do
  local label, d = case[1], case[2]
  local s1 = savedOn(UnionCenters.FLOOR_2F, mtMoon)
  check(UnionSafety.settle(s1, d) ~= nil, label .. ": a 2F save is settled at load")
  eq(spot(s1), "MT_MOON_POKECENTER@3,3:up", label .. ": 2F save lands in front of the origin nurse")
  check(Origin.get(s1) == nil, label .. ": settle clears the origin")
  eq(s1.lastOutdoor.id, "ROUTE_4", label .. ": lastOutdoor follows the origin center's town")
  local s2 = savedOn(UnionCenters.UNION_ROOM, { gen = 1, version = "red", map = "INDIGO_PLATEAU_LOBBY", warp = 4, x = 15, y = 5 })
  UnionSafety.settle(s2, d)
  eq(spot(s2), "INDIGO_PLATEAU_LOBBY@7,7:up", label .. ": room save lands below the Indigo nurse")
  eq(s2.lastOutdoor.id, "INDIGO_PLATEAU", label .. ": Indigo save keeps the plateau as lastOutdoor")
  local s3 = savedOn(UnionCenters.FLOOR_2F)
  UnionSafety.settle(s3, d)
  eq(spot(s3), "VIRIDIAN_POKECENTER@3,3:up", label .. ": no origin uses the heal point's center nurse")
  local s4 = savedOn(UnionCenters.FLOOR_2F)
  s4.lastHeal = { map = "GONE", x = 1, y = 1 }
  UnionSafety.settle(s4, d)
  eq(spot(s4), "VIRIDIAN_POKECENTER@3,3:up", label .. ": an unknown heal point uses the boot heal town's center")
  local s5 = savedOn("VIRIDIAN_POKECENTER", nil, 12, 1)
  UnionSafety.settle(s5, d)
  eq(spot(s5), "VIRIDIAN_POKECENTER@3,3:up", label .. ": a 1F stairs alcove cell is not vanilla and moves")
  local s6 = savedOn("VIRIDIAN_POKECENTER", nil, 11, 3)
  check(UnionSafety.settle(s6, d) == nil and spot(s6) == "VIRIDIAN_POKECENTER@11,3:left",
        label .. ": a vanilla 1F cell is left alone")
  local s7 = savedOn("VIRIDIAN_CITY", nil, 5, 5)
  check(UnionSafety.settle(s7, d) == nil, label .. ": ordinary maps are left alone")
end

local live = savedOn(UnionCenters.UNION_ROOM, mtMoon, 12, 20)
live.party = { "mon" }
local livePlayer = live.player
local written
local ok = UnionSafety.write(live, data, function(out)
  written = out
  out.meta = { stamped = true }
  return true
end)
check(ok, "write passes the writer's result through")
check(written ~= live, "write hands the writer a copy")
eq(spot(written), "MT_MOON_POKECENTER@3,3:up", "written save stands in front of the origin nurse")
check(Origin.get(written) == nil, "written save carries no origin")
eq(written.lastOutdoor.id, "ROUTE_4", "written lastOutdoor matches the 1F center")
check(written.party == live.party, "written save shares the rest of the save")
check(live.player == livePlayer and spot(live) == "UNION_ROOM@12,20:left", "the live player is not moved")
eq((Origin.get(live) or {}).map, "MT_MOON_POKECENTER", "the live origin stays")
eq(live.lastOutdoor.id, "PALLET_TOWN", "the live lastOutdoor stays")
check(live.meta and live.meta.stamped, "writer stamps flow back to the live save")
local plain = savedOn("VIRIDIAN_CITY", nil, 5, 5)
local seenPlain
UnionSafety.write(plain, data, function(out) seenPlain = out return true end)
check(seenPlain == plain, "a vanilla position writes the live table unchanged")

T.finish("union_gen1_centers")
