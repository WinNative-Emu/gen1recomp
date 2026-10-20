-- engine/events/hidden_events/museum_fossils.asm:25 DisplayMonFrontSpriteInBox
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.load()

local S = require("tests.harness").suite("picbox mon palette")
local check, eq = S.check, S.eq

local PaletteFX = require("src.render.PaletteFX")
local PicBox = require("src.ui.PicBox")
require("src.render.Font").load(Data)

local prevMode = PaletteFX.mode
local base = { {255,255,255}, {200,200,200}, {100,100,100}, {0,0,0} }

local below = {}
function below:sgbPalettes() return { PaletteFX.whole(base) } end

local game = { data = Data, stack = { states = {} } }

local function boxZones(species, mode)
  PaletteFX.setMode(mode)
  local box = PicBox.new(game, "missing.png", nil, species)
  game.stack.states = { below, box }
  return box:sgbPalettes(game), box
end

check(type(PicBox.sgbPalettes) == "function", "PicBox exposes sgbPalettes")

if type(PicBox.sgbPalettes) == "function" then
  local zones, box = boxZones("ARTICUNO", "redpp")
  zones = zones or {}
  eq(#zones, 2, "ADVANCED: the screen zone plus the pic zone")
  eq(zones[1] and zones[1].colors, base, "ADVANCED: screen keeps the map palette")
  local pic = zones[2] or {}
  eq(pic.colors, PaletteFX.monPal(Data, "ARTICUNO"),
     "ADVANCED: the pic wears ARTICUNO's own palette")
  check(pic.colors ~= nil and pic.colors == PaletteFX.pal(Data, "BLUEMON"),
        "ADVANCED: ARTICUNO resolves to BLUEMON")

  local drawn
  local origDraw = love.graphics.draw
  love.graphics.draw = function(_, x, y) drawn = { x = x, y = y } end
  box.image = { getDimensions = function() return 56, 56 end }
  pcall(function() box:draw() end)
  love.graphics.draw = origDraw
  check(drawn ~= nil, "the pic is drawn")
  if drawn then
    eq(pic.x, drawn.x, "pic zone starts at the pic's left edge")
    eq(pic.y, drawn.y, "pic zone starts at the pic's top edge")
    eq(pic.w, 56, "pic zone is 7 tiles wide")
    eq(pic.h, 56, "pic zone is 7 tiles tall")
  end

  for _, mode in ipairs({ "gbc", "ogred", "og", "classic" }) do
    local z = boxZones("ARTICUNO", mode) or {}
    eq(#z, 1, mode .. ": the box inherits the screen zones unchanged")
    eq(z[1] and z[1].colors, base, mode .. ": no pic zone")
  end

  local z = boxZones(nil, "redpp") or {}
  eq(#z, 1, "ADVANCED with no species: screen zones unchanged")
end

PaletteFX.setMode(prevMode)
S.finish()
