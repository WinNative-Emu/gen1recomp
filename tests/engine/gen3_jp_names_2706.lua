package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")
local T = require("tests.harness")
local Gen3Save = require("src.save_convert.Gen3Save")

local NICK = string.char(0x70, 0x85, 0x53, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF)
local OT = string.char(0x51, 0x52, 0x5A, 0xFF, 0xFF, 0xFF, 0xFF)
local JP = 1 -- pokeemerald/include/constants/global.h:20

for _, v in ipairs({ "sapphire", "ruby", "emerald", "firered", "leafgreen" }) do
  local c = Gen3Save.forVersion(v)
  T.eq(c.decodeString(NICK, 0, 10, JP), "ミュウ", v .. " Japanese nickname decodes as kana")
  T.eq(c.decodeString(OT, 0, 7, JP), "アイコ", v .. " Japanese OT name decodes as kana")
  local mon = { personality = 0xABCDEF01, otId = 57342, otSecretId = 1, otName = "アイコ", nickname = "ミュウ",
    language = JP, species = 151, ivs = {}, evs = {}, contest = {}, moves = { 1, 0, 0, 0 }, pp = { 35, 0, 0, 0 } }
  local ok, bytes = pcall(c.encodeBoxMon, mon)
  T.check(ok, v .. " Japanese mon encodes")
  if ok then
    T.eq(bytes:sub(9, 18), NICK, v .. " nickname bytes are the cart's kana codes")
    T.eq(bytes:sub(0x15, 0x1B), OT, v .. " OT bytes are the cart's kana codes")
    T.eq(bytes:byte(0x13), JP, v .. " language byte kept")
    local back = c.decodeBoxMon(bytes)
    T.eq(back.nickname, "ミュウ", v .. " decoded nickname")
    T.eq(back.otName, "アイコ", v .. " decoded OT name")
    T.eq(c.encodeBoxMon(back), bytes, v .. " Japanese mon round-trips its bytes")
  end
  local stale = { personality = 1, language = JP, nickname = "{70}<{53}", otName = "¿¡Í",
    cartExtra = { nicknameRaw = { NICK:byte(1, -1) }, otNameRaw = { OT:byte(1, -1) } } }
  local rok, repaired = pcall(Gen3Save.repairJapaneseNames, { stale })
  T.check(rok and repaired, v .. " stale English-decoded import is repaired")
  T.eq(stale.nickname, "ミュウ", v .. " repaired nickname")
  T.eq(stale.otName, "アイコ", v .. " repaired OT name")
end

T.finish("gen3_jp_names_2706")
