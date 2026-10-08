local Font = require("src.render.Font")
local Theme = require("src.ui.Theme")

local Screen = {}
Screen.__index = Screen
Screen.isOpaque = true

Screen.COLS, Screen.ROWS = 20, 18
Screen.MENU_MAX = 4
Screen.KEYS = { "up", "down", "a", "b" }

function Screen.layout(pg, model)
  local items = pg.items or {}
  local visible = math.min(#items, Screen.MENU_MAX)
  local menuH = visible > 0 and visible + 2 or 0
  local infoH = Screen.ROWS - menuH
  local room = infoH - 3
  local body = model:formatLines(pg.lines)
  local lines = {}
  if pg.pager then
    local first = math.max(0, math.min(pg.scroll or 0, math.max(0, #body - room)))
    for i = first + 1, math.min(#body, first + room) do lines[#lines + 1] = body[i] end
    return { menuH = menuH, infoH = infoH, title = model:label(pg.title), lines = lines,
      more = first + room < #body, less = first > 0, visible = 0, scroll = 0, items = items }
  end
  lines = model.fitGroups(model:formatGroups(pg.lines), model:formatGroups(pg.info), room,
    { notice = pg.notice, keepBody = pg.keepBody })
  local cursor = pg.cursor or 1
  local scroll = 0
  if visible > 0 then
    scroll = math.max(0, math.min(cursor - visible, #items - visible))
    if cursor - 1 < scroll then scroll = cursor - 1 end
  end
  return { menuH = menuH, infoH = infoH, title = model:label(pg.title), lines = lines,
    visible = visible, scroll = scroll, cursor = cursor, items = items,
    more = #items > scroll + visible }
end

function Screen.label(model, it)
  local text = model:label(it.label)
  if it.disabled then text = "(" .. text .. ")" end
  local spans = Font.split(text)
  if #spans > 17 then text = text:sub(1, spans[17].to) end
  return text
end

function Screen.open(game, model, onDone)
  local self = setmetatable({ game = game, model = model, onDone = onDone, closed = false }, Screen)
  game.stack:push(self)
  return self
end

function Screen:press(key)
  if key == "a" or key == "b" then
    local data = self.game.data
    if data and data.audio then require("src.core.Sound").play(data, "Press_AB") end
  end
  self.model:input(key)
end

function Screen:update(_dt)
  if self.closed then return end
  self.model:poll()
  local input = self.game.input
  if input then
    for _, key in ipairs(Screen.KEYS) do
      if input:wasPressed(key) then
        self:press(key)
        break
      end
    end
  end
  if self.model.done then self:finish() end
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
  local pg = self.model:page()
  local L = Screen.layout(pg, self.model)
  Font.drawBox(0, 0, Screen.COLS, L.infoH)
  G.setColor(0, 0, 0, 1)
  Font.draw(L.title, 8, 8)
  for i, line in ipairs(L.lines) do Font.draw(line, 8, (1 + i) * 8) end
  if pg.pager and L.more then Font.drawCode(Theme.moreArrow, 18 * 8, (L.infoH - 2) * 8) end
  if L.menuH > 0 then
    local top = L.infoH
    Font.drawBox(0, top, Screen.COLS, L.menuH)
    G.setColor(0, 0, 0, 1)
    for row = 1, L.visible do
      local it = L.items[L.scroll + row]
      if it then
        local y = (top + row) * 8
        if it.chosen and L.scroll + row ~= L.cursor then Font.drawCode(Theme.cursorHollow, 8, y) end
        Font.draw(Screen.label(self.model, it), 16, y)
      end
    end
    Font.drawCode(Theme.cursor, 8, (top + L.cursor - L.scroll) * 8)
    if L.more then Font.drawCode(Theme.moreArrow, 18 * 8, (top + L.menuH - 1) * 8) end
  end
  G.setColor(1, 1, 1, 1)
end

return Screen
