package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

love = love or require("tests.love_stub")

package.loaded["src.core.Logger"] = {
  info = function() end, warn = function() end, error = function() end,
}

local G = love.graphics
local surface = { d = 1, w = 1612, h = 720, pw = 1612, ph = 720 }
G.getDPIScale = function() return surface.d end
G.getDimensions = function() return surface.w, surface.h end
G.getPixelDimensions = function() return surface.pw, surface.ph end

local function use(d, w, h, pw, ph)
  surface.d, surface.w, surface.h, surface.pw, surface.ph = d, w, h, pw, ph
end

local Chrome = require("src.ui.gen2.Chrome")
local World = require("src.world.gen2.World")
local world = setmetatable({}, { __index = World })

local function near(a, b) return math.abs(a - b) < 1e-6 end
local function whole(v) return near(v, math.floor(v + 0.5)) end

use(1, 1612, 720, 1612, 720)
eq(Chrome.fitScale(1612, 720), 5, "1x: 1612x720 fits at 5")
local ox, oy = Chrome.fitOrigin(1612, 720)
eq(ox, 406, "1x: origin x")
eq(oy, 0, "1x: origin y")
eq(world:fitScale(), 5, "1x: world fit")

for _, case in ipairs({
  { 2, 806, 360 },
  { 1.5, 1075, 480 },
}) do
  local d, w, h = case[1], case[2], case[3]
  use(d, w, h, 1612, 720)
  local tag = string.format("%sx (%dx%d units)", tostring(d), w, h)
  local scale = Chrome.fitScale(w, h)
  check(near(scale * d, 5), tag .. ": the panel is 5 framebuffer px per GB px, got "
    .. tostring(scale * d))
  check(near(world:fitScale() * d, 5), tag .. ": the world fits at 5 px too")
  local x, y = Chrome.fitOrigin(w, h, scale)
  check(whole(x * d) and whole(y * d), tag .. ": the panel origin is on a framebuffer pixel")
  check(near(x * d, math.floor((w * d - 800) / 2)), tag .. ": the panel is centred")
end

T.finish("gen2_dpi_fit_bug2997")
