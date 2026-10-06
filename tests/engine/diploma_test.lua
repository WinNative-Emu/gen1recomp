-- Diploma screen rendering and dismiss tests (engine/events/diploma.asm).
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.load()

local S = require("tests.harness").suite("diploma")
local check, eq = S.check, S.eq

local Game = require("src.core.Game")
local Input = require("src.core.Input")
local StateStack = require("src.core.StateStack")
local SaveData = require("src.core.SaveData")
local Diploma = require("src.ui.Diploma")

Game.data = Data
Data.palettes = {
  palettes = {
    MEWMON = { {255,255,255}, {180,180,180}, {90,90,90}, {0,0,0} }
  }
}
Game.input = Input; Input:init()
Game.stack = StateStack; StateStack:init()
Game.save = SaveData.newGame()
Game.save.player.name = "ASH"
require("src.render.Font").load(Data)

local done = false
local diploma = Diploma.new(Game, function() done = true end)
Game.stack:push(diploma)

check(diploma.isOpaque, "Diploma is opaque screen")
local pals = diploma:sgbPalettes(Game)
check(pals ~= nil, "Diploma resolves sgbPalettes")

-- Confirm rendering does not crash
local ok, err = pcall(function()
  diploma:draw()
end)
check(ok, "Diploma:draw() runs without error: " .. tostring(err))

local PaletteFX = require("src.render.PaletteFX")
local Sprites = require("src.pokemon.Sprites")
local SpriteRenderer = require("src.render.SpriteRenderer")
local GameVersion = require("src.core.GameVersion")

local fakePic = setmetatable({ w = 40, h = 56 }, {
  __index = {
    getDimensions = function(s) return s.w, s.h end,
    getWidth = function(s) return s.w end,
    getHeight = function(s) return s.h end,
  },
})
local origPlayerPic, origObp = Sprites.playerPic, SpriteRenderer.obpImage
local origScissor, origDraw = love.graphics.setScissor, love.graphics.draw
local origMode, origIsBlue = PaletteFX.mode, GameVersion.isBlue
local bakes, scissors, picDraws = {}, {}, {}
Sprites.playerPic = function() return "fake/player.png", false end
SpriteRenderer.obpImage = function(path, ramp, group)
  bakes[#bakes + 1] = { path = path, ramp = ramp, group = group }
  return fakePic
end
love.graphics.setScissor = function(...)
  scissors[#scissors + 1] = { ... }
end
love.graphics.draw = function(img, a, b)
  if img == fakePic then picDraws[#picDraws + 1] = { a, b } end
end

local function renderIn(mode, pass)
  bakes, scissors, picDraws = {}, {}, {}
  PaletteFX.mode = mode
  PaletteFX.clearSpriteRedraws()
  PaletteFX.setPass(pass)
  local okR, errR = pcall(Diploma.render, Game)
  check(okR, "Diploma.render under " .. tostring(mode) .. "/"
    .. tostring(pass) .. ": " .. tostring(errR))
  local redraws = {}
  for _, r in ipairs(PaletteFX.uiSpriteRedraws()) do redraws[#redraws + 1] = r end
  PaletteFX.setPass(nil)
  PaletteFX.clearSpriteRedraws()
  return redraws
end

local function noNarrowScissor(label)
  for _, s in ipairs(scissors) do
    local x, w = s[1], s[3]
    check(x == nil or x + w >= 155,
      label .. ": scissor never clips the pic short of x 155")
  end
end

local r = renderIn("sgb", "ui")
noNarrowScissor("sgb")
eq(#picDraws, 1, "sgb draws the player pic once")
eq(picDraws[1] and picDraws[1][1], 115, "pic x 115 (diploma.asm:44 +33)")
eq(picDraws[1] and picDraws[1][2], 80, "pic y 80")
eq(bakes[1] and bakes[1].group, "diploma", "sgb keeps the OBP0 $90 DMG bake")
eq(#r, 0, "sgb records no OBJ-ramp redraw")

GameVersion.isBlue = function() return false end
r = renderIn("ogred", "ui")
noNarrowScissor("ogred")
eq(bakes[1] and bakes[1].group, "diploma_og", "OG RED bakes the OBJ ramp")
local c = PaletteFX.OG_RED_SOFT_OBJ
local ramp = bakes[1] and bakes[1].ramp or {}
check(ramp[2] == c[1] and ramp[3] == c[2] and ramp[4] == c[3],
  "OG RED OBP0 $90 maps colors 1-3 to OBJ shades 0, 1, 2")
check(r[1] and r[1].image == fakePic and r[1].x == 115 and r[1].y == 80,
  "OG RED replays the pic at (115, 80) after the zone pass")
check(r[2] and r[2].clip and r[2].clip[1] == 115 and r[2].clip[2] == 80
  and r[2].clip[3] == 40 and r[2].clip[4] == 56,
  "OG RED replays the BG text over the pic, clipped to the pic")

local canvasSets = 0
local origSetCanvas = love.graphics.setCanvas
love.graphics.setCanvas = function(c)
  if c then canvasSets = canvasSets + 1 end
  return origSetCanvas(c)
end
renderIn("ogred", "ui")
eq(canvasSets, 0, "OG RED reuses the cached text overlay on a second draw")
Game.save.player.name = "RED"
renderIn("ogred", "ui")
eq(canvasSets, 1, "a changed player name rebuilds the text overlay once")
Game.save.player.name = "ASH"
love.graphics.setCanvas = origSetCanvas

GameVersion.isBlue = function() return true end
r = renderIn("ogred", "ui")
eq(bakes[1] and bakes[1].group, "diploma_og_blue",
  "OG BLUE bakes under a version-distinct cache group")
check(bakes[1] and bakes[1].ramp[3] == PaletteFX.GBC_OBJ_BLUE[2],
  "OG BLUE uses Blue's OBJ ramp")
GameVersion.isBlue = origIsBlue

r = renderIn("ogred", nil)
eq(bakes[1] and bakes[1].group, "diploma", "printer path keeps the DMG bake")
eq(#r, 0, "printer path records no redraw")

Sprites.playerPic, SpriteRenderer.obpImage = origPlayerPic, origObp
love.graphics.setScissor, love.graphics.draw = origScissor, origDraw
PaletteFX.mode = origMode

-- Confirm dismissal on A or B press
Input.pressed = { a = true }
diploma:update()
check(done, "Diploma calls onDone on A press")
eq(Game.stack:top(), nil, "Diploma pops from stack")

S.finish()
