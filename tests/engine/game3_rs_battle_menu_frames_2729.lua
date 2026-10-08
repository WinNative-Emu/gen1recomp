#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path
require("tests.fixture_data.game3_map_sections").install()

local T = require("tests.harness")
local eq = T.eq
require("tests.game3_cache").stubSpeciesNames()

require("src.core.GameVersion").set("firered")
package.loaded["src.core.game3.audio"] = {
  playSe = function() end, playCry = function() end,
  playSong = function() end, stopAll = function() end,
}
package.loaded["src.core.game3.rom_text"] = {
  plain = function(key) return key end, box = function(key) return key end,
  ascii = function(key) return key end, has = function() return true end,
  key = function(n, i, j) return j and (n .. "[" .. i .. "][" .. j .. "]") or (n .. "[" .. i .. "]") end,
  at = function(n, i, j) return j and (n .. "[" .. i .. "][" .. j .. "]") or (n .. "[" .. i .. "]") end,
  count = function() return 0 end, list = function() return {} end,
  lazy = function(map) return setmetatable({}, { __index = function(_, k) return map[k] end }) end,
}

local drawn = {}
package.loaded["src.ui.game3.chrome"] = {
  _frameType = 0,
  userFrame = function(_, x, y, w, h) drawn[#drawn + 1] = { x, y, w, h } end,
}

local BattleChrome = require("src.ui.game3.battle_chrome")
local Ui = require("src.core.game3.battle.ui")
local RS = { layout = "rse", assetLayout = "rs" }
local EMERALD = { layout = "rse" }

local function frames(mode)
  drawn = {}
  Ui.drawMenuFrames(mode)
  return drawn
end

local function same(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do
    for j = 1, 4 do if a[i][j] ~= b[i][j] then return false end end
  end
  return true
end

BattleChrome._manifest = RS
local mv = frames("moves")
eq(same(mv, { { 1, 15, 20, 4 }, { 23, 15, 6, 4 } }), true, "RS move menu frames follow menu_map.bin")
eq((mv[1] and (mv[1][1] + mv[1][3]) * 8) or -1, 168, "RS left move box content ends at x=168")
eq(same(frames("menu"), { { 18, 15, 11, 4 } }), true, "RS action menu frame follows menu_map.bin")

BattleChrome._manifest = EMERALD
eq(same(frames("moves"), { { 1, 15, 18, 4 }, { 21, 15, 8, 4 } }), true, "Emerald move menu frames unchanged")
eq(same(frames("menu"), { { 16, 15, 13, 4 } }), true, "Emerald action menu frame unchanged")

T.finish("game3 RS battle menu frames #2729")
