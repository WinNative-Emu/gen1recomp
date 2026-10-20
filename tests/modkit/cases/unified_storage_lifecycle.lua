package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Loader = require("src.mods.Loader")
local Storage = require("src.mods.Storage")
local Runtime = require("src.mods.Runtime")
local SaveData = require("src.core.SaveData")
local Serializer = require("src.core.SaveSerializer")
local GameVersion = require("src.core.GameVersion")
local Schema = require("src.core.game3.save_schema_firered")
local Rng = require("src.core.game3.rng")
local Merge = require("src.mods.Merge")

local VERSIONS = { "red", "blue", "yellow", "gold", "silver", "crystal",
  "firered", "leafgreen", "ruby", "sapphire", "emerald" }
local MOD = "fix_storage_lifecycle"
local COMMON = [[
local mod = ...
local out, storage = mod.exports, mod.storage
out.storage = storage
out.roundtrip = function(game)
  assert(storage:write(game, "state/value", { count = 7, nested = { ready = true } }))
  local value = assert(storage:read(game, "state/value"))
  assert(value.count == 7 and value.nested.ready == true)
  assert(storage:writeBytes(game, "state/bytes", "CACHE\0\255\128"))
  assert(storage:readBytes(game, "state/bytes") == "CACHE\0\255\128")
  return storage:context(game)
end
out.isolated = function(game)
  local value, code = storage:read(game, "state/value")
  assert(value == nil and code == "not_found")
  value, code = storage:readBytes(game, "state/bytes")
  assert(value == nil and code == "not_found")
end
mod.hooks:wrap("save.new_game", function(nextFn, save)
  save = nextFn(save)
  if out.authoredId then
    save.meta = { playthroughId = out.authoredId, cartId = "fixture_cart" }
    save.modData = { fixture = { retained = true } }
  end
  return save
end)
]]

local savedFs, savedPortableFs = love.filesystem, SaveData.portableFs
local savedVersion, savedRng = GameVersion.get(), Rng.getState()
local savedRuntime = { Runtime.events, Runtime.hooks, Runtime.errors }
local savedCurrentMod = Runtime.currentMod

local function filesystem()
  local files = {
    ["mods/" .. MOD .. "/manifest.json"] = '{"id":"' .. MOD
      .. '","name":"Storage Lifecycle","version":"1.0.0","api":3,'
      .. '"games":["all"],"entry":"main.lua"}',
    ["mods/" .. MOD .. "/main.lua"] = COMMON,
  }
  local fs = T.sdk.memfs(files)
  local write = fs.write
  fs.write = function(path, body)
    if fs.failTmp and path:sub(-4) == ".tmp" then return false, "tmp denied" end
    return write(path, body)
  end
  fs.remove = function(path) files[path] = nil return true end
  fs.createDirectory = function() return true end
  love.filesystem = fs
  SaveData.portableFs = function() return fs end
  SaveData.resetSlotState()
  return fs, files
end

local function load(version, fs, game)
  local generation = GameVersion.generation(version)
  local loader = Loader.new({ fs = fs, generation = generation, version = version })
  loader.game = game
  local data = generation == 3 and T.sdk.gen3Data() or T.fixtures.fresh()
  T.check(loader:load(data) == true, version .. " API 3 loader succeeds")
  T.eq(#loader.errors, 0, version .. " loader has no errors")
  return assert(loader.exports[MOD]), loader
end

local function checkCall(fn, game, label)
  local ok, result = pcall(fn, game)
  T.check(ok, label .. ": " .. tostring(result))
  return ok and result or nil
end

local function run()
  for _, version in ipairs(VERSIONS) do
    GameVersion.set(version)
    local fs = filesystem()
    local first = { save = { version = version, meta = { playthroughId = "first" } } }
    local second = { save = { version = version, meta = { playthroughId = "second" } } }
    local api = load(version, fs, first)
    local context = checkCall(api.roundtrip, first, version .. " shared value/byte contract")
    T.eq(context and context.gameVersion, version, version .. " context version")
    T.eq(context and context.playthroughId, "first", version .. " context identity")
    checkCall(api.isolated, second, version .. " shared playthrough isolation")
  end

  for _, version in ipairs({ "firered", "leafgreen" }) do
    GameVersion.set(version)
    local fs, files = filesystem()
    local api, loader = load(version, fs)
    local previousId = "previous_" .. version
    T.check(SaveData.save({ version = version, meta = { playthroughId = previousId } }),
      version .. " seed existing same-slot mapping in memory")
    local slot = SaveData.activeSlot(version)
    local beforeNewGame = Merge.deepCopy(files)
    local first = Schema.newGame({ version = version, rngSeed = 7,
      engineOptions = SaveData.loadOptions() })
    local firstRng = Rng.getState()
    local second = Schema.newGame({ version = version, rngSeed = 7,
      engineOptions = SaveData.loadOptions() })
    T.same(Rng.getState(), firstRng, version .. " fresh identities preserve native RNG sequence")
    T.same(files, beforeNewGame, version .. " native New Game writes no progress or options")
    local firstId = first.meta and first.meta.playthroughId
    local secondId = second.meta and second.meta.playthroughId
    T.check(type(firstId) == "string" and firstId ~= "", version .. " first unsaved identity")
    T.check(type(secondId) == "string" and secondId ~= "", version .. " second unsaved identity")
    T.neq(firstId, secondId, version .. " unsaved sessions in one slot have distinct identities")
    T.neq(firstId, previousId, version .. " first New Game ignores old slot mapping")
    T.neq(secondId, previousId, version .. " second New Game ignores old slot mapping")
    T.eq(SaveData.activeSlot(version), slot, version .. " both sessions share the same slot")

    first.modData[MOD] = { retained = 19 }
    first.options.frameType = 7
    local game = { save = Schema.toSaveTable(first) }
    local other = { save = Schema.toSaveTable(second) }
    loader.game = game
    T.eq(game.save.meta, first.meta, version .. " snapshot shares session metadata table")
    T.eq(game.save.modData, first.modData, version .. " snapshot retains modData table")
    checkCall(api.roundtrip, game, version .. " native first session persists value and bytes")
    checkCall(api.isolated, other, version .. " native second session cannot read first")
    T.eq(Storage.new(MOD, fs):context(game).playthroughId, firstId,
      version .. " real Storage resolves the same native identity")

    local rngBefore = Rng.getState()
    SaveData.newPlaythroughId()
    Schema.toSaveTable(first)
    T.same(Rng.getState(), rngBefore, version .. " identity helper and snapshot consume no native RNG")
    T.eq(first.meta.playthroughId, firstId, version .. " repeated snapshot never reallocates identity")
    local decoded = assert(Serializer.decode(Serializer.encode(game.save)))
    local continued = Schema.fromSaveTable(decoded)
    T.eq(continued.meta.playthroughId, firstId, version .. " serialized Continue retains identity")
    T.same(continued.modData[MOD], { retained = 19 }, version .. " Continue retains modData")
    T.eq(continued.options.frameType, 7, version .. " Continue retains native options")

    fs.failTmp = true
    local written, code = api.storage:write(game, "state/value", { count = 99 })
    T.check(not written and code == "write_failed", version .. " failed value write is reported")
    written, code = api.storage:writeBytes(game, "state/bytes", "replacement")
    fs.failTmp = false
    T.check(not written and code == "write_failed", version .. " failed byte write is reported")
    T.eq(api.storage:context(game).playthroughId, firstId, version .. " failed writes retain bucket")
    T.eq(api.storage:read(game, "state/value").count, 7, version .. " failed value write retains data")
    T.eq(api.storage:readBytes(game, "state/bytes"), "CACHE\0\255\128",
      version .. " failed byte write retains data")
    checkCall(api.isolated, other, version .. " failed writes leave second bucket empty")

    local snapshot = Schema.toSaveTable(first)
    snapshot.meta = SaveData.buildMeta(loader:status().loaded, snapshot.meta)
    first.meta = snapshot.meta
    T.eq(snapshot.meta.playthroughId, firstId, version .. " normal-save stamp retains identity")
    T.check(SaveData.save(snapshot), version .. " normal save succeeds in memory")
    T.eq(Schema.toSaveTable(first).meta, snapshot.meta,
      version .. " stamped metadata stays bound to native session")
    SaveData.resetSlotState()
    local reloaded = Schema.fromSaveTable(assert(SaveData.load(version)))
    local reboundGame = { save = Schema.toSaveTable(reloaded) }
    local rebound, reboundLoader = load(version, fs, reboundGame)
    T.eq(rebound.storage:context(reboundGame).playthroughId, firstId,
      version .. " provider rebind preserves saved identity")
    T.eq(rebound.storage:read(reboundGame, "state/value").count, 7,
      version .. " reload reads original value bucket")
    T.eq(rebound.storage:readBytes(reboundGame, "state/bytes"), "CACHE\0\255\128",
      version .. " reload reads original byte bucket")
    T.same(reloaded.modData[MOD], { retained = 19 }, version .. " normal save retains modData")
    T.eq(reloaded.options.frameType, 7, version .. " normal save retains options")
    local fresh = Schema.newGame({ version = version, rngSeed = 7 })
    reboundLoader.game = { save = Schema.toSaveTable(fresh) }
    T.neq(fresh.meta.playthroughId, firstId, version .. " rebound New Game cannot reuse old bucket")
    checkCall(rebound.isolated, reboundLoader.game, version .. " rebound New Game is isolated")

    rebound.authoredId = "authored_" .. version
    local authored = Schema.newGame({ version = version, rngSeed = 7 })
    T.eq(authored.meta.playthroughId, rebound.authoredId, version .. " new-game hook identity retained")
    T.eq(authored.meta.cartId, "fixture_cart", version .. " hook cart identity retained")
    T.same(authored.modData, { fixture = { retained = true } }, version .. " hook modData retained")
    local authoredContinue = Schema.fromSaveTable(assert(Serializer.decode(
      Serializer.encode(Schema.toSaveTable(authored)))))
    T.eq(authoredContinue.meta.playthroughId, rebound.authoredId,
      version .. " identified Continue never replaces authored identity")
    T.eq(authoredContinue.meta.cartId, "fixture_cart", version .. " Continue retains cart identity")

    local legacy = Schema.fromSaveTable(decoded)
    legacy.meta = {}
    local legacyGame = { save = Schema.toSaveTable(legacy) }
    T.eq(legacy.meta.playthroughId, nil, version .. " legacy serialization allocates no identity")
    local legacyContext = rebound.storage:context(legacyGame)
    T.eq(legacyGame.save.meta, legacy.meta, version .. " legacy snapshot shares metadata table")
    T.eq(legacy.meta.playthroughId, legacyContext.playthroughId,
      version .. " storage context backfills actual legacy session")
    T.eq(legacy.meta.playthroughId, firstId, version .. " legacy Continue uses saved slot mapping")
    T.same(legacy.modData[MOD], { retained = 19 }, version .. " legacy snapshot retains modData")
  end
end

local ok, err = xpcall(run, debug.traceback)
SaveData.resetSlotState()
love.filesystem, SaveData.portableFs = savedFs, savedPortableFs
Runtime.install(savedRuntime[1], savedRuntime[2], savedRuntime[3])
Runtime.currentMod = savedCurrentMod
Rng.setState(savedRng)
GameVersion.set(savedVersion)
T.check(ok, "storage lifecycle completes: " .. tostring(err))
T.finish("unified storage lifecycle")
