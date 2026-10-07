package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")
rawset(_G, "print", function() end)

local root, templatesPath = arg[1], arg[2]
assert(root and templatesPath,
  "usage: luajit tools/rs_mystery_event_mons.lua <ruby cache data/generated/gba root> <gen3_event_catalog.py output>")

local GameVersion = require("src.core.GameVersion")
GameVersion.set("ruby")
local Dataset = require("src.core.game3.dataset")
Dataset.cacheRootOverride = root
Dataset.mountExtractRoots()
local Pokemon = require("src.core.game3.pokemon")
Pokemon.install(nil)
local Rng = require("src.core.game3.rng")
local Base64 = require("src.core.Base64")
local Json = require("src.link.Json")
local MysteryGift = require("src.core.game3.mystery_gift")
local bit = require("bit")
local codec = require("src.save_convert.Gen3Save").forVersion("ruby")

local BASE = 0x02000000
local FATEFUL = 0xFF
local POKE_BALL = 4

local function u8(n) return string.char(n % 256) end
local function u16(n) return u8(n) .. u8(math.floor(n / 256)) end
local function u32(n) return u16(n % 65536) .. u16(math.floor(n / 65536)) end

local function crc16(s)
  local crc = 0x1121
  for i = 1, #s do
    crc = bit.bxor(crc, s:byte(i))
    for _ = 1, 8 do
      if bit.band(crc, 1) ~= 0 then crc = bit.bxor(bit.rshift(crc, 1), 0x8408) else crc = bit.rshift(crc, 1) end
    end
  end
  return bit.band(bit.bnot(crc), 0xFFFF)
end

local function giftOf(t)
  local g = { kind = t.egg and "egg" or "mon", species = t.species, ball = POKE_BALL }
  if not t.egg then
    g.level, g.metLocation, g.metLevel = t.level, FATEFUL, t.metLevel
  end
  if #t.moves > 0 then
    g.moves, g.movesOnly = {}, true
    for i, m in ipairs(t.moves) do g.moves[tostring(i)] = m end
  end
  if t.ot and t.ot ~= "" then g.otName = t.ot end
  if t.otNames then g.otNames = t.otNames end
  if t.otIdMax then g.otIdMax = t.otIdMax elseif t.otId then g.otId = t.otId end
  if t.secretIdRandom then g.secretIdRandom = true end
  if t.otGender then g.otGender = t.otGender end
  if t.language then g.language = t.language end
  if t.metGame then g.metGame = t.metGame end
  if t.nickname then g.nickname = t.nickname end
  g.shiny = t.shiny
  if not t.fateful then g.fateful = false end
  if t.nationalRibbon then g.nationalRibbon = true end
  return g
end

local function partyMon(t, gift, seed)
  Rng.SeedRng(seed)
  local session = { version = "ruby", party = {}, name = "PLAYER", trainerId = 0, secretId = 0, gender = 0 }
  local card = MysteryGift.normalizeCard({ flagId = 1019, idNumber = 1, type = 0, gift = gift }, "ruby")
  assert(card, "gift does not normalize: " .. t.key)
  local mon = assert(MysteryGift.createEventMon(session, card.gift), "could not build " .. t.key)
  local cart = codec.fromPortMon(mon, { trainerId = mon.otId, secretId = mon.otSecretId, playerName = mon.otName,
    speciesName = Pokemon.name }, true)
  local bytes = codec.encodePartyMon(cart)
  assert(#bytes == 100, "party mon is not 100 bytes")
  local back = codec.decodePartyMon(bytes)
  assert(back.species == t.species and back.otId == mon.otId, "party mon does not round trip: " .. t.key)
  if t.language == 1 and mon.otName ~= "" then
    assert(codec.decodeString(back.otNameRaw, 0, 7, 1, true) == mon.otName, "Japanese OT lost: " .. t.key)
  end
  return bytes
end

-- pokeruby/include/macros/mystery_event_script.inc:5 me_checkcompat
local function payload(monBytes)
  local mail = string.rep("\0", 36)
  local monAt = 17 + 13 + 5 + 1
  local total = monAt + #monBytes + #mail
  local header = u8(1) .. u32(BASE) .. u16(2) .. u32(2) .. u16(4) .. u32(0x180)
  local body = u8(12) .. u32(BASE + monAt) .. u8(2) .. monBytes .. mail
  local crcOp = u8(16) .. u32(crc16(body)) .. u32(BASE + 30) .. u32(BASE + total)
  local out = header .. crcOp .. body
  assert(#out == total and #out <= 0x7D4)
  return out
end

local templates = Json.decode(io.open(templatesPath, "rb"):read("*a"))
local out = {}
for i, t in ipairs(templates) do
  local gift = giftOf(t)
  local row = { key = t.key, label = t.label, title = t.title, games = t.games, source = t.source,
    idNumber = t.idNumber, egg = t.egg, gift = gift, note = t.note }
  local rs = false
  for _, g in ipairs(t.games) do if g == "ruby" or g == "sapphire" then rs = true end end
  if rs then row.payload = Base64.encode(payload(partyMon(t, gift, 0x47334500 + i))) end
  out[#out + 1] = row
end
io.write(Json.encode(out), "\n")
