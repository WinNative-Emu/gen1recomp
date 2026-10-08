-- Quiet, black-keyed animated layer behind the launcher UI.
local LauncherThemeVideo = {}
LauncherThemeVideo.__index = LauncherThemeVideo

local SHEET_PATH = "assets/launcher/current_theme_sheet.bin"
local HEADER_SIZE = 14

function LauncherThemeVideo.new()
  local self = setmetatable({}, LauncherThemeVideo)
  local ok, err = pcall(function()
    assert(love.graphics.getImageFormats().r8, "r8 textures unsupported")
    local packed = assert(love.filesystem.read(SHEET_PATH))
    local data = love.data.decompress("string", "zlib", packed)
    local fw, fh, cols, rows, frames, fps, sheets =
      love.data.unpack("<HHHHHHH", data)
    local sheetW, sheetH = cols * fw, rows * fh
    local sheetBytes = sheetW * sheetH
    self.images = {}
    for s = 1, sheets do
      local first = HEADER_SIZE + (s - 1) * sheetBytes + 1
      local pixels = love.image.newImageData(sheetW, sheetH, "r8",
        data:sub(first, first + sheetBytes - 1))
      local image = love.graphics.newImage(pixels)
      pixels:release()
      image:setFilter("linear", "linear")
      self.images[s] = image
    end
    self.quad = love.graphics.newQuad(0, 0, fw, fh, sheetW, sheetH)
    self.frameW, self.frameH = fw, fh
    self.cols, self.perSheet = cols, cols * rows
    self.frames, self.fps = frames, fps
    self.time, self.frame, self.sheet = 0, -1, 1
    self.shader = love.graphics.newShader([[
      vec4 effect(vec4 color, Image texture, vec2 uv, vec2 screen) {
        float gray = Texel(texture, uv).r;
        float coverage = smoothstep(0.012, 0.10, gray);
        return vec4(vec3(gray), coverage * 0.12) * color;
      }
    ]])
  end)
  if not ok then
    self:release()
    print("[launcher theme video] unavailable: " .. tostring(err))
    return nil
  end
  return self
end

function LauncherThemeVideo:update(dt)
  if not self.images then return end
  self.time = (self.time + (dt or 0)) % (self.frames / self.fps)
  local frame = math.floor(self.time * self.fps) % self.frames
  if frame ~= self.frame then
    self.frame = frame
    self.sheet = math.floor(frame / self.perSheet) + 1
    local slot = frame % self.perSheet
    self.quad:setViewport((slot % self.cols) * self.frameW,
      math.floor(slot / self.cols) * self.frameH, self.frameW, self.frameH)
  end
end

function LauncherThemeVideo:draw()
  local g = love.graphics
  local width, height = g.getDimensions()
  local vw, vh = self.frameW, self.frameH
  local scale = math.max(width / vw, height / vh)

  g.push("all")
  g.origin()
  g.setScissor()
  g.setBlendMode("alpha", "alphamultiply")
  g.setColor(1, 1, 1, 1)
  g.setShader(self.shader)
  g.draw(self.images[self.sheet], self.quad, (width - vw * scale) / 2,
    (height - vh * scale) / 2, 0, scale, scale)
  g.pop()
end

function LauncherThemeVideo:release()
  if self.images then
    for _, image in ipairs(self.images) do image:release() end
    self.images = nil
  end
  for _, key in ipairs({ "quad", "shader" }) do
    local resource = self[key]
    if resource then resource:release(); self[key] = nil end
  end
end

return LauncherThemeVideo
