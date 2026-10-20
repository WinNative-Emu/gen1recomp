local Logger = require("src.core.Logger")

local PaletteMods = {}

local records = {}
local lookup = nil
local revision = 0
local warned = {}

PaletteMods.MON_SUFFIX = "MON"
PaletteMods.SHINY_SUFFIX = "MON_SHINY"
PaletteMods.OBJECT_PREFIX = "OBJ_EVENT_GFX_"

function PaletteMods.idKind(id)
  if type(id) ~= "string" then return nil end
  local shiny = id:match("^(.+)MON_SHINY$")
  if shiny then return "monShiny", shiny end
  local mon = id:match("^(.+)MON$")
  if mon then return "mon", mon end
  local obj = id:match("^OBJ_EVENT_GFX_(.+)$")
  if obj then return "object", id end
  return nil
end

local function channel(v)
  v = tonumber(v) or 0
  if v < 0 then return 0 end
  if v > 255 then return 255 end
  return v
end

local function colourOf(entry)
  if type(entry) ~= "table" then return nil end
  local r, g, b = entry[1] or entry.r, entry[2] or entry.g, entry[3] or entry.b
  if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then return nil end
  return { channel(r), channel(g), channel(b) }
end

local function rampOf(value)
  local list = type(value) == "table" and (value.colors or value) or nil
  if type(list) ~= "table" or #list ~= 4 then return nil end
  local ramp = {}
  for i = 1, 4 do
    ramp[i] = colourOf(list[i])
    if not ramp[i] then return nil end
  end
  return ramp
end

PaletteMods.rampOf = rampOf

local function gbaChannel(v)
  local c5 = math.floor(v / 255 * 31 + 0.5)
  return math.floor(c5 * 255 / 31 + 0.5)
end

local function luma(r, g, b)
  return 0.299 * r + 0.587 * g + 0.114 * b
end

local function mapper(ramp, lo, hi)
  local memo = {}
  local span = hi - lo
  return function(r, g, b)
    local key = r * 65536 + g * 256 + b
    local hit = memo[key]
    if hit then return hit[1], hit[2], hit[3] end
    local t = span > 0 and (luma(r, g, b) - lo) / span or 1
    if t < 0 then t = 0 elseif t > 1 then t = 1 end
    local p = (1 - t) * 3
    local i = math.floor(p)
    if i > 2 then i = 2 end
    local f = p - i
    local a, c = ramp[i + 1], ramp[i + 2]
    local or_ = gbaChannel(a[1] + (c[1] - a[1]) * f)
    local og = gbaChannel(a[2] + (c[2] - a[2]) * f)
    local ob = gbaChannel(a[3] + (c[3] - a[3]) * f)
    memo[key] = { or_, og, ob }
    return or_, og, ob
  end
end

function PaletteMods.recolourRgba(rgba, ramp)
  if type(rgba) ~= "string" or not ramp then return rgba end
  local n = math.floor(#rgba / 4)
  local lo, hi = 255, 0
  local byte = string.byte
  for i = 0, n - 1 do
    local o = i * 4
    if byte(rgba, o + 4) > 0 then
      local l = luma(byte(rgba, o + 1), byte(rgba, o + 2), byte(rgba, o + 3))
      if l < lo then lo = l end
      if l > hi then hi = l end
    end
  end
  if hi < lo then return rgba end
  local map = mapper(ramp, lo, hi)
  local out = {}
  local char = string.char
  for i = 0, n - 1 do
    local o = i * 4
    local a = byte(rgba, o + 4)
    if a > 0 then
      local r, g, b = map(byte(rgba, o + 1), byte(rgba, o + 2), byte(rgba, o + 3))
      out[i + 1] = char(r, g, b, a)
    else
      out[i + 1] = rgba:sub(o + 1, o + 4)
    end
  end
  return table.concat(out) .. rgba:sub(n * 4 + 1)
end

local function to8(v)
  v = math.floor((tonumber(v) or 0) * 255 + 0.5)
  if v < 0 then return 0 end
  if v > 255 then return 255 end
  return v
end

local function wordRgb(word)
  word = tonumber(word) or 0
  return math.floor((word % 32) * 255 / 31 + 0.5),
    math.floor((math.floor(word / 32) % 32) * 255 / 31 + 0.5),
    math.floor((math.floor(word / 1024) % 32) * 255 / 31 + 0.5)
end

local function rgbWord(r, g, b)
  return math.floor(r / 255 * 31 + 0.5) + math.floor(g / 255 * 31 + 0.5) * 32
    + math.floor(b / 255 * 31 + 0.5) * 1024
end

local function remapWords(words, map)
  if type(words) ~= "table" then return words end
  local out = {}
  for k, v in pairs(words) do out[k] = v end
  for i = 1, 15 do
    if type(words[i]) == "number" then
      local r, g, b = map(wordRgb(words[i]))
      out[i] = rgbWord(r, g, b)
    end
  end
  return out
end

function PaletteMods.recolourImageData(data, ramp, palettes)
  if not (data and ramp) then return nil end
  local lo, hi = 255, 0
  data:mapPixel(function(_, _, r, g, b, a)
    if a > 0 then
      local l = luma(to8(r), to8(g), to8(b))
      if l < lo then lo = l end
      if l > hi then hi = l end
    end
    return r, g, b, a
  end)
  if hi < lo then return nil end
  local map = mapper(ramp, lo, hi)
  local copy = data:clone()
  copy:mapPixel(function(_, _, r, g, b, a)
    if a <= 0 then return r, g, b, a end
    local nr, ng, nb = map(to8(r), to8(g), to8(b))
    return nr / 255, ng / 255, nb / 255, a
  end)
  local remapped = {}
  for key, words in pairs(palettes or {}) do remapped[key] = remapWords(words, map) end
  return copy, remapped
end

function PaletteMods.install(data)
  records = {}
  lookup = nil
  revision = revision + 1
  local source = type(data) == "table" and data.gen3Palettes or nil
  if type(source) ~= "table" then return false end
  for id, value in pairs(source) do
    local kind, name = PaletteMods.idKind(id)
    local ramp = rampOf(value)
    if kind and ramp then
      records[#records + 1] = { id = id, kind = kind, name = name, ramp = ramp }
    elseif not warned[id] then
      warned[id] = true
      Logger.warn("[gen3] palette %s ignored: expected a four colour record "
        .. "named <SPECIES>MON, <SPECIES>MON_SHINY or OBJ_EVENT_GFX_<NAME>", tostring(id))
    end
  end
  table.sort(records, function(a, b) return a.id < b.id end)
  return #records > 0
end

function PaletteMods.revision() return revision end

function PaletteMods.active() return #records > 0 end

local function warnOnce(key, fmt, ...)
  if warned[key] then return end
  warned[key] = true
  Logger.warn(fmt, ...)
end

local function build()
  local out = { mon = {}, monShiny = {}, object = {} }
  local P = package.loaded["src.core.game3.pokemon"]
  local C
  local okC, Constants = pcall(require, "src.core.game3.constants")
  if okC then
    local Runtime = package.loaded["src.core.game3.runtime"]
    local session = Runtime and Runtime.getSession and Runtime.getSession()
    local okA, set = pcall(Constants.active, session)
    C = okA and set or nil
  end
  for _, rec in ipairs(records) do
    if rec.kind == "object" then
      local gid = C and C.event_objects and C.event_objects.byName[rec.name]
      if gid then
        out.object[gid] = rec.ramp
      else
        warnOnce("gfx:" .. rec.id, "[gen3] palette %s names no overworld graphic in this game", rec.id)
      end
    else
      local species = P and P.speciesFromName and P.speciesFromName(rec.name)
      if species then
        out[rec.kind][species] = rec.ramp
      else
        warnOnce("sp:" .. rec.id, "[gen3] palette %s names no species in this game", rec.id)
      end
    end
  end
  return out
end

local function resolved()
  if not lookup then lookup = build() end
  return lookup
end

function PaletteMods.monRamp(species, shiny)
  if #records == 0 then return nil end
  local set = resolved()
  species = tonumber(species)
  if not species then return nil end
  if shiny then return set.monShiny[species] end
  return set.mon[species]
end

function PaletteMods.objectRamp(gid)
  if #records == 0 then return nil end
  gid = tonumber(gid)
  if not gid then return nil end
  return resolved().object[gid]
end

function PaletteMods.recolourPic(rgba, species, shiny)
  local ramp = PaletteMods.monRamp(species, shiny)
  if not ramp then return rgba end
  return PaletteMods.recolourRgba(rgba, ramp)
end

function PaletteMods.recolourIcon(rgba, species)
  local ramp = PaletteMods.monRamp(species, false)
  if not ramp then return rgba end
  return PaletteMods.recolourRgba(rgba, ramp)
end

function PaletteMods.recolourOwSprite(gid, spr)
  local ramp = PaletteMods.objectRamp(gid)
  if not (ramp and spr and spr.imageData and love and love.graphics) then return spr end
  if spr.nativeImageData then return spr end
  local data, palettes = PaletteMods.recolourImageData(spr.imageData, ramp,
    { palette = spr.palette, mappedReflectionPalette = spr.mappedReflectionPalette })
  if not data then return spr end
  local image = love.graphics.newImage(data)
  image:setFilter("nearest", "nearest")
  spr.nativeImageData, spr.nativeImage = spr.imageData, spr.image
  spr.image, spr.imageData = image, data
  if palettes.palette then spr.palette = palettes.palette end
  if palettes.mappedReflectionPalette then
    spr.mappedReflectionPalette = palettes.mappedReflectionPalette
  end
  return spr
end

return PaletteMods
