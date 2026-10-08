package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")
local T = require("tests.harness")
local Avatars = require("src.online.union.Avatars")
local Badge = require("src.online.union.Badge")
local Presence = require("src.world.gen2.UnionRoomPresence")
local Tag = require("src.ui.gen2.union.Tag")

local function u32(n)
  return string.char(math.floor(n / 16777216) % 256, math.floor(n / 65536) % 256,
                     math.floor(n / 256) % 256, n % 256)
end

local function png(w, h)
  return "\137PNG\r\n\26\n" .. u32(13) .. "IHDR" .. u32(w) .. u32(h) .. "\2\0\0\0\0"
end

local FILES = {
  ["red|assets/generated/sprites/red.png"] = png(16, 96),
  ["crystal|assets/generated/sprites/kris.png"] = png(16, 96),
  ["crystal|data/generated/sprites.lua"] = [[return { SPRITE_KRIS = { paletteId = 1, palette = "PAL_OW_BLUE" } }]],
  ["crystal|data/generated/palettes.lua"] = [[return { objects = { DAY = {
    { { 255, 255, 255 }, { 255, 160, 120 }, { 200, 40, 40 }, { 0, 0, 0 } },
    { { 255, 255, 255 }, { 150, 180, 255 }, { 40, 60, 220 }, { 0, 0, 0 } } } } }]],
  ["firered|data/generated/gba/ow/manifest.lua"] = [[return { sprites = {
    [19] = { width = 16, height = 32, frameCount = 10 } } }]],
  ["firered|data/generated/gba/union_room/avatars.lua"] = [[return { gfx_ids = {
    male = { 41, 54, 39, 19, 19, 20, 25, 26 }, female = { 42, 58, 40, 22, 23, 24, 28, 29 } } }]],
  ["firered|data/generated/gba/ow/19.rgba"] = ("\0"):rep(16 * 32 * 10 * 4),
}

local reads = 0
Avatars.setReader(function(version, rel)
  reads = reads + 1
  return FILES[version .. "|" .. rel]
end)
Badge.reset()

local drawn = {}
local realDraw = love.graphics.draw
love.graphics.draw = function(img, quad, x, y, r, sx, sy)
  drawn[#drawn + 1] = { img = img, x = x, y = y, sx = sx, sy = sy }
  return realDraw(img, quad, x, y, r, sx, sy)
end

local session = { lost = false }
local people = {
  { slot = 1, id = "00000001", name = "RED", game = "red", gen = 1, gender = 0, style = "player" },
  { slot = 2, id = "00000002", name = "KRIS", game = "crystal", gen = 2, gender = 1, style = "player" },
  { slot = 3, id = "00000003", name = "LEAF", game = "firered", gen = 3, gender = 0, style = "g3:3" },
  { slot = 4, id = "00000004", name = "MAY", game = "emerald", gen = 3, gender = 1, style = "g3:5" },
}
local ents = {}
for i, p in ipairs(people) do
  ents[i] = Presence.Entity.new(session, p)
  ents[i].alpha = 1
end

T.check(not ents[1].avatar.standin and ents[1].avatar.layout == "gb", "the Gen 1 member has its own sprite")
T.check(not ents[2].avatar.standin and ents[2].avatar.palette.mode == "gbc", "the Crystal member has her GBC palette")
T.check(not ents[3].avatar.standin and ents[3].avatar.h == 32, "the FRLG class member is 16x32")
T.check(ents[4].avatar.standin, "a member from a game with no cache is a stand-in")
T.eq(ents[4].avatar.need and ents[4].avatar.need[1], "emerald", "the stand-in names the import it needs")

for _, e in ipairs(ents) do e:draw(0, 0, 3) end
local reads0, images0, badges0 = reads, Avatars.stats().images, Badge.builds()
for _ = 1, 200 do
  for _, e in ipairs(ents) do e:draw(0, 0, 3) end
end
T.eq(reads, reads0, "drawing members reads no cache files after the first frame")
T.eq(Avatars.stats().images, images0, "member images are built once")
T.eq(Badge.builds(), badges0, "badge images are built once")

drawn = {}
ents[3]:draw(10, 20, 2)
local sprite = drawn[1]
T.check(sprite ~= nil, "the GBA member draws")
T.eq(sprite.y, 20 + (ents[3].py + Presence.FOOT) * 2 - 32 * 2, "a 16x32 member stands on its feet")
T.eq(sprite.sx, 2, "members draw at the world's integer scale")

drawn = {}
ents[1]:draw(0, 0, 1)
T.eq(drawn[1].y, ents[1].py + Presence.FOOT - 16, "a 16x16 member lands where Gen 2 sprites land")

local w1, h1 = Tag.size("RED", false)
local w2, h2 = Tag.size("RED", true)
T.check(w2 > w1 and h2 > h1, "the name tag is wider than the bare badge")
T.check(w2 <= 48, "a 3-letter tag fits between two columns")

love.graphics.draw = realDraw
T.finish("union_gen2_presence_draw")
