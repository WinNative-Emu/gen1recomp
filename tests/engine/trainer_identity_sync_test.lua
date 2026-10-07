package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")
local T = require("tests.harness")
local bit = require("bit")
local Sync = require("src.core.TrainerIdSync")
local Identity = require("src.core.TrainerIdentity")
local SaveData = require("src.core.SaveData")
local Store = require("src.box.Store")
local Records = require("src.box.Records")
local Gifts = require("src.box.Gifts")
local Transaction = require("src.box.Transaction")
local Pokemon = require("src.core.game3.pokemon")
local Engine = require("src.core.game3.battle.engine")
local target = { id = 100, sid = 42, name = "RED" }
local other = { id = 200, sid = 0x1234, name = "MAY" }
local owners = {}
Sync.addOwner(owners, target, 3)
Sync.addOwner(owners, other, 3)
local function mon(id, sid, name, pid, species)
  return { species = species or 25, otId = id, otSecretId = sid, otName = name,
    ot = name, personality = pid or 12345, nickname = "PIKA", moves = { 84 },
    level = 100, hp = 99, maxHp = 99, ivs = { hp = 31 }, opaque = "keep" }
end
local function nativeShiny(m)
  return bit.bxor(m.otId, m.otSecretId, m.personality % 65536, math.floor(m.personality / 65536)) < 8
end
local function shinyMon(profile, low, species)
  return mon(profile.id, profile.sid, profile.name,
    bit.bxor(profile.id, profile.sid, low) * 65536 + low, species)
end

for gen = 1, 3 do
  local own = mon(other.id, other.sid, other.name)
  local foreignName = mon(other.id, other.sid, "BLUE")
  local foreignSid = mon(other.id, other.sid + 1, other.name)
  local save = { version = gen == 1 and "red" or gen == 2 and "gold" or "emerald",
    player = { id = other.id, name = other.name }, name = other.name,
    trainerId = other.id, secretId = other.sid, party = { own, foreignName, foreignSid },
    boxes = { { Store.copy(own) } }, daycare = { mon = Store.copy(own) },
    storage = { boxes = { [3] = { mons = { [7] = Store.copy(own) } } } },
    savedPlayerParty = { Store.copy(own) }, frontier = { towerPlayer = { party = { Store.copy(own) } } },
    dayCare = { man = { mon = Store.copy(own) }, lady = { mon = Store.copy(own) }, egg = Store.copy(own) },
    modData = { emerald_daycare = { daycare = { Store.copy(own), Store.copy(own) },
      route5Daycare = { mon = Store.copy(own) } } },
    mail = gen == 2 and { party = { { author = "MAY", authorId = 200 }, { author = "BLUE", authorId = 200 } } }
      or gen == 3 and { { playerName = "MAY", trainerId = other.id + other.sid * 65536 } } or nil,
    secretBases = { { trainerName = "MAY", trainerId = { 200, 0, 0x34, 0x12 } } },
    hallOfFameTeams = { { { trainerId = 200, otSecretId = other.sid, personality = 12345 } } } }
  T.check(Sync.rewriteSave(save, gen, target, owners), "Gen " .. gen .. " sync rewrites")
  local profile = Identity.profile(save, gen)
  T.eq(profile.id, target.id, "public ID follows selected save")
  T.eq(profile.name, target.name, "player name follows selected save")
  if gen == 3 then
    T.eq(profile.sid, target.sid, "secret ID follows selected save")
    T.eq(foreignSid.otSecretId, other.sid + 1, "colliding public ID with foreign SID untouched")
    T.check(not Pokemon.isTradedMon(own, save), "synced mon passes native ownership check")
    T.check(not Engine.isTradedMon({ session = save }, own), "battle ownership uses actual session")
    T.check(Engine.isTradedMon({ session = save }, foreignSid), "battle detects different full OT ID")
    T.eq(save.mail[1].trainerId, target.id + target.sid * 65536, "mail full identity syncs")
    T.eq(save.secretBases[1].trainerName, "RED", "own secret base name syncs")
    T.same(save.secretBases[1].trainerId, { 100, 0, 42, 0 }, "own secret base full ID syncs")
    T.eq(save.hallOfFameTeams[1][1].trainerId, 200, "nameless historical OT is not guessed")
  elseif gen == 2 then
    T.eq(save.mail.party[1].authorId, 100, "own mail ID")
    T.eq(save.mail.party[1].author, "RED", "own mail name")
    T.eq(save.mail.party[2].authorId, 200, "foreign mail collision protected")
  end
  T.eq(own.otName, "RED", "OT name synced")
  T.eq(own.ot, "RED", "OT alias synced")
  T.eq(own.otId, 100, "OT ID synced")
  T.eq(own.opaque, "keep", "opaque mon data retained")
  T.eq(foreignName.otName, "BLUE", "foreign name untouched")
  T.eq(foreignName.otId, 200, "ID collision does not relabel foreign mon")
  for _, m in ipairs(Sync.monsOf(save, gen)) do
    if m ~= foreignName and m ~= foreignSid then T.eq(m.otId, 100, "every live collection synced") end
  end
  local afterOwners = {}
  Sync.addOwner(afterOwners, target, 3)
  local body = SaveData.encode(save)
  T.check(not Sync.rewriteSave(save, gen, target, afterOwners), "second sync has no changes")
  T.eq(SaveData.encode(save), body, "second sync retains exact serialized record")
end

for _, species in ipairs({ 25, 290, 308 }) do
  for low = 0, 65535, 257 do
    local m = shinyMon(other, low, species)
    local pid = assert(Identity.personality(m, target))
    T.eq(pid % 25, m.personality % 25, "nature retained")
    T.eq(pid % 256, low % 256, "gender byte retained")
    T.eq(pid % 2, m.personality % 2, "ability parity retained")
    if species == 290 then
      T.eq(math.floor(pid / 65536) % 10 < 5, math.floor(m.personality / 65536) % 10 < 5,
        "Wurmple evolution retained")
    end
    m.personality, m.otId, m.otSecretId = pid, target.id, target.sid
    T.check(nativeShiny(m), "shiny remains shiny under canonical ID")
    local ordinary = mon(other.id, other.sid, other.name, low + 10000 * 65536, species)
    local nextTarget = { id = ordinary.personality % 65536, sid = math.floor(ordinary.personality / 65536) }
    local adjusted = assert(Identity.personality(ordinary, nextTarget))
    T.eq(adjusted % 25, ordinary.personality % 25, "accidental shiny correction keeps nature")
    T.eq(adjusted % 65536, ordinary.personality % 65536, "accidental shiny correction keeps lower word")
    ordinary.personality, ordinary.otId, ordinary.otSecretId = adjusted, nextTarget.id, nextTarget.sid
    T.check(not nativeShiny(ordinary), "non-shiny remains non-shiny")
  end
end

for low = 0, 255 do
  local m = shinyMon(other, low, 201)
  local pid, why = Identity.personality(m, target)
  T.check(pid ~= nil or why ~= nil, "Unown either preserves its traits or refuses conversion")
  if pid then
    T.eq(Pokemon.unownLetter(pid), Pokemon.unownLetter(m.personality), "Unown letter retained")
    T.eq(pid % 25, m.personality % 25, "Unown nature retained")
    T.eq(pid % 2, m.personality % 2, "Unown parity retained")
    m.personality, m.otId, m.otSecretId = pid, target.id, target.sid
    T.check(nativeShiny(m), "Unown shininess retained")
  end
end

do
  local raw = ("00"):rep(12) .. "00C8" .. ("00"):rep(30)
  local carrier = { cartRaw = raw, cartOt = "8C809850" .. ("AB"):rep(7) }
  local save = { player = { id = 200, name = "MAY" }, party = { carrier } }
  T.check(Sync.rewriteSave(save, 1, target, owners), "Gen 1 raw carrier sync")
  T.eq(carrier.cartRaw:sub(25, 28), "0064", "Gen 1 carrier numeric ID patched")
  T.eq(Identity.monName(carrier), "RED", "Gen 1 carrier OT name patched")
  T.eq(carrier.cartOt:sub(9), ("AB"):rep(7), "raw name tail preserved")
  T.eq(#carrier.cartRaw, #raw, "raw record length preserved")
  local raw2 = ("00"):rep(6) .. "00C8" .. ("00"):rep(24)
  local c2 = { species = 99, otId = 200, ot = "MAY", cartRaw = raw2 }
  T.check(Sync.rewriteSave({ player = { id = 200, name = "MAY" }, party = { c2 } }, 2, target, owners),
    "Gen 2 carrier sync")
  T.eq(c2.cartRaw:sub(13, 16), "0064", "Gen 2 raw ID patched")
  T.check(c2.cartRawFp ~= nil, "Gen 2 carrier fingerprint updated")
end

local realFs = love.filesystem
local function fresh()
  local files, fault = {}, {}
  love.filesystem = {
    read = function(path) return files[path] end,
    getInfo = function(path) return files[path] and { type = "file" } end,
    createDirectory = function() return true end,
    remove = function(path) files[path] = nil; return true end,
    write = function(path, body)
      if path == fault.path then
        if fault.partial then files[path] = body:sub(1, math.floor(#body / 2)) end
        return nil, "disk fault"
      end
      files[path] = body; return true
    end,
  }
  SaveData.resetSlotState()
  local a = SaveData.createSlot("emerald")
  SaveData.writeSlot("emerald", a, { version = "emerald", engine = "game3", name = other.name,
    trainerId = other.id, secretId = other.sid, meta = { playthroughId = "em-one" },
    party = { shinyMon(other, 123, 25) } })
  local b = SaveData.createSlot("firered")
  SaveData.writeSlot("firered", b, { version = "firered", engine = "game3", name = target.name,
    trainerId = target.id, secretId = target.sid, meta = { playthroughId = "fr-one" },
    party = { mon(target.id, target.sid, target.name) } })
  return files, fault, a, b
end
local function finish(job)
  for _ = 1, 1000 do if job:step() then return end end
  error("ID Sync did not finish")
end

do
  local files, _, a, b = fresh()
  local state = Store.new()
  state.nextId = 3
  local stored = { id = 1, generation = 3, version = "emerald", slotId = a,
    mon = shinyMon(other, 123, 308), display = {}, depositorId = other.id + other.sid * 65536,
    tags = "keep", archives = { { id = 1, generation = 2, version = "gold", display = {},
      mon = { species = "PIKACHU", otId = other.id, ot = other.name } } } }
  state.boxes[1].mons[1] = stored
  state.departures = { [2] = { entry = { id = 2, generation = 3, version = "emerald",
    mon = shinyMon(other, 123), display = {} }, path = "saves/emerald/" .. a .. ".lua" } }
  state.departures[2].identity = Records.identity(3, state.departures[2].entry.mon)
  state.stages = {}
  state.presets = { { name = "Team", ids = { 1, 2 } } }
  local source = { version = "emerald", path = "saves/emerald/" .. a .. ".lua" }
  local oldSave = SaveData.decode(files[source.path])
  state.progress = { [Gifts.identity(source, oldSave)] = 500 }
  files[Store.PATH] = SaveData.encode(state)
  local job = Sync.newJob({ scope = "firered", slot = b })
  finish(job)
  T.eq(job.error, nil, "warehouse job succeeds")
  T.check(job.boxUpdated, "warehouse is included in coordinated commit")
  local saved = SaveData.decode(files[source.path])
  local box = SaveData.decode(files[Store.PATH])
  T.eq(box.boxes[1].mons[1].mon.otName, "RED", "stored OT name follows")
  T.check(nativeShiny(box.boxes[1].mons[1].mon), "stored shiny preserved")
  T.eq(box.boxes[1].mons[1].archives[1].mon.ot, "RED", "restorable archive identity follows")
  T.eq(box.boxes[1].mons[1].depositorId, target.id + target.sid * 65536, "depositor ID follows")
  T.eq(box.boxes[1].mons[1].tags, "keep", "labels preserved")
  T.same(box.presets, state.presets, "team references preserved")
  T.eq(box.progress[Gifts.identity(source, saved)], 500, "gift peak survives identity change")
  T.eq(box.departures[2].identity, Records.identity(3, box.departures[2].entry.mon), "return identity refreshed")
  T.eq(box.departures[2].identity, Records.identity(3, saved.party[1]), "return tracking matches updated game mon")
  T.check(box.syncMembers["emerald/em-one"] ~= nil, "changed save linked to warehouse sync")
  T.eq(files[Transaction.PATH], nil, "completed journal removed")
  local before = SaveData.encode(box)
  local again = Sync.newJob({ scope = "firered", slot = b })
  finish(again)
  T.eq(again.error, nil, "repeat job succeeds")
  T.eq(again.written, 0, "repeat job writes no saves")
  T.eq(files[Store.PATH], before, "repeat job leaves warehouse unchanged")
end

for _, mode in ipairs({ "changed", "unreadable", "pending", "partial" }) do
  local files, fault, a, b = fresh()
  local path = "saves/emerald/" .. a .. ".lua"
  local original, source = files[path], files["saves/firered/" .. b .. ".lua"]
  local Trade = require("src.online.Trade")
  local pendingSentAt = Trade.pendingSentAt
  if mode == "pending" then Trade.pendingSentAt = function() return { {} } end end
  if mode == "unreadable" then files[path], files[path .. ".bak"] = "invalid save", "invalid backup" end
  local job = Sync.newJob({ scope = "firered", slot = b })
  if mode == "changed" then
    while job.phase == "read" do job:step() end
    files[path] = original .. "\n-- changed externally"
  elseif mode == "partial" then fault.path, fault.partial = path, true end
  finish(job)
  T.check(job.error ~= nil, mode .. " reports a failure")
  T.eq(job.written, 0, mode .. " does not claim success")
  T.eq(files["saves/firered/" .. b .. ".lua"], source, mode .. " source is untouched")
  if mode == "partial" then
    fault.path = nil
    T.check(Transaction.recover(love.filesystem), "partial identity commit recovers")
    T.eq(SaveData.decode(files[path]).party[1].otName, "RED", "recovery completes exact intended identity")
    T.eq(files[path .. ".bak"], files[path], "recovery backup follows committed side")
  else T.eq(files[Transaction.PATH], nil, mode .. " starts no transaction") end
  Trade.pendingSentAt = pendingSentAt
end
love.filesystem = realFs

do
  local Gen3Save = require("src.save_convert.Gen3Save")
  local codec = Gen3Save.forVersion("emerald")
  local JP = codec.L.LANGUAGE_JAPANESE
  local egg = { personality = 12345, otId = 1, otSecretId = 2, otName = "BRYAN", language = JP,
    isEgg = true, isEggFlag = true, species = 1, nicknameBytes = codec.L.EGG_NICKNAME,
    ivs = {}, evs = {}, contest = {}, moves = { 1, 0, 0, 0 }, pp = { 35, 0, 0, 0 } }
  local decoded = codec.decodeBoxMon(codec.encodeBoxMon(egg))
  T.eq(decoded.otName, "BRYAN", "egg OT name decodes in the player's charset")
  T.eq(decoded.nickname, "タマゴ", "egg nickname keeps its Japanese bytes")
  local healed = { personality = 1, language = JP, isEgg = true, otName = "ＢＲＹＡＮ", ot = "ＢＲＹＡＮ",
    cartExtra = { otNameRaw = { codec.encodeString("BRYAN", 8, 0xFF):byte(1, -1) } } }
  T.check(Gen3Save.repairJapaneseNames({ healed }), "fullwidth egg OT name is healed")
  T.eq(healed.otName, "BRYAN", "healed egg OT name")
  T.eq(healed.ot, "BRYAN", "healed egg OT alias")
  local flagged = { personality = 1, language = JP, cartExtra = { flagsRaw = 6 }, otName = "ＡＳＨ１" }
  T.check(Gen3Save.repairJapaneseNames({ flagged }), "egg flag byte alone marks an egg for healing")
  T.eq(flagged.otName, "ASH1", "fullwidth digits heal too")
  local japanese = { personality = 1, language = JP, otName = "さとし", nickname = "ピカチュウ", species = 25,
    ivs = {}, evs = {}, contest = {}, moves = { 1, 0, 0, 0 }, pp = { 35, 0, 0, 0 } }
  local bytes = codec.encodeBoxMon(japanese)
  local back = codec.decodeBoxMon(bytes)
  T.eq(back.otName, "さとし", "Japanese OT name decodes")
  T.eq(codec.encodeBoxMon(back), bytes, "Japanese names round-trip their bytes")
end

T.finish("trainer_identity_sync")
