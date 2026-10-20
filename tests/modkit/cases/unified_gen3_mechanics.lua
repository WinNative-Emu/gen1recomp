package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.harness").suite("unified gen3 mechanics")
local Sdk = require("tests.modkit.sdk")
local ModRuntime = require("src.mods.Runtime")
local Events = require("src.mods.Events")
local Hooks = require("src.mods.Hooks")
local Callbacks = require("src.mods.UnifiedCallbacks")
local Records = require("src.mods.UnifiedRecords")
local Version = require("src.core.GameVersion")
local Runtime = require("src.core.game3.runtime")
local Pokemon = require("src.core.game3.pokemon")
local Party = require("src.core.game3.party")
local Breeding = require("src.core.game3.breeding")
local Daycare = require("src.core.game3.daycare")
local Roamer = require("src.core.game3.roamer")
local Rng = require("src.core.game3.rng")
local Dex = require("src.core.game3.dex")
local Profile = require("src.core.game3.profile")
local Link = require("src.core.game3.link")
local LT = require("src.core.game3.link.trade")
local Scene = require("src.core.game3.trade_scene")
local Protocol = require("src.link.Protocol")
local FakeRelay = require("tests.g3link_fake_relay")
local RomText = require("src.core.game3.rom_text")

local originalVersion, originalRng = Version.get(), Rng.getState()
local savedRuntime = { ModRuntime.events, ModRuntime.hooks, ModRuntime.errors }
local restore = {}
local function fixture(owner, key, value)
  local old = owner[key]
  restore[#restore + 1] = function() owner[key] = old end
  owner[key] = value
end

fixture(RomText, "plain", function(key) return key end)

local function setup(version)
  Version.set(version)
  ModRuntime.install(Events.new(), Hooks.new(), {})
  local data = Sdk.gen3Data()
  data.gen3Inputs = { stats = data.gen3Pokemon._stats, types = data.gen3Pokemon._types,
    abilities = data.gen3Pokemon._abilities, meta = data.gen3Pokemon._speciesMeta,
    moves = data.gen3Moves._rom, items = data.gen3Items._byId,
    typeChart = require("src.core.game3.battle.types").TABLE, natures = {}, constants = {} }
  for key, value in pairs(data.gen3Pokemon) do fixture(Pokemon, key, value) end
  fixture(Pokemon, "_battleMoves", data.gen3Moves._rom)
  fixture(Pokemon, "_tmhm", { machines = {}, learnsets = {} })
  fixture(Pokemon, "_national", { toNational = { [4] = 4, [5] = 5, [16] = 16 } })
  local session = { version = version, name = "RED", trainerId = 4242, secretId = 0,
    party = {}, flags = {}, vars = {}, store = { flags = {}, vars = {} },
    dex = Dex.new(), mapSec = 1, map = "FR_TRADE_CENTER", gameStats = {} }
  local game = { data = data, session = session, phase = "field" }
  session.game = game
  fixture(Runtime, "active", true)
  fixture(Runtime, "session", session)
  fixture(Runtime, "_game", game)
  fixture(Runtime, "_mod", nil)
  local loader = { generation = 3, version = version, game = game,
    events = ModRuntime.events, hooks = ModRuntime.hooks }
  function loader:_game() return self.game end
  return session, Callbacks.new(loader, "mechanics"), game
end

local function makeMon(session, species, personality, trainerId)
  local scratch = { party = {}, name = session.name, version = session.version,
    trainerId = trainerId or session.trainerId, secretId = 0, mapSec = 1 }
  local ok, _, mon = Party.giveMon(scratch, species or 4, 5, "",
    { fixedPersonality = personality or 0 })
  assert(ok and mon, "native Party.giveMon fixture failed")
  return mon
end

local function pair(session, differentSpecies, differentTrainer)
  local dc = Daycare.stateOf(session)
  dc[1] = makeMon(session, 4, 0)
  dc[2] = makeMon(session, differentSpecies and 5 or 4, 254,
    differentTrainer and 777 or session.trainerId)
  dc.steps, dc.stepCounter = { 254, 254 }, 0
  dc.offspringPersonality, dc.eggPending = 0, false
  return dc
end

local function nextRoll(value)
  return { value = Rng.mulU32((value * 65536 - 24691) % 4294967296, 4005161829),
    value2 = 123, wild = 456 }
end

local function copy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for key, item in pairs(value) do out[key] = copy(item) end
  return out
end

local function canonical(mon, raw, session, label)
  T.same(mon, Records.mon(raw, 3, session.game.data, session.version), label)
  T.neq(mon, raw, label .. " is detached")
  T.neq(mon.native, raw, label .. " native extension is detached")
end

local function exercise(version, label, fn)
  local ok, err = xpcall(fn, debug.traceback)
  T.check(ok, version .. " " .. label .. " completes: " .. tostring(err))
  Scene.cancel()
  LT.reset()
  Link.reset()
end

for _, version in ipairs({ "firered", "leafgreen", "ruby", "sapphire", "emerald" }) do
  exercise(version, "friendship bytes and notifications", function()
    local session, api = setup(version)
    local mon = makeMon(session)
    mon.friendship, mon.happiness = 254, 254
    local seen, once = {}, 0
    local unsubscribe = api.events:on("happiness.changed", function(ev)
      seen[#seen + 1] = ev
      T.eq(mon.friendship, ev.to, version .. " friendship committed before callback")
      T.eq(mon.happiness, ev.to, version .. " legacy alias committed before callback")
      canonical(ev.mon, mon, session, version .. " happiness mon")
    end)
    api.events:once("happiness.changed", function() once = once + 1 end)
    local rng = Rng.getState()
    Pokemon.setFriendship(mon, 999, "GAINLEVEL")
    T.eq(#seen, 1, version .. " actual clamped change notifies once")
    T.eq(seen[1].from, 254, version .. " friendship old byte")
    T.eq(seen[1].to, 255, version .. " friendship clamps to byte")
    T.eq(seen[1].delta, 1, version .. " friendship delta is applied units")
    T.eq(seen[1].event, "GAINLEVEL", version .. " explicit event preserved")
    T.eq(seen[1].reason, "event", version .. " explicit event reason")
    Pokemon.setFriendship(mon, 999, "GAINLEVEL")
    T.eq(#seen, 1, version .. " unchanged saturated byte is silent")
    Pokemon.setFriendship(mon, -10)
    T.eq(seen[2].delta, -255, version .. " downward clamp reports signed delta")
    T.eq(once, 1, version .. " once subscription retires on actual mutation")
    T.same(Rng.getState(), rng, version .. " observing direct writes consumes no RNG")
    seen[1].mon.species, seen[1].mon.native.friendship = "PIDGEY", 17
    T.eq(mon.species, 4, version .. " notification cannot change native species")
    T.eq(mon.friendship, 0, version .. " notification extension cannot change byte")
    local egg = makeMon(session)
    egg.isEgg = true
    Pokemon.setFriendship(egg, 3)
    Pokemon.adjustFriendship(egg, Pokemon.FRIENDSHIP_EVENT_WALKING)
    T.eq(#seen, 2, version .. " egg hatch counter is not friendship")
    unsubscribe()
    Pokemon.setFriendship(mon, 70)
    T.eq(#seen, 2, version .. " unsubscribe silences real writes")

    local function walk(observe)
      mon.friendship, mon.happiness = 70, 70
      local event
      local remove = observe and api.events:on("happiness.changed", function(ev) event = ev end)
      Rng.setState(nextRoll(0))
      Pokemon.adjustFriendship(mon, Pokemon.FRIENDSHIP_EVENT_WALKING)
      local out = { friendship = mon.friendship, rng = Rng.getState() }
      if remove then remove() end
      return out, event
    end
    local stock = walk(false)
    local observed, event = walk(true)
    T.same(observed, stock, version .. " walking listener preserves result and RNG")
    T.eq(event.reason, "step", version .. " walking reason uses Gen2 contract")
    T.eq(event.event, nil, version .. " walking has no explicit event")
    T.eq(event.delta, event.to - event.from, version .. " walking delta uses bytes")
    T.same(walk(false), stock, version .. " walking unsubscribe restores native sequence")
  end)

  exercise(version, "pure gender and shiny hooks", function()
    local session, api = setup(version)
    local mon = makeMon(session, 4, 0)
    mon.otId, mon.otSecretId = 0, 0
    local rng, genes = Rng.getState(), { mon.personality, copy(mon.ivs) }
    T.eq(Pokemon.gender(4, 0), "F", version .. " native female predicate")
    T.eq(Pokemon.gender(4, 254), "M", version .. " native male predicate")
    T.eq(Pokemon.isShiny(mon), true, version .. " native shiny XOR predicate")
    local calls = 0
    local remove = api.hooks:wrap("gender.roll", function(next, ctx)
      calls = calls + 1
      T.eq(ctx.species, "CHARMANDER", version .. " gender species is canonical")
      T.eq(ctx.def.id, "CHARMANDER", version .. " gender definition is canonical")
      T.eq(ctx.ratio, 31, version .. " gender ratio retains byte units")
      T.eq(next(ctx), "female", version .. " downstream returns shared gender")
      return "male"
    end)
    T.eq(Pokemon.gender(4, 0), "M", version .. " shared male overrides real predicate")
    T.eq(Pokemon.gender(4, 0), "M", version .. " repeated accessor remains deterministic")
    T.eq(calls, 2, version .. " both real accessor evaluations invoke hook")
    remove()
    remove = api.hooks:wrap("gender.roll", function() return "invalid" end)
    T.eq(Pokemon.gender(4, 0), "F", version .. " invalid gender falls back to native")
    remove()
    T.eq(Pokemon.gender(4, 0), "F", version .. " gender unsubscribe restores predicate")
    remove = api.hooks:wrap("shiny.roll", function(next, ctx)
      T.eq(ctx.species, "CHARMANDER", version .. " shiny species is canonical")
      T.eq(ctx.personality, mon.personality, version .. " shiny uses saved PID")
      T.eq(next(ctx), true, version .. " downstream shiny keeps native result")
      return false
    end)
    T.eq(Pokemon.isShiny(mon), false, version .. " hook changes actual shiny accessor")
    mon.isShiny = true
    T.eq(Pokemon.isShiny(mon), true, version .. " forced native shiny remains authoritative")
    mon.isShiny = nil
    remove()
    T.eq(Pokemon.isShiny(mon), true, version .. " shiny unsubscribe restores predicate")
    T.same({ mon.personality, mon.ivs }, genes, version .. " pure hooks preserve saved genes")
    T.same(Rng.getState(), rng, version .. " accessor hooks never reroll RNG")
  end)

  exercise(version, "compatibility units and native egg decision", function()
    local session, api = setup(version)
    for _, tier in ipairs({ { false, false, 50, 177 }, { false, true, 70, 254 },
      { true, false, 20, 51 }, { true, true, 50, 128 } }) do
      local dc = pair(session, tier[1], tier[2])
      T.eq(Breeding.compatibility(dc, session), tier[3], version .. " native compatibility tier")
      local rng, calls = Rng.getState(), 0
      local remove = api.hooks:wrap("breeding.compatibility", function(next, ctx)
        calls = calls + 1
        T.eq(ctx.data, session.game.data, version .. " compatibility data handle")
        canonical(ctx.mon1, dc[1], session, version .. " first parent")
        canonical(ctx.mon2, dc[2], session, version .. " second parent")
        T.eq(ctx.dayCare, false, version .. " speculative compatibility context")
        return next(ctx)
      end)
      T.eq(Breeding.compatibility(dc, session), tier[3], version .. " observer preserves native tier")
      T.eq(calls, 1, version .. " native query invokes inherited hook once")
      remove()
      remove = api.hooks:wrap("breeding.compatibility", function(next, ctx)
        T.eq(next(ctx), tier[4], version .. " hook boundary exposes Gen2 compatibility units")
        return next(ctx)
      end)
      T.eq(Breeding.compatibility(dc, session), tier[3], version .. " repeated next preserves tier")
      remove()
      T.same(Rng.getState(), rng, version .. " compatibility query consumes no RNG")
    end
    local dc = pair(session)
    for _, score in ipairs({ 0, 51, 128, 177, 254, 255, -1, 999 }) do
      local remove = api.hooks:wrap("breeding.compatibility", function() return score end)
      local expected = (score <= 0 or score >= 255) and 0 or score < 70 and 20
        or score < 230 and 50 or 70
      T.eq(Breeding.compatibility(dc, session), expected, version .. " shared override " .. score)
      remove()
    end
    for _, invalid in ipairs({ "invalid", false, {} }) do
      local remove = api.hooks:wrap("breeding.compatibility", function() return invalid end)
      T.eq(Breeding.compatibility(dc, session), 50, version .. " invalid compatibility fallback")
      remove()
    end
    local level = dc[1].level
    local remove = api.hooks:wrap("breeding.compatibility", function(next, ctx)
      ctx.mon1.level, ctx.mon2.species = 42, "NO_SUCH_SPECIES"
      return next(ctx)
    end)
    T.eq(Breeding.compatibility(dc, session), 50, version .. " invalid record transaction falls back")
    T.eq(dc[1].level, level, version .. " failed transaction rolls back valid sibling edit")
    T.eq(dc[2].species, 4, version .. " failed transaction preserves invalid target")
    remove()
    remove = api.hooks:wrap("breeding.compatibility", function(next, ctx)
      ctx.mon2.species = "CHARMELEON"
      return next(ctx)
    end)
    T.eq(Breeding.compatibility(dc, session), 20, version .. " canonical parent edit changes native tier")
    T.eq(dc[2].species, 5, version .. " successful hook transaction writes native species")
    remove()
    T.eq(Breeding.compatibility(dc, session), 20, version .. " committed parent edit survives unsubscribe")
    dc = pair(session)

    local contexts, created = {}, 0
    api.events:on("breeding.egg_created", function() created = created + 1 end)
    remove = api.hooks:wrap("breeding.compatibility", function(_, ctx)
      contexts[#contexts + 1] = ctx
      return 0
    end)
    Rng.setState(nextRoll(0))
    Daycare.step(session)
    T.eq(Daycare.isEggPending(dc), false, version .. " hook refuses actual daycare egg decision")
    T.eq(#contexts, 1, version .. " native step uses inherited decision hook")
    T.eq(contexts[1] and contexts[1].dayCare, true, version .. " native step identifies daycare query")
    T.eq(created, 0, version .. " refusal constructs no egg")
    remove()
    dc.steps = { 254, 254 }
    Rng.setState(nextRoll(0))
    Daycare.step(session)
    T.eq(Daycare.isEggPending(dc), true, version .. " unsubscribe restores native egg decision")
    T.eq(created, 0, version .. " pending PID does not fabricate an egg record")

    local function produce(observe)
      Breeding.removeEgg(dc)
      dc.steps, dc.stepCounter = { 254, 254 }, 0
      local unsubscribe = observe and api.hooks:wrap("breeding.compatibility", function(next, ctx)
        return next(ctx)
      end)
      Rng.setState(nextRoll(0))
      Daycare.step(session)
      local out = { pending = dc.offspringPersonality, rng = Rng.getState() }
      if unsubscribe then unsubscribe() end
      return out
    end
    local vanilla = produce(false)
    T.same(produce(true), vanilla, version .. " decision observer preserves pending PID and RNG")
    T.same(produce(false), vanilla, version .. " decision unsubscribe preserves pending PID and RNG")
    Breeding.removeEgg(dc)
    dc[2].personality = 0
    dc.steps = { 254, 254 }
    local before = nextRoll(0)
    remove = api.hooks:wrap("breeding.compatibility", function(_, ctx)
      T.eq(ctx.dayCare, true, version .. " allowed override reaches native step")
      return 254
    end)
    Rng.setState(before)
    Daycare.step(session)
    T.eq(Daycare.isEggPending(dc), true, version .. " hook permits otherwise incompatible native pair")
    T.neq(Rng.getState().value, before.value, version .. " real egg decision advances native RNG")
    remove()
  end)

  exercise(version, "egg construction and post-hatch state", function()
    local session, api = setup(version)
    local dc = pair(session)
    dc[2].moves, dc[2].pp, dc[2].maxPp = { 57 }, { 15 }, { 15 }
    Breeding.triggerPendingEgg(session, dc)
    session.party, session.dex = {}, Dex.new()
    local created, once = {}, 0
    local remove = api.events:on("breeding.egg_created", function(ev)
      created[#created + 1] = ev
      T.eq(#session.party, 0, version .. " complete egg notification precedes grant")
      canonical(ev.mother, dc[1], session, version .. " egg mother")
      canonical(ev.father, dc[2], session, version .. " egg father")
      T.eq(ev.egg.species, "CHARMANDER", version .. " constructed egg species canonical")
      T.eq(ev.egg.isEgg, true, version .. " egg initialized before callback")
      T.eq(ev.compatibility, 177, version .. " creation compatibility is Gen2 score")
      T.eq(ev.stepsToEgg, 0, version .. " completed construction has zero remaining steps")
      T.eq(ev.egg.native.friendship, 20, version .. " initialized hatch-cycle byte")
      T.check(ev.egg.native.ivs.hp ~= nil and ev.egg.native.ivs.spd ~= nil,
        version .. " IVs initialized before construction notification")
      local inherited = false
      for _, move in ipairs(ev.egg.moves) do if move.id == "SURF" then inherited = true end end
      T.eq(inherited, true, version .. " inherited moves initialized before callback")
    end)
    api.events:once("breeding.egg_created", function() once = once + 1 end)
    local seed, pending = Rng.getState(), dc.offspringPersonality
    local egg = Breeding.giveEggFromDaycare(session)
    local built = copy(egg)
    local observedRng = Rng.getState()
    T.eq(#created, 1, version .. " actual egg construction notifies once")
    T.eq(once, 1, version .. " construction once listener retires")
    T.eq(session.party[1], egg, version .. " native grant puts constructed egg in party")
    T.eq(Dex.isCaught(session.dex, 4), false, version .. " egg grant does not register catch")
    T.eq(Daycare.isEggPending(dc), false, version .. " native grant clears pending egg")
    local view = created[1].egg
    view.moves[1].pp = 0
    view.native.ivs.hp = 99
    T.neq(egg.ivs.hp, 99, version .. " egg notification IVs are detached")
    T.neq(egg.pp[1], 0, version .. " egg notification moves are detached")
    remove()
    session.party = {}
    dc.offspringPersonality, dc.eggPending = pending, true
    Rng.setState(seed)
    local stock = Breeding.giveEggFromDaycare(session)
    T.eq(once, 1, version .. " later construction cannot rerun once listener")
    T.same(stock, built, version .. " egg observer preserves complete native record")
    T.same(Rng.getState(), observedRng, version .. " egg listener adds no construction RNG")

    session.party, session.dex = { egg }, Dex.new()
    local hatched = {}
    local removeHatch = api.events:on("egg.hatched", function(ev)
      hatched[#hatched + 1] = ev
      T.eq(session.party[ev.slot], egg, version .. " native hatch party state committed")
      T.eq(egg.isEgg, false, version .. " native egg bit cleared before callback")
      T.eq(Dex.isSeen(session.dex, 4), true, version .. " hatch registers seen before callback")
      T.eq(Dex.isCaught(session.dex, 4), true, version .. " hatch registers caught before callback")
      canonical(ev.mon, egg, session, version .. " hatchling record")
      T.eq(ev.egg.isEgg, true, version .. " hatch carries pre-mutation egg")
      T.eq(ev.mon.isEgg, false, version .. " hatch carries post-mutation mon")
      T.neq(ev.mon, ev.egg, version .. " egg and hatchling never alias")
      T.eq(ev.slot, 1, version .. " hatch slot is one based")
      T.eq(ev.species, "CHARMANDER", version .. " hatch species canonical")
      T.eq(ev.nickname, egg.nickname ~= "" and egg.nickname or nil,
        version .. " hatch nickname follows native result")
    end)
    local pid, ivs = egg.personality, {}
    for key, value in pairs(egg.ivs) do ivs[key] = value end
    local beforeHatch, hatchSeed = copy(egg), Rng.getState()
    Breeding.hatchMon(session, egg)
    local hatchRng, nativeHatch = Rng.getState(), copy(egg)
    T.eq(#hatched, 1, version .. " actual hatch emits exactly once")
    T.eq(egg.personality, pid, version .. " hatch preserves native personality")
    T.same(egg.ivs, ivs, version .. " hatch preserves inherited IVs")
    T.eq(egg.friendship, 120, version .. " hatch switches counter to friendship")
    T.eq(hatched[1].egg.native.friendship, 20, version .. " old egg counter remains detached")
    Breeding.hatchMon(session, egg)
    T.eq(#hatched, 1, version .. " repeated hatch call emits no duplicate")
    removeHatch()
    session.party, session.dex = { beforeHatch }, Dex.new()
    Rng.setState(hatchSeed)
    Breeding.hatchMon(session, beforeHatch)
    T.same(beforeHatch, nativeHatch, version .. " hatch unsubscribe preserves complete native record")
    T.same(Rng.getState(), hatchRng, version .. " hatch listener adds no native RNG")
    T.eq(#hatched, 1, version .. " unsubscribed hatch notification silent")
  end)

  exercise(version, "native Pokerus writes and policy", function()
    local session, api = setup(version)
    local enabled = require(Profile.forSession(session).saveRules).POKERUS == true
    local function spread(observe)
      session.party = { makeMon(session), makeMon(session, 16) }
      session.party[1].pokerus = 0x23
      local seen = {}
      local remove = observe and api.events:on("pokerus.infected", function(ev)
        seen[#seen + 1] = ev
        T.eq(ev.slot, 2, version .. " spread slot is one based")
        T.eq(ev.source, "spread", version .. " spread source contract")
        T.eq(ev.strain, 2, version .. " strain is high nibble")
        T.eq(ev.days, 3, version .. " days is low nibble")
        T.eq(session.party[2].pokerus, 0x23, version .. " infection written before callback")
        canonical(ev.mon, session.party[2], session, version .. " infected mon")
        canonical(ev.party[2], session.party[2], session, version .. " infected party member")
        T.neq(ev.party, session.party, version .. " party notification is detached")
      end)
      Rng.setState(nextRoll(0))
      Pokemon.partySpreadPokerus(session.party, session)
      local out = { bytes = { session.party[1].pokerus, session.party[2].pokerus }, rng = Rng.getState() }
      if remove then remove() end
      return out, seen
    end
    local stock = spread(false)
    local observed, seen = spread(true)
    T.same(observed, stock, version .. " spread observer preserves native bytes and RNG")
    T.eq(#seen, enabled and 1 or 0, version .. " spread notifications honor native policy")
    T.eq(observed.bytes[2], enabled and 0x23 or 0, version .. " spread uses native policy")
    T.same(spread(false), stock, version .. " spread unsubscribe preserves native stream")
    local contracted = {}
    local remove = api.events:on("pokerus.infected", function(ev)
      contracted[#contracted + 1] = ev
      T.eq(ev.source, "contracted", version .. " contraction source contract")
      T.eq(ev.slot, 1, version .. " contraction reports actual one based slot")
      local byte = session.party[1].pokerus
      T.eq(ev.strain, math.floor(byte / 16), version .. " contraction strain units")
      T.eq(ev.days, byte % 16, version .. " contraction day units")
      canonical(ev.mon, session.party[1], session, version .. " contracted mon")
    end)
    session.party = { makeMon(session) }
    Rng.setState(nextRoll(0x4000))
    Pokemon.randomlyGivePartyPokerus(session.party, session)
    T.eq(#contracted, enabled and 1 or 0, version .. " real random contraction notifies")
    local byte = session.party[1].pokerus
    Rng.setState(nextRoll(0x4000))
    Pokemon.randomlyGivePartyPokerus(session.party, session)
    T.eq(session.party[1].pokerus, byte, version .. " existing infection is not overwritten")
    Pokemon.updatePartyPokerusTime(10, session)
    T.eq(#contracted, enabled and 1 or 0, version .. " existing infection and cure do not notify")
    T.eq(session.party[1].pokerus % 16, 0, version .. " native cure spends days")
    session.party[2] = makeMon(session)
    Rng.setState(nextRoll(0))
    Pokemon.partySpreadPokerus(session.party, session)
    T.eq(#contracted, enabled and 1 or 0, version .. " cured carrier cannot infect")
    remove()
  end)

  exercise(version, "roamer routes and encounters", function()
    local session, api = setup(version)
    local prefix = Profile.forSession(session).family == "rse" and "RSE_ROUTE_" or "FR_ROUTE_"
    local a, b, c = prefix .. "1", prefix .. "2", prefix .. "3"
    local cfg = Roamer.config(session)
    fixture(Roamer._locations, cfg, { { a, b, c }, { b, a, c }, { c, a, b } })
    local function reset()
      session.roamer = { active = true, species = 16, level = cfg.level, map = a,
        personality = 123, hp = 40, status = 0, history = { false, false, false },
        ivs = { hp = 31, atk = 30, def = 29, spe = 28, spa = 27, spd = 26 } }
    end
    local moves, encounters = {}, {}
    local remove = api.events:on("roamer.moved", function(ev)
      moves[#moves + 1] = ev
      T.eq(session.roamer.map, ev.to, version .. " route changed before callback")
      T.neq(ev.from, ev.to, version .. " movement means actual route change")
      T.eq(ev.index, 1, version .. " single native roamer uses shared index")
      T.eq(ev.species, "PIDGEY", version .. " roamer species canonical")
      T.eq(ev.slot.map, ev.to, version .. " roamer slot carries new route")
    end)
    reset()
    Rng.SeedRng(0x1234)
    Roamer.move(session, "connection", a)
    T.eq(#moves, 1, version .. " native connection moves once")
    T.eq(moves[1].reason, "connection", version .. " connection reason inherited")
    local observed = { map = session.roamer.map, rng = Rng.getState() }
    remove()
    reset()
    Rng.SeedRng(0x1234)
    Roamer.move(session, "connection", a)
    T.same({ map = session.roamer.map, rng = Rng.getState() }, observed,
      version .. " movement unsubscribe preserves route and RNG")
    T.eq(#moves, 1, version .. " unsubscribed movement silent")
    remove = api.events:on("roamer.moved", function(ev) moves[#moves + 1] = ev end)
    Roamer.move(session, "warp", a)
    T.eq(#moves, 2, version .. " native warp emits one movement")
    T.eq(moves[2].reason, "jump", version .. " warp maps to inherited jump reason")
    session.roamer.active = false
    Roamer.moveToOtherSet(session)
    T.eq(#moves, 2, version .. " inactive slot cannot move or notify")
    remove()

    local removeEncounter = api.events:on("roamer.encountered", function(ev)
      encounters[#encounters + 1] = ev
      T.eq(ev.index, 1, version .. " encounter index is one based")
      T.eq(ev.species, "PIDGEY", version .. " encounter species canonical")
      T.eq(ev.level, session.roamer.level, version .. " encounter level unchanged")
      T.eq(ev.mapId, session.roamer.map, version .. " encounter uses local route")
    end)
    reset()
    local seed = nextRoll(0)
    Rng.setState(seed)
    T.eq(Roamer.tryEncounter(session, b), nil, version .. " remote route cannot encounter")
    T.same(Rng.getState(), seed, version .. " remote route consumes no encounter chance")
    T.eq(#encounters, 0, version .. " remote route emits no observer encounter")
    Rng.setState(nextRoll(1))
    T.eq(Roamer.tryEncounter(session, a), nil, version .. " failed native chance cannot encounter")
    T.eq(#encounters, 0, version .. " failed chance emits no observer encounter")
    Rng.setState(seed)
    local mon = Roamer.tryEncounter(session, a)
    local rng = Rng.getState()
    T.check(mon and mon.roamer == true, version .. " native local encounter succeeds")
    T.eq(#encounters, 1, version .. " successful encounter notifies once")
    removeEncounter()
    reset()
    Rng.setState(seed)
    T.same(Roamer.tryEncounter(session, a), mon, version .. " observer preserves native encounter")
    T.same(Rng.getState(), rng, version .. " observer adds no encounter RNG")
    session.roamer.active = false
    T.eq(Roamer.tryEncounter(session, a), nil, version .. " inactive roamer cannot encounter")
    session.roamer = nil
    T.eq(Roamer.tryEncounter(session, a), nil, version .. " empty roamer cannot encounter")
    T.eq(#encounters, 1, version .. " inactive and empty encounters emit nothing")
  end)

  exercise(version, "link commit save and once notifications", function()
    local session, api, game = setup(version)
    fixture(love, "graphics", nil)
    local receivedEvents, completedEvents, once = {}, {}, 0
    local saves, failSave = 0, false
    function game:saveGame()
      saves = saves + 1
      T.eq(#receivedEvents, #completedEvents, version .. " save precedes trade notifications")
      return not failSave
    end
    local journal
    fixture(LT, "journalIo", {
      read = function() return journal end,
      write = function(text) journal = text; return true end,
      remove = function() journal = nil; return true end,
    })
    fixture(LT, "loopbackCommit", false)
    local transaction
    local removeReceived = api.events:on("pokemon.received", function(ev)
      receivedEvents[#receivedEvents + 1] = ev
      T.eq(ev.from, "link", version .. " receive source inherited")
      T.eq(ev.peerName, "BLUE", version .. " receive peer inherited")
      canonical(ev.mon, session.party[1], session, version .. " received record")
      T.eq(Dex.isCaught(session.dex, session.party[1].species), true,
        version .. " received Dex state committed before callback")
      T.eq(transaction.saved, true, version .. " native save completed before callback")
      T.eq(LT.finishTrade(transaction), false, version .. " reentrant finish cannot duplicate trade")
    end)
    local removeCompleted = api.events:on("trade.completed", function(ev)
      completedEvents[#completedEvents + 1] = ev
      T.eq(#receivedEvents, #completedEvents, version .. " receive notification precedes completed")
      canonical(ev.sent, transaction.sent, session, version .. " sent record")
      canonical(ev.received, session.party[1], session, version .. " completed received record")
      T.eq(ev.evolveTo, nil, version .. " ordinary trade invents no evolution")
    end)
    api.events:once("trade.completed", function() once = once + 1 end)

    local function exchange(cancel, badBlock)
      LT.reset()
      Link.reset()
      local host, peer = FakeRelay.pair({ game = game, linkType = require("src.link.Game3Link").LINKTYPE.TRADE })
      host:update(0)
      peer:update(0)
      Link.attach(host)
      local remote = makeMon(session, 16, 254, 777)
      local packed = Protocol.packMon3(remote)
      LT.state, LT.cursor, LT.partnerCursor = "menu", 0, 0
      LT.peer = { name = "BLUE", trainerId = 777, version = Version.gameCode(version) }
      LT._peerPacked = { packed }
      LT._onDone = function() end
      T.eq(LT.beginTrade(), true, version .. " actual native block exchange starts")
      transaction = LT._transaction
      if cancel then
        T.eq(LT.abort("declined"), true, version .. " actual negotiation cancels")
        T.eq(LT.finishTrade(transaction), false, version .. " cancelled finish rejected")
        return
      end
      peer:update(0)
      local outgoing = peer:take(LT.MSG.MON)
      T.check(outgoing ~= nil, version .. " native trade sends offered block")
      peer:send({ type = LT.MSG.MON, name = "BLUE", trainerId = 777,
        mon = badBlock and {} or packed })
      LT.pump()
      if badBlock then
        T.eq(LT.state, "canceled", version .. " invalid real block refuses transaction")
        T.eq(LT.finishTrade(transaction), false, version .. " failed load cannot finish")
        return
      end
      T.eq(LT.state, "commit_wait", version .. " real block validated before commit")
      T.eq(LT.onCommit({ n = 1, digests = { "wrong", "wrong" } }), false,
        version .. " mismatched commit rejected")
      T.eq(LT.onCommit({ n = 1, digests = { LT._digest, LT._digest } }), true,
        version .. " matching native commit starts real scene")
      local guard = 0
      while Scene.isOpen() and guard < 20000 do
        Scene.peerConfirmed()
        Scene.step()
        LT.trySave()
        guard = guard + 1
      end
      T.eq(Scene.isOpen(), false, version .. " native trade scene finishes")
      T.eq(transaction.saved, not failSave, version .. " native transaction records save result")
      T.eq(LT.finishTrade(transaction), false, version .. " duplicate native finish rejected")
    end

    session.party = { makeMon(session, 4), makeMon(session, 5) }
    local sent = session.party[1]
    exchange(true)
    T.eq(session.party[1], sent, version .. " cancellation preserves offered mon")
    T.eq(#receivedEvents, 0, version .. " cancellation emits no receipt")
    T.eq(#completedEvents, 0, version .. " cancellation emits no completion")
    exchange(false, true)
    T.eq(session.party[1], sent, version .. " failed block preserves offered mon")
    T.eq(#completedEvents, 0, version .. " failed block emits no completion")
    exchange()
    T.eq(#receivedEvents, 1, version .. " successful native trade receives once")
    T.eq(#completedEvents, 1, version .. " successful native trade completes once")
    T.eq(once, 1, version .. " trade once listener retires")
    T.eq(saves, 1, version .. " real trade saves exactly once")
    local previous = session.party[1]
    exchange()
    T.eq(transaction.sent, previous, version .. " later trade accepts previously received object")
    T.eq(#completedEvents, 2, version .. " later transaction is not suppressed")
    T.eq(once, 1, version .. " later transaction cannot rerun once subscription")
    failSave = true
    exchange()
    T.eq(transaction.saved, false, version .. " failed native save stays visible")
    T.eq(#receivedEvents, 2, version .. " failed save emits no successful receipt")
    T.eq(#completedEvents, 2, version .. " failed save emits no successful completion")
    failSave = false
    removeReceived()
    removeCompleted()
    exchange()
    T.eq(#receivedEvents, 2, version .. " receive unsubscribe silences actual trade")
    T.eq(#completedEvents, 2, version .. " completion unsubscribe silences actual trade")
    T.eq(transaction.saved, true, version .. " unsubscribed native transaction still saves")
  end)
end

Scene.cancel()
LT.reset()
Link.reset()
for i = #restore, 1, -1 do restore[i]() end
ModRuntime.install(savedRuntime[1], savedRuntime[2], savedRuntime[3])
Rng.setState(originalRng)
Version.set(originalVersion)
T.finish()
