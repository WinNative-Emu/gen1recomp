package.path = "./?.lua;./?/init.lua;" .. package.path
local ROM_TEXT = { ["sStartMenuActionTable[3]"] = "{PLAYER}" }
local function romTextKey(n, i, j) return j and (n .. "[" .. i .. "][" .. j .. "]") or (n .. "[" .. i .. "]") end
local function romTextPlain(key, ctx) return ((ROM_TEXT[key] or key):gsub("{PLAYER}", ctx and ctx.playerName or "")) end
package.loaded["src.core.game3.rom_text"] = {
  plain = romTextPlain, box = romTextPlain, ascii = romTextPlain, has = function() return true end,
  key = romTextKey, at = function(n, i, j, ctx) return romTextPlain(romTextKey(n, i, j), ctx) end,
  count = function() return 0 end, list = function() return {} end,
  lazy = function(map) return setmetatable({}, { __index = function(_, k) return map[k] end }) end,
}

local T = require("tests.harness")
local check = T.check
love = love or require("tests.love_stub")
love.graphics.draw = function() end
love.graphics.setColor = function() end
love.graphics.newQuad = function() return { setViewport = function() end } end

local GameVersion = require("src.core.GameVersion")
GameVersion.set("firered")
local MB = require("src.core.game3.mb")
local Collision = require("src.core.game3.collision")
local FieldEffects = require("src.core.game3.field_effects")
local MB_HOT_SPRINGS = 0x28
local MB_ICE = MB.id("ICE")

local npcs = {}
package.loaded["src.core.game3.objects"] = {
  forDraw = function() return npcs end,
  walkPhase = function() return 0 end,
}
package.loaded["src.core.game3.player"] = { isVisible = function() return false end }
package.loaded["src.core.game3.runtime"] = {}
FieldEffects._anims = {}
FieldEffects._sheets.tall_grass = false
local springImage = {}
FieldEffects._sheets.hot_springs_water = {
  image = springImage, quads = { [0] = {} }, quadsFront = {}, fw = 16, fh = 16, frames = 1,
}
Collision.isGrass = function() return false end

-- pokefirered/src/event_object_movement.c:8196
do
  local springs = { [2 * 100 + 2] = true, [2 * 100 + 3] = true, [3 * 100 + 2] = true }
  Collision.behavior = function(x, y) return springs[x * 100 + y] and MB_HOT_SPRINGS or 1 end
  local soaking = { localId = 1, cellX = 2, cellY = 2, px = 32, py = 32, elevation = 3 }
  local wading = { localId = 2, cellX = 2, cellY = 3, targetX = 2, targetY = 4, moving = true, px = 32, py = 56 }
  local entering = { localId = 3, cellX = 4, cellY = 2, targetX = 3, targetY = 2, moving = true, px = 56, py = 32 }
  local dry = { localId = 4, cellX = 6, cellY = 6, px = 96, py = 96 }
  npcs = { soaking, wading, entering, dry }
  local actors = {}
  FieldEffects.collectActors(actors, 0, 0)
  local by = {}
  for _, a in ipairs(actors) do
    if a.kind == "field_effect_hot_springs" and a.disguiseObject then by[a.disguiseObject] = a end
  end
  local a = by[soaking]
  check(a ~= nil, "NPC standing in the hot spring gets the water sprite")
  check(a and a.x == 32 and a.y == 32, "water sprite sits on the NPC's cell")
  check(by[wading] == nil, "NPC stepping out of the spring loses the water sprite")
  check(by[entering] == nil, "NPC stepping into the spring has no water sprite until both cells are springs")
  check(by[dry] == nil, "NPC on dry ground has no water sprite")
  npcs = {}
end

-- pokefirered/src/field_effect_helpers.c:38
do
  local spr = {
    width = 16, height = 32, frameCount = 1, quads = { [0] = true },
    image = { getDimensions = function() return 16, 32 end },
  }
  package.loaded["src.core.game3.ow_sprites"] = {
    getDraw = function() return spr end,
    getReflectionDraw = function() return spr end,
    pose = function() return 0, false end,
    playerGraphicsId = function() return nil end,
  }
  Collision.behavior = function() return 1 end
  Collision.worldBehavior = function(_, y) return y >= 2 and MB_ICE or 1 end
  local covered = {}
  package.loaded["src.core.game3.field_effects_rse"] = {
    coverCells = function(cells, n)
      for i = 1, n, 2 do covered[#covered + 1] = cells[i] .. "," .. cells[i + 1] end
    end,
  }
  npcs = { { localId = 5, graphicsId = 1, facing = "down", cellX = 1, cellY = 1, px = 16, py = 16 } }
  FieldEffects.drawBehind(0, 0)
  check(FieldEffects.lastFrlgReflections == 1, "object on ice reflects")
  local set = {}
  for _, k in ipairs(covered) do set[k] = true end
  check(set["1,2"] == true, "reflected ice cell is re-covered by the middle BG layer")
  check(set["1,1"] == nil, "cells without a drawn reflection are left alone")
  npcs = {}
end

-- pokefirered/src/overworld.c:1470
do
  local steps = 0
  package.loaded["src.core.game3.tileset_anim"] = { step = function() steps = steps + 1 end }
  local StartMenu = require("src.ui.game3.start_menu")
  StartMenu.update()
  StartMenu.update()
  check(steps == 2, "tile animations keep running while the start menu is up (" .. steps .. ")")
  package.loaded["src.core.game3.tileset_anim"] = nil
end

T.finish("game3_field_overlay_parity_test")
