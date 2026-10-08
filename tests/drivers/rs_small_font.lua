local U = require("tests.drivers.util")
local X = require("tests.drivers.em_xa_util")

local W, H, SCALE = 120, 64, 4

local function render(lines)
  local FrlgFont = require("src.ui.game3.frlg_font")
  local canvas = love.graphics.newCanvas(W, H)
  canvas:setFilter("nearest", "nearest")
  love.graphics.push("all")
  love.graphics.setCanvas(canvas)
  love.graphics.origin()
  love.graphics.clear(1, 1, 1, 1)
  for _, l in ipairs(lines) do
    l.opts.colors = FrlgFont.COLOR.NORMAL
    FrlgFont.draw(l.text, l.x, l.y, l.opts)
  end
  love.graphics.setCanvas()
  love.graphics.pop()
  return canvas:newImageData()
end

local function ink(img, x0, y0, x1, y1)
  local n = 0
  for y = y0, y1 do
    for x = x0, x1 do
      local r, g, b = img:getPixel(x, y)
      if r + g + b < 2.5 then n = n + 1 end
    end
  end
  return n
end

local function save(img, path)
  local big = love.image.newImageData(W * SCALE, H * SCALE)
  big:mapPixel(function(x, y) return img:getPixel(math.floor(x / SCALE), math.floor(y / SCALE)) end)
  os.execute('mkdir -p "' .. path:match("^(.*)/[^/]+$") .. '" 2>/dev/null')
  local f = io.open(path, "wb")
  f:write(big:encode("png"):getString())
  f:close()
end

return function(game)
  local d = X.new("rs_small_font", "/tmp/rs_small_font")
  local session = X.newGame(d, game, 0)
  if not session then return d.finish() end
  X.settle(game)
  U.wait(10)
  local img = render({
    { text = "aaaa", x = 2, y = 0, opts = { small = true } },
    { text = "RED KRIS MAY", x = 2, y = 16, opts = { small = true } },
    { text = "RED KRIS MAY", x = 2, y = 32, opts = { font = "narrow" } },
    { text = "RED KRIS MAY", x = 2, y = 48, opts = {} },
  })
  save(img, d.dir .. "/rs_small_font_" .. (os.getenv("POKEPORT_VERSION") or "ruby") .. ".png")
  d.check(ink(img, 2, 0, 40, 6) == 0, "small lowercase draws nothing in its cell's top rows (" .. ink(img, 2, 0, 40, 6) .. " px)")
  d.check(ink(img, 2, 8, 40, 15) > 0, "small lowercase still draws")
  return d.finish()
end
