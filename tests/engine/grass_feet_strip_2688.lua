-- data/sprites/facings.asm:51

package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.modkit")
local check, eq = T.check, T.eq

T.fixtures.fresh()

local TileRenderer = require("src.render.TileRenderer")
local PaletteFX = require("src.render.PaletteFX")
local OW = require("src.world.OverworldController")

local function upvalue(fn, name)
  local i = 1
  while true do
    local n, v = debug.getupvalue(fn, i)
    if not n then return nil end
    if n == name then return v end
    i = i + 1
  end
end

check(type(TileRenderer.feetStrip) == "function", "TileRenderer exposes the feet strip")

local x0, y0, x1, y1 = TileRenderer.feetStrip(32, 48, nil)
eq(x0, 32, "strip starts at the sprite's left edge")
eq(y0, 52, "strip starts 4 px into the cell (bottom OAM row, sprite row 8)")
eq(x1, 48, "strip is the sprite's 16 px width")
eq(y1, 60, "strip ends 4 px above the cell bottom (sprite row 15)")

local vanilla = { frameWidth = 16, frameHeight = 16, anchorX = 8, anchorY = 16 }
x0, y0, x1, y1 = TileRenderer.feetStrip(32, 48, vanilla)
eq(y0, 52, "vanilla 16x16 frame gets the same strip")
eq(y1, 60, "vanilla 16x16 frame strip is 8 rows")

local tall = { frameWidth = 16, frameHeight = 32, anchorX = 8, anchorY = 32 }
x0, y0, x1, y1 = TileRenderer.feetStrip(32, 48, tall)
eq(y0, 52, "a 32-tall frame keeps its strip on the frame's bottom 8 rows")
eq(y1, 60, "a 32-tall frame strip is still 8 rows")

local function spans(a, b, c, d)
  local out = {}
  TileRenderer.eachStripSpan(a, b, c, d, function(tx, ty, x, y, ox, oy, w, h)
    out[#out + 1] = { tx = tx, ty = ty, x = x, y = y, ox = ox, oy = oy, w = w, h = h }
  end)
  return out
end

local s = spans(32, 52, 48, 60)
eq(#s, 4, "a standing strip touches 2x2 tiles")
eq(s[1].ty, 6, "first span is the cell's top tile row")
eq(s[1].oy, 4, "top tile row is cut from its row 4")
eq(s[1].h, 4, "top tile row contributes its lower 4 rows")
eq(s[3].ty, 7, "second span is the cell's bottom tile row")
eq(s[3].oy, 0, "bottom tile row starts at its row 0")
eq(s[3].h, 4, "bottom tile row contributes its upper 4 rows")
eq(s[1].w, 8, "standing strip spans whole tile columns")

s = spans(36, 54, 52, 62)
eq(#s, 6, "a mid-step strip straddles three tile columns")
eq(s[1].ox, 4, "left column clips to the sprite's left edge")
eq(s[1].w, 4, "left column keeps only the covered pixels")
eq(s[3].w, 4, "right column clips to the sprite's right edge")
eq(s[1].oy + s[1].h, 8, "top span runs to its tile's bottom")
eq(s[4].h, 6, "bottom span covers the rest of the strip")

local image = { getDimensions = function() return 128, 128 end }
local fakeMap = {
  tileset = { tilesPerRow = 16 },
  tileAt = function() return 0x52 end,
}
local r = setmetatable({ map = fakeMap, image = image, quads = { [0x52] = {} } },
                       TileRenderer)

local drawn = {}
local realDraw = love.graphics.draw
love.graphics.draw = function(_, q, x, y)
  drawn[#drawn + 1] = { q = q, x = x, y = y }
end
r:drawStripRaw(32, 52, 48, 60, 0, 0)
love.graphics.draw = realDraw

local covered = {}
for _, d in ipairs(drawn) do
  for row = d.y, d.y + d.q.h - 1 do covered[row] = true end
end
for row = 48, 51 do
  check(not covered[row], "sprite row " .. (row - 44) .. " stays above the grass")
end
for row = 52, 59 do
  check(covered[row], "sprite row " .. (row - 44) .. " is behind the grass")
end
for row = 60, 63 do
  check(not covered[row], "cell row " .. (row - 48) .. " below the sprite is not redrawn")
end

local marks = {}
local realMark = PaletteFX.markSpriteRedraw
PaletteFX.markSpriteRedraw = function(img, q, x, y)
  marks[#marks + 1] = { q = q, x = x, y = y }
end
r:markStripRedraw(32, 52, 48, 60, 0, 0, {})
PaletteFX.markSpriteRedraw = realMark
local markRows = {}
for _, m in ipairs(marks) do
  for row = m.y, m.y + m.q.h - 1 do markRows[row] = true end
end
check(markRows[52] and markRows[59] and not markRows[60] and not markRows[51],
      "OG RED replay redraws the same strip")

local grassStrip = upvalue(OW.drawWorld, "grassStrip")
check(type(grassStrip) == "function", "drawWorld places grass by the feet strip")
if grassStrip then
  local map = {
    renderer = r,
    isGrassCell = function(_, cx, cy) return cx == 2 and cy == 3 end,
  }
  local ow = { map = map }
  local standing = { cellX = 2, cellY = 3, px = 32, py = 48 }
  local a, b, c, d = grassStrip(ow, standing)
  eq(b, 52, "entity standing in grass gets the strip from row py+4")
  eq(d, 60, "entity standing in grass gets the strip to row py+12")
  local entering = { cellX = 2, cellY = 2, targetX = 2, targetY = 3, px = 32, py = 40,
                     pose = function(self) return vanilla, self.px, self.py end }
  a, b, c, d = grassStrip(ow, entering)
  eq(b, 44, "stepping into grass follows the sprite mid-step")
  check(grassStrip(ow, { cellX = 1, cellY = 1, px = 16, py = 16 }) == nil,
        "entity outside grass gets no strip")
end

T.finish("grass feet strip")
