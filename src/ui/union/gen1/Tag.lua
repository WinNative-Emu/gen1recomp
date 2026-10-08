local Badge = require("src.online.union.Badge")
local Font = require("src.render.Font")

local Tag = {}

Tag.HOST_GEN = 1
Tag.PAD = 2
Tag.GLYPH_H = 8
Tag.LIFT = 2
Tag.FILL = { 1, 1, 1 }
Tag.EDGE = { 0, 0, 0 }

local widths = {}

function Tag.nameWidth(name)
  local hit = widths[name]
  if hit then return hit end
  local w = Font.width(name)
  widths[name] = w
  return w
end

function Tag.size(name, withName)
  local bw, bh = Badge.size(1)
  if not withName then return bw, bh end
  local w = Tag.nameWidth(name) + Tag.PAD * 3 + bw
  local h = math.max(Tag.GLYPH_H, bh) + Tag.PAD * 2
  return w, h
end

function Tag.rect(x, y, name, withName)
  local w, h = Tag.size(name, withName)
  return math.floor(x) - math.floor(w / 2), math.floor(y) - Tag.LIFT - h, w, h
end

function Tag.draw(x, y, name, digit, withName)
  local G = love.graphics
  local left, top, w, h = Tag.rect(x, y, name, withName)
  if withName then
    G.setColor(Tag.EDGE[1], Tag.EDGE[2], Tag.EDGE[3], 1)
    G.rectangle("fill", left, top, w, h)
    G.setColor(Tag.FILL[1], Tag.FILL[2], Tag.FILL[3], 1)
    G.rectangle("fill", left + 1, top + 1, w - 2, h - 2)
    G.setColor(0, 0, 0, 1)
    Font.draw(name, left + Tag.PAD, top + Tag.PAD)
    Badge.drawBeside(left + Tag.PAD + Tag.nameWidth(name), top + Tag.PAD - 1,
      Tag.GLYPH_H + 2, digit, Tag.HOST_GEN, 1, Tag.PAD)
  else
    Badge.draw(left, top, digit, Tag.HOST_GEN, 1)
  end
  G.setColor(1, 1, 1, 1)
  return left, top, w, h
end

return Tag
