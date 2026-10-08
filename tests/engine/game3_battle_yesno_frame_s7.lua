#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local eq = T.eq

package.loaded["src.core.game3.rom_text"] = {
  plain = function(key) if key == "gText_BattleYesNoChoice" then return "Yes\nNo" end return key end,
}

local log
package.loaded["src.ui.game3.window"] = {
  template = function(l, t, w, h) return { left = l, top = t, width = w, height = h } end,
  userFrame = function(tpl) log.frame = { tpl.left - 1, tpl.top - 1, tpl.left + tpl.width, tpl.top + tpl.height } end,
  stdFrame = function() end,
  cursorPx = function(x, y) log.arrow = { x, y } end,
  printPx = function(s, x, y) log.text[#log.text + 1] = { s, x, y } end,
}
package.loaded["src.ui.game3.rs.menu_cursor"] = {
  draw = function(x, y, w) log.rsCursor = { x, y, w } end,
}
local layout = "frlg"
package.loaded["src.ui.game3.battle_chrome"] = { layout = function() return layout end }
package.loaded["src.core.game3.runtime"] = { getSession = function() return { options = { frameType = 0 } } end }

local Choice = require("src.ui.game3.choice")

local function run(l, cursor)
  layout = l
  log = { text = {} }
  Choice.yesNo(function() end, { left = 24, top = 9, style = "battle" })
  Choice.cursor = cursor or 1
  Choice.draw()
  return log
end

local function rect(r) return table.concat(r or {}, ",") end

local fr = run("frlg")
eq(rect(fr.frame), "23,8,29,13", "frlg frame tiles 23..29 x 8..13")
eq(rect(fr.arrow), "192,72", "frlg arrow at tile 24 row 9")
eq(fr.text[1] and fr.text[1][2], 200, "frlg labels at tile 25")
eq(fr.text[1] and fr.text[1][3], 74, "frlg label y +2")
eq(fr.rsCursor, nil, "frlg has no RS cursor")

local em = run("emerald", 2)
eq(rect(em.frame), "24,8,29,13", "emerald frame tiles 24..29 x 8..13")
eq(rect(em.arrow), "200,88", "emerald arrow at tile 25 row 11")
eq(em.text[1] and em.text[1][2], 208, "emerald labels at tile 26")
eq(em.text[1] and em.text[1][3], 73, "emerald label y +1")
eq(em.rsCursor, nil, "emerald has no RS cursor")

local rs = run("rs", 2)
eq(rect(rs.frame), "24,8,29,13", "rs frame tiles 24..29 x 8..13")
eq(rs.arrow, nil, "rs draws no arrow glyph")
eq(rect(rs.rsCursor), "200,88,32", "rs highlight cursor at (200, 72+16*pos) width 32")
eq(rs.text[1] and rs.text[1][2], 200, "rs labels at tile 25")
eq(rs.text[2] and rs.text[2][3], 88, "rs second label at y 88")

T.finish("game3 battle yes/no frame per layout")
