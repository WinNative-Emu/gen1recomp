local Stack = require("src.ui.game3.stack")
local Window = require("src.ui.game3.window")
local FrlgFont = require("src.ui.game3.frlg_font")

local Screen = {}

Screen.ID = "union_trade_prep"
Screen.W, Screen.H = 240, 160
Screen.INFO = Window.template(1, 1, 17, 18)
Screen.MENU = Window.template(20, 1, 9, 18)
Screen.PITCH = 15
Screen.ROWS = 9
Screen.KEYS = { "up", "down", "left", "right", "a", "b" }
Screen.TITLE = { colors = FrlgFont.COLOR.BLUE }
Screen.BODY = { colors = FrlgFont.COLOR.NORMAL }
Screen.BACKGROUND = { 0.37, 0.56, 0.71 }

local function wrapped(lines, width)
  local out = {}
  for _, line in ipairs(lines or {}) do
    local text = FrlgFont.wrap(line, width)
    for part in (text .. "\n"):gmatch("(.-)\n") do out[#out + 1] = part end
  end
  return out
end

function Screen.layout(pg, ctl)
  local width = Screen.INFO.width * 8
  local room = Screen.ROWS - 1
  local body = wrapped(pg.lines, width)
  for _, l in ipairs(wrapped(pg.info, width)) do body[#body + 1] = l end
  local maxFirst = math.max(0, #body - room)
  local first = math.min(pg.scroll or 0, maxFirst)
  if ctl and (pg.scroll or 0) > maxFirst then ctl.scroll = maxFirst end
  local lines = {}
  for i = first + 1, math.min(#body, first + room) do lines[#lines + 1] = body[i] end
  local items = pg.items or {}
  local visible = math.min(#items, Screen.ROWS)
  local cursor = pg.cursor or 1
  local scroll = 0
  if visible > 0 and cursor > visible then scroll = cursor - visible end
  return { lines = lines, first = first, room = room, more = first < maxFirst, items = items, visible = visible, scroll = scroll,
    cursor = cursor, listMore = #items > scroll + visible }
end

function Screen.pageOn(ctl, key)
  if key ~= "a" then return false end
  local L = Screen.layout(ctl:page(), ctl)
  if not L.more then return false end
  ctl.scroll = L.first + L.room
  return true
end

function Screen.open(_game, ctl, onDone)
  local mod = { ticks = 0 }
  local closed = false
  local function finish()
    if closed then return end
    closed = true
    Stack.pop(Screen.ID)
    if onDone then onDone() end
  end
  function mod.update(dt)
    if closed then return end
    mod.ticks = mod.ticks + 1
    ctl:poll(dt)
    if ctl.done then finish() end
  end
  function mod.handleInput(input)
    if closed or not input then return end
    for _, key in ipairs(Screen.KEYS) do
      if input:wasPressed(key) then
        if key == "a" or key == "b" then
          local okA, Audio = pcall(require, "src.core.game3.audio")
          local okS, SE = pcall(require, "src.core.game3.se_ids")
          if okA and okS and Audio.playSe then pcall(Audio.playSe, SE.SE_SELECT) end
        end
        if Screen.pageOn(ctl, key) then mod.ticks = 0 else ctl:input(key) end
        break
      end
    end
    if ctl.done then finish() end
  end
  function mod.draw() Screen.draw(ctl, mod.ticks) end
  mod.ctl = ctl
  mod.finish = finish
  Stack.push(Screen.ID, mod, { hideBelow = true, fullscreen = true })
  return mod
end

function Screen.arrow(px, py)
  local c = FrlgFont.COLOR.NORMAL.fg
  love.graphics.setColor(c[1] or 0, c[2] or 0, c[3] or 0, 1)
  love.graphics.polygon("fill", px, py, px + 6, py, px + 3, py + 4)
  love.graphics.setColor(1, 1, 1, 1)
end

local BOUNCE = { 0, 1, 2, 3, 2, 1 }

function Screen.moreArrow(px, py, ticks)
  local Chrome = require("src.ui.game3.chrome")
  local rse = Chrome.arrowSpec()
  local frame
  if rse then
    frame = math.floor(ticks / (rse.period or ((rse.delay or 0) + 1)))
  else
    frame = BOUNCE[1 + math.floor(ticks / 8) % #BOUNCE]
  end
  Chrome.promptArrow(px, py, frame)
end

function Screen.draw(ctl, ticks)
  local G = love.graphics
  local bg = Screen.BACKGROUND
  G.setColor(bg[1], bg[2], bg[3], 1)
  G.rectangle("fill", 0, 0, Screen.W, Screen.H)
  G.setColor(1, 1, 1, 1)
  local pg = ctl:page()
  local L = Screen.layout(pg, ctl)
  local info, menu = Screen.INFO, Screen.MENU
  Window.stdFrame(info)
  local x, y = info.left * 8, info.top * 8
  Window.printPx(pg.title or "", x, y, Screen.TITLE)
  for i, line in ipairs(L.lines) do Window.printPx(line, x, y + i * Screen.PITCH, Screen.BODY) end
  if L.more then Screen.moreArrow(x + info.width * 8 - 10, y + Screen.ROWS * Screen.PITCH - 8, ticks or 0) end
  if L.visible > 0 then
    Window.stdFrame(menu)
    local mx, my = menu.left * 8, menu.top * 8
    local maxW = menu.width * 8 - Window.CURSOR_WIDTH
    for row = 1, L.visible do
      local it = L.items[L.scroll + row]
      if it then
        local label = it.disabled and ("(" .. (it.label or "") .. ")") or (it.label or "")
        Window.printPx(label, mx + Window.CURSOR_WIDTH, my + (row - 1) * Screen.PITCH,
          { colors = Screen.BODY.colors, maxWidth = maxW })
      end
    end
    Window.cursorPx(mx, my + (L.cursor - L.scroll - 1) * Screen.PITCH)
    if L.listMore then Screen.arrow(mx + menu.width * 8 - 8, my + Screen.ROWS * Screen.PITCH - 4) end
  end
  G.setColor(1, 1, 1, 1)
end

return Screen
