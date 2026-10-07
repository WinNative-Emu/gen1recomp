package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")
local T = require("tests.harness")
local Store = require("src.box.Store")
local Gifts = require("src.box.Gifts")
local Service = require("src.box.Service")
local Catalog = require("src.box.Catalog")
local Serializer = require("src.core.SaveSerializer")
local CacheFs = require("src.import.CacheFs")
local GameVersion = require("src.core.GameVersion")
local oldRead, tables = CacheFs.readAt, {}
local root = "data/generated/gba/pokemon/"
local names, national, meta, moves, battle = {}, { toSpecies = {}, toNational = {} }, {}, {}, {}
for i, award in ipairs(Gifts.AWARDS) do
  local species = ({ 358, 288, 315, 172 })[i]
  names[species], national.toSpecies[award.national], national.toNational[species] = award.name, species, award.national
  meta[species] = { eggCycles = 20, growthRate = 0, genderRatio = 127 }
  for _, move in ipairs(award.moves) do moves[move], battle[move] = "MOVE " .. move, { pp = 20 } end
end
for _, version in ipairs({ "ruby", "sapphire", "firered", "leafgreen", "emerald" }) do
  for path, value in pairs({ ["names.lua"] = names, ["national.lua"] = national, ["meta.lua"] = meta,
      ["move_names.lua"] = moves, ["battle_moves.lua"] = { moves = battle } }) do
    tables[GameVersion.cachePrefix(version)..root..path] = Serializer.encode(value)
  end
end
CacheFs.readAt = function(path) return tables[path] end; Catalog.reset()
local source = { version = "firered", path = "saves/firered/slot1.lua", slotId = "slot1" }
local function filesystem(state, flags)
  local save = { version = "firered", generation = 3, trainerId = 42, secretId = 97, name = "Owner",
    meta = { playthroughId = "first-game" }, party = {}, modData = { cartImport = { boxFlags = flags or 0 } } }
  local files = { [Store.PATH] = Serializer.encode(state), [source.path] = Serializer.encode(save) }
  local mode, writes = {}, 0
  local fs = { read = function(path) return files[path] end,
    getInfo = function(path) return files[path] and { type = "file" } end,
    createDirectory = function() return true end,
    remove = function(path) files[path] = nil; return true end,
    write = function(path, body)
      writes = writes + 1
      if writes == mode.fault then files[path] = body:sub(1, math.floor(#body / 2)); return nil, "interruption" end
      files[path] = body; return true
    end }
  return fs, files, mode, save
end
local function stateWith(count, credited)
  local state = Store.new()
  for i = 1, count do
    local mon = { species = 172, level = 5, personality = i, otId = 123, otSecretId = 45, moves = { 84 } }
    local b, slot = math.floor((i - 1) / 60) + 1, (i - 1) % 60 + 1
    state.boxes[b].mons[slot] = { id = i, generation = 3, version = "firered", mon = mon,
      display = Catalog.describe("firered", mon), depositorId = i <= (credited or count) and 42 + 97 * 65536 or 99 }
  end
  state.nextId = count + 1
  return state
end
local initialRng = require("src.core.game3.rng").getState()
for index, award in ipairs(Gifts.AWARDS) do
  local mon = assert(Gifts.create("firered", index, 0))
  T.eq(mon.personality, 0x0000E97E, award.name .. " uses high then low PID draws")
  T.same(mon.ivs, { hp = 17, atk = 19, def = 20, spe = 16, spa = 13, spd = 12 }, award.name .. " uses next two IV draws")
  T.same(mon.moves, award.moves, award.name .. " has complete native gift moves")
  T.eq(mon.isEgg, true, award.name .. " starts as an egg")
  T.eq(mon.language, 1, award.name .. " has original egg language")
  T.eq(mon.metLocation, 255, award.name .. " has original egg met location")
end
T.same(require("src.core.game3.rng").getState(), initialRng, "offline gifts do not disturb active game's RNG")
for _, vector in ipairs({ {99,1,false}, {100,1,true}, {499,3,false}, {500,3,true}, {1498,5,false}, {1499,5,true}, {1500,7,false} }) do
  local fs, files = filesystem(stateWith(vector[1]), vector[2])
  local service = assert(Service.open(fs))
  T.eq(assert(service:giftProgress(source)).eligible, vector[3], "threshold " .. vector[1] .. " flags " .. vector[2])
  local before = files[source.path]
  local ok = service:claimEgg(source, 0)
  T.eq(not not ok, vector[3], "claim behavior matches threshold " .. vector[1])
  if ok then
    T.eq(Store.count(service.state), vector[1] + 1, "award creates exactly one warehouse record")
    T.eq(Gifts.flags(assert(Serializer.decode(files[source.path]))), vector[2] + 2, "award advances native receipt ordinal")
  else T.eq(files[source.path], before, "ineligible claim preserves native save") end
end
do
  local fs, files = filesystem(Store.new(), 0x80)
  local service = assert(Service.open(fs))
  T.check(service:claimEgg(source, 0), "first connection can claim Swablu without depositing")
  T.eq(Gifts.flags(assert(Serializer.decode(files[source.path]))), 0x81, "first egg sets usedBoxRS and preserves unrelated native bits")
  T.eq(Store.count(service.state), 1, "first connection stores exactly one egg")
  T.check(not service:claimEgg(source, 0), "reopening cannot repeat first egg")
  local nextSave = assert(Serializer.decode(files[source.path]))
  nextSave.meta.playthroughId = "new-game"
  T.check(Gifts.identity(source, nextSave) ~= Gifts.identity(source, { meta = {playthroughId="first-game"}, trainerId=42,secretId=97 }),
    "reused slot new playthrough has independent progress identity")
end
do
  local fs = filesystem(stateWith(101, 99), 1)
  T.eq(assert(assert(Service.open(fs)):giftProgress(source)).current, 99, "mixed-source entries do not credit another depositor")
  local state = stateWith(100)
  local _, _, _, save = filesystem(state, 1)
  Gifts.recordProgress(state, source, save)
  state.boxes[1].mons[1] = nil
  T.eq(assert(Gifts.progress(state, source, save)).peak, 100, "withdrawing cannot erase reached progress")
  state.boxes[1].mons[1] = Store.copy(state.boxes[1].mons[2]); state.boxes[1].mons[1].id = 101;state.nextId=102
  T.eq(assert(Gifts.progress(state, source, save)).peak, 100, "redeposit does not increment a lifetime deposit counter")
end
do
  local fs, files = filesystem(stateWith(1500), 0)
  local service = assert(Service.open(fs)); local before = files[source.path]
  T.check(not service:claimEgg(source, 0), "full warehouse refuses even the first gift")
  T.eq(files[source.path], before, "full warehouse consumes no native receipt")
end
for fault = 1, 6 do
  local fs, files, mode = filesystem(Store.new(), 0)
  local service = assert(Service.open(fs)); mode.fault = fault
  service:claimEgg(source, 0); mode.fault = nil
  service = assert(Service.open(fs))
  local count, flags = Store.count(service.state), Gifts.flags(assert(Serializer.decode(files[source.path])))
  T.check(count == 0 and flags == 0 or count == 1 and flags == 1, "interrupted award " .. fault .. " restores consistent egg and receipt")
end

local Pokemon = package.loaded["src.core.game3.pokemon"]
package.loaded["src.core.game3.pokemon"] = { name = function(species) return names[species] end,
  _names=names,movePp=function(move) return battle[move] and battle[move].pp or 0 end,
  currentMapSec = function() return 88 end, applyStats = function() end,
  playerSecretId = function(session) return session and tonumber(session.secretId) or 0 end }
local Breeding = require("src.core.game3.breeding")
for _, version in ipairs({"ruby","sapphire","emerald","firered","leafgreen"}) do
 local codec = require("src.save_convert.Gen3Save").forVersion(version)
 for index, award in ipairs(Gifts.AWARDS) do
  local mon = assert(Gifts.create(version, index, 0))
  Breeding.hatchMon({ version = version, name = "Owner", trainerId = 42, secretId = 97, gender = 0 }, mon)
  local decoded = assert(codec.decodeBoxMon(codec.encodeBoxMon(codec.fromPortMon(mon, {}, false))))
  T.eq(decoded.isEgg, false, award.name .. " hatches through engine and native egg bit clears")
  T.eq(mon.level, 5, award.name .. " hatches at level 5")
  T.eq(decoded.personality, 0xE97E, award.name .. " hatch preserves PID")
  T.eq(decoded.otId, 42, award.name .. " hatch binds recipient trainer")
  T.eq(decoded.moves[#award.moves], award.moves[#award.moves], award.name .. " hatch preserves special move")
 end
 for _, flags in ipairs({248,249,251,253,255}) do
  local image=assert(codec.encode({playerName="Owner",trainerId=42,secretId=97,boxFlags=248}))
  local port=codec.toPortSave(assert(codec.decode(image)),version)
  port.map=codec.mapFor(0,0)
  Gifts.setFlags(port,flags)
  local exported=assert(codec.exportPort(port,{version=version,template=image,toNational=function(n)return n end,
    itemId=tonumber,mapLayoutId=function()return 1 end}))
  T.eq(assert(codec.decode(exported)).boxFlags,flags,version.." native .sav preserves reward receipt and unrelated upper bits")
  local imported=codec.toPortSave(assert(codec.decode(exported)),version)
  T.eq(Gifts.flags(imported),flags,version.." native receipt returns to Box on import")
 end
end
package.loaded["src.core.game3.pokemon"] = Pokemon
CacheFs.readAt = oldRead; Catalog.reset()
T.finish("Box gifts")
