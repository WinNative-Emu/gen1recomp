package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")
local T = require("tests.harness")
local Sync = require("src.core.TrainerIdSync")
local Identity = require("src.core.TrainerIdentity")
local Compat = require("src.save_convert.Compat")
local K = require("tests.save_compat._codec")
for _, version in ipairs({ "red", "blue", "yellow" }) do
  if not pcall(K.gen1Data, version) then
    print("trainer_identity_sync skipped (needs Gen 1 fixture caches; set RED_CACHE, BLUE_CACHE, YELLOW_CACHE)")
    os.exit(0)
  end
end
local G1 = require("tests.fixtures.save.gen1_build")
local G2 = require("tests.fixtures.save.gen2_build")
local Gen3Save = require("src.save_convert.Gen3Save")
local bit = require("bit")
local target = { id = 100, sid = 42, name = "RED" }
K.gen2Data.pokemon = { CYNDAQUIL = { index = 155, dex = 155, name = "CYNDAQUIL" } }

for _, version in ipairs({ "red", "blue", "yellow", "gold", "silver", "crystal" }) do
  local gen = (version == "red" or version == "blue" or version == "yellow") and 1 or 2
  local builder = gen == 1 and G1 or G2
  local spec = { version = version, player = "MAY", playerId = 200,
    party = { builder.mon({ otId = 200, ot = "MAY" }),
      builder.mon({ species = gen == 1 and 0x1F or 252, otId = 200, ot = "MAY" }),
      builder.mon({ otId = 200, ot = "BLUE" }) } }
  local bytes = builder.build(spec)
  local save = assert(K.import(gen, version, bytes))
  local raw = save.party[2].cartRaw
  T.check(raw ~= nil, version .. " exercises an opaque carrier")
  local own = assert(Identity.profile(save, gen))
  local owners = {}; Sync.addOwner(owners, own, gen)
  T.check(Sync.rewriteSave(save, gen, target, owners), version .. " sync prepares")
  local out, why = K.export(gen, version, save, bytes)
  T.check(out ~= nil, version .. " exports: " .. tostring(why))
  if out then
    T.eq(#Compat.check(out, version).errors, 0, version .. " native checksum/reader rules pass")
    local back = assert(K.import(gen, version, out))
    T.eq(back.player.id, 100, version .. " native player ID")
    T.eq(back.player.name, "RED", version .. " native player name")
    T.eq(back.party[1].otId, 100, version .. " native own OT ID")
    T.eq(Identity.monName(back.party[1]), "RED", version .. " native own OT name")
    T.eq(Identity.rawId(back.party[2], gen), 100, version .. " raw carrier native OT ID")
    T.eq(Identity.monName(back.party[2]), "RED", version .. " raw carrier native OT name")
    T.eq(back.party[3].otId, 200, version .. " foreign ID collision retained")
    T.eq(Identity.monName(back.party[3]), "BLUE", version .. " foreign OT retained")
    local at = gen == 1 and 25 or 13
    local afterRaw = back.party[2].cartRaw
    T.eq(afterRaw:sub(1, at - 1) .. afterRaw:sub(at + 4),
      raw:sub(1, at - 1) .. raw:sub(at + 4), version .. " opaque carrier bytes retained apart from OT ID")
  end
end

for _, version in ipairs({ "firered", "leafgreen", "ruby", "sapphire", "emerald" }) do
  local Codec = Gen3Save.forVersion(version)
  local old = { id = 200, sid = 0x1234, name = "MAY" }
  local low = 0x1298
  local pid = bit.bxor(old.id, old.sid, low) * 65536 + low
  local raw = Codec.encodeBoxMon({ species = 25, personality = pid, otId = old.id,
    otSecretId = old.sid, otName = old.name, nickname = "PIKA", language = 2,
    moves = { 84, 45 }, pp = { 11, 23 }, ivs = { hp = 31, atk = 23 },
    exp = 1000, friendship = 120, markings = 5, abilityNum = pid % 2,
    unknown = 0x1234, metLocation = 88 })
  local cart = assert(Codec.decodeBoxMon(raw))
  local native = Codec.toPortMon(cart, false)
  local save = { name = old.name, trainerId = old.id, secretId = old.sid, party = { native } }
  local owners = {}; Sync.addOwner(owners, old, 3)
  T.check(Sync.rewriteSave(save, 3, target, owners), version .. " identity/PID changes prepare")
  cart.personality, cart.otId, cart.otSecretId, cart.otIdRaw, cart.otName =
    native.personality, native.otId, native.otSecretId, nil, native.otName
  local updated = assert(Codec.decodeBoxMon(Codec.encodeBoxMon(cart)))
  T.eq(updated.otId, 100, version .. " encrypted record TID")
  T.eq(updated.otSecretId, 42, version .. " encrypted record SID")
  T.eq(updated.otName, "RED", version .. " native OT name")
  T.eq(updated.isBadEgg, false, version .. " encrypted checksum remains valid")
  T.eq(updated.personality % 25, pid % 25, version .. " native nature retained")
  T.eq(updated.personality % 256, pid % 256, version .. " native gender retained")
  T.eq(updated.abilityNum, cart.abilityNum, version .. " native ability retained")
  T.eq(updated.unknown, 0x1234, version .. " opaque header retained")
  T.eq(updated.pp[1], 11, version .. " PP retained")
  T.eq(updated.metLocation, 88, version .. " met location retained")
  T.check(bit.bxor(updated.otId, updated.otSecretId, updated.personality % 65536,
    math.floor(updated.personality / 65536)) < 8, version .. " native shiny remains shiny")
end
T.finish("trainer_identity_sync_native_codecs")
