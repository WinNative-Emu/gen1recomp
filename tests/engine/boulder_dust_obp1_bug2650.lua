package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")

local T = require("tests.harness").suite("Boulder dust OBP1 flash #2650")
local GameVersion = require("src.core.GameVersion")
local PaletteFX = require("src.render.PaletteFX")
local Assets = require("src.render.Assets")
local Game = require("src.core.Game")
local OW = require("src.world.OverworldController")
local ImageWriter = require("src.import.ImageWriter")

local bytes = {
  smoke = {0,24,26,102,4,66,11,129,86,137,26,46,76,18,56,56},
  redTree = {170,0,65,20,168,106,85,124,162,198,87,103,239,255,93,127,
    170,40,213,252,162,214,73,227,226,214,85,236,236,126,189,88,
    172,47,66,23,170,66,86,2,165,12,90,12,166,15,81,7,
    42,224,85,192,234,64,213,64,106,48,213,56,104,242,149,224},
  yellowTree = {170,0,65,20,168,106,85,124,130,254,87,127,239,255,93,127,
    170,40,213,252,162,254,85,255,250,254,85,252,236,126,189,88,
    172,47,66,23,170,66,86,2,165,12,90,12,166,15,81,7,
    42,224,85,192,234,64,213,64,106,48,213,56,104,242,149,224},
}

local ID = {}; ID.__index = ID
function ID:getDimensions() return self.w, self.h end
function ID:getWidth() return self.w end
function ID:getHeight() return self.h end
function ID:getPixel(x, y) return unpack(self.p[y * self.w + x + 1] or {0,0,0,0}) end
function ID:setPixel(x, y, ...) self.p[y * self.w + x + 1] = {...} end
function ID:mapPixel(fn)
  for y = 0, self.h - 1 do
    for x = 0, self.w - 1 do self:setPixel(x, y, fn(x, y, self:getPixel(x, y))) end
  end
end
function ID:setFilter() end
local function imageData(w, h) return setmetatable({w = w, h = h, p = {}}, ID) end
local paths, draws, allocations, tint = {}, {}, 0, {1,1,1,1}
love.image.newImageData = function(a, b)
  if type(a) == "number" then return imageData(a, b) end
  local source = assert(paths[a], "missing fixture " .. tostring(a))
  local out = imageData(source.w, source.h)
  for y = 0, source.h - 1 do
    for x = 0, source.w - 1 do out:setPixel(x, y, source:getPixel(x, y)) end
  end
  return out
end
love.graphics.newImage = function(a)
  allocations = allocations + 1
  return type(a) == "string" and love.image.newImageData(a) or a
end
love.graphics.setShader = function() end
love.graphics.setColor = function(...) tint = {...} end
love.graphics.draw = function(image, ...)
  draws[#draws + 1] = {image = image, args = {...}, alpha = tint[4]}
end

local function upvalue(fn, wanted)
  for i = 1, 100 do
    local name, value = debug.getupvalue(fn, i)
    if not name then break end
    if name == wanted then return value end
  end
end
local fxDust = assert(upvalue(OW.drawWorld, "fxDust"))
local fxCutTree = assert(upvalue(OW.drawWorld, "fxCutTree"))
for i = 1, 100 do
  local name = debug.getupvalue(fxDust, i)
  if name == "Game" then debug.setupvalue(fxDust, i, Game); break end
end

local definitions = {
  smoke = {path = "assets/generated/fx/b2650_smoke.png", w = 8, h = 8},
  cutTree = {path = "assets/generated/fx/b2650_tree.png", w = 16, h = 16},
}
local function fixtures(version)
  for key, def in pairs(definitions) do
    local raw = key == "cutTree" and bytes[version == "yellow" and "yellowTree" or "redTree"] or bytes[key]
    paths[def.path] = ImageWriter.decode2bpp(raw, def.w, def.h, true)
  end
end
local function state()
  return setmetatable({ map = {id = "VICTORY_ROAD_1F"}, camera = {x = 0, y = 0} }, {__index = OW})
end
Game.data = {field = {overworldFx = definitions}, palettes = {palettes = {}}, maps = {}}

local FLASH = { [0] = 0, [1] = 0, [2] = 0, [3] = 2 }
local function colorOf(r) return r > .83 and 0 or r > .5 and 1 or r > .17 and 2 or 3 end

local function checkPixels(rows, key, colors, label)
  local source = paths[definitions[key].path]
  local wrong, opaqueZero, translucent, visible = 0, 0, 0, 0
  for _, row in ipairs(rows) do
    local q = type(row.args[1]) == "table" and row.args[1]
    for y = q and q.y or 0, (q and q.y or 0) + (q and q.h or source.h) - 1 do
      for x = q and q.x or 0, (q and q.x or 0) + (q and q.w or source.w) - 1 do
        local sr, _, _, sa = source:getPixel(x, y)
        local c = colorOf(sr)
        local p = {row.image:getPixel(x, y)}
        if sa == 0 or c == 0 then
          if p[4] ~= 0 then opaqueZero = opaqueZero + 1 end
        else
          local want = colors[c + 1]
          for i = 1, 3 do
            if math.abs(p[i] - want[i] / 255) > .00001 then wrong = wrong + 1; break end
          end
          if p[4] ~= 1 then translucent = translucent + 1 end
          visible = visible + 1
        end
      end
    end
    T.eq(row.alpha, 1, label .. " drawn opaque, no alpha stand-in")
  end
  T.eq(wrong, 0, label .. " OBP1 %10000000 shade remap")
  T.eq(opaqueZero, 0, label .. " color 0 stays transparent")
  T.eq(translucent, 0, label .. " nonzero colors fully opaque")
  T.check(visible > 0, label .. " nonempty")
end

local function flashOf(colors)
  return { colors[FLASH[0] + 1], colors[FLASH[1] + 1], colors[FLASH[2] + 1], colors[FLASH[3] + 1] }
end

local cases = {
  {name = "boulder", key = "smoke", group = 7, draw = fxDust, count = 4,
    flash = function(s) s:startDustAnim(2, 3, nil, "right"); s.dustAnim.faded = true end,
    lit = function(s) s:startDustAnim(2, 3, nil, "right"); s.dustAnim.faded = false end},
  {name = "cut grass", key = "smoke", group = 6, draw = fxDust, count = 4,
    flash = function(s) s:startDustAnim(2, 3); s.dustAnim.frames = 31 end,
    lit = function(s) s:startDustAnim(2, 3); s.dustAnim.frames = 30 end},
  {name = "cut tree", key = "cutTree", group = 6, draw = fxCutTree, count = 2,
    flash = function(s) s:startCutTreeAnim(2, 3); s.cutAnim.frames = 7 end,
    lit = function(s) s:startCutTreeAnim(2, 3); s.cutAnim.frames = 6 end},
}

local function render(s, case, which)
  s.dustAnim, s.cutAnim = nil, nil
  case[which](s); draws = {}; case.draw(s, s.camera)
  return draws
end
local function rawOf(s, case) return s[case.key == "smoke" and "smokeImg" or "cutTreeImg"] end

local s = state()
local seen = {}
for _, version in ipairs({"red", "blue", "yellow"}) do
  GameVersion.set(version); fixtures(version)
  PaletteFX.setShadeMap(nil); PaletteFX.setDarkWorld(false)
  for _, case in ipairs(cases) do
    for _, mode in ipairs({"og", "gbc", "ogred"}) do
      PaletteFX.setMode(mode)
      local label = version .. " " .. mode .. " " .. case.name
      local rows = render(s, case, "flash")
      T.eq(#rows, case.count, label .. " draw count")
      T.check(rows[1].image ~= rawOf(s, case), label .. " flash frame is not the identity image")
      checkPixels(rows, case.key, flashOf(PaletteFX.GRAYS), label .. " flash")
      local img, before = rows[1].image, allocations
      T.eq(render(s, case, "flash")[1].image, img, label .. " flash bake cached")
      T.eq(allocations, before, label .. " repeated flash draw allocates no image")
      rows = render(s, case, "lit")
      T.eq(rows[1].image, rawOf(s, case), label .. " identity frame is the raw image")
      T.eq(rows[1].alpha, 1, label .. " identity frame opaque")
      seen[version .. mode .. case.name] = img
    end
    PaletteFX.setMode("redpp")
    local label = version .. " redpp " .. case.name
    local obj = PaletteFX.worldPack().spritePalettes[case.group]
    local rows = render(s, case, "flash")
    checkPixels(rows, case.key, flashOf(obj), label .. " flash")
    local img, before = rows[1].image, allocations
    T.eq(render(s, case, "flash")[1].image, img, label .. " flash bake cached")
    T.eq(allocations, before, label .. " repeated flash draw allocates no image")
    rows = render(s, case, "lit")
    checkPixels(rows, case.key, obj, label .. " identity")
    T.check(rows[1].image ~= img, label .. " identity and flash bakes differ")
  end
end
T.check(seen["yellowogredcut tree"] ~= seen["redogredcut tree"], "yellow tree flash does not alias red bake")

PaletteFX.setMode("gbc")
T.finish()
