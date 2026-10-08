local Avatars = require("src.online.union.Avatars")
local PaletteFX = require("src.render.PaletteFX")

local Look = {}

Look.LEVELS = { 0.7, 0.33, 0 }

local stats = { grays = 0 }

function Look.stats()
  return { grays = stats.grays }
end

function Look.trueColor()
  return PaletteFX.usesGbcPack()
end

local function levelOf(r, g, b)
  local l = 0.299 * r + 0.587 * g + 0.114 * b
  if l > 0.78 then return Look.LEVELS[1] end
  if l > 0.42 then return Look.LEVELS[2] end
  return Look.LEVELS[3]
end

function Look.grayEntry(entry)
  if entry._grayEntry ~= nil then return entry._grayEntry or nil end
  local base = Avatars.imageData(entry)
  if not base then
    entry._grayEntry = false
    return nil
  end
  local id = base.clone and base:clone() or base
  local colors = entry.palette and entry.palette.mode == "gbc" and entry.palette.colors or nil
  id:mapPixel(function(_, _, r, g, b, a)
    if a == 0 then return 1, 1, 1, 0 end
    if colors then
      if r > 0.83 then return 1, 1, 1, 0 end
      local c = colors[r > 0.5 and 2 or r > 0.17 and 3 or 4]
      r, g, b = c[1] / 255, c[2] / 255, c[3] / 255
    end
    local v = levelOf(r, g, b)
    return v, v, v, a
  end)
  local gray = {}
  for k, v in pairs(entry) do gray[k] = v end
  gray.palette = { mode = "dmg" }
  gray._imageData, gray._images, gray._lookKey, gray._lookImg = id, nil, nil, nil
  gray._grayEntry = nil
  entry._grayEntry = gray
  stats.grays = stats.grays + 1
  return gray
end

function Look.objColors()
  if PaletteFX.usesSpriteObp() and PaletteFX.spriteRedrawPassActive() then
    return PaletteFX.ogObjWorld(), true
  end
  return PaletteFX.dmgObj(), false
end

function Look.gen1Colors(playerDef, seed)
  if PaletteFX.usesGbcPack() then
    local colors = PaletteFX.spriteObp(playerDef, seed)
    if colors then return colors, false end
    return PaletteFX.dmgObj(), false
  end
  if PaletteFX.usesSpriteObp() and PaletteFX.spriteRedrawPassActive() then
    return PaletteFX.ogObjWorld(), true
  end
  return PaletteFX.dmgObj(), false
end

local function blit(img, quad, x, y, w, flip, redraw)
  if flip then
    love.graphics.draw(img, quad, x + w, y, 0, -1, 1)
    if redraw then PaletteFX.markSpriteRedraw(img, quad, x + w, y, -1) end
  else
    love.graphics.draw(img, quad, x, y)
    if redraw then PaletteFX.markSpriteRedraw(img, quad, x, y, 1) end
  end
end

local OWN = {}

local function imageFor(entry, colors)
  local key = colors or OWN
  if entry._lookKey == key and entry._lookImg then return entry._lookImg end
  local img = Avatars.image(entry, colors)
  entry._lookKey, entry._lookImg = key, img
  return img
end

local function artHeight(entry)
  local id = Avatars.imageData(entry)
  if not (id and id.getPixel) then return entry.h end
  local keyed = entry.palette.mode ~= "rgba"
  for y = 0, entry.h - 1 do
    for x = 0, entry.w - 1 do
      local r, _, _, a = id:getPixel(x, y)
      if a > 0 and not (keyed and r > 0.83) then return entry.h - y end
    end
  end
  return entry.h
end

function Look.height(entry)
  if type(entry) ~= "table" or entry.standin then return 0 end
  if not entry._artH then entry._artH = artHeight(entry) end
  return entry._artH
end

function Look.draw(entry, footX, footY, facing, opts)
  love.graphics.setColor(1, 1, 1, 1)
  if type(entry) ~= "table" or entry.standin then return false end
  local quads = Avatars.quads(entry)
  if not quads then return false end
  local frame, flip = Avatars.pose(entry, facing, 0, false)
  local x = footX - entry.anchor.x
  local y = footY - entry.anchor.y
  local img, redraw
  if entry.palette.mode == "dmg" then
    local colors
    colors, redraw = Look.gen1Colors(opts and opts.playerDef, opts and opts.seed)
    img = imageFor(entry, colors)
  elseif Look.trueColor() then
    img = imageFor(entry, nil)
  else
    local gray = Look.grayEntry(entry)
    local colors
    colors, redraw = Look.objColors()
    img = gray and imageFor(gray, colors)
  end
  if not img then return false end
  blit(img, quads[frame], x, y, entry.w, flip, redraw)
  return true
end

return Look
