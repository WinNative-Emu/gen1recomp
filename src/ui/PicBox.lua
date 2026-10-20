-- A framed picture pop-up (DisplayMonFrontSpriteInBox): shows an image
-- in a bordered box over the screen; any button closes it, then the
-- optional text plays.

local Font = require("src.render.Font")

local PicBox = {}
PicBox.__index = PicBox
PicBox.isOpaque = false

function PicBox.new(game, imagePath, text, species)
  local self = setmetatable({}, PicBox)
  self.game = game
  local ok, img = pcall(love.graphics.newImage, imagePath)
  self.image = ok and img or nil
  self.text = text
  self.species = species
  return self
end

function PicBox:sgbPalettes(game)
  local states = game.stack and game.stack.states or {}
  local zones
  local below = false
  for i = #states, 1, -1 do
    local s = states[i]
    if below and s.sgbPalettes then
      zones = s:sgbPalettes(game)
      break
    end
    if s == self then below = true end
  end
  local P = require("src.render.PaletteFX")
  if not (zones and self.species and P.usesGbcPack()) then return zones end
  local pic = P.zone(P.monPal(game.data, self.species), 7, 5, 13, 11)
  if not pic then return zones end
  local out = {}
  for i = 1, #zones do out[i] = zones[i] end
  out[#out + 1] = pic
  return out
end

function PicBox:update(dt)
  local input = self.game.input
  if input:wasPressed("a") or input:wasPressed("b") then
    self.game.stack:pop()
    if self.text then
      local TextBox = require("src.render.TextBox")
      self.game.stack:push(TextBox.new(self.game, self.text))
    end
  end
end

function PicBox:draw()
  Font.drawBox(6, 4, 9, 9)
  if self.image then
    love.graphics.setColor(1, 1, 1, 1)
    local w, h = self.image:getDimensions()
    love.graphics.draw(self.image, math.floor((6 + 4.5) * 8 - w / 2),
                       math.floor((4 + 4.5) * 8 - h / 2))
  end
end

return PicBox
