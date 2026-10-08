#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local eq, check = T.eq, T.check

local drawn = {}
package.loaded["src.ui.game3.chrome"] = {
  _frameType = 0,
  userFrame = function(_, x, y, w, h) drawn[#drawn + 1] = { x, y, w, h } end,
}

local BattleChrome = require("src.ui.game3.battle_chrome")

eq(BattleChrome.isRse, nil, "BattleChrome.isRse is gone")

BattleChrome._manifest = { layout = "rse", assetLayout = "rs" }
eq(BattleChrome.layout(), "rs", "RS battle manifest resolves to the rs layout")
eq(BattleChrome.isHoenn(), true, "RS is Hoenn")
local rects = BattleChrome.menuFrameRects("menu", BattleChrome.layout())
eq(rects and rects[1][1], 18, "RS action menu frame starts at tile 18")
drawn = {}
BattleChrome.drawMenuFrames("moves")
eq(#drawn == 2 and drawn[1][3] == 20 and drawn[2][1] == 23, true,
  "drawMenuFrames reads the RS layout without a caller hint")

BattleChrome._manifest = { layout = "rse" }
eq(BattleChrome.layout(), "emerald", "Emerald battle manifest resolves to the emerald layout")
eq(BattleChrome.isHoenn(), true, "Emerald is Hoenn")
drawn = {}
BattleChrome.drawMenuFrames("menu")
eq(#drawn == 1 and drawn[1][1] == 16 and drawn[1][3] == 13, true, "Emerald action menu frame unchanged")

BattleChrome._manifest = {}
eq(BattleChrome.layout(), "frlg", "manifest without a layout is frlg")
eq(BattleChrome.isHoenn(), false, "FRLG is not Hoenn")
drawn = {}
BattleChrome.drawMenuFrames("menu")
eq(#drawn, 0, "FRLG draws no battle menu frames")
BattleChrome._manifest = nil
eq(BattleChrome.layout(), "frlg", "no manifest is frlg")

local RsUi = require("src.core.game3.profiles.rs.ui")
eq(RsUi.saveMenu, "rs", "RS save menu layout is rs")
eq(type(RsUi.coinsWindow) == "table" and RsUi.coinsWindow.frameOrigin, true,
  "RS coins window draws its frame at the script origin")

local seen = {}
local function walk(t, path)
  if seen[t] then return end
  seen[t] = true
  for k, v in pairs(t) do
    local p = path .. "." .. tostring(k)
    if v == "rse" then check(false, "RS ui profile value " .. p .. " is the Emerald layout") end
    if type(v) == "table" then walk(v, p) end
  end
end
walk(RsUi, "ui")
check(true, "RS ui profile walked for rse layout values")

T.finish("game3 RS layout keys")
