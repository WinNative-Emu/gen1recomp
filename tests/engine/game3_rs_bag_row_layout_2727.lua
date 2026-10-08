#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local eq = T.eq

local draws, images = {}, {}
_G.love = _G.love or {}
love.graphics = {
  setColor = function() end,
  rectangle = function() end,
  newQuad = function() return {} end,
  draw = function(img) images[#images + 1] = img.path end,
}

local manifest = {
  layout = "rs",
  layers = {bg = {png = "bg.png", variants = {female = "bg_female.png"}}},
  sprites = {male = {anims = {}}, female = {anims = {}}},
  labels = {{male = "l_m", female = "l_f"}, {male = "l_m", female = "l_f"}, {male = "l_m", female = "l_f"},
    {male = "l_m", female = "l_f"}, {male = "l_m", female = "l_f"}},
  indicators = {idle = "indicator_0.png", selected = "indicator_1.png",
    idleFemale = "indicator_0_female.png", selectedFemale = "indicator_1_female.png"},
  hm = "hm.png", number = "number.png", select = "select.png",
}
package.loaded["src.ui.game3.rse.scene_kit"] = {
  manifest = function() return manifest end,
  image = function(path)
    if path and path:find("indicator", 1, true) then
      return {path = path, getDimensions = function() return 8, 8 end}
    end
  end,
  playSe = function() end, resetCaches = function() end,
}
package.loaded["src.ui.game3.frlg_font"] = {
  STDPAL = {{1, 1, 1, 1}, {1, 0, 0, 1}, [8] = {0, 0, 0, 1}},
  COLOR = {NORMAL = {}},
  sync = function() end,
  measure = function(s) return #s * 6 end,
  draw = function(s, x, y, opts) draws[#draws + 1] = {s = s, x = x, y = y, w = opts and opts.maxWidth} end,
}
package.loaded["src.ui.game3.chrome"] = {stdFrame = function() end, dialogueFrame = function() end}
package.loaded["src.ui.game3.rs.menu_cursor"] = {draw = function() end}
package.loaded["src.core.game3.rom_text"] = {plain = function(key) return key end, overrides = {}}
package.loaded["src.core.game3.trig"] = {sin = function() return 0 end}
package.loaded["src.core.game3.bag"] = {}
local HM = {HM01 = 1}
local TM = {TM39 = 39, HM01 = 1}
local BERRY = {LIECHI = 36}
package.loaded["src.core.game3.items_data"] = {
  isHm = function(id) return HM[id] ~= nil end,
  tmNumber = function(id) return TM[id] end,
  berryNumber = function(id) return BERRY[id] end,
  toNumericId = function(id) return id end,
}
package.loaded["src.core.game3.pokemon"] = {
  moveFromTmItem = function(id) return id end,
  moveName = function(id) return ({TM39 = "ROCK TOMB", HM01 = "CUT"})[id] end,
}

local M = require("src.ui.game3.rs.bag_menu")

local function render(pocket, rows, gender, pocketIdx)
  draws, images = {}, {}
  local Bag = {
    open = true, mode = "list", scroll = 0, cursor = 1, pocketIdx = pocketIdx or 1,
    _session = {gender = gender},
    list = function() return rows end,
    currentPocket = function() return pocket end,
  }
  Bag._rsBag = {pos = {}, frame = 0, gridPos = 1, lastMode = "list"}
  M.draw(Bag)
  return draws
end

local function at(list, s, y)
  for _, d in ipairs(list) do if d.s == s and (y == nil or d.y == y) then return d end end
end

T.suite("rs bag row layout")

local tm = render("TM_CASE", {{id = "TM39", name = "TM39", qty = 1, description = ""},
  {id = "HM01", name = "HM01", qty = 1, description = ""}}, 0, 4)
eq(at(tm, "39", 16) and at(tm, "39", 16).x, 120, "TM number x")
eq(at(tm, "ROCK TOMB", 16) and at(tm, "ROCK TOMB", 16).x, 136, "TM name x")
eq(at(tm, "ROCK TOMB", 16) and at(tm, "ROCK TOMB", 16).w, 78, "TM name width")
eq(at(tm, "×", 16) and at(tm, "×", 16).x, 214, "TM multiply sign x")
eq(at(tm, "1", 16) and at(tm, "1", 16).x, 226, "TM count right-aligned to 232")
eq(at(tm, "1", 32) and at(tm, "1", 32).x, 129, "HM number x")
eq(at(tm, "CUT", 32) and at(tm, "CUT", 32).x, 136, "HM name x")
eq(at(tm, "×", 32), nil, "HM row has no quantity")

local berry = render("BERRY_POUCH", {{id = "LIECHI", name = "LIECHI", qty = 10, description = ""}}, 1, 5)
eq(at(berry, "36", 16) and at(berry, "36", 16).x, 120, "berry number x")
eq(at(berry, "LIECHI", 16) and at(berry, "LIECHI", 16).w, 72, "berry name width")
eq(at(berry, "×", 16) and at(berry, "×", 16).x, 208, "berry multiply sign x")
eq(at(berry, "10", 16) and at(berry, "10", 16).x, 220, "berry count right-aligned to 232")

local items = render("ITEMS", {{id = "POTION", name = "POTION", qty = 5, description = ""}}, 0, 1)
eq(at(items, "POTION", 16) and at(items, "POTION", 16).x, 112, "item name x")
eq(at(items, "×", 16) and at(items, "×", 16).x, 214, "item multiply sign x")
eq(at(items, "5", 16) and at(items, "5", 16).x, 226, "item count right-aligned to 232")

render("ITEMS", {}, 1, 2)
local fem = table.concat(images, ",")
eq(fem, "indicator_0_female.png,indicator_1_female.png,indicator_0_female.png,indicator_0_female.png,indicator_0_female.png",
  "female indicator dots use female bake")
render("ITEMS", {}, 0, 2)
eq(table.concat(images, ","), "indicator_0.png,indicator_1.png,indicator_0.png,indicator_0.png,indicator_0.png",
  "male indicator dots use male bake")

T.finish("rs bag row layout")
