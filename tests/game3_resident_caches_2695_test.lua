package.path = package.path .. ";./?.lua"

local passed, failed = 0, 0
local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    passed = passed + 1
    print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. " -> " .. tostring(err))
  end
end
local function eq(a, b, msg)
  if a ~= b then
    error(string.format("%s: expected %s, got %s", msg or "eq", tostring(b), tostring(a)), 2)
  end
end

local released = 0
local Obj = {}
Obj.__index = Obj
function Obj:release() self.released = true; released = released + 1 end
function Obj:setFilter() end
function Obj:getDimensions() return self.w or 64, self.h or 64 end
local function obj(t) return setmetatable(t or {}, Obj) end

love = {
  graphics = {
    newImage = function(data) return obj({ w = data and data.w or 64, h = data and data.h or 64 }) end,
    newQuad = function(x, y, w, h) return { x = x, y = y, w = w, h = h } end,
  },
  image = { newImageData = function(w, h) return obj({ w = w, h = h }) end },
  timer = { getTime = function() return 0 end },
}

local NativeTileset = require("src.core.game3.tileset_native")
local TilesetAnim = require("src.core.game3.tileset_anim")

local function fakePair(i)
  return { pair = "p" .. i, image = obj(), overImage = obj(), imageAlt = obj(), overImageAlt = obj(),
    imageData = obj(), overImageData = obj(), idxBlob = "x", overBlob = "y",
    quads = {}, overQuads = {}, slotPix = {}, midToSlot = { [0] = 0 }, cols = 16 }
end

test("trim keeps the current pair plus the LRU cap and releases the rest", function()
  NativeTileset._pairs, NativeTileset._use, NativeTileset._tick = {}, {}, 0
  TilesetAnim._pairs, TilesetAnim._visible = {}, {}
  released = 0
  local all = {}
  for i = 1, 10 do
    local ts = fakePair(i)
    all[i] = ts
    NativeTileset._pairs[ts.pair] = ts
    NativeTileset._use[ts.pair] = i
    TilesetAnim._pairs[ts.pair] = { atlas = ts }
    TilesetAnim._visible[ts.pair] = true
  end
  local evicted = NativeTileset.trim({ p1 = true }, 4, {})
  eq(NativeTileset.resident(), 4, "resident pairs")
  eq(#evicted, 6, "evicted pairs")
  eq(released, 36, "4 images + 2 ImageData released per evicted pair")
  if not NativeTileset._pairs.p1 then error("kept pair evicted", 0) end
  for i = 8, 10 do
    if not NativeTileset._pairs["p" .. i] then error("most recent pair p" .. i .. " evicted", 0) end
  end
  for i = 2, 7 do
    eq(NativeTileset._pairs["p" .. i], nil, "p" .. i .. " resident")
    eq(TilesetAnim._pairs["p" .. i], nil, "p" .. i .. " anim binding")
    eq(TilesetAnim._visible["p" .. i], nil, "p" .. i .. " anim visible")
    eq(all[i].image, nil, "p" .. i .. " image dropped")
    eq(all[i].imageData, nil, "p" .. i .. " ImageData dropped")
  end
end)

test("trim never releases a texture a live SpriteBatch still draws", function()
  NativeTileset._pairs, NativeTileset._use, NativeTileset._tick = {}, {}, 0
  released = 0
  local busyTs
  for i = 1, 8 do
    local ts = fakePair(i)
    NativeTileset._pairs[ts.pair] = ts
    NativeTileset._use[ts.pair] = i
    if i == 1 then busyTs = ts end
  end
  NativeTileset.trim({ p8 = true }, 2, { [busyTs.imageAlt] = true })
  if not NativeTileset._pairs.p1 then error("busy pair evicted", 0) end
  eq(busyTs.image.released, nil, "busy image released")
  eq(NativeTileset.resident(), 2, "resident pairs")
end)

test("trim is a no-op under the cap", function()
  NativeTileset._pairs, NativeTileset._use = {}, {}
  for i = 1, 3 do NativeTileset._pairs["p" .. i] = fakePair(i) end
  eq(#NativeTileset.trim({}, 4, {}), 0, "evicted")
  eq(NativeTileset.resident(), 3, "resident")
end)

local Pokemon = require("src.core.game3.pokemon")

test("mon pic cache stays at the cap and keeps mod-seeded entries", function()
  local savedCache = Pokemon._cache
  Pokemon._cache = { read = function() return string.rep("\0", 64 * 64 * 4) end }
  Pokemon._front = {}
  local seeded = { image = obj(), w = 64, h = 64 }
  Pokemon._front[1] = seeded
  for sp = 2, 200 do Pokemon.frontPic(sp) end
  eq(Pokemon.picCacheSize(Pokemon._front), Pokemon.PIC_CAP, "front pics resident")
  eq(Pokemon._front[1], seeded, "mod-seeded entry")
  local recent = Pokemon._front[200]
  if not recent then error("most recent pic evicted", 0) end
  eq(Pokemon.frontPic(200), recent, "recent pic reused")
  Pokemon._back = {}
  for sp = 2, 120 do Pokemon.backPic(sp) end
  eq(Pokemon.picCacheSize(Pokemon._back), Pokemon.PIC_CAP, "back pics resident")
  Pokemon._cache = savedCache
  Pokemon._front, Pokemon._back = {}, nil
end)

test("spinda pics keyed by personality stay bounded", function()
  local saved = Pokemon._spinda
  Pokemon._spinda = { tiles = string.rep("\17", 2048), normal = string.rep("\0", 32),
    shiny = string.rep("\0", 32), spots = string.rep("\0", 144) }
  Pokemon._spindaPics = {}
  for p = 1, 40 do Pokemon.frontPic(Pokemon.SPECIES_SPINDA, nil, false, p * 7919) end
  eq(Pokemon.picCacheSize(Pokemon._spindaPics), Pokemon.SPINDA_CAP, "spinda pics resident")
  Pokemon._spinda, Pokemon._spindaPics = saved, nil
end)

print(string.format("game3_resident_caches_2695: %d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
