#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local eq = T.eq

local gfx = setmetatable({}, { __index = function() return function() end end })
_G.love = _G.love or { graphics = gfx }

local ui = {}
package.loaded["src.core.game3.profile"] = {
  forSession = function() return { ui = ui, family = "rse" } end,
  family = function() return "rse" end,
}
local keys = {}
package.loaded["src.core.game3.rom_text"] = {
  plain = function(key, ctx)
    keys[#keys + 1] = key
    return ctx.stringVars[1] .. " COINS"
  end,
}

local Window = require("src.ui.game3.window")
local FrlgFont = require("src.ui.game3.frlg_font")
local CoinsBox = require("src.ui.game3.coins_box")

local tpl, printed
Window.stdFrame = function(t) tpl = t end
Window.printPx = function(text, x, y) printed = { text = text, x = x, y = y } end
FrlgFont.measure = function(s) return #tostring(s) * 6 end

local RsUi = require("src.core.game3.profiles.rs.ui")
ui = RsUi
CoinsBox.show(0, 0, 50)
CoinsBox.draw()
eq(tpl and tpl.left, 1, "RS showcoinsbox 0,0 frame corner is tile 0 (interior at 1)")
eq(tpl and tpl.top, 1, "RS showcoinsbox 0,0 frame top is tile 0 (interior at 1)")
eq(tpl and tpl.width, 8, "RS coins interior is 8 tiles wide (frame x..x+9)")
eq(tpl and tpl.height, 2, "RS coins interior is 2 tiles tall (frame y..y+3)")
eq(keys[#keys], "gOtherText_Coins2", "RS coins text is gOtherText_Coins2")
eq(printed and printed.x, 8 + 7 + 2 * 6, "RS coins digits padded to four columns")
eq(printed and printed.y, 8, "RS coins text on the interior's first row")

ui = {}
CoinsBox.show(1, 1, 50)
CoinsBox.draw()
eq(tpl and tpl.left, 1, "Emerald showcoinsbox 1,1 interior stays at the script origin")
eq(tpl and tpl.top, 1, "Emerald showcoinsbox 1,1 interior top stays at the script origin")
eq(keys[#keys], "gText_Coins", "Emerald coins text is gText_Coins")

T.finish("game3 RS coins box")
