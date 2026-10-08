local Badge = {}

Badge.SIZE = 9

Badge.MASK = {
  "..#####..",
  ".#.....#.",
  "#.......#",
  "#.......#",
  "#.......#",
  "#.......#",
  "#.......#",
  ".#.....#.",
  "..#####..",
}

Badge.DIGITS = {
  [1] = { ".#.", "##.", ".#.", ".#.", "###" },
  [2] = { "##.", "..#", ".#.", "#..", "###" },
  [3] = { "###", "..#", ".##", "..#", "###" },
}

Badge.DIGIT_X = 3
Badge.DIGIT_Y = 2

Badge.STYLES = {
  [1] = { ring = { 8, 24, 32 }, fill = { 224, 248, 208 }, digit = { 8, 24, 32 } },
  [2] = { ring = { 24, 56, 160 }, fill = { 248, 248, 248 }, digit = { 24, 56, 160 } },
  [3] = { ring = { 56, 56, 64 }, fill = { 255, 255, 255 }, digit = { 208, 48, 48 } },
}

local images = {}
local builds = 0

local function inside(row, col)
  local line = Badge.MASK[row]
  local first = line:find("#", 1, true)
  local last = #line - (line:reverse():find("#", 1, true) or 1) + 1
  return first ~= nil and col > first and col < last
end

function Badge.styleOf(style)
  if type(style) == "table" and style.ring and style.fill and style.digit then return style end
  return Badge.STYLES[tonumber(style) or 3] or Badge.STYLES[3]
end

function Badge.size(scale)
  local s = math.max(1, math.floor(tonumber(scale) or 1))
  return Badge.SIZE * s, Badge.SIZE * s
end

function Badge.pixels(digit, style)
  local st = Badge.styleOf(style)
  local glyph = Badge.DIGITS[tonumber(digit) or 0]
  local out = {}
  for row = 1, Badge.SIZE do
    local line = Badge.MASK[row]
    for col = 1, Badge.SIZE do
      local c = nil
      if line:sub(col, col) == "#" then
        c = st.ring
      elseif inside(row, col) then
        c = st.fill
        local gy, gx = row - Badge.DIGIT_Y, col - Badge.DIGIT_X
        if glyph and gy >= 1 and gy <= 5 and gx >= 1 and gx <= 3 and glyph[gy]:sub(gx, gx) == "#" then
          c = st.digit
        end
      end
      if c then out[#out + 1] = { x = col - 1, y = row - 1, c = c } end
    end
  end
  return out
end

local function styleKey(st)
  return table.concat({ st.ring[1], st.ring[2], st.ring[3], st.fill[1], st.fill[2], st.fill[3],
                        st.digit[1], st.digit[2], st.digit[3] }, ",")
end

local function imageFor(digit, st)
  if not (love and love.image and love.image.newImageData and love.graphics.newImage) then return nil end
  local key = tostring(digit) .. "|" .. styleKey(st)
  local hit = images[key]
  if hit then return hit end
  local id = love.image.newImageData(Badge.SIZE, Badge.SIZE)
  for _, p in ipairs(Badge.pixels(digit, st)) do
    id:setPixel(p.x, p.y, p.c[1] / 255, p.c[2] / 255, p.c[3] / 255, 1)
  end
  local img = love.graphics.newImage(id)
  if img.setFilter then img:setFilter("nearest", "nearest") end
  images[key] = img
  builds = builds + 1
  return img
end

function Badge.builds()
  return builds
end

function Badge.reset()
  images = {}
  builds = 0
end

function Badge.draw(x, y, digit, style, scale)
  if not (love and love.graphics) then return false end
  if not Badge.DIGITS[tonumber(digit) or 0] then return false end
  local s = math.max(1, math.floor(tonumber(scale) or 1))
  local st = Badge.styleOf(style)
  local img = imageFor(tonumber(digit), st)
  local g = love.graphics
  local r0, g0, b0, a0 = 1, 1, 1, 1
  if g.getColor then r0, g0, b0, a0 = g.getColor() end
  if img then
    g.setColor(1, 1, 1, 1)
    g.draw(img, math.floor(x), math.floor(y), 0, s, s)
  else
    for _, p in ipairs(Badge.pixels(digit, st)) do
      g.setColor(p.c[1] / 255, p.c[2] / 255, p.c[3] / 255, 1)
      g.rectangle("fill", math.floor(x) + p.x * s, math.floor(y) + p.y * s, s, s)
    end
  end
  g.setColor(r0, g0, b0, a0)
  return true
end

function Badge.drawBeside(nameRight, nameTop, nameHeight, digit, style, scale, gap)
  local w, h = Badge.size(scale)
  local x = nameRight + (gap or 1) * math.max(1, math.floor(tonumber(scale) or 1))
  local y = nameTop + math.floor(((nameHeight or h) - h) / 2)
  Badge.draw(x, y, digit, style, scale)
  return x + w, y, w, h
end

return Badge
