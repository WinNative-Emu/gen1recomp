local Font = require("src.render.Font")
local Theme = require("src.ui.Theme")

local Screen = {}
Screen.__index = Screen
Screen.isOpaque = true

Screen.COLS, Screen.ROWS = 20, 18
Screen.MENU_MAX = 4
Screen.KEYS = { "up", "down", "left", "right", "a", "b" }
Screen.LABEL_MAX = 17

function Screen.layout(pg, ctl)
  local items = pg.items or {}
  local visible = math.min(#items, Screen.MENU_MAX)
  local menuH = visible > 0 and visible + 2 or 0
  local infoH = Screen.ROWS - menuH
  local room = infoH - 3
  local body = ctl:formatLines(pg.lines)
  local info = ctl:formatLines(pg.info)
  for _, l in ipairs(info) do body[#body + 1] = l end
  local maxFirst = math.max(0, #body - room)
  local first = math.min(pg.scroll or 0, maxFirst)
  if (pg.scroll or 0) > maxFirst then ctl.scroll = maxFirst end
  local lines = {}
  for i = first + 1, math.min(#body, first + room) do lines[#lines + 1] = body[i] end
  local cursor = pg.cursor or 1
  local scroll = 0
  if visible > 0 then
    scroll = math.max(0, math.min(cursor - visible, #items - visible))
    if cursor - 1 < scroll then scroll = cursor - 1 end
  end
  return { menuH = menuH, infoH = infoH, title = ctl:label(pg.title), lines = lines, first = first, room = room,
    more = first < maxFirst, less = first > 0, visible = visible, scroll = scroll, cursor = cursor,
    items = items, listMore = #items > scroll + visible }
end

function Screen.label(ctl, it)
  local text = ctl:label(it.label)
  if it.disabled then text = "(" .. text .. ")" end
  local spans = Font.split(text)
  if #spans > Screen.LABEL_MAX then text = text:sub(1, spans[Screen.LABEL_MAX].to) end
  return text
end

function Screen.open(game, ctl, onDone)
  local self = setmetatable({ game = game, ctl = ctl, onDone = onDone, closed = false }, Screen)
  game.stack:push(self)
  return self
end

function Screen.pageOn(self, key)
  if key ~= "a" then return false end
  local L = Screen.layout(self.ctl:page(), self.ctl)
  if not L.more then return false end
  self.ctl.scroll = L.first + L.room
  self.blink = 0
  return true
end

function Screen.arrowOn(self, period)
  return (self.blink or 0) % period < period / 2
end

function Screen:press(key)
  if key == "a" or key == "b" then
    local data = self.game.data
    if data and data.audio then require("src.core.Sound").play(data, "Press_AB") end
  end
  if Screen.pageOn(self, key) then return end
  self.ctl:input(key)
end

function Screen:update(dt)
  if self.closed then return end
  self.blink = (self.blink or 0) + 1
  self.ctl:poll(dt)
  local input = self.game.input
  if input then
    for _, key in ipairs(Screen.KEYS) do
      if input:wasPressed(key) then
        self:press(key)
        break
      end
    end
  end
  if self.ctl.done then self:finish() end
end

function Screen:finish()
  if self.closed then return end
  self.closed = true
  local stack = self.game.stack
  if stack:top() == self then stack:pop() end
  if self.onDone then self.onDone() end
end

function Screen:draw()
  local G = love.graphics
  G.setColor(1, 1, 1, 1)
  G.rectangle("fill", 0, 0, Screen.COLS * 8, Screen.ROWS * 8)
  local pg = self.ctl:page()
  local L = Screen.layout(pg, self.ctl)
  Font.drawBox(0, 0, Screen.COLS, L.infoH)
  G.setColor(0, 0, 0, 1)
  Font.draw(L.title, 8, 8)
  for i, line in ipairs(L.lines) do Font.draw(line, 8, (1 + i) * 8) end
  if L.more and Screen.arrowOn(self, 60) then Font.drawCode(Theme.moreArrow, 18 * 8, (L.infoH - 2) * 8) end
  if L.menuH > 0 then
    local top = L.infoH
    Font.drawBox(0, top, Screen.COLS, L.menuH)
    G.setColor(0, 0, 0, 1)
    for row = 1, L.visible do
      local it = L.items[L.scroll + row]
      if it then Font.draw(Screen.label(self.ctl, it), 16, (top + row) * 8) end
    end
    Font.drawCode(Theme.cursor, 8, (top + L.cursor - L.scroll) * 8)
    if L.listMore then Font.drawCode(Theme.moreArrow, 18 * 8, (top + L.menuH - 1) * 8) end
  end
  G.setColor(1, 1, 1, 1)
end

return Screen
