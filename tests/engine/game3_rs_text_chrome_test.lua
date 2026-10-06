package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.harness")
local Chrome = require("src.import.gba.rs.text_chrome_extract")
local data = {}
local function bytes(off, values) for i, v in ipairs(values) do data[off + i - 1] = v end end
local rom = { get = function(_, off) return data[off] or 0 end }
local V = {
  RS_FONT_TYPE1_MAP = { off = 0, count = 2 },
  RS_FONT_TYPE3_MAP = { off = 8, count = 2 },
  RS_FONT_WIDTHS = { [0] = { off = 20, count = 2 }, [1] = { off = 30, count = 4 },
    [3] = { off = 40, count = 2 }, [4] = { off = 50, count = 4 } },
}
bytes(0, { 3, 1, 0, 2 })
bytes(8, { 1, 3, 2, 0 })
bytes(20, { 5, 7 })
bytes(30, { 4, 5, 6, 7 })
bytes(40, { 6, 8 })
bytes(50, { 3, 4, 5, 6 })
local function spec(kind, id, language, stride, size, lower)
  return { type = kind, id = id, language = language or "latin", glyphs = 100,
    glyphSize = stride or 8, bytes = size or 4096, lowerTileOffset = lower or 8,
    bpp = (id < 3 or id == 6) and 1 or 4 }
end
local upper, lower = Chrome.glyphPointers(rom, spec(0, 0, nil, 16), 1, V)
T.eq(upper, 116, "font 0 upper tile is sequential")
T.eq(lower, 124, "font 0 lower tile offset is native")
upper, lower = Chrome.glyphPointers(rom, spec(1, 1), 1, V)
T.eq(upper, 100, "font 1 remaps upper tile")
T.eq(lower, 116, "font 1 remaps lower tile")
T.eq(Chrome.glyphPointers(rom, spec(1, 1), 2, V), nil, "font 1 stops at native map count")
upper, lower = Chrome.glyphPointers(rom, spec(2, 2), 1, V)
T.eq(upper, 1796, "font 2 uses blank tile 212")
T.eq(lower, 108, "font 2 lower tile uses raw glyph index")
upper, lower = Chrome.glyphPointers(rom, spec(3, 6), 1, V)
T.eq(upper, 116, "braille uses type 3 upper map")
T.eq(lower, 100, "braille uses type 3 lower map")
upper, lower = Chrome.glyphPointers(rom, spec(4, 3, "japanese", 64, 4096, 512), 17, V)
T.eq(upper, 1156, "Japanese font 3 interleaves 16 upper tiles")
T.eq(lower, 1668, "Japanese font 3 lower plane is 512 bytes later")
T.eq(Chrome.glyphPointers(rom, spec(0, 3, nil, 64, 64, 32), 1, V), nil, "glyph cannot spill into the next ROM asset")
T.eq(Chrome.glyphWidth(rom, spec(0, 0), 1, V), 7, "font 0 native width")
T.eq(Chrome.glyphWidth(rom, spec(1, 1), 1, V), 6, "font 1 width follows lower remap")
T.eq(Chrome.glyphWidth(rom, spec(2, 2), 1, V), 6, "font 2 width still follows type 1 map")
T.eq(Chrome.glyphWidth(rom, spec(1, 4), 1, V), 5, "font 4 native width follows remap")
T.eq(Chrome.glyphWidth(rom, spec(0, 0, "japanese"), 100, V), 8, "Japanese advances eight pixels")
T.eq(Chrome.glyphWidth(rom, spec(3, 6), 1, V), 8, "braille advances eight pixels")
T.eq(Chrome.glyphWidth(rom, spec(0, 0), 2, V), nil, "Latin width table bounds glyph domain")
bytes(100, { 0x81, 0xE3 })
T.eq(Chrome.pixel(rom, 100, 1, 0, 0), 15, "1bpp bit zero is left foreground")
T.eq(Chrome.pixel(rom, 100, 1, 1, 0), 0, "1bpp background")
T.eq(Chrome.pixel(rom, 100, 1, 7, 0), 15, "1bpp bit seven is right foreground")
T.eq(Chrome.pixel(rom, 101, 4, 0, 0), 3, "4bpp keeps fixed palette index")
T.eq(Chrome.pixel(rom, 101, 4, 1, 0), 14, "4bpp shadow is E")
T.finish("game3_rs_text_chrome_test")
