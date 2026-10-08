package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.harness")
local check = T.check
love = require("tests.love_stub")
local G = love.graphics

local canvasA = G.newCanvas(240, 160)
local canvasB = G.newCanvas(240, 160)
canvasA.name, canvasB.name = "A", "B"

local function noop() end
local Renderer = { canvas = G.newCanvas(240, 160), worldCanvas = canvasA }
function Renderer:init() end
function Renderer:setUISize() end
function Renderer:beginFrame() end
function Renderer:worldViewSize() return 240, 160 end
function Renderer:beginWorldPass()
  self.worldActive = true
  G.setCanvas(self.worldCanvas)
end
function Renderer:exchangeWorldCanvas(current, replacement)
  if self.worldCanvas ~= current then return false end
  self.worldCanvas = replacement
  return true
end
function Renderer:endWorldPass() G.setCanvas(self.canvas) end
function Renderer:endFrame() end

local seen = {}
local Transition = {
  isActive = function() return true end,
  drawWorld = function(canvas)
    seen.handed = canvas
    seen.bound = G.getCanvas()
  end,
}

local stubs = {
  ["src.render.Renderer"] = Renderer,
  ["src.render.PaletteFX"] = { mode = "gbc" },
  ["src.render.Tilt"] = { active = function() return false end },
  ["src.ui.game3.help_system"] = { isOpen = function() return false end },
  ["src.core.game3.battle"] = { isActive = function() return false end },
  ["src.core.game3.bg"] = { hasVisible = function() return false end },
  ["src.core.game3.oam"] = {
    resetFrame = noop, setLayer = function() return "world" end, animateSprites = noop,
    buildOamBuffer = noop, flush = noop, flushPriority = noop,
  },
  ["src.core.game3.field_view"] = {
    draw = function(_, _, _, opts)
      local cur = G.getCanvas()
      if opts.exchangeCanvas and opts.exchangeCanvas(cur, canvasB) then
        G.setCanvas(canvasB)
      end
    end,
  },
  ["src.core.game3.battle_transition"] = Transition,
}
local saved = {}
for name, mod in pairs(stubs) do
  saved[name] = package.loaded[name]
  package.loaded[name] = mod
end

package.loaded["src.core.game3.display"] = nil
local Display = require("src.core.game3.display")
Display.setUiRenderer(noop)
Display.planesBroken = false
Display.present({ options = {} }, 240, 160)

check(not Display.planesBroken, "plane present ran without falling back")
check(Renderer.worldCanvas == canvasB, "field pass exchanged the world canvas")
check(seen.handed == canvasB, "drawWorld is handed the exchanged world canvas")
check(seen.bound == canvasB, "world canvas still bound after the field pass pop")

for name in pairs(stubs) do package.loaded[name] = saved[name] end
package.loaded["src.core.game3.display"] = nil

local BT = require("src.core.game3.battle_transition")
local Pal = require("src.core.game3.pal_fade")
local drawnOn = {}
local rect = G.rectangle
G.rectangle = function() drawnOn[#drawnOn + 1] = G.getCanvas() end
BT._active, BT._opts, BT._fx = true, {}, nil
BT._pal = Pal.new()
BT._pal.slots[0].y = 8
G.setCanvas(canvasA)
BT.drawWorld(canvasB, 240, 160)
G.rectangle = rect
check(#drawnOn > 0, "intro overlay drew")
check(drawnOn[1] == canvasB, "drawWorld draws the intro overlay into the canvas it is handed")
check(G.getCanvas() == canvasA, "drawWorld restores the caller's canvas")
BT._active, BT._pal, BT._worldDrawn = false, nil, false

T.finish()
