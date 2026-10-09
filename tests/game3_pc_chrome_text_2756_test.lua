#!/usr/bin/env luajit
package.path = "./?.lua;./?/init.lua;" .. package.path

local failed = 0
local function check(cond, msg)
  if cond then print("[ok] " .. msg) else failed = failed + 1; print("[FAIL] " .. msg) end
end

local game = "firered"
local texts, pics, romKeys, marks = {}, {}, {}, {}

local MARKINGS_IMG = {markings = true, getDimensions = function() return 32, 128 end}

_G.love = {
  graphics = {
    setColor = function() end,
    getShader = function() return nil end,
    setShader = function() end,
    rectangle = function() end,
    newQuad = function(x, y, w, h) return {qx = x, qy = y, qw = w, qh = h} end,
    draw = function(img, x, y, r, sx, sy)
      if img == MARKINGS_IMG then marks[#marks + 1] = {quad = x, x = y, y = r} return end
      if img and img.pic then pics[#pics + 1] = {x = x, y = y, sx = sx or 1, sy = sy or 1} end
    end,
  },
}

local COLOR = {WHITE = {}, MALE = {}, FEMALE = {}}
package.loaded["src.ui.game3.frlg_font"] = {
  COLOR = COLOR,
  truncate = function(s) return s end,
  measure = function(s) return #s * 6 end,
  draw = function(s, x, y, opts)
    texts[#texts + 1] = {text = s, x = x, y = y, font = opts and opts.font, small = opts and opts.small,
      colors = opts and opts.colors}
  end,
  drawGlyph = function() end,
}
local monGender = "M"
package.loaded["src.core.game3.pokemon"] = {
  isEgg = function() return false end,
  speciesOrEgg = function() return 348 end,
  speciesOf = function() return 348 end,
  name = function() return "ARMALDO" end,
  gender = function() return monGender end,
  monFrontPic = function()
    return {image = {pic = true, getDimensions = function() return 64, 64 end}}
  end,
}
package.loaded["src.core.game3.constants"] = {
  of = function() return {require = function(_, _, name) return name == "SPECIES_NIDORAN_M" and 32 or 29 end} end,
}
local RS_TEXT = {fg = {}, shadow = {}}
package.loaded["src.ui.game3.rs.storage_visuals"] = {textColors = function() return RS_TEXT end}
package.loaded["src.core.game3.items_data"] = {displayName = function() return "SCOPE LENS" end}
package.loaded["src.core.game3.rom_text"] = {
  plain = function(key) romKeys[#romKeys + 1] = key; return "BOX" end,
}
package.loaded["src.ui.game3.storage_presentation"] = {}
package.loaded["src.import.CacheBlob"] = {}
package.loaded["src.core.GameVersion"] = {get = function() return game end}

local PcChrome = require("src.ui.game3.pc_chrome")

local PAL = {}
for i = 0, 15 do PAL[i] = {i * 10, i * 10 + 1, i * 10 + 2} end
local MANIFEST = {palettes = {scrollingBg = PAL}}

local function render(g, mon)
  game = g
  PcChrome._initialized, PcChrome._game = true, g
  PcChrome._manifest, PcChrome._markingsImg = MANIFEST, MARKINGS_IMG
  texts, pics, marks = {}, {}, {}
  PcChrome.drawLeftDataPanel(mon or {nickname = "ARMALDO", level = 100, gender = "M", heldItem = 15}, 0, 0)
end

local function palIs(color, idx)
  local c = PAL[idx]
  return type(color) == "table" and color[1] == c[1] / 255 and color[2] == c[2] / 255 and color[3] == c[3] / 255
end

local function find(pred)
  for _, t in ipairs(texts) do if pred(t) then return t end end
end

for _, g in ipairs({"firered", "emerald"}) do
  render(g)
  local pic = pics[1]
  -- pokeemerald/src/pokemon_storage_system.c:3954
  check(pic and pic.x == 8 and pic.y == 16 and pic.sx == 1 and pic.sy == 1,
    g .. ": display mon pic is 64x64 at (8,16), scale 1")
  local mark = find(function(t) return t.text == "♂" end)
  check(mark and mark.x == 10, g .. ": gender glyph starts at x=10")
  local lv = find(function(t) return t.text:find("{LV_2}", 1, true) end)
  check(lv and lv.x == 10 + 6 * #"♂ ", g .. ": level follows gender glyph and a space")
  local nick = find(function(t) return t.text == "ARMALDO" end)
  check(nick and nick.colors and palIs(nick.colors.fg, 2) and palIs(nick.colors.shadow, 3),
    g .. ": PKMN DATA text is sScrollingBg_Pal fg idx2 shadow idx3")
  check(lv and lv.colors and palIs(lv.colors.fg, 2) and palIs(lv.colors.shadow, 3),
    g .. ": level text is sScrollingBg_Pal fg idx2 shadow idx3")
  check(mark and mark.colors and palIs(mark.colors.fg, 4) and palIs(mark.colors.shadow, 5),
    g .. ": male glyph is sScrollingBg_Pal idx4/idx5")
  render(g, {nickname = "ARMALDO", level = 100, gender = "F", markings = 9})
  local fem = find(function(t) return t.text == "♀" end)
  check(fem and fem.colors and palIs(fem.colors.fg, 6) and palIs(fem.colors.shadow, 7),
    g .. ": female glyph is sScrollingBg_Pal idx6/idx7")
  local m = marks[1]
  check(#marks == 1 and m.x == 24 and m.y == 146 and m.quad.qy == 72 and m.quad.qw == 32 and m.quad.qh == 8,
    g .. ": markings combo 9 drawn from the cache sheet as a 32x8 sprite centered (40,150)")
  render(g, {nickname = "ARMALDO", level = 100, gender = "M"})
  check(#marks == 1 and marks[1].quad.qy == 0, g .. ": unmarked mon shows combo 0 (all off)")
  PcChrome._manifest = {}
  local ok = pcall(PcChrome.drawLeftDataPanel, {nickname = "ARMALDO", level = 5, gender = "M"}, 0, 0)
  check(not ok, g .. ": missing storage text palette is an error, not a fallback")
  PcChrome._manifest, PcChrome._markingsImg = MANIFEST, nil
  ok = pcall(PcChrome.drawLeftDataPanel, {nickname = "ARMALDO", level = 5, gender = "M"}, 0, 0)
  check(not ok, g .. ": missing markings sheet is an error, not a fallback")
end

render("ruby", {nickname = "ARMALDO", level = 100, markings = 15})
check(#marks == 1 and marks[1].x == 24 and marks[1].y == 145 and marks[1].quad.qy == 120,
  "ruby: markings combo 15 drawn centered (40,149)")

render("firered")
local sp = find(function(t) return t.text == "/ARMALDO" end)
check(sp and sp.y == 102 and sp.font == nil, "firered: species line FONT_NORMAL y=102")
local mark = find(function(t) return t.text == "♂" end)
check(mark and mark.y == 116 and mark.font == nil, "firered: gender line FONT_NORMAL y=116")
local item = find(function(t) return t.text == "SCOPE LENS" end)
check(item and item.y == 132 and item.small, "firered: item line FONT_SMALL y=132")

render("emerald")
sp = find(function(t) return t.text == "/ARMALDO" end)
check(sp and sp.y == 103 and sp.font == "short", "emerald: species line FONT_SHORT y=103")
mark = find(function(t) return t.text == "♂" end)
check(mark and mark.y == 117 and mark.font == "short", "emerald: gender line FONT_SHORT y=117")
item = find(function(t) return t.text == "SCOPE LENS" end)
check(item and item.y == 131 and item.small, "emerald: item line FONT_SMALL y=131")

texts = {}
PcChrome.drawBoxHeader(nil, 1, false, {noArrows = true})
local title = find(function() return true end)
check(title and title.text == "BOX1", "emerald: default box name is gText_Box .. 1 (" .. tostring(title and title.text) .. ")")
check(romKeys[#romKeys] == "gText_Box", "emerald: default box name reads gText_Box")

game, PcChrome._game = "ruby", "ruby"
texts = {}
PcChrome.drawBoxHeader("BOX 3", 3, false, {noArrows = true})
title = find(function() return true end)
check(title and title.text == "BOX3" and romKeys[#romKeys] == "gPCText_BOX", "ruby: default box name reads gPCText_BOX")

texts = {}
PcChrome.drawBoxHeader("PIKA", 3, false, {noArrows = true})
title = find(function() return true end)
check(title and title.text == "PIKA", "typed box names are left alone")

local function finish()
  if failed > 0 then
    print(failed .. " failure(s)")
    os.exit(1)
  end
  print("all passed")
  os.exit(0)
end

for _, name in ipairs({"src.import.CacheBlob", "src.core.GameVersion", "src.core.game3.rom_text",
    "src.core.game3.constants", "src.core.game3.pokemon", "src.core.game3.items_data"}) do
  package.loaded[name] = nil
end
local root = require("tests.game3_cache").root()
if not root then
  print("[skip] storage manifest checks need a current FRLG cache")
  finish()
end
local CacheBlob = require("src.import.CacheBlob")
local function readCache(rel)
  local f = io.open(root .. "/" .. rel, "rb")
  if not f then return nil end
  local data = CacheBlob.decode(root .. "/" .. rel, f:read("*a"))
  f:close()
  return data
end
local src = readCache("pokemon/storage/manifest.lua")
local manifest = src and load(src, "@manifest", "t", {})()
local P = manifest and manifest.palettes and manifest.palettes.scrollingBg
local function rgbIs(c, r, g, b) return c and c[1] == r and c[2] == g and c[3] == b end
check(P and rgbIs(P[1], 148, 148, 173) and rgbIs(P[2], 255, 255, 255) and rgbIs(P[3], 0, 0, 0),
  "cache: sScrollingBg_Pal idx1 panel, idx2 white, idx3 black")
check(P and rgbIs(P[4], 123, 189, 255) and rgbIs(P[5], 0, 123, 255) and rgbIs(P[6], 255, 132, 132)
  and rgbIs(P[7], 173, 25, 25), "cache: sScrollingBg_Pal gender colors idx4..7")
local png = readCache("pokemon/storage/markings.png")
local function be32(s, at) local a, b, c, d = s:byte(at, at + 3); return ((a * 256 + b) * 256 + c) * 256 + d end
check(png and #png > 24 and be32(png, 17) == 32 and be32(png, 21) == 128, "cache: markings.png is the 32x128 combo sheet")
check(require("src.import.gba.storage_chrome_extract").ready(nil, root), "cache: storage chrome is ready at the current format")

if failed > 0 then
  print(failed .. " failure(s)")
  os.exit(1)
end
print("all passed")
