local GameVersion = require("src.core.GameVersion")

local Avatars = {}

local readerOverride = nil
local resolved = {}
local tables = {}
local hostBases = {}
local stats = { reads = 0, resolves = 0, images = 0 }

Avatars.GB_FRAME = 16
-- pokered/data/sprites/facings.asm:1
Avatars.GB_STAND = { down = 0, up = 1, left = 2, right = 2 }
Avatars.GB_WALK = { down = 3, up = 4, left = 5, right = 5 }
-- pokeemerald/src/data/object_events/object_event_anims.h:825
Avatars.GBA_STAND = { down = 0, up = 1, left = 2, right = 2 }
Avatars.GBA_WALK_A = { down = 3, up = 5, left = 7, right = 7 }
Avatars.GBA_WALK_B = { down = 4, up = 6, left = 8, right = 8 }

local GB1 = { "red", "blue", "yellow" }
local GB2 = { "gold", "silver", "crystal" }
local GB2_FEMALE = { "crystal" }
local FRLG = { "firered", "leafgreen" }
local RSE = { "ruby", "sapphire", "emerald" }
local RSE_CLASSES = { "emerald" }

local SPRITE_GB1 = "assets/generated/sprites/red.png"
-- pokecrystal/data/sprites/player_sprites.asm:1
local SPRITE_GB2 = { [0] = { png = "assets/generated/sprites/chris.png", id = "SPRITE_CHRIS" },
                     [1] = { png = "assets/generated/sprites/kris.png", id = "SPRITE_KRIS" } }
local GB2_SPRITES = "data/generated/sprites.lua"
local GB2_PALETTES = "data/generated/palettes.lua"
local GB2_DAYTIME = "DAY"
local OW_ROOT = "data/generated/gba/ow/"
local UNION_AVATARS = "data/generated/gba/union_room/avatars.lua"

local function defaultReader(version, rel)
  local prefix = GameVersion.cachePrefix(version)
  return require("src.import.CacheFs").readAt(prefix .. rel)
end

function Avatars.directoryReader(roots)
  local CacheBlob = require("src.import.CacheBlob")
  return function(version, rel)
    local root = type(roots) == "table" and roots[version] or roots
    if type(root) ~= "string" then return nil end
    local path = root .. "/" .. GameVersion.cachePrefix(version) .. rel
    local f = io.open(path, "rb")
    if not f then return nil end
    local body = f:read("*a")
    f:close()
    return CacheBlob.decode(path, body)
  end
end

function Avatars.setReader(fn)
  readerOverride = fn
  Avatars.reset()
end

function Avatars.reset()
  resolved = {}
  tables = {}
  hostBases = {}
  stats = { reads = 0, resolves = 0, images = 0 }
end

function Avatars.refresh()
  resolved = {}
  tables = {}
  hostBases = {}
end

function Avatars.stats()
  return { reads = stats.reads, resolves = stats.resolves, images = stats.images }
end

local function read(version, rel)
  stats.reads = stats.reads + 1
  local fn = readerOverride or defaultReader
  local ok, bytes = pcall(fn, version, rel)
  if ok and type(bytes) == "string" and #bytes > 0 then return bytes end
  return nil
end

local function evaluate(body, label)
  if type(body) ~= "string" then return nil end
  local chunk = (loadstring or load)(body, "@" .. label)
  if not chunk then return nil end
  if setfenv then setfenv(chunk, {}) end
  local ok, value = pcall(chunk)
  return ok and type(value) == "table" and value or nil
end

local function tableAt(version, rel)
  local key = version .. "|" .. rel
  local hit = tables[key]
  if hit ~= nil then return hit or nil end
  local t = evaluate(read(version, rel), version .. "/" .. rel)
  tables[key] = t or false
  return t
end

function Avatars.pngSize(bytes)
  if type(bytes) ~= "string" or #bytes < 24 or bytes:sub(1, 8) ~= "\137PNG\r\n\26\n" then
    return nil
  end
  local function u32(i)
    local a, b, c, d = bytes:byte(i, i + 3)
    return ((a * 256 + b) * 256 + c) * 256 + d
  end
  return u32(17), u32(21)
end

local function ordered(first, family)
  local out, seen = {}, {}
  if first then
    for _, v in ipairs(family) do
      if v == first then out[1], seen[v] = v, true end
    end
  end
  for _, v in ipairs(family) do
    if not seen[v] then out[#out + 1] = v end
  end
  return out
end

local function classIndex(style)
  local n = type(style) == "string" and tonumber(style:match("^g3:(%d+)$")) or nil
  if n and n >= 0 and n <= 7 then return math.floor(n) end
  return nil
end

function Avatars.family(p)
  local version = p and p.game
  local gen = GameVersion.VERSIONS[version or ""] and GameVersion.generation(version) or tonumber(p and p.gen)
  local female = p and p.gender == 1
  if gen == 1 then return "gb1", ordered(version, GB1) end
  if gen == 2 then
    if female and version == "crystal" then return "gb2f", ordered(version, GB2_FEMALE) end
    return "gb2m", ordered(version, GB2)
  end
  if gen == 3 then
    local cls = classIndex(p.style)
    local frlg = version == "firered" or version == "leafgreen"
    if frlg then return cls and "frlg:class" or "frlg:player", ordered(version, FRLG) end
    if cls then return "rse:class", ordered(version, RSE_CLASSES) end
    return "rse:player", ordered(version, RSE)
  end
  return nil, {}
end

local function rects(w, h, count)
  local out = {}
  for i = 0, count - 1 do out[i] = { x = 0, y = i * h, w = w, h = h } end
  return out
end

local function gb2PaletteFor(version, spriteId)
  local sprites = tableAt(version, GB2_SPRITES)
  local palettes = tableAt(version, GB2_PALETTES)
  local def = sprites and sprites[spriteId]
  local id = def and tonumber(def.paletteId)
  local objects = palettes and palettes.objects
  local day = type(objects) == "table" and objects[GB2_DAYTIME] or nil
  local colors = day and id and day[id + 1]
  if type(colors) ~= "table" or #colors ~= 4 then return nil end
  return { mode = "gbc", colors = colors, name = def.palette }
end

local function gb2Palette(version, gender)
  return gb2PaletteFor(version, SPRITE_GB2[gender].id)
end

local function gbEntry(version, gen, path, palette)
  local bytes = read(version, path)
  local w, h = Avatars.pngSize(bytes)
  if not w or w ~= Avatars.GB_FRAME or h < Avatars.GB_FRAME * 6 then return nil end
  local frames = math.floor(h / Avatars.GB_FRAME)
  return {
    version = version, gen = gen, layout = "gb",
    source = { kind = "png", rel = path, bytes = bytes },
    w = w, h = Avatars.GB_FRAME, frames = frames, sheetW = w, sheetH = h,
    rects = rects(w, Avatars.GB_FRAME, frames),
    anchor = { x = w / 2, y = Avatars.GB_FRAME },
    palette = palette,
  }
end

local function frlgPlayer(gender)
  local V = require("src.import.gba.versions_frlg")
  return gender == 1 and V.OW_PLAYER_FEMALE or V.OW_PLAYER_MALE
end

local function gbaGid(version, kind, p)
  local gender = p.gender == 1 and 1 or 0
  if kind == "frlg:player" then return frlgPlayer(gender) end
  if kind == "rse:player" then
    local manifest = tableAt(version, OW_ROOT .. "manifest.lua")
    local rows = manifest and manifest.avatars and manifest.avatars.player
    for _, row in ipairs(type(rows) == "table" and rows or {}) do
      if row.state == "NORMAL" then return gender == 1 and row.female or row.male end
    end
    return nil
  end
  local av = tableAt(version, UNION_AVATARS)
  local ids = av and av.gfx_ids
  local row = ids and (gender == 1 and ids.female or ids.male)
  local n = classIndex(p.style)
  return row and n and row[n + 1] or nil
end

local function gbaEntry(version, kind, p)
  local gid = kind == "host" and p.gid or gbaGid(version, kind, p)
  if not gid then return nil end
  local manifest = tableAt(version, OW_ROOT .. "manifest.lua")
  local info = manifest and manifest.sprites and manifest.sprites[gid]
  if type(info) ~= "table" then return nil end
  local w, h, n = tonumber(info.width), tonumber(info.height), tonumber(info.frameCount)
  if not (w and h and n) or n < 9 then return nil end
  local rel = OW_ROOT .. gid .. ".rgba"
  local bytes = read(version, rel)
  if not bytes or #bytes ~= w * h * n * 4 then return nil end
  return {
    version = version, gen = 3, layout = "gba", gid = gid,
    source = { kind = "rgba", rel = rel, bytes = bytes },
    w = w, h = h, frames = n, sheetW = w, sheetH = h * n,
    rects = rects(w, h, n),
    anchor = { x = w / 2, y = h },
    palette = { mode = "rgba" },
  }
end

local function candidate(kind, version, p)
  if kind == "gb1" then
    return gbEntry(version, 1, SPRITE_GB1, { mode = "dmg" })
  end
  if kind == "gb2m" or kind == "gb2f" then
    local gender = kind == "gb2f" and 1 or 0
    local palette = gb2Palette(version, gender)
    if not palette then return nil end
    return gbEntry(version, 2, SPRITE_GB2[gender].png, palette)
  end
  return gbaEntry(version, kind, p)
end

function Avatars.key(p)
  if type(p) ~= "table" then return "?" end
  return table.concat({ tostring(p.game), tostring(p.style or "player"),
                        tostring(p.gender == 1 and 1 or 0) }, "|")
end

-- pokered/constants/sprite_constants.asm:4
Avatars.HOST_GB1 = {
  [0] = { "SPRITE_YOUNGSTER", "SPRITE_COOLTRAINER_M", "SPRITE_HIKER", "SPRITE_BIKER",
          "SPRITE_SUPER_NERD", "SPRITE_GAMBLER", "SPRITE_GENTLEMAN", "SPRITE_FISHER",
          "SPRITE_SAILOR", "SPRITE_SWIMMER", "SPRITE_ROCKER", "SPRITE_SCIENTIST",
          "SPRITE_MIDDLE_AGED_MAN" },
  [1] = { "SPRITE_BRUNETTE_GIRL", "SPRITE_LITTLE_GIRL", "SPRITE_GIRL", "SPRITE_COOLTRAINER_F",
          "SPRITE_BEAUTY", "SPRITE_CHANNELER", "SPRITE_MIDDLE_AGED_WOMAN" },
}
-- pokecrystal/constants/sprite_constants.asm:4
Avatars.HOST_GB2 = {
  [0] = { "SPRITE_YOUNGSTER", "SPRITE_BUG_CATCHER", "SPRITE_COOLTRAINER_M", "SPRITE_BIKER",
          "SPRITE_BLACK_BELT", "SPRITE_FISHER", "SPRITE_GENTLEMAN", "SPRITE_POKEFAN_M",
          "SPRITE_ROCKER", "SPRITE_SAILOR", "SPRITE_SCIENTIST", "SPRITE_SUPER_NERD",
          "SPRITE_SWIMMER_GUY", "SPRITE_SAGE" },
  [1] = { "SPRITE_LASS", "SPRITE_COOLTRAINER_F", "SPRITE_BEAUTY", "SPRITE_POKEFAN_F",
          "SPRITE_SWIMMER_GIRL", "SPRITE_TEACHER", "SPRITE_TWIN" },
}
-- pokefirered/include/constants/event_objects.h:22
Avatars.HOST_FRLG = {
  [0] = { 16, 18, 19, 20, 25, 26, 27, 30, 32, 39, 41, 52, 53, 54, 55, 56, 57, 61, 62 },
  [1] = { 17, 22, 23, 24, 28, 29, 31, 35, 40, 42, 58 },
}
-- pokeemerald/include/constants/event_objects.h:14
Avatars.HOST_RSE = {
  [0] = { 7, 9, 13, 19, 23, 31, 35, 36, 37, 38, 39, 44, 46, 48, 49, 50, 55 },
  [1] = { 8, 10, 14, 16, 32, 40, 45, 47 },
}

local function hashOf(text)
  local h = 5381
  for i = 1, #text do h = (h * 33 + text:byte(i)) % 4294967296 end
  return h
end

function Avatars.pickKey(p)
  if type(p) ~= "table" then return "?" end
  return table.concat({ tostring(p.game), tostring(math.floor(tonumber(p.trainerId) or 0)),
                        tostring(p.name or ""), tostring(p.gender == 1 and 1 or 0) }, "|")
end

function Avatars.hostOf(host)
  local version = type(host) == "table" and host.version or host or GameVersion.get()
  if not GameVersion.VERSIONS[version or ""] then return nil end
  return version, GameVersion.generation(version)
end

function Avatars.hostList(version, gender)
  local gen = GameVersion.generation(version)
  local lists
  if gen == 1 then lists = Avatars.HOST_GB1
  elseif gen == 2 then lists = Avatars.HOST_GB2
  elseif version == "firered" or version == "leafgreen" then lists = Avatars.HOST_FRLG
  else lists = Avatars.HOST_RSE end
  return lists[gender == 1 and 1 or 0]
end

local function hostBase(version, ref)
  local key = version .. "|" .. tostring(ref)
  local hit = hostBases[key]
  if hit ~= nil then return hit or nil end
  local gen = GameVersion.generation(version)
  local entry
  if gen == 3 then
    entry = gbaEntry(version, "host", { gid = ref })
  else
    local sprites = tableAt(version, GB2_SPRITES)
    local def = sprites and sprites[ref]
    if type(def) == "table" and def.walker and type(def.image) == "string" then
      local palette = { mode = "dmg" }
      if gen == 2 then palette = gb2PaletteFor(version, ref) end
      if palette then entry = gbEntry(version, gen, def.image, palette) end
    end
  end
  if entry then entry.hostRef = ref end
  hostBases[key] = entry or false
  return entry
end

Avatars.hostEntry = hostBase

local function hostStandin(p, host, need, family)
  local version = Avatars.hostOf(host)
  if not version then return nil end
  local list = Avatars.hostList(version, p.gender)
  if not list or #list == 0 then return nil end
  local start = hashOf(Avatars.pickKey(p)) % #list
  for i = 0, #list - 1 do
    local base = hostBase(version, list[(start + i) % #list + 1])
    if base then
      local out = {}
      for k, v in pairs(base) do out[k] = v end
      out.hostStandin = true
      out.hostVersion = version
      out.hostGen = base.gen
      out.gen = GameVersion.VERSIONS[p.game or ""] and GameVersion.generation(p.game) or tonumber(p.gen)
      out.need = need
      out.family = family
      return out
    end
  end
  return nil
end

function Avatars.resolve(p, host)
  local key = Avatars.key(p)
  local hit = resolved[key]
  if hit and not hit.hostStandin and not hit.standin then return hit end
  local hostVersion = Avatars.hostOf(host)
  local pickKey = "host|" .. tostring(hostVersion) .. "|" .. Avatars.pickKey(p)
  local picked = resolved[pickKey]
  if hit and picked then return picked end
  stats.resolves = stats.resolves + 1
  local kind, versions = Avatars.family(p)
  local entry
  if hit then
    kind, versions = hit.family, hit.need
  elseif kind then
    for _, version in ipairs(versions) do
      entry = candidate(kind, version, p)
      if entry then break end
    end
  end
  if entry then
    entry.key = key
    entry.family = kind
    resolved[key] = entry
    return entry
  end
  if not hit then resolved[key] = { key = key, standin = true, family = kind, need = versions } end
  local gen = GameVersion.VERSIONS[p and p.game or ""] and GameVersion.generation(p.game) or nil
  entry = type(p) == "table" and hostStandin(p, host, versions, kind) or nil
  if entry then
    entry.key = pickKey
  else
    entry = { key = pickKey, standin = true, family = kind, gen = gen, need = versions }
  end
  resolved[pickKey] = entry
  return entry
end

function Avatars.pose(entry, facing, walkPhase, stepFlip)
  facing = facing or "down"
  if type(entry) ~= "table" or entry.standin then return 0, facing == "right" end
  local flip = facing == "right"
  local frame
  if entry.layout == "gba" then
    if walkPhase == 1 then
      frame = stepFlip and Avatars.GBA_WALK_A[facing] or Avatars.GBA_WALK_B[facing]
    end
    frame = frame or Avatars.GBA_STAND[facing] or 0
  else
    if walkPhase == 1 then
      frame = Avatars.GB_WALK[facing]
      if (facing == "down" or facing == "up") and stepFlip then flip = true end
    end
    frame = frame or Avatars.GB_STAND[facing] or 0
  end
  if frame >= entry.frames then frame = 0 end
  return frame, flip
end

local function shadeIndex(r)
  if r > 0.83 then return 0 end
  if r > 0.5 then return 1 end
  if r > 0.17 then return 2 end
  return 3
end

local function bakeShades(id, colors)
  id:mapPixel(function(_, _, r, g, b, a)
    local s = shadeIndex(r)
    if s == 0 then return r, g, b, 0 end
    local c = colors and colors[s + 1]
    if not c then return r, g, b, a end
    return c[1] / 255, c[2] / 255, c[3] / 255, a
  end)
end

function Avatars.imageData(entry)
  if type(entry) ~= "table" or entry.standin then return nil end
  if entry._imageData then return entry._imageData end
  if not (love and love.image and love.image.newImageData) then return nil end
  local src = entry.source
  local id
  if src.kind == "rgba" then
    id = love.image.newImageData(entry.sheetW, entry.sheetH, "rgba8", src.bytes)
  else
    local data = love.filesystem.newFileData(src.bytes, "avatar.png")
    id = love.image.newImageData(data)
  end
  entry._imageData = id
  return id
end

function Avatars.image(entry, colors)
  if type(entry) ~= "table" or entry.standin then return nil end
  local paletteKey = colors and table.concat({ tostring(colors[2] and colors[2][1]),
    tostring(colors[3] and colors[3][1]), tostring(colors[4] and colors[4][1]),
    tostring(colors[2] and colors[2][2]), tostring(colors[3] and colors[3][2]),
    tostring(colors[4] and colors[4][3]) }, ",") or "own"
  entry._images = entry._images or {}
  local img = entry._images[paletteKey]
  if img then return img end
  if not (love and love.graphics and love.graphics.newImage) then return nil end
  local base = Avatars.imageData(entry)
  if not base then return nil end
  local id = base
  if entry.palette.mode ~= "rgba" then
    id = base.clone and base:clone() or base
    bakeShades(id, colors or entry.palette.colors)
  end
  img = love.graphics.newImage(id)
  if img.setFilter then img:setFilter("nearest", "nearest") end
  stats.images = stats.images + 1
  entry._images[paletteKey] = img
  return img
end

function Avatars.quads(entry)
  if type(entry) ~= "table" or entry.standin then return nil end
  if entry._quads then return entry._quads end
  if not (love and love.graphics and love.graphics.newQuad) then return nil end
  local q = {}
  for i = 0, entry.frames - 1 do
    local r = entry.rects[i]
    q[i] = love.graphics.newQuad(r.x, r.y, r.w, r.h, entry.sheetW, entry.sheetH)
  end
  entry._quads = q
  return q
end

function Avatars.draw(entry, footX, footY, facing, walkPhase, stepFlip, scale, colors)
  scale = scale or 1
  if type(entry) ~= "table" or entry.standin then return false end
  local img, quads = Avatars.image(entry, colors), Avatars.quads(entry)
  if not (img and quads) then return false end
  local frame, flip = Avatars.pose(entry, facing, walkPhase, stepFlip)
  local x = footX - entry.anchor.x * scale
  local y = footY - entry.anchor.y * scale
  if flip then
    love.graphics.draw(img, quads[frame], x + entry.w * scale, y, 0, -scale, scale)
  else
    love.graphics.draw(img, quads[frame], x, y, 0, scale, scale)
  end
  return true
end

Avatars.STANDIN_H = 16

function Avatars.drawStandin()
  return false
end

return Avatars
