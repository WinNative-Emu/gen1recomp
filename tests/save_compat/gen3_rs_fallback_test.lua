package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.harness")
local check, eq = T.check, T.eq
local GameVersion = require("src.core.GameVersion")
local SaveConvert = require("src.save_convert.SaveConvert")
local SaveSerializer = require("src.core.SaveSerializer")
local G = require("src.save_convert.Gen3Save").forVersion("ruby")

local f = io.open(".claude/skills/pygba-headless/assets/pokemon-ruby.sav", "rb")
if not f then
  print("[skip] gen3_rs_fallback_test: real Ruby save not present")
  T.finish()
  return
end
local orig = f:read("*a")
f:close()

local SECTOR, SLOT = 0x1000, 14
local function poke(s, off, b) return s:sub(1, off) .. string.char(b) .. s:sub(off + 2) end
local function flip(s, off) return poke(s, off, (s:byte(off + 1) + 1) % 256) end

local blocks = assert(G.readBlocks(orig))
local cur, old = blocks.slot * SLOT * SECTOR, (1 - blocks.slot) * SLOT * SECTOR

-- pokeruby/src/save.c:536
local b1 = G.readBlocks(flip(orig, cur + 100))
check(b1 ~= nil and b1.olderSlot and b1.slot ~= blocks.slot, "a damaged newest copy falls back to the other slot")
local b2 = G.readBlocks(flip(orig, old + 100))
check(b2 ~= nil and b2.slot == blocks.slot and b2.sb1 == blocks.sb1, "a damaged older copy keeps the newest slot")
local b3, why3 = G.readBlocks(flip(flip(orig, cur + 100), old + 100))
eq(b3, nil, "both copies damaged reads nothing")
eq(why3, "corrupt", "both copies damaged is reported as corrupt")
local _, why4 = G.readBlocks(string.rep("\255", #orig))
eq(why4, "empty", "an erased flash image is empty")
local _, why5 = G.readBlocks(orig:sub(1, 100000))
eq(why5, "size", "a truncated image is refused by size")

for _, case in ipairs({
  { "truncated", orig:sub(1, 100000) }, { "empty string", "" }, { "erased", string.rep("\255", #orig) },
  { "both damaged", flip(flip(orig, cur + 100), old + 100) },
}) do
  local ok, s, err = pcall(SaveConvert.importSav, case[2], "ruby", "ruby")
  check(ok and s == nil and type(err) == "string" and err ~= "", "importSav refuses a " .. case[1] .. " Ruby image without raising")
end

local sec1
for i = 0, SLOT - 1 do
  local base = cur + i * SECTOR
  if orig:byte(base + 0xFF5) + orig:byte(base + 0xFF6) * 256 == 1 then sec1 = base end
end
local off = sec1 + 0x238 + 100 + 0x25
local bad = poke(orig, off, (orig:byte(off + 1) + 0x5A) % 256)
local ck = G.checksum(bad, sec1, 0xF80)
bad = bad:sub(1, sec1 + 0xFF6) .. string.char(ck % 256, math.floor(ck / 256)) .. bad:sub(sec1 + 0xFF9)
local badBlocks = assert(G.readBlocks(bad))
local raw = G.decodePartyMon(badBlocks.sb1:sub(0x238 + 101, 0x238 + 200))
check(raw.isBadEgg and raw.isEgg and not raw.checksumOk, "a party mon with a bad checksum decodes as a Bad Egg")

do
  GameVersion.set("ruby")
  local s = { version = "ruby", party = { { species = 305, isEgg = true, isBadEgg = true, friendship = 9 },
    { species = 1, isEgg = true, friendship = 9 } } }
  require("src.core.game3.daycare").stateOf(s).stepCounter = 254
  require("src.core.game3.rs.daycare").step(s)
  -- pokeruby/src/pokemon_2.c:705
  eq(s.party[1].friendship, 9, "an egg cycle leaves a Bad Egg's counter alone")
  eq(s.party[2].friendship, 8, "an egg cycle still ticks a real egg")
end

local okCache = pcall(function()
  GameVersion.set("ruby")
  local Dataset = require("src.core.game3.dataset")
  assert(Dataset.cache():read("data/generated/gba/pokemon/national.lua"))
end)
if not okCache then
  print("[skip] gen3_rs_fallback_test: no Ruby cache for the conversion half")
  T.finish()
  return
end

local s = assert(SaveConvert.importSav(bad, "ruby", "ruby"))
local egg = s.party[2]
check(egg.isBadEgg and egg.isEgg, "the imported Bad Egg stays an egg")
-- pokeruby/src/pokemon_2.c:342
eq(egg.nickname, "Bad EGG", "the imported Bad Egg carries the native Bad EGG name")
local round = assert(SaveSerializer.decode(SaveSerializer.encode(s)))
local out = assert(SaveConvert.exportSav(round, "ruby", nil))
eq(G.readBlocks(out).sb1, badBlocks.sb1, "a template export keeps the Bad Egg bytes")
round.modData.cartImage = nil
local bare = assert(SaveConvert.exportSav(round, "ruby", nil))
eq(G.readBlocks(bare).sb1:sub(0x238 + 101, 0x238 + 200), badBlocks.sb1:sub(0x238 + 101, 0x238 + 200),
  "a templateless export keeps the Bad Egg bytes")

local good = assert(SaveConvert.importSav(orig, "ruby", "ruby"))
local g2 = assert(SaveSerializer.decode(SaveSerializer.encode(good)))
local same = assert(SaveConvert.exportSav(g2, "ruby", nil))
local a, b = G.readBlocks(orig), G.readBlocks(same)
check(a.sb1 == b.sb1 and a.sb2 == b.sb2 and a.storage == b.storage, "a real Ruby save round trips byte-exact")
g2.modData.cartImage, g2.money = nil, 4242
local fresh = assert(SaveConvert.exportSav(g2, "ruby", nil))
local back = assert(SaveConvert.importSav(fresh, "ruby", "ruby"))
eq(back.money, 4242, "a templateless export reimports its money")
eq(#back.party, #good.party, "a templateless export reimports its party")

local recovered, _, note = SaveConvert.importSav(flip(orig, cur + 100), "ruby", "ruby")
check(recovered ~= nil and type(note) == "string", "a damaged newest copy imports the previous save with a note")

T.finish()
