local Logger = require("src.core.Logger")

local FontMods = {}

local CELL = 8
local BASELINE_ROW = 11
local GLYPH_CEILING = 0x400

local state = { glyphs = nil, rev = nil, ttf = nil }

local function warn(fmt, ...) Logger.warn("[gen3] " .. fmt, ...) end

local function decodeAt(text, i)
  local b = text:byte(i)
  if not b then return nil, i end
  if b < 0x80 then return b, i end
  local cont, cp
  if b >= 0xF0 then cont, cp = 3, b - 0xF0
  elseif b >= 0xE0 then cont, cp = 2, b - 0xE0
  elseif b >= 0xC0 then cont, cp = 1, b - 0xC0
  else return nil, i end
  for k = i + 1, i + cont do
    local c = text:byte(k)
    if not c or c < 0x80 or c > 0xBF then return nil, i end
    cp = cp * 64 + (c - 0x80)
  end
  return cp, i + cont
end

local function singleChar(seq)
  if type(seq) ~= "string" or seq == "" then return false end
  local cp, last = decodeAt(seq, 1)
  return cp ~= nil and last == #seq
end

local function imageData(path)
  local okA, Assets = pcall(require, "src.render.Assets")
  if okA and Assets and Assets.imageData then
    local ok, data = pcall(Assets.imageData, path)
    if ok and data then return data end
  end
  local ok, data = pcall(love.image.newImageData, path)
  if ok and data then return data end
  return nil
end

local function maskSheets(data)
  local w, h = data:getDimensions()
  local fg = love.image.newImageData(w, h)
  local sh = love.image.newImageData(w, h)
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      local _, _, _, a = data:getPixel(x, y)
      if a > 0 then
        fg:setPixel(x, y, 1, 1, 1, a)
        if x + 1 < w and y + 1 < h and (x + 1) % CELL ~= 0 and (y + 1) % CELL ~= 0 then
          sh:setPixel(x + 1, y + 1, 1, 1, 1, a)
        end
      end
    end
  end
  local fgImage, shImage = love.graphics.newImage(fg), love.graphics.newImage(sh)
  fgImage:setFilter("nearest", "nearest")
  shImage:setFilter("nearest", "nearest")
  return fgImage, shImage, w, h
end

local function loadPages(def, glyphs)
  for id, page in pairs(type(def.pages) == "table" and def.pages or {}) do
    local data = type(page) == "table" and imageData(page.image)
    if not data then
      warn("font page %s ignored: image %s could not be loaded", tostring(id), tostring(page and page.image))
    elseif type(page.base) ~= "number" or page.base < 0 or page.base >= GLYPH_CEILING then
      warn("font page %s ignored: base must be a code below 0x%X", tostring(id), GLYPH_CEILING)
    else
      local fg, sh, w, h = maskSheets(data)
      local perRow = math.max(1, page.glyphsPerRow or math.floor(w / CELL))
      local rows = math.floor(h / CELL)
      local advance = page.advance or CELL
      local count = 0
      for i = 0, perRow * rows - 1 do
        local code = page.base + i
        if code >= GLYPH_CEILING then break end
        glyphs[code] = {
          fg = fg, sh = sh, advance = advance, dy = BASELINE_ROW + 1 - CELL,
          quad = love.graphics.newQuad((i % perRow) * CELL, math.floor(i / perRow) * CELL,
            CELL, CELL, w, h),
        }
        count = count + 1
      end
      if count == 0 then warn("font page %s ignored: the image holds no %dx%d cells", tostring(id), CELL, CELL) end
    end
  end
end

local function loadCharmap(def, rev)
  local rows = {}
  for _, entry in ipairs(type(def.charmap) == "table" and def.charmap or {}) do rows[#rows + 1] = entry end
  for _, page in pairs(type(def.pages) == "table" and def.pages or {}) do
    for _, entry in ipairs(type(page) == "table" and type(page.charmap) == "table" and page.charmap or {}) do
      rows[#rows + 1] = entry
    end
  end
  for _, entry in ipairs(rows) do
    if type(entry) == "table" and singleChar(entry.seq) and type(entry.code) == "number"
        and entry.code >= 0 and entry.code < GLYPH_CEILING then
      rev[entry.seq] = entry.code
    elseif type(entry) == "table" then
      warn("charmap row %s ignored: Gen 3 text maps one character to one glyph code below 0x%X",
        tostring(entry.seq), GLYPH_CEILING)
    end
  end
end

local function tileSet(tiles)
  local set = {}
  if type(tiles) == "string" then
    local i = 1
    while i <= #tiles do
      local _, last = decodeAt(tiles, i)
      set[tiles:sub(i, last)] = true
      i = last + 1
    end
  elseif type(tiles) == "table" then
    for _, seq in ipairs(tiles) do set[seq] = true end
  end
  return set
end

local function loadTtf(def)
  local spec = def.ttf
  if type(spec) ~= "table" then return nil end
  local Font = require("src.render.Font")
  local file = spec.file or Font.PLAINPIXEL
  local size = spec.size or Font.PLAINPIXEL_SIZE
  local ok, obj = pcall(love.graphics.newFont, file, size, "mono", 1)
  if not (ok and obj) then
    warn("font ttf %q ignored: %s", tostring(file), tostring(obj))
    return nil
  end
  if obj.setFilter then pcall(obj.setFilter, obj, "nearest", "nearest") end
  return {
    font = obj, spacing = spec.spacing or 0, bold = spec.bold == true,
    yOffset = spec.yOffset or (BASELINE_ROW - (obj.getBaseline and obj:getBaseline() or obj:getHeight() - 3)),
    tiles = tileSet(spec.tiles), widths = {},
  }
end

function FontMods.install(def)
  state = { glyphs = nil, rev = nil, ttf = nil }
  if type(def) ~= "table" or not (love and love.graphics and love.image) then return false end
  local glyphs, rev = {}, {}
  loadPages(def, glyphs)
  loadCharmap(def, rev)
  state.glyphs = next(glyphs) and glyphs or nil
  state.rev = next(rev) and rev or nil
  state.ttf = loadTtf(def)
  return state.glyphs ~= nil or state.rev ~= nil or state.ttf ~= nil
end

function FontMods.active()
  return state.glyphs ~= nil or state.rev ~= nil or state.ttf ~= nil
end

function FontMods.glyph(id)
  local glyphs = state.glyphs
  return glyphs and glyphs[id] or nil
end

function FontMods.overrides()
  return state.rev
end

function FontMods.ttfEligible(ch)
  local ttf = state.ttf
  if not ttf or ttf.tiles[ch] then return false end
  local cp = decodeAt(ch, 1)
  return cp ~= nil and ((cp >= 0x20 and cp <= 0x7E) or (cp >= 0xC0 and cp <= 0x24F))
end

function FontMods.ttfAdvance(ch)
  local ttf = state.ttf
  local w = ttf.widths[ch]
  if not w then
    w = ttf.font:getWidth(ch) + ttf.spacing + (ttf.bold and 1 or 0)
    ttf.widths[ch] = w
  end
  return w
end

function FontMods.ttfDraw(ch, x, y, fg, shadow, setColor)
  local ttf = state.ttf
  local previous = love.graphics.getFont()
  love.graphics.setFont(ttf.font)
  local ty = y + ttf.yOffset
  if shadow and (not shadow[4] or shadow[4] > 0) then
    setColor(shadow)
    love.graphics.print(ch, x + 1, ty + 1)
    if ttf.bold then love.graphics.print(ch, x + 2, ty + 1) end
  end
  if fg and (not fg[4] or fg[4] > 0) then
    setColor(fg)
    love.graphics.print(ch, x, ty)
    if ttf.bold then love.graphics.print(ch, x + 1, ty) end
  end
  love.graphics.setFont(previous)
end

return FontMods
