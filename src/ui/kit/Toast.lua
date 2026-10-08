local Toast = {}

Toast.KINDS = {
  ok = { color = "green", icon = "check", hold = 3.5 },
  error = { color = "red", icon = "triangle-alert", hold = 7 },
  warn = { color = "yellow", icon = "triangle-alert", hold = 6 },
  info = { color = "blue", icon = "circle-help", hold = 5 },
}
Toast.SLIDE = .18
Toast.FADE = .25

local function now()
  if love and love.timer and love.timer.getTime then return love.timer.getTime() end
  return nil
end

local function holdOf(t)
  if t.sticky then return math.huge end
  return t.hold or Toast.KINDS[t.kind].hold
end

local function expired(t, at)
  return t.at and at and (at - t.at) > holdOf(t) + Toast.FADE
end

function Toast.show(store, text, kind, opts)
  if text == nil or text == "" then store.toast = nil; return end
  text = tostring(text)
  kind = Toast.KINDS[kind] and kind or "info"
  opts = opts or {}
  local t, at = store.toast, now()
  if t and t.text == text and t.kind == kind and not expired(t, at) then
    if t.at and at then t.at = at - math.min(Toast.SLIDE, at - t.at) end
    t.sticky, t.hold = opts.sticky, opts.hold
    return t
  end
  store.toast = { text = text, kind = kind, at = at, sticky = opts.sticky, hold = opts.hold }
  return store.toast
end

function Toast.clear(store)
  store.toast = nil
end

function Toast.current(store)
  local t = store and store.toast
  if not t then return nil end
  if expired(t, now()) then store.toast = nil; return nil end
  return t
end

function Toast.hit(store, x, y)
  local t = Toast.current(store)
  local r = t and t.rect
  if r and t.at then
    local at = now()
    local elapsed = at and (at - t.at)
    if elapsed and (elapsed < Toast.SLIDE or elapsed > holdOf(t)) then return false end
  end
  return r ~= nil and x ~= nil and y ~= nil
    and x >= r[1] and x <= r[1] + r[3] and y >= r[2] and y <= r[2] + r[4]
end

local function wrapLines(font, text, w)
  if not font then return { text } end
  local ok, _, lines = pcall(font.getWrap, font, text, w)
  return (ok and lines and #lines > 0) and lines or { text }
end

local function lineHeight(font)
  return font and font:getHeight() or 12
end

local function cachedLines(t, font, w)
  local c = t._wrap
  if c and c.font == font and c.w == w then return c.lines end
  local lines = wrapLines(font, t.text, w)
  t._wrap = { font = font, w = w, lines = lines }
  return lines
end

local function defaultText(font, lines, x, y, w, color, maxLines)
  local G = love and love.graphics
  if not G or not font then return end
  local Theme = require("src.ui.kit.Theme")
  local lh = lineHeight(font)
  G.setFont(font)
  Theme.col(color, 1)
  for i = 1, math.min(#lines, maxLines) do
    local line = lines[i]
    if i == maxLines and #lines > maxLines then line = Theme.ellipsize(font, line .. "...", w) end
    pcall(G.print, line, Theme.snap(x), Theme.snap(y + (i - 1) * lh))
  end
end

function Toast.draw(store, area)
  local t = store and store.toast
  if not t then return nil end
  local at = now()
  if not t.at then t.at = at end
  local elapsed = (at and t.at) and (at - t.at) or 0
  local hold = holdOf(t)
  if elapsed > hold + Toast.FADE then store.toast = nil; return nil end
  local Theme = require("src.ui.kit.Theme")
  local Icons = require("src.ui.kit.Icons")
  local PAL = Theme.PAL
  local style = Toast.KINDS[t.kind]
  local slide = math.min(1, elapsed / Toast.SLIDE, (hold + Toast.FADE - elapsed) / Toast.FADE)
  slide = 1 - (1 - math.max(0, slide)) ^ 3
  local s, color = area.s or 1, PAL[style.color]
  local pad, gap, icon = 12 * s, 10 * s, 20 * s
  local maxLines = area.maxLines or 4
  local w = area.width or math.min(420 * s, area.w - 32 * s)
  local textW = w - 2 * pad - icon - gap
  local lines = (not area.wrapHeight or not area.drawText) and cachedLines(t, area.font, textW)
  local textH = area.wrapHeight and area.wrapHeight(t.text, textW, maxLines)
    or math.min(#lines, maxLines) * lineHeight(area.font)
  local h = 2 * pad + math.max(icon, textH)
  local x = (area.x or 0) + (area.w - w) / 2
  local y, fromAbove
  if area.place then y, fromAbove = area.place(x, w, h) end
  if y == nil then
    if area.centerY then
      y, fromAbove = area.centerY - h / 2, true
    elseif area.top and not (area.bottom and area.maxY and area.top + 12 * s + h > area.maxY) then
      y, fromAbove = area.top + 12 * s, true
    else
      y, fromAbove = area.bottom - h - 12 * s, false
    end
  end
  if fromAbove then
    y = y - (1 - slide) * (h + 24 * s)
  else
    y = y + (1 - slide) * (h + 24 * s)
  end
  t.rect = { x, y, w, h }
  local r = area.radius or Theme.cardRadius()
  Theme.fillRounded(x + 2 * s, y + 4 * s, w, h, PAL.inverse, .35, r)
  Theme.fillRounded(x, y, w, h, PAL.surface, .98, r)
  Theme.fillRounded(x, y, w, h, color, .16, r)
  Theme.strokeRounded(x, y, w, h, color, .75, 1.5, r)
  Icons.draw(style.icon, x + pad, y + (h - icon) / 2, icon, color, 1)
  if area.drawText then
    area.drawText(t.text, x + pad + icon + gap, y + pad, textW, PAL.heading, maxLines)
  else
    defaultText(area.font, lines, x + pad + icon + gap, y + pad, textW, PAL.heading, maxLines)
  end
  return t.rect
end

return Toast
