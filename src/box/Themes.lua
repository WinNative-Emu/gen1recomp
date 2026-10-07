local Theme = require("src.ui.kit.Theme")
local Themes = {}
local COLORS = { Forest = { 38, 107, 56 }, Sky = { 51, 92, 148 },
  Brick = { 107, 66, 79 }, Sunset = { 130, 66, 43 }, Ocean = { 26, 99, 117 } }
local images, count, retired = {}, 0, {}
Themes.MAX_IMAGES = 4

local function stamp()
  local kit = package.loaded["src.ui.kit.Kit"]
  return kit and kit.time
end

local function retire(image)
  if image and image.release then retired[#retired + 1] = { image = image, at = stamp() } end
end

local function flush(all)
  local now, kept = stamp(), {}
  for _, row in ipairs(retired) do
    if all or row.at ~= now then pcall(row.image.release, row.image) else kept[#kept + 1] = row end
  end
  retired = kept
end

function Themes.forget(path)
  local image = images[path]
  if image == nil then return end
  images[path] = nil
  if image then
    count = count - 1
    retire(image)
  end
end

function Themes.reset()
  for _, image in pairs(images) do retire(image or nil) end
  images, count = {}, 0
end

function Themes.release()
  Themes.reset()
  flush(true)
end

function Themes.draw(box, x, y, w, h, scale)
  if #retired > 0 then flush(false) end
  if box.theme == "Showcase" and box.wallpaper and love.graphics.newImage then
    local image = images[box.wallpaper]
    if image == nil then
      if count >= Themes.MAX_IMAGES then Themes.reset() end
      local ok, value = pcall(function()
        local fs = require("src.core.SaveData").persistenceFs()
        local bytes = fs and fs.read and fs.read(box.wallpaper)
        if type(bytes) ~= "string" then return false end
        local file = love.filesystem.newFileData(bytes, box.wallpaper)
        local loaded = love.graphics.newImage(file)
        if file.release then file:release() end
        return loaded
      end)
      image = ok and value or false
      images[box.wallpaper] = image
      if image then count = count + 1 end
    end
    if image then
      local old = love.graphics.getScissor and { love.graphics.getScissor() }
      local left, top, right, bottom = x, y, x + w, y + h
      if old and #old == 4 then
        left, top = math.max(left, old[1]), math.max(top, old[2])
        right, bottom = math.min(right, old[1] + old[3]), math.min(bottom, old[2] + old[4])
      end
      if love.graphics.setScissor then love.graphics.setScissor(left, top, math.max(0, right-left), math.max(0, bottom-top)) end
      Theme.col({ 255, 255, 255 }, 0.3)
      love.graphics.draw(image, x, y, 0, w / image:getWidth(), h / image:getHeight())
      if love.graphics.setScissor then
        if old and #old == 4 then love.graphics.setScissor(unpack(old)) else love.graphics.setScissor() end
      end
      return
    end
  end
  local color = COLORS[box.theme]
  if not color then return end
  Theme.fillRounded(x, y, w, h, color, 0.35, 8)
  local cell = 32 * (scale or 1)
  for row = 0, math.ceil(h / cell) - 1 do
    for col = 0, math.ceil(w / cell) - 1 do
      if (row + col) % 2 == 0 then
        Theme.fillRounded(x + col * cell, y + row * cell, math.min(cell - 2, w-col*cell),
          math.min(cell - 2, h-row*cell), color, 0.16, box.theme == "Brick" and 2 or 8)
      end
    end
  end
end
require("src.render.Assets").register({ invalidate = Themes.reset, release = Themes.release })
return Themes
