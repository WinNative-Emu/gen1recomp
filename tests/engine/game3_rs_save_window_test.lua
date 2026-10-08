#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local eq = T.eq

local gfx = setmetatable({}, { __index = function() return function() end end })
_G.love = _G.love or { graphics = gfx }

local layout = "rs"
package.loaded["src.core.game3.profile"] = {
  forSession = function() return { ui = { saveMenu = layout } } end,
  family = function() return "rse" end,
}
package.loaded["src.core.game3.rom_text"] = {
  plain = function(key) return key end,
}

local Window = require("src.ui.game3.window")
local Chrome = require("src.ui.game3.chrome")
local FrlgFont = require("src.ui.game3.frlg_font")
local SaveMenu = require("src.ui.game3.save_menu")

local frames, texts = {}, {}
local arrow, bar
Window.stdFrame = function(tpl) frames[#frames + 1] = tpl end
Chrome.dialogueFrame = function() end
Chrome.dialogueWindow = function() return 2, 15, 26 end
Window.cursorPx = function(x, y) arrow = { x, y } end
package.loaded["src.ui.game3.rs.menu_cursor"] = { draw = function(x, y, w) bar = { x, y, w } end }
package.loaded["src.core.game3.rse.init"] = { system = function() return nil end }
FrlgFont.measure = function(s) return #tostring(s) * 6 end
FrlgFont.wrap = function(s) return s end
FrlgFont.linePitch = function() return 16 end
FrlgFont.draw = function(s, x, y, opts) texts[#texts + 1] = { s = tostring(s), x = x, y = y, colors = opts and opts.colors } end

local hasDex = true
SaveMenu.hasDex = function() return hasDex end
SaveMenu.locationName = function() return "LITTLEROOT TOWN" end
SaveMenu.countBadges = function() return 3 end
SaveMenu.countDex = function() return 42 end

local phase = "saved"
local function render()
  frames, texts, arrow, bar = {}, {}, nil, nil
  SaveMenu.open = true
  SaveMenu._phase = phase
  SaveMenu._session = { name = "MAY", gender = 1, playtime = { hours = 5, minutes = 7 } }
  SaveMenu._layout = SaveMenu.layout(SaveMenu._session)
  SaveMenu._rse = SaveMenu.isHoenn(SaveMenu._session)
  SaveMenu.draw()
  local stats = frames[1]
  return stats, texts
end

local function find(s)
  for _, t in ipairs(texts) do if t.s == s then return t end end
end

layout = "rs"
local stats = render()
eq(stats and stats.left, 1, "RS stats window interior starts at tile 1")
eq(stats and stats.width, 12, "RS stats window is 12 tiles wide (frame tiles 0..13)")
eq(stats and stats.height, 10, "RS stats window with the dex is 10 tiles tall (frame tiles 0..11)")
local header = find("LITTLEROOT TOWN")
eq(header and header.x, 8, "RS map name at tile 1")
eq(header and header.colors, FrlgFont.COLOR.NORMAL, "RS map name in the default menu color")
local name = find("MAY")
eq(name and name.x + 18, 104, "RS player name right-aligned to tile 13")
eq(name and name.colors, FrlgFont.COLOR.NORMAL, "RS values are not gender tinted")
local time = find("5:07")
eq(time and time.y, 8 + 64, "RS play time row is the fifth two-tile row")
hasDex = false
stats = render()
eq(stats and stats.height, 8, "RS stats window without the dex is 8 tiles tall")
hasDex = true

-- pokeruby/src/start_menu.c:699, pokeruby/src/menu.c:609, :721, :750
phase = "confirm"
SaveMenu.cursor = 2
render()
eq(arrow, nil, "RS save Yes/No draws no FRLG arrow glyph")
eq(bar and table.concat(bar, ","), "168,88,40", "RS save Yes/No highlight bar at (168, 72 + 16 * pos) width 40")
local yes = find("gText_Yes")
eq(yes and yes.x .. "," .. yes.y, "168,72", "RS YES label at tile (21, 9)")
local no = find("gText_No")
eq(no and no.x .. "," .. no.y, "168,88", "RS NO label at tile (21, 11)")
SaveMenu.cursor = 1
render()
eq(bar and bar[2], 72, "RS highlight bar follows the cursor to YES")
SaveMenu.cursor = 1
phase = "saved"

layout = "rse"
stats = render()
eq(stats and stats.width, 14, "Emerald stats window keeps its 14-tile template")
local em = find("LITTLEROOT TOWN")
eq(em and em.colors ~= FrlgFont.COLOR.NORMAL, true, "Emerald map name keeps its green header")
phase = "confirm"
SaveMenu.cursor = 2
render()
eq(bar, nil, "Emerald save Yes/No draws no RS highlight bar")
eq(arrow and table.concat(arrow, ","), "168,89", "Emerald save Yes/No keeps the arrow glyph on NO")
phase = "saved"

T.finish("game3 RS save stats window")
