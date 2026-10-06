package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local Ppu = require("src.core.game3.gba_ppu")

local function obj(x, y, w, h, affine, mode)
  return { x = x, y = y, w = w, h = h, affineMode = affine or 0, objMode = mode or 0 }
end
local function covers(ranges, e, y)
  for _, r in ipairs(ranges[e]) do if y >= r[1] and y < r[2] then return true end end
  return false
end

local list = {}
for i = 1, 6 do list[i] = obj(0, 40, 64, 32, 3) end
local r = Ppu.objScanlineRanges(list, 0)
T.check(covers(r, list[5], 40), "last sprite draws before 1210 cycles expire")
T.check(not covers(r, list[6], 40), "next overlapping sprite is suppressed")
r = Ppu.objScanlineRanges(list, Ppu.DISPCNT_HBLANK_FREE)
T.check(covers(r, list[4], 40), "954-cycle budget draws the fourth box")
T.check(not covers(r, list[5], 40), "HBlank-free suppresses the fifth box")

list = {}
for i = 1, 5 do list[i] = obj(0, 40, 64, 8, 3, 2) end
local last = obj(0, 32, 64, 32, 3)
list[6] = last
r = Ppu.objScanlineRanges(list, 0)
T.check(covers(r, last, 39), "sprite draws before overlapping OBJ-window rows")
T.check(not covers(r, last, 40), "OBJ-window sprites exhaust the shared row")
T.check(not covers(r, last, 55), "double-size height extends budget consumption")
T.check(covers(r, last, 56), "sprite resumes below overlapping OBJ-window rows")
T.eq(#r[last], 2, "visible bands remain separate around the cutoff")

list = {}
for i = 1, 5 do list[i] = obj(240, 255, 64, 32, 3) end
for i = 6, 10 do list[i] = obj(0, 0, 64, 32, 2) end
last = obj(0, 255, 64, 32, 3); list[11] = last
r = Ppu.objScanlineRanges(list, 0)
T.check(covers(r, last, 0), "wrapped sprite survives offscreen and disabled OAM")
T.check(covers(r, last, 62), "wrapped double-size box ends at row 63")
T.check(not covers(r, last, 63), "wrapped box does not reach row 63")
for i = 1, 5 do list[i].x = 384 end
r = Ppu.objScanlineRanges(list, 0)
T.check(not covers(r, last, 0), "box ending exactly at x=0 consumes cycles")
for i = 1, 5 do list[i].x = 383 end
r = Ppu.objScanlineRanges(list, 0)
T.check(covers(r, last, 0), "fully offscreen negative-x box is skipped")

list = {}
for i = 1, 20 do list[i] = obj(0, 0, 64, 8) end
r = Ppu.objScanlineRanges(list, 0)
T.check(covers(r, list[19], 0), "normal OBJ 19 draws at the 1210-cycle boundary")
T.check(not covers(r, list[20], 0), "normal OBJ 20 exceeds the row budget")

T.finish("game3_gba_obj_budget_test")
