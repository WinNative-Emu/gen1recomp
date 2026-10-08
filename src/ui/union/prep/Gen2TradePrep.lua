local Chrome = require("src.ui.gen2.Chrome")
local Font = require("src.render.Font")
local Gen1 = require("src.ui.union.prep.Gen1TradePrep")
local Sound = require("src.core.Sound")

local Screen = {}
Screen.__index = Screen
Screen.isOpaque = true

function Screen.open(game, ctl, onDone)
  local self = setmetatable({ game = game, ctl = ctl, onDone = onDone, closed = false }, Screen)
  game.stack:push(self)
  return self
end

function Screen:wantsFillScale() return true end

function Screen:press(key)
  if key == "a" or key == "b" then
    local data = self.game.data
    local sfx = data and data.audio and data.audio.sfx
    if sfx and sfx[Sound.resolve(data, "Sfx_ReadText2")] then Sound.play(data, "Sfx_ReadText2") end
  end
  if Gen1.pageOn(self, key) then return end
  self.ctl:input(key)
end

Screen.update = Gen1.update
Screen.finish = Gen1.finish

function Screen.arrow(tx, ty)
  love.graphics.setColor(0, 0, 0, 1)
  Font.drawCode(Chrome.DOWN_ARROW, tx * 8, ty * 8)
end

function Screen:draw()
  local G = love.graphics
  Chrome.paletteFill(0, 0, Chrome.SCREEN_W * 8, Chrome.SCREEN_H * 8)
  local pg = self.ctl:page()
  local L = Gen1.layout(pg, self.ctl)
  Chrome.box(0, 0, Chrome.SCREEN_W, L.infoH)
  Chrome.print(L.title, 1, 1)
  for i, line in ipairs(L.lines) do Chrome.print(line, 1, 1 + i) end
  -- pokegold/home/joypad.asm:430
  if L.more and Gen1.arrowOn(self, 32) then Screen.arrow(18, L.infoH - 2) end
  if L.menuH > 0 then
    local top = L.infoH
    Chrome.box(0, top, Chrome.SCREEN_W, L.menuH)
    for row = 1, L.visible do
      local it = L.items[L.scroll + row]
      if it then Chrome.print(Gen1.label(self.ctl, it), 2, top + row) end
    end
    Chrome.cursor(1, top + L.cursor - L.scroll)
    if L.listMore then Screen.arrow(18, top + L.menuH - 1) end
  end
  G.setColor(1, 1, 1, 1)
end

return Screen
