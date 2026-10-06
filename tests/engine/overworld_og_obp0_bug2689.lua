package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local GameVersion = require("src.core.GameVersion")
local PaletteFX = require("src.render.PaletteFX")
local Assets = require("src.render.Assets")
local SpriteRenderer = require("src.render.SpriteRenderer")

local prevVersion, prevMode, prevDark = GameVersion.get(), PaletteFX.mode, PaletteFX.darkWorld()
local realImageData, realImage = Assets.imageData, Assets.image
local realNewImage = love.graphics.newImage

local SHADES = { 1.0, 0.66, 0.33, 0.0 }

Assets.imageData = function(path)
  local probe = { path = path }
  function probe:mapPixel(fn)
    self.mapped = {}
    for i, v in ipairs(SHADES) do
      local r, g, b, a = fn(0, 0, v, v, v, 1)
      self.mapped[i] = { r, g, b, a }
    end
  end
  return probe
end
Assets.image = function(path)
  return realNewImage(path)
end
love.graphics.newImage = function(src)
  local img = realNewImage(src)
  if type(src) == "table" and src.mapped then img.mapped = src.mapped end
  return img
end

local serial = 0
local function freshPath(tag)
  serial = serial + 1
  return "bug2689/" .. tag .. "_" .. serial .. ".png"
end

local function rgb(c) return string.format("%d,%d,%d", c[1], c[2], c[3]) end
local function mappedRgb(m)
  return string.format("%d,%d,%d", math.floor(m[1] * 255 + 0.5),
    math.floor(m[2] * 255 + 0.5), math.floor(m[3] * 255 + 0.5))
end

local function stubSprite(tag)
  return setmetatable({ def = { image = freshPath(tag) } }, SpriteRenderer)
end

local function expectRamp(img, ramp, label)
  local m = img and img.mapped
  check(m ~= nil, label .. ": bake ran through mapPixel")
  if not m then return end
  eq(m[1][4], 0, label .. ": OBJ color 0 is transparent")
  eq(mappedRgb(m[2]), rgb(ramp[1]), label .. ": OBJ color 1 -> rOBP0 shade")
  eq(mappedRgb(m[3]), rgb(ramp[2]), label .. ": OBJ color 2 -> rOBP0 shade")
  eq(mappedRgb(m[4]), rgb(ramp[3]), label .. ": OBJ color 3 -> rOBP0 shade")
end

local function lastRedrawImage()
  local list = PaletteFX.spriteRedraws()
  local e = list[#list]
  return e and e.image
end

for _, version in ipairs({ "red", "blue" }) do
  GameVersion.set(version)
  PaletteFX.setMode("ogred")
  PaletteFX.setDarkWorld(false)
  PaletteFX.setFadeObp(nil)
  local base = PaletteFX.ogObjBase()
  local lit = { base[1], base[2], base[4] }

  expectRamp(stubSprite(version):resolveImage(), lit,
             version .. " lit resolveImage")

  PaletteFX.clearSpriteRedraws()
  PaletteFX.setPass("world")
  local ok, err = pcall(SpriteRenderer.drawTile, stubSprite(version),
                        freshPath(version .. "_tile"), 0, 0, false)
  PaletteFX.setPass(nil)
  check(ok, version .. " drawTile runs headless" .. (ok and "" or (": " .. tostring(err))))
  expectRamp(lastRedrawImage(), lit, version .. " lit drawTile redraw")
  PaletteFX.clearSpriteRedraws()

  PaletteFX.setFadeObp({ [0] = 0, [1] = 1, [2] = 2, [3] = 3 })
  expectRamp(stubSprite(version):resolveImage(), { base[2], base[3], base[4] },
             version .. " FadePal3 rOBP0 $E4 step")
  PaletteFX.setFadeObp({ [0] = 0, [1] = 0, [2] = 1, [3] = 3 })
  expectRamp(stubSprite(version):resolveImage(), lit,
             version .. " FadePal4 rOBP0 $D0 step")
  PaletteFX.setFadeObp(nil)

  PaletteFX.setDarkWorld(true)
  local _, group = PaletteFX.ogObjWorld()
  check(tostring(group):match("dark$") ~= nil,
        version .. " dark map keeps the FadePal2 OBJ shift (" .. tostring(group) .. ")")
  expectRamp(stubSprite(version):resolveImage(), { base[4], base[4], base[4] },
             version .. " dark map rOBP0 3,3,3,2")
  PaletteFX.setDarkWorld(false)

  local _, litGroup = PaletteFX.ogObjWorld()
  local _, rawGroup = PaletteFX.ogObj()
  check(litGroup ~= rawGroup,
        version .. " overworld bake group differs from the $E4 title/battle bake")
end

love.graphics.newImage = realNewImage
Assets.imageData, Assets.image = realImageData, realImage
PaletteFX.setFadeObp(nil)
PaletteFX.setDarkWorld(prevDark)
GameVersion.set(prevVersion)
PaletteFX.setMode(prevMode)

T.finish("overworld OG rOBP0 #2689")
