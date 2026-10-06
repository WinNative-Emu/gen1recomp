-- A Menu without a title (the main menu's CONTINUE / NEW GAME / OPTION, the
-- START menu) draws its choices in black.  The color used to be set only in
-- the title branch, so the choices took the white left by the box and the
-- previous frame: invisible as tiles never showed it, but a translation's
-- TTF font draws in the current color and printed every choice white on white.
--
--   luajit tests/engine/menu_labels_black_without_title.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Font = require("src.render.Font")
local Menu = require("src.ui.Menu")

local drawn = {}
local stockDraw = Font.draw
Font.draw = function(text, x, y)
  local r, g, b, a = love.graphics.getColor()
  drawn[#drawn + 1] = { text = text, color = ("%s,%s,%s,%s"):format(r, g, b, a) }
  return 0
end

local function colorsOf(menu)
  drawn = {}
  love.graphics.setColor(1, 1, 1, 1)
  menu:draw()
  local out = {}
  for _, d in ipairs(drawn) do out[d.text] = d.color end
  return out
end

local items = { { label = "CONTINUE" }, { label = "NEW GAME" }, { label = "OPTION" } }
local plain = colorsOf(Menu.new({}, items, { tx = 0, ty = 0 }))
for _, it in ipairs(items) do
  T.eq(plain[it.label], "0,0,0,1", it.label .. " is drawn black in a menu without a title")
end

local titled = colorsOf(Menu.new({}, { { label = "RED" } }, { tx = 0, ty = 0, title = "NAME" }))
T.eq(titled.NAME, "0,0,0,1", "a title is drawn black")
T.eq(titled.RED, "0,0,0,1", "and so are the choices under it")

local r, g, b, a = love.graphics.getColor()
T.eq(("%s,%s,%s,%s"):format(r, g, b, a), "1,1,1,1", "the menu still hands white back to the next draw")

Font.draw = stockDraw
T.finish("menu_labels_black_without_title")
