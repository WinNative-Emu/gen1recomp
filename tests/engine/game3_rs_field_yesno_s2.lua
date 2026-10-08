#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local eq = T.eq

local function romTextPlain(key) return key end
package.loaded["src.core.game3.rom_text"] = {
  plain = romTextPlain, box = romTextPlain, ascii = romTextPlain, has = function() return true end,
  key = function(n) return n end, at = function(n) return n end,
  count = function() return 0 end, list = function() return {} end,
  lazy = function(map) return setmetatable({}, { __index = function(_, k) return map[k] end }) end,
}

local log
local saveMenu = "frlg"
package.loaded["src.ui.game3.window"] = {
  OPTION_HEIGHT = 15, CURSOR_WIDTH = 8,
  template = function(l, t, w, h) return { left = l, top = t, width = w, height = h, h = h } end,
  stdFrame = function(tpl) log.std = { tpl.left, tpl.top, tpl.width, tpl.height } end,
  userFrame = function() end,
  cursorPx = function(x, y) log.arrow = { x, y } end,
  printPx = function(s, x, y) log.text[#log.text + 1] = { s, x, y } end,
  menuRowPx = function(top, i) return top + (i - 1) * 15 end,
}
package.loaded["src.ui.game3.rs.menu_cursor"] = {
  draw = function(x, y, w) log.rsCursor = { x, y, w } end,
}
package.loaded["src.core.game3.runtime"] = { getSession = function() return { version = "sapphire" } end, isActive = function() return true end }
package.loaded["src.core.game3.profile"] = {
  forSession = function() return { ui = { saveMenu = saveMenu } } end,
  family = function() return "rse" end,
}

local Choice = require("src.ui.game3.choice")

local function run(layout, cursor, left, top)
  saveMenu = layout
  log = { text = {} }
  Choice.yesNo(function() end, left and { left = left, top = top } or nil)
  Choice.cursor = cursor or 1
  Choice.draw()
  return log
end

local function rect(r) return table.concat(r or {}, ",") end

local fr = run("frlg", 2, 20, 8)
eq(rect(fr.std), "21,9,6,4", "frlg yesnobox 20,8 ignores left/top (ScriptMenu_YesNo fixed template)")
eq(rect(fr.arrow), "168,88", "frlg yesnobox arrow glyph on row 2 at tile 21")
eq(fr.rsCursor, nil, "frlg yesnobox draws no RS bar")

local frd = run("frlg")
eq(rect(frd.std), "21,9,6,4", "frlg default Yes/No interior at (21,9)")

local em = run("rse", 2, 20, 8)
eq(rect(em.std), "21,9,5,4", "emerald yesnobox 20,8 uses sYesNo_WindowTemplates 21,9 5x4")
eq(rect(em.arrow), "168,88", "emerald yesnobox arrow glyph at tile 21")

local emd = run("rse", 1, 3, 2)
eq(rect(emd.std), "21,9,5,4", "emerald yesnobox 3,2 still at 21,9")

local function multi(layout, cursor, opts, cols, left, top)
  saveMenu = layout
  log = { text = {} }
  package.loaded["src.ui.game3.frlg_font"] = { measure = function(s) return #s * 6 end }
  Choice.multi(opts, cursor - 1, function() end, { left = left, top = top, cols = cols, maxRight = 29 })
  Choice.draw()
  package.loaded["src.ui.game3.frlg_font"] = nil
  return log
end

local fm = multi("frlg", 1, { "50 COINS", "CANCEL" }, 1, 16, 1)
eq(fm.rsCursor, nil, "frlg multichoice draws no RS bar")
eq(fm.arrow ~= nil, true, "frlg multichoice keeps the arrow glyph")

local rm = multi("rs", 2, { "50 COINS", "500 COINS", "CANCEL" }, 1, 16, 1)
eq(rect(rm.std), "16,1,7,6", "rs multichoice 15,0: interior at 16,1, width = widest label in tiles, height 2*count")
eq(rm.arrow, nil, "rs multichoice draws no FRLG arrow glyph")
eq(rect(rm.rsCursor), "128,24,56", "rs multichoice highlight bar at ((left+1)*8, (top+1+2*pos)*8) width 8*tiles")
eq(rm.text[1] and rect(rm.text[1]), "50 COINS,128,8", "rs multichoice item 0 at tile left+1, top+1")
eq(rm.text[3] and rect(rm.text[3]), "CANCEL,128,40", "rs multichoice item 2 at top+5")

local rc = multi("rs", 1, { "LILYCOVE", "BATTLE TOWER", "CANCEL" }, 1, 20, 5)
eq(rect(rc.std), "20,5,9,6", "rs multichoice right <= 29 keeps its left")
local rk = multi("rs", 1, { "ABCDEFGHIJKLMNOPQRSTUVWX" }, 1, 20, 5)
eq(rect(rk.std), "11,5,18,2", "rs multichoice right > 29 shifts left (left += 29 - right)")
eq(rect(rk.rsCursor), "88,40,144", "rs multichoice shifted bar follows the frame")

local rg = multi("rs", 5, { "PSN", "PAR", "SLP", "BRN", "FRZ", "CANCEL" }, 3, 9, 2)
eq(rect(rg.std), "9,2,17,4", "rs multichoicegrid 8,1 x3: columns widest+1 apart, rows = count/cols")
eq(rg.arrow, nil, "rs multichoicegrid draws no FRLG arrow glyph")
eq(rect(rg.rsCursor), "120,32,40", "rs multichoicegrid bar at column 1 row 1, width = widest label")
eq(rg.text[5] and rect(rg.text[5]), "FRZ,120,32", "rs multichoicegrid item 4 at column 1 row 1")

local rs = run("rs", 2, 20, 8)
eq(rect(rs.std), "21,9,5,4", "rs yesnobox 20,8 frames tiles 20..26 x 8..13 (interior 21,9 5x4)")
eq(rs.arrow, nil, "rs yesnobox draws no FRLG arrow glyph")
eq(rect(rs.rsCursor), "168,88,40", "rs yesnobox highlight bar at (168, 72+16*pos) width 40")
eq(rs.text[1] and rect(rs.text[1]), "gText_Yes,168,72", "rs YES at tile 21 row 9")
eq(rs.text[2] and rect(rs.text[2]), "gText_No,168,88", "rs NO at tile 21 row 11")

local rsd = run("rs", 1)
eq(rect(rsd.std), "21,9,5,4", "rs default Yes/No is DisplayYesNoMenu(20, 8)")
eq(rect(rsd.rsCursor), "168,72,40", "rs default bar on YES")

package.loaded["src.ui.game3.choice"] = nil

local loveStub = require("tests.love_stub")
_G.love = _G.love or loveStub
local StartMenu = require("src.ui.game3.start_menu")
local FrlgFont = require("src.ui.game3.frlg_font")
local Chrome = require("src.ui.game3.chrome")
local RsData = require("src.ui.game3.rs.start_menu_data")
local RseData = require("src.ui.game3.rse.start_menu_data")
local ListMenu = require("src.ui.game3.list_menu")
FrlgFont.draw = function(s, x, y) log.text[#log.text + 1] = { s, x, y } end
Chrome.dialogueFrame = function() end
ListMenu.drawScrollArrows = function() end

local function confirm(dataMod, cursor)
  log = { text = {} }
  StartMenu.ENTRIES = { { id = "exit", label = "EXIT" } }
  StartMenu._data = dataMod
  StartMenu._ctx = nil
  StartMenu.open = true
  StartMenu.cursor = 1
  StartMenu._scrollOffset = 0
  StartMenu._confirmExit = true
  StartMenu._confirmCursor = cursor
  StartMenu.draw()
  return log
end

local function lastText(l, s)
  for _, t in ipairs(l.text) do if t[1] == s then return rect(t) end end
end

local em = confirm(RseData, 2)
eq(rect(em.std), "21,9,6,4", "emerald exit confirm keeps the FRLG template")
eq(rect(em.arrow), "169,90", "emerald exit confirm arrow on NO")
eq(em.rsCursor, nil, "emerald exit confirm draws no RS bar")

local rx = confirm(RsData, 2)
eq(rect(rx.std), "21,9,5,4", "rs exit confirm frames tiles 20..26 x 8..13")
eq(rx.arrow, nil, "rs exit confirm draws no FRLG arrow glyph")
eq(rect(rx.rsCursor), "168,88,40", "rs exit confirm highlight bar at (168, 88) width 40 on NO")
eq(lastText(rx, "gText_Yes"), "gText_Yes,168,72", "rs exit confirm YES at (168, 72)")
eq(lastText(rx, "gText_No"), "gText_No,168,88", "rs exit confirm NO at (168, 88)")
local ry = confirm(RsData, 1)
eq(rect(ry.rsCursor), "168,72,40", "rs exit confirm bar on YES")

T.finish("game3 rs field yes/no boxes use the RS highlight bar")
