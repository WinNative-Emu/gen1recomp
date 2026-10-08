package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")
local T = require("tests.harness")
local Avatars = require("src.online.union.Avatars")
local Badge = require("src.online.union.Badge")
local Participant = require("src.online.union.Participant")
local GameVersion = require("src.core.GameVersion")

local function u32(n)
  return string.char(math.floor(n / 16777216) % 256, math.floor(n / 65536) % 256,
                     math.floor(n / 256) % 256, n % 256)
end

local function png(w, h)
  return "\137PNG\r\n\26\n" .. u32(13) .. "IHDR" .. u32(w) .. u32(h) .. "\2\0\0\0\0"
end

local function lua(t)
  local out = {}
  local function emit(v)
    if type(v) == "table" then
      out[#out + 1] = "{"
      for k, x in pairs(v) do
        out[#out + 1] = "[" .. (type(k) == "string" and ("%q"):format(k) or tostring(k)) .. "]="
        emit(x)
        out[#out + 1] = ","
      end
      out[#out + 1] = "}"
    elseif type(v) == "string" then
      out[#out + 1] = ("%q"):format(v)
    else
      out[#out + 1] = tostring(v)
    end
  end
  emit(t)
  return "return " .. table.concat(out)
end

local GB2_PALETTES = [[return { objects = { DAY = {
  { { 255, 255, 255 }, { 255, 160, 120 }, { 200, 40, 40 }, { 0, 0, 0 } },
  { { 255, 255, 255 }, { 150, 180, 255 }, { 40, 60, 220 }, { 0, 0, 0 } } } } }]]
local FRLG_UNION = [[return { gfx_ids = { male = { 41, 54, 39, 19, 19, 20, 25, 26 },
  female = { 42, 58, 40, 22, 23, 24, 28, 29 } } }]]
local E_UNION = [[return { gfx_ids = { male = { 33, 44, 31, 35, 37, 36, 65, 66 },
  female = { 34, 40, 32, 47, 47, 14, 20, 45 } } }]]

local function rgba(w, h, n) return ("\0"):rep(w * h * n * 4) end

local function gbSprites(lists, extra, gen)
  local t = {}
  for _, list in pairs(lists) do
    for _, id in ipairs(list) do
      t[id] = { walker = true, frames = 6, paletteId = 1, palette = "PAL_OW_BLUE",
                image = "assets/generated/sprites/" .. id:gsub("^SPRITE_", ""):lower() .. ".png" }
    end
  end
  for _, id in ipairs(extra) do
    t[id] = { walker = true, frames = 6, paletteId = 0, palette = "PAL_OW_RED",
              image = "assets/generated/sprites/" .. id:gsub("^SPRITE_", ""):lower() .. ".png" }
  end
  return t
end

local function gbaManifest(lists, own, withAvatars)
  local sprites = {}
  for gid, n in pairs(own) do sprites[gid] = { width = 16, height = 32, frameCount = n } end
  for _, list in pairs(lists) do
    for _, gid in ipairs(list) do sprites[gid] = { width = 16, height = 32, frameCount = 9 } end
  end
  local t = { sprites = sprites }
  if withAvatars then t.avatars = { player = { { state = "NORMAL", male = 0, female = 89 } } } end
  return t
end

local log = {}

local function synthetic(imported)
  local files = {}
  local function put(version, rel, body) files[version .. "|" .. rel] = body end
  local gb1 = gbSprites(Avatars.HOST_GB1, { "SPRITE_RED", "SPRITE_OAK", "SPRITE_NURSE" })
  for _, v in ipairs({ "red", "blue", "yellow" }) do
    put(v, "data/generated/sprites.lua", lua(gb1))
    for _, def in pairs(gb1) do put(v, def.image, png(16, 96)) end
  end
  local gb2 = gbSprites(Avatars.HOST_GB2, { "SPRITE_CHRIS", "SPRITE_KRIS", "SPRITE_ELM", "SPRITE_CLERK" })
  gb2.SPRITE_CHRIS.paletteId, gb2.SPRITE_KRIS.paletteId = 0, 1
  gb2.SPRITE_KRIS.palette = "PAL_OW_BLUE"
  for _, v in ipairs({ "gold", "silver", "crystal" }) do
    put(v, "data/generated/sprites.lua", lua(gb2))
    put(v, "data/generated/palettes.lua", GB2_PALETTES)
    for id, def in pairs(gb2) do
      if id ~= "SPRITE_KRIS" or v == "crystal" then put(v, def.image, png(16, 96)) end
    end
  end
  for _, v in ipairs({ "firered", "leafgreen" }) do
    local m = gbaManifest(Avatars.HOST_FRLG, { [0] = 20, [7] = 20, [64] = 9, [71] = 9 }, false)
    put(v, "data/generated/gba/ow/manifest.lua", lua(m))
    put(v, "data/generated/gba/union_room/avatars.lua", FRLG_UNION)
    for gid, info in pairs(m.sprites) do
      put(v, "data/generated/gba/ow/" .. gid .. ".rgba", rgba(16, 32, info.frameCount))
    end
  end
  for _, v in ipairs({ "ruby", "sapphire", "emerald" }) do
    local m = gbaManifest(Avatars.HOST_RSE, { [0] = 18, [89] = 18, [33] = 9, [58] = 9 }, true)
    put(v, "data/generated/gba/ow/manifest.lua", lua(m))
    for gid, info in pairs(m.sprites) do
      if gid ~= 33 or v == "emerald" then
        put(v, "data/generated/gba/ow/" .. gid .. ".rgba", rgba(16, 32, info.frameCount))
      end
    end
  end
  put("emerald", "data/generated/gba/union_room/avatars.lua", E_UNION)
  local set = {}
  for _, v in ipairs(imported) do set[v] = true end
  return function(version, rel)
    local body = set[version] and files[version .. "|" .. rel] or nil
    if body then log[#log + 1] = version .. "|" .. rel end
    return body
  end
end

local function who(game, gender, style, tid, name)
  return { game = game, gen = Participant.genOf(game), gender = gender or 0, style = style or "player",
           trainerId = tid or 1, name = name or "ASH" }
end

local function needs(e)
  return table.concat(e.need or {}, ",")
end

local function inList(list, v)
  for _, x in ipairs(list) do if x == v then return true end end
  return false
end

do
  Avatars.setReader(synthetic(GameVersion.ORDER))
  local host = { version = "red" }
  local r = Avatars.resolve(who("red"), host)
  T.check(not r.standin and not r.hostStandin, "a Gen 1 player resolves to the real sprite")
  T.eq(r.version, "red", "the Gen 1 sprite comes from the participant's own version")
  T.eq(r.source.rel, "assets/generated/sprites/red.png", "the Gen 1 player is the RED sheet")
  T.eq(r.layout, "gb", "Gen 1 sheets use the GB layout")
  T.eq(r.frames, 6, "a GB walker sheet has 6 frames")
  T.eq(r.w .. "x" .. r.h, "16x16", "GB frames are 16x16")
  T.eq(r.anchor.y, 16, "the anchor is the feet")
  T.eq(r.palette.mode, "dmg", "Gen 1 sprites keep DMG shades")
  T.eq(r.rects[3].y, 48, "frame rects step down the sheet")
  T.eq(Avatars.resolve(who("yellow"), host).version, "yellow", "Yellow uses its own sheet when imported")
  local g = Avatars.resolve(who("gold"), host)
  T.eq(g.source.rel, "assets/generated/sprites/chris.png", "a Gen 2 male uses the Chris sheet")
  T.eq(g.palette.mode, "gbc", "Gen 2 sprites carry a GBC palette")
  T.eq(g.palette.name, "PAL_OW_RED", "the Chris sheet wears PAL_OW_RED")
  T.eq(#g.palette.colors, 4, "the palette has four colors")
  local k = Avatars.resolve(who("crystal", 1), host)
  T.eq(k.source.rel, "assets/generated/sprites/kris.png", "a Crystal female uses the Kris sheet")
  T.eq(k.palette.name, "PAL_OW_BLUE", "the Kris sheet wears PAL_OW_BLUE")
  local fr = Avatars.resolve(who("firered"), host)
  T.eq(fr.gid, 0, "a FireRed male player is gfx 0")
  T.eq(fr.layout, "gba", "Gen 3 sheets use the GBA layout")
  T.eq(fr.palette.mode, "rgba", "Gen 3 sheets are baked RGBA")
  T.eq(fr.h, 32, "Gen 3 frames are 32 tall")
  T.eq(Avatars.resolve(who("leafgreen", 1), host).gid, 7, "a LeafGreen female player is gfx 7")
  T.eq(Avatars.resolve(who("firered", 0, "g3:3"), host).gid, 19, "a FRLG class token picks the union class sprite")
  T.eq(Avatars.resolve(who("emerald", 0, "g3:0"), host).gid, 33, "an Emerald class token picks the Emerald class sprite")
  T.eq(Avatars.resolve(who("ruby", 1), host).gid, 89, "a Ruby female player is May")
  T.eq(Avatars.resolve(who("sapphire"), host).version, "sapphire", "Sapphire uses its own sheet")
end

do
  Avatars.setReader(synthetic({ "red" }))
  local host = { version = "red" }
  T.eq(Avatars.resolve(who("blue"), host).version, "red", "Blue's player shows from an imported Red")
  T.eq(Avatars.resolve(who("yellow"), host).version, "red", "Yellow's player shows from an imported Red")
  log = {}
  local g = Avatars.resolve(who("gold", 0, "player", 4242, "ETHAN"), host)
  T.check(g.hostStandin and not g.standin, "a Gen 2 player without a Gen 2 import wears a Red NPC")
  T.eq(g.version, "red", "the host stand-in comes from the viewer's game")
  T.eq(g.layout, "gb", "the host stand-in is in the viewer's native layout")
  T.eq(g.palette.mode, "dmg", "a Red viewer's stand-in keeps DMG shades")
  T.check(inList(Avatars.HOST_GB1[0], g.hostRef), "a male stand-in is a curated Gen 1 trainer (" .. tostring(g.hostRef) .. ")")
  T.eq(needs(g), "gold,silver,crystal", "the stand-in still names the imports for the real look")
  T.eq(g.gen, 2, "the stand-in keeps the source gen for the badge")
  T.eq(g.anchor.y, 16, "the stand-in is anchored at the feet")
  local foreign = false
  for _, l in ipairs(log) do if l:sub(1, 4) ~= "red|" then foreign = true end end
  T.check(not foreign and #log > 0, "the stand-in reads only the active game's cache")
  local e = Avatars.resolve(who("emerald", 1, "player", 77, "MAY"), host)
  T.check(e.hostStandin and e.version == "red", "a Gen 3 player is never drawn with a Gen 3 sheet the viewer lacks")
  T.check(inList(Avatars.HOST_GB1[1], e.hostRef), "a female stand-in is a curated Gen 1 trainer")
  T.check(Avatars.draw(e, 40, 40, "down", 0, false, 1), "the stand-in draws like a sprite")
  T.eq(Avatars.drawStandin(), false, "nothing draws a pawn")
end

do
  local host = { version = "red" }
  local picks = {}
  for tid = 1, 40 do
    Avatars.setReader(synthetic({ "red" }))
    local p = who("gold", 0, "player", tid, "T" .. tid)
    local a = Avatars.resolve(p, host)
    local b = Avatars.resolve(p, host)
    Avatars.reset()
    Avatars.setReader(synthetic({ "red" }))
    local c = Avatars.resolve(p, host)
    if a.hostRef ~= b.hostRef or a.hostRef ~= c.hostRef then picks.unstable = true end
    picks[a.hostRef] = true
  end
  T.check(not picks.unstable, "the same participant gets the same pick across frames and sessions")
  local n = 0
  for k in pairs(picks) do if k ~= "unstable" then n = n + 1 end end
  T.check(n >= 5, "different participants spread across the curated list (" .. n .. ")")
  Avatars.setReader(synthetic({ "red" }))
  local x = Avatars.resolve(who("gold", 0, "player", 9, "AAA"), host)
  local y = Avatars.resolve(who("gold", 0, "player", 9, "AAA"), { version = "red" })
  T.check(x == y, "a repeated resolve returns the cached stand-in")
end

do
  Avatars.setReader(synthetic({ "gold" }))
  local host = { version = "gold" }
  local k = Avatars.resolve(who("crystal", 1, "player", 5, "KRIS"), host)
  T.check(k.hostStandin, "Kris needs Crystal: a Gold viewer shows a Gold NPC")
  T.eq(needs(k), "crystal", "the female stand-in names Crystal only")
  T.check(inList(Avatars.HOST_GB2[1], k.hostRef), "the Gold stand-in is a curated female trainer")
  T.eq(k.palette.mode, "gbc", "a Gold viewer's stand-in wears a GBC palette")
  T.eq(k.version, "gold", "the Gold stand-in comes from Gold")
  T.eq(Avatars.resolve(who("crystal", 0), host).version, "gold", "Crystal's Chris shows from Gold")
  T.eq(Avatars.resolve(who("silver"), host).version, "gold", "Silver's Chris shows from Gold")
  local r = Avatars.resolve(who("red", 0, "player", 3, "RED"), host)
  T.check(r.hostStandin and r.gen == 1 and inList(Avatars.HOST_GB2[0], r.hostRef),
    "a Gen 1 player seen from Gold wears a Gold trainer and keeps badge 1")
end

do
  Avatars.setReader(synthetic({ "ruby", "firered" }))
  local host = { version = "ruby" }
  T.eq(Avatars.resolve(who("emerald"), host).version, "ruby", "Emerald's Brendan shows from Ruby")
  local cls = Avatars.resolve(who("emerald", 0, "g3:0", 8, "WALLY"), host)
  T.check(cls.hostStandin and cls.version == "ruby", "an Emerald class without Emerald wears a Ruby NPC")
  T.eq(needs(cls), "emerald", "the class stand-in names Emerald")
  T.check(inList(Avatars.HOST_RSE[0], cls.gid), "the Ruby stand-in is a curated RS trainer gfx")
  T.eq(cls.layout, "gba", "a Ruby viewer's stand-in is a GBA sheet")
  T.eq(cls.palette.mode, "rgba", "a Ruby viewer's stand-in is RGBA")
  T.eq(Avatars.resolve(who("leafgreen", 0, "g3:3"), host).version, "firered", "LeafGreen classes show from FireRed")
  local r = Avatars.resolve(who("red", 1, "player", 2, "LEAF"), { version = "firered" })
  T.check(r.hostStandin and inList(Avatars.HOST_FRLG[1], r.gid) and r.version == "firered",
    "a Gen 1 player seen from FireRed wears a curated FRLG trainer")
end

do
  local banned1 = { SPRITE_RED = 1, SPRITE_BLUE = 1, SPRITE_OAK = 1, SPRITE_NURSE = 1, SPRITE_CLERK = 1,
    SPRITE_GIOVANNI = 1, SPRITE_BROCK = 1, SPRITE_MISTY = 1, SPRITE_LANCE = 1, SPRITE_AGATHA = 1,
    SPRITE_BRUNO = 1, SPRITE_LORELEI = 1, SPRITE_KOGA = 1, SPRITE_MOM = 1, SPRITE_DAISY = 1,
    SPRITE_MR_FUJI = 1, SPRITE_ROCKET = 1, SPRITE_ROCKET_GIRL = 1, SPRITE_SEEL = 1, SPRITE_BIRD = 1,
    SPRITE_MONSTER = 1, SPRITE_FAIRY = 1, SPRITE_PIKACHU = 1, SPRITE_CHRIS = 1, SPRITE_KRIS = 1,
    SPRITE_RIVAL = 1, SPRITE_ELM = 1, SPRITE_RECEPTIONIST = 1, SPRITE_LINK_RECEPTIONIST = 1,
    SPRITE_GYM_GUIDE = 1, SPRITE_FALKNER = 1, SPRITE_WHITNEY = 1, SPRITE_KIMONO_GIRL = 1,
    SPRITE_SILPH_WORKER_F = 1, SPRITE_OFFICER = 1, SPRITE_OFFICER_JENNY = 1, SPRITE_WAITER = 1 }
  local bad = {}
  for _, lists in ipairs({ Avatars.HOST_GB1, Avatars.HOST_GB2 }) do
    for _, list in pairs(lists) do
      for _, id in ipairs(list) do if banned1[id] then bad[#bad + 1] = id end end
    end
  end
  local bannedFrlg = { [0] = 1, [7] = 1, [14] = 1, [15] = 1, [49] = 1, [50] = 1, [64] = 1, [65] = 1,
    [66] = 1, [68] = 1, [71] = 1, [72] = 1, [73] = 1, [74] = 1, [75] = 1, [76] = 1, [77] = 1, [78] = 1, [79] = 1 }
  local bannedRse = { [0] = 1, [4] = 1, [28] = 1, [41] = 1, [58] = 1, [59] = 1, [60] = 1, [64] = 1,
    [70] = 1, [71] = 1, [72] = 1, [73] = 1, [74] = 1, [75] = 1, [83] = 1, [85] = 1, [89] = 1 }
  for g = 0, 1 do
    for _, gid in ipairs(Avatars.HOST_RSE[g]) do if bannedRse[gid] then bad[#bad + 1] = "rse" .. gid end end
    for _, gid in ipairs(Avatars.HOST_FRLG[g]) do if bannedFrlg[gid] then bad[#bad + 1] = "frlg" .. gid end end
  end
  T.eq(table.concat(bad, ","), "", "the curated lists hold no story characters, staff, Pokemon or objects")
end

do
  Avatars.setReader(synthetic({ "red", "gold" }))
  local host = { version = "red" }
  local p = who("red")
  Avatars.resolve(p, host)
  local before = Avatars.stats()
  for _ = 1, 200 do Avatars.resolve(p, host) end
  for _ = 1, 200 do Avatars.resolve(who("gold"), host) end
  local after = Avatars.stats()
  T.eq(after.reads - before.reads, 3, "repeated resolves read each source file once")
  for _ = 1, 50 do Avatars.resolve(who("crystal", 1, "player", 6, "K"), host) end
  T.eq(Avatars.stats().resolves, 3, "a stand-in is cached per participant too")
  local readsBefore = Avatars.stats().reads
  local entry = Avatars.resolve(p, host)
  for _ = 1, 60 do Avatars.draw(entry, 40, 40, "down", 0, false, 2) end
  T.eq(Avatars.stats().reads, readsBefore, "drawing never reads the cache")
  T.eq(Avatars.stats().images, 1, "drawing builds the image once")
end

do
  local gb = { layout = "gb", frames = 6 }
  local f, flip = Avatars.pose(gb, "right", 0, false)
  T.eq(f .. tostring(flip), "2true", "GB right is the left frame flipped")
  f, flip = Avatars.pose(gb, "down", 1, true)
  T.eq(f .. tostring(flip), "3true", "GB alternate down step flips the walk frame")
  local gba = { layout = "gba", frames = 9 }
  T.eq((Avatars.pose(gba, "up", 1, true)), 5, "GBA north step A is frame 5")
  T.eq((Avatars.pose(gba, "left", 1, false)), 8, "GBA west step B is frame 8")
  T.eq((Avatars.pose(gba, "up", 0)), 1, "GBA stands north on frame 1")
end

do
  T.eq(select(1, Badge.size(1)), 9, "the badge is 9 px at 1x")
  T.eq(select(2, Badge.size(3)), 27, "the badge scales by integer factors")
  local function sig(d)
    local out = {}
    for _, p in ipairs(Badge.pixels(d, 3)) do
      if p.c == Badge.STYLES[3].digit then out[#out + 1] = p.x .. ":" .. p.y end
    end
    return table.concat(out, ",")
  end
  T.check(sig(1) ~= sig(2) and sig(2) ~= sig(3) and sig(1) ~= sig(3), "the three digits draw differently")
  T.check(#sig(1) > 0, "a digit has pixels")
  local ring = 0
  for _, p in ipairs(Badge.pixels(2, 1)) do if p.c == Badge.STYLES[1].ring then ring = ring + 1 end end
  T.eq(ring, 24, "the ring is a closed 9x9 circle")
  T.eq(Badge.STYLES[1].fill[2], 248, "the Gen 1 style uses DMG shades")
  Badge.reset()
  for _ = 1, 100 do Badge.draw(10, 10, 1, 1, 2) end
  Badge.draw(10, 10, 2, 1, 2)
  T.eq(Badge.builds(), 2, "badge images are built once per digit and style")
  T.check(not Badge.draw(0, 0, 4, 1), "only 1, 2 and 3 have badges")
end

local function cacheRoot(version)
  local home = os.getenv("HOME")
  if not home then return nil end
  local prefix = GameVersion.cachePrefix(version)
  local probe = GameVersion.generation(version) == 3 and "data/generated/gba/ow/manifest.lua"
    or "assets/generated/sprites/red.png"
  if GameVersion.generation(version) == 2 then probe = "assets/generated/sprites/chris.png" end
  for _, base in ipairs({ home .. "/Library/Application Support/LOVE", home .. "/.local/share/love" }) do
    for _, id in ipairs({ os.getenv("POKEPORT_IDENTITY") or "", "g1r-" .. version, "pokeport-test-caches" }) do
      if id ~= "" then
        local root = base .. "/" .. id
        local f = io.open(root .. "/" .. prefix .. probe, "rb")
        if f then
          f:close()
          return root
        end
      end
    end
  end
  return nil
end

do
  local roots, list = {}, {}
  for _, v in ipairs(GameVersion.ORDER) do
    roots[v] = cacheRoot(v)
    if roots[v] then list[#list + 1] = v end
  end
  if #list == 0 then
    print("[skip] no imported caches for the real avatar checks")
  else
    Avatars.setReader(Avatars.directoryReader(roots))
    for _, v in ipairs(list) do
      local gen = GameVersion.generation(v)
      local e = Avatars.resolve(who(v, 0))
      T.check(not e.standin, v .. ": the real player sprite resolves from the cache")
      if not e.standin then
        T.eq(e.gen, gen, v .. ": the sprite comes from the participant's own gen")
        T.check(e.frames >= (gen == 3 and 9 or 6), v .. ": the sheet has every walk frame")
        if gen == 2 then T.eq(#e.palette.colors, 4, v .. ": the real Gen 2 palette has four colors") end
      end
      local missing = {}
      for g = 0, 1 do
        for _, ref in ipairs(Avatars.hostList(v, g)) do
          local h = Avatars.hostEntry(v, ref)
          if not h or h.frames < (gen == 3 and 9 or 6) then missing[#missing + 1] = tostring(ref) end
        end
      end
      T.eq(table.concat(missing, ","), "", v .. ": every curated stand-in is a walking sprite in the cache")
      if v == "crystal" then
        local k = Avatars.resolve(who("crystal", 1))
        T.eq(k.source and k.source.rel, "assets/generated/sprites/kris.png", "crystal: the real Kris sheet resolves")
      end
      if v == "firered" or v == "leafgreen" or v == "emerald" then
        for n = 0, 7 do
          local c = Avatars.resolve(who(v, n % 2, "g3:" .. n))
          T.check(not c.standin and c.layout == "gba", v .. ": union class " .. n .. " resolves")
        end
      end
    end
  end
  Avatars.setReader(nil)
end

T.finish()
