package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Loader = require("src.mods.Loader")
local Runtime = require("src.mods.Runtime")
local GameVersion = require("src.core.GameVersion")
local Merge = require("src.mods.Merge")
local Records = require("src.mods.UnifiedRecords")
local Callbacks = require("src.mods.UnifiedCallbacks")
local CallSites = require("tests.modkit.callback_sites").scan("src")

local GEN2_ONLY = {}
for name in ([[intro.boot.copyright intro.boot.gamefreak intro.boot.title intro.boot.movie
  intro.boot.movie_ended clock.day_changed phone.call_received radio.channel mail.written
  mail.read unown.unlocked apricorn.converted bug_contest.scored phone.contact_list
  ]]):gmatch("%S+") do GEN2_ONLY[name] = true end
local function pack(...) return { n = select("#", ...), ... } end
local originalVersion = GameVersion.get()
local VERSIONS = { "red", "blue", "yellow", "gold", "silver", "crystal",
  "firered", "leafgreen", "ruby", "sapphire", "emerald" }

local CATALOG = {
  events = {
    [[mods.loaded assets.transformed game.ready save.created save.loading save.loaded
      save.writing checkpoint.restored screen.pushed screen.popped flag.changed
      music.started music.stopped sound.played discord.join_requested
      map.entered map.exited map.reloaded player.warped world.stepped
      world.block_replaced world.object_toggled world.npc_spawned world.interacted
      world.trainer_engaged world.blacked_out world.boulder_moved
      battle.started battle.ended battle.turn_started battle.turn_ended
      battle.move_used battle.damage_dealt battle.status_inflicted battle.fainted
      battle.battler_switched battle.exp_gained battle.ball_thrown pokemon.caught
      pokemon.level_up pokemon.move_learned pokemon.evolved pokemon.before_give
      intro.oak_speech.started intro.oak_speech.step intro.oak_speech.answered
      intro.oak_speech.finished world.live_maps_preparing world.live_maps_updated
      world.tod_changed link.connected link.ended link.battle_ended link.desync
      pokemon.received trade.completed script.started script.ended
      mod.options_changed]],
    [[intro.boot.copyright intro.boot.gamefreak intro.boot.title intro.boot.movie
      intro.boot.movie_ended clock.day_changed phone.call_received radio.channel
      breeding.egg_created egg.hatched happiness.changed pokerus.infected
      mail.written mail.read roamer.moved roamer.encountered unown.unlocked
      apricorn.converted bug_contest.scored]],
  },
  hooks = {
    [[core.update core.quit_to_launcher core.logic_speed input.step input.key
      input.gamepad input.wheel input.pointer render.hud render.viewport render.window
      zoom.range screen.render_visible save.write save.new_game
      music.select music.volume pokemon.sprite pokemon.icon
      movement.collision warp.destination world.follower.spawn world.talk
      encounter.table encounter.roll encounter.species trainer.party evolution.check
      battle.accuracy battle.damage battle.crit battle.charge_required battle.run
      battle.turn_order battle.enemy_action battle.low_health_alarm catch.rate
      exp.gain item.use script.command ui.start_menu.items
      render.zones render.compose render.output_enabled render.output render.letterbox
      player.sprite movement.speed world.tod map.palette fieldmove.eligibility
      encounter.fishing link.fingerprint ui.title_menu.items ui.pc.items ui.list_menu
      ui.options.rows ui.naming.grid ui.party.submenu ui.party.grid_navigation
      intro.oak_speech.build battle.status_hud_visible battle.move_grid_navigation
      battle.overlay battle.exp_award battle.bottom_ui_visible battle.catch_exp
      trainer.before_battle battle.caught_marker_visible battle.menu_auxiliary
      battle.field_residual pokemon.level_visible battle.style catch.nickname
      catch.party_full transition.style]],
    [[shiny.roll gender.roll held_item.trigger breeding.compatibility phone.contact_list
      battle.enemy_switch_or_item]],
  },
}
local expectedCatalog, catalogSource = {}, { "local catalog = {}" }
for _, surface in ipairs({ "events", "hooks" }) do
  expectedCatalog[surface] = {}
  catalogSource[#catalogSource + 1] = ("catalog.%s = {%q, %q}")
    :format(surface, CATALOG[surface][1], CATALOG[surface][2])
  for introduction, names in ipairs(CATALOG[surface]) do
    for name in names:gmatch("%S+") do expectedCatalog[surface][name] = introduction end
  end
end

local REGISTRATION = table.concat(catalogSource, "\n") .. "\n" .. [[
local mod = ...
local out = mod.exports
out.catalog, out.contexts = { events = {}, hooks = {} }, {}
for surface, groups in pairs(catalog) do
  for _, names in ipairs(groups) do
    for name in names:gmatch("%S+") do
      local entry = { calls = 0, onceCalls = 0, supported = mod:supports(surface, name) }
      out.catalog[surface][name] = entry
      if surface == "events" then
        entry.remove = mod.events:on(name, function()
          entry.calls = entry.calls + 1
        end)
        entry.removeOnce = mod.events:once(name, function()
          entry.onceCalls = entry.onceCalls + 1
        end)
      else
        entry.remove = mod.hooks:wrap(name, function(next, ...)
          entry.calls = entry.calls + 1
          if name == "shiny.roll" or name == "gender.roll" then out.contexts[name] = (...) end
          return next(...)
        end)
      end
    end
  end
end
out.unknown = {}
for _, surface in ipairs({ "events", "hooks" }) do
  local name = "battle.no_such_callback"
  local ok, reason = pcall(function()
    if surface == "hooks" then mod.hooks:wrap(name, function(next, ...) return next(...) end)
    else mod.events:on(name, function() end) end
  end)
  out.unknown[surface] = { ok = ok, reason = reason }
end
out.unknownOnce = pcall(function()
  mod.events:once("battle.no_such_callback", function() end)
end)
]]

local function dataFor(generation)
  if generation == 3 then return T.sdk.gen3Data() end
  local data = { pokemon = {}, moves = {}, items = {}, maps = {}, text = {},
    trainers = {}, encounters = {}, type_chart = { types = {}, matchups = {} } }
  for _, id in ipairs({ "PIDGEY", "MEW" }) do
    local stats = { hp = 100, attack = 100, defense = 100, speed = 100 }
    if generation == 1 then stats.special = 100
    else stats.specialAttack, stats.specialDefense = 100, 100 end
    local row = { id = id, name = id, dex = id == "MEW" and 151 or 16,
      types = { "NORMAL" }, baseStats = stats, catchRate = 45, baseExp = 64,
      growthRate = "MEDIUM_FAST", evolutions = {}, tmhm = {},
      spriteFront = "front.png", spriteBack = "back.png" }
    if generation == 1 then
      row.frontSize, row.level1Moves, row.learnset = 5, { "POUND" }, {}
    else row.picSize, row.levelMoves = 5, { { level = 1, move = "POUND" } } end
    data.pokemon[id] = row
  end
  if generation == 2 then
    data.pokemon.growthRates = { MEDIUM_FAST = {
      numerator = 1, denominator = 1, squared = 0, linear = 0, constant = 0 } }
  end
  for _, id in ipairs({ "POUND", "SURF" }) do
    data.moves[id] = { id = id, name = id, type = "NORMAL", power = 40,
      accuracy = 100, pp = id == "POUND" and 35 or 15,
      effect = generation == 1 and "NO_ADDITIONAL_EFFECT" or "EFFECT_NORMAL_HIT" }
  end
  data.items.POTION = { id = "POTION", name = "POTION", price = 300 }
  return data
end

local function nativeMon(generation)
  local mon = { species = generation == 3 and 16 or "PIDGEY", nickname = "BIRD",
    level = 5, hp = 20, maxHp = 30,
    status = generation == 3 and 8 or generation == 2 and "poison" or "PSN" }
  if generation == 3 then
    mon.stats = { hp = 30, atk = 12, def = 13, spe = 14, spa = 15, spd = 16 }
    mon.moves, mon.pp, mon.maxPp = { 1 }, { 10 }, { 35 }
  else
    mon.stats = { hp = 30, attack = 12, defense = 13, speed = 14 }
    if generation == 1 then mon.stats.special = 15
    else mon.stats.specialAttack, mon.stats.specialDefense = 15, 16 end
    mon.moves = { { id = "POUND", pp = 10, maxPp = 35 } }
  end
  return mon
end

local function addMod(files, id, api, body)
  files["mods/" .. id .. "/manifest.json"] = ('{"id":"%s","name":"%s",'
    .. '"version":"1.0.0","api":%d,"games":["all"],"entry":"main.lua"}')
    :format(id, id, api)
  files["mods/" .. id .. "/main.lua"] = body
end

local function load(files, generation, version)
  GameVersion.set(version)
  T.sdk.captureRuntime()
  local loader = Loader.new({ fs = T.sdk.memfs(files), generation = generation,
    version = version, dev = true })
  local data = dataFor(generation)
  loader.game = { data = data, generation = generation, phase = "field" }
  local ok, result = pcall(loader.load, loader, data)
  T.check(ok, version .. " Loader completes: " .. tostring(result))
  return loader, ok and result
end

local COMMON = [[
local mod = ...
local out = mod.exports
out.mode = "pass"
out.eventCalls, out.onceCalls, out.removedCalls = 0, 0, 0
mod.events:on("battle.move_used", function(ev)
  out.eventCalls = out.eventCalls + 1
  out.event = ev
  out.recordOK = ev.user.species == "PIDGEY" and ev.user.mon.species == "PIDGEY"
    and ev.user.nickname == "BIRD" and ev.user.stats.special == 15
    and ev.user.stats.attack == 12 and ev.user.stats.specialAttack == 15
    and ev.user.stats.specialDefense == (mod.generation == 1 and 15 or 16)
    and ev.user.status == "PSN" and ev.user.moves[1].id == "POUND"
    and ev.move.id == "POUND" and ev.moveId == "POUND"
  ev.user.hp = 1
  ev.user.mon.native.hp = 2
end, 10)
mod.events:on("pokemon.before_give", function(ev)
  out.giftCalls = (out.giftCalls or 0) + 1
  if out.invalidGift then
    ev.mon.nickname, ev.mon.hp, ev.mon.stats.special, ev.mon.status = "PORTABLE", 7, 31, "BRN"
    ev.pokemon.species = "NO_SUCH_SPECIES"
  else
    ev.mon.nickname, ev.mon.hp, ev.level = "PORTABLE", 7, 9
    ev.mon.stats.special, ev.mon.status = 31, "BRN"
    ev.species = "MEW"
  end
end, 10)
mod.events:once("mod.a_callbacks.once", function()
  out.onceCalls = out.onceCalls + 1
end)
out.unsubscribe = mod.events:on("mod.a_callbacks.removed", function()
  out.removedCalls = out.removedCalls + 1
end)
mod.events:once("mod.a_callbacks.once_error", function()
  out.onceErrors = (out.onceErrors or 0) + 1
  error("intentional once error")
end)
mod.events:on("mod.foreign.pulse", function(ev) out.foreign = ev end)
out.emit = function(name, payload) return mod.events:emit(name, payload) end
out.levelVisible = mod:supports("hooks", "pokemon.level_visible")
mod.hooks:wrap("battle.accuracy", function(next, ctx)
  out.scalarBefore = ctx.moveId
  out.scalarSource = ctx.source
  ctx.moveId = "SURF"
  return next(ctx)
end, 10)
mod.hooks:wrap("encounter.roll", function(next, tables, ctx)
  if out.encounterMode == "before" then error("intentional before encounter next") end
  local encounter, middle, tail = next(tables, ctx)
  out.rollSpecies = encounter and encounter.species
  if encounter and out.changeEncounter then encounter.species = "MEW" end
  if out.encounterMode == "after" then error("intentional after encounter next") end
  return encounter, middle, tail
end)
mod.hooks:wrap("encounter.species", function(next, encounter, ctx)
  if out.encounterMode == "before" then error("intentional before encounter next") end
  out.speciesBefore = encounter and encounter.species
  local result, middle, tail = next(encounter, ctx)
  out.speciesAfter = result and result.species
  if result and out.changeEncounter then result.species = "MEW" end
  if out.encounterMode == "after" then error("intentional after encounter next") end
  return result, middle, tail
end)
mod.hooks:wrap("trainer.party", function(next, class, id, party)
  out.partyBefore = party[1].species
  local result, middle, tail = next(class, id, party)
  out.partyAfter = result[1].species
  if out.changeParty then
    result[1].species = "MEW"
    result[1].moves = { { id = "SURF", pp = 10, maxPp = 15 } }
  end
  return result, middle, tail
end)
out.unhook = mod.hooks:wrap("core.update", function(next, ...)
  if out.mode == "before" then error("intentional before next") end
  if out.mode == "nil" then return nil, "blocked", nil end
  if out.mode == "empty" then return end
  if out.mode == "swallow" then
    pcall(next, ...)
    error("intentional after swallowed vanilla error")
  end
  local a, b, c = next(...)
  if out.mode == "twice" then next(...) end
  if out.mode == "after" then error("intentional after next") end
  return a, b, c
end)
out.unhookMenu = mod.hooks:wrap("ui.start_menu.items", function(next, game, rows)
  rows = next(game, rows)
  if out.menuMode == "replace" then
    rows[1].onSelect = function(...)
      out.selected, out.selectedArgs, out.selectedGame = "replaced", select("#", ...), game
    end
    rows[#rows + 1] = { id = "portable", label = "PORTABLE", onSelect = function(...)
      out.selected, out.selectedArgs, out.selectedGame = "added", select("#", ...), game
    end }
  elseif out.menuMode == "legacy" then
    return { { id = "exit", label = "LEAVE" } }
  elseif out.menuMode == "invalid" then
    rows[1].label = "BROKEN"
    return out.invalidRows
  end
  return rows
end)
]]

local LEGACY = [[
local mod = ...
mod.events:on("battle.move_used", function(ev) mod.exports.event = ev end, -10)
mod.events:on("pokemon.before_give", function(ev) mod.exports.gift = ev end, -10)
mod.hooks:wrap("battle.accuracy", function(next, ctx)
  mod.exports.moveId = ctx.moveId
  return next(ctx)
end, -10)
]]

local function filesFor()
  local files = {}
  addMod(files, "a_callbacks", 3, COMMON)
  addMod(files, "b_legacy", 2, LEGACY)
  return files
end

local function checkCallbacks(version)
  local generation = GameVersion.generation(version)
  local loader, result = load(filesFor(), generation, version)
  T.eq(result, true, version .. " complete load succeeds")
  T.eq(#loader.errors, 0, version .. " callbacks load without errors")
  local out, legacy = loader.exports.a_callbacks, loader.exports.b_legacy
  if not out or not legacy then T.sdk.restoreRuntime(); return end
  local mon = nativeMon(generation)
  local move = { id = generation == 3 and 1 or "POUND", power = 40, pp = 35 }
  local event = { user = { mon = mon, side = "player" }, move = move,
    moveId = generation == 3 and 1 or "POUND" }
  Runtime.emit("battle.move_used", event)
  T.eq(out.recordOK, true, version .. " canonical battler, stats, status and move IDs")
  T.eq(out.eventCalls, 1, version .. " portable listener runs once")
  T.eq(mon.hp, 20, version .. " notification record and native extension are detached")
  T.check(legacy.event == event, version .. " API 2 listener retains native payload identity")
  T.check(out.event ~= event, version .. " API 3 notification has its own view")
  T.eq(out.levelVisible, true, version .. " level visibility capability is inherited")

  local gift = { mon = nativeMon(generation), species = "PIDGEY", level = 5 }
  Runtime.emit("pokemon.before_give", gift)
  T.eq(out.giftCalls, 1, version .. " mutable callback ran")
  T.eq(gift.mon.nickname, "PORTABLE", version .. " before_give writes native nickname")
  T.eq(gift.mon.hp, 7, version .. " before_give writes native HP")
  T.eq(gift.mon.status, generation == 3 and 16 or generation == 2 and "burn" or "BRN",
    version .. " before_give writes native status")
  local giftView = Records.mon(gift.mon, generation, loader.game.data, version)
  T.eq(giftView.stats.special, 31, version .. " before_give writes common Special")
  T.eq(giftView.stats.specialAttack, 31, version .. " before_give writes Special Attack")
  T.eq(giftView.stats.specialDefense, 31, version .. " before_give writes Special Defense")
  T.eq(gift.level, 9, version .. " before_give writes scalar level")
  T.eq(gift.species, "MEW", version .. " before_give accepts canonical species")
  T.check(legacy.gift == gift, version .. " legacy listener sees the mutable native gift")
  out.invalidGift = true
  local invalid = { mon = nativeMon(generation), pokemon = nativeMon(generation) }
  local pristine = Merge.deepCopy(invalid)
  Runtime.emit("pokemon.before_give", invalid)
  T.same(invalid, pristine, version .. " invalid second record leaves both native records intact")
  out.invalidGift = false

  local record = nativeMon(generation)
  local data = loader.game.data
  local view = Records.mon(record, generation, data, version)
  local original = Merge.deepCopy(record)
  T.eq(Records.applyMon(record, view, generation, data, version), true,
    version .. " real Records backend accepts its unchanged view")
  T.same(record, original, version .. " unchanged view preserves native stats and status representation")
  for _, patch in ipairs({
      { nickname = "REJECTED", hp = 7, stats = { special = 31 }, status = "NO_SUCH_STATUS" },
      { nickname = "REJECTED", hp = 7, stats = { special = 31, specialAttack = 32 }, status = "BRN" },
    }) do
    local ok, reason = Records.applyMon(record, patch, generation, data, version)
    T.eq(ok, nil, version .. " invalid Gen 1-shaped record write is rejected")
    T.eq(type(reason), "string", version .. " rejected record write explains the failure")
    T.same(record, original, version .. " rejected nickname, Special and status writes are atomic")
  end
  T.eq(Records.applyMon(record, { nickname = "PORTABLE", stats = { special = 31 }, status = "BRN" },
    generation, data, version), true, version .. " real Records backend accepts Gen 1-shaped writes")
  T.eq(record.nickname, "PORTABLE", version .. " Records writes raw native nickname")
  T.eq(record.status, generation == 3 and 16 or generation == 2 and "burn" or "BRN",
    version .. " Records writes native status representation")
  T.eq(record.stats[generation == 1 and "special" or generation == 2 and "specialAttack" or "spa"],
    31, version .. " Records writes native common Special")
  if generation == 1 then
    T.eq(record.stats.specialAttack, nil, version .. " native Gen 1 has no Special Attack field")
    T.eq(record.stats.specialDefense, nil, version .. " native Gen 1 has no Special Defense field")
  else
    T.eq(record.stats[generation == 2 and "specialDefense" or "spd"], 31,
      version .. " common Special writes both native split stats")
  end
  view = Records.mon(record, generation, data, version)
  T.eq(view.nickname, "PORTABLE", version .. " raw nickname reads back")
  T.eq(view.stats.special, 31, version .. " common Special reads back")
  T.eq(view.status, "BRN", version .. " status reads back as a Gen 1 short ID")
  original = Merge.deepCopy(record)
  T.eq(Records.applyMon(record, { status = "burn" }, generation, data, version), true,
    version .. " lowercase status alias is accepted")
  T.same(record, original, version .. " equivalent status alias preserves the native record")
  T.eq(Records.applyMon(record, { name = "ALIAS", status = false }, generation, data, version), true,
    version .. " display name alias and status clearing remain supported")
  T.eq(record.nickname, "ALIAS", version .. " display name alias writes native nickname")
  T.eq(record.status, generation == 3 and 0 or nil, version .. " status clearing uses native healthy value")
  T.eq(Records.mon(record, generation, data, version).status, nil,
    version .. " cleared status reads as nil")

  local accuracyCalls = 0
  local scalar = { moveId = generation == 3 and 1 or "POUND", source = "weather" }
  local accuracy = Runtime.call("battle.accuracy", function(ctx)
    accuracyCalls = accuracyCalls + 1
    T.eq(ctx.moveId, generation == 3 and 57 or "SURF", version .. " scalar move ID writeback")
    T.eq(ctx.source, "weather", version .. " unrelated source retains its role")
    return true
  end, scalar)
  T.eq(accuracy, true, version .. " scalar change reaches vanilla")
  T.eq(accuracyCalls, 1, version .. " scalar conversion calls vanilla once")
  T.eq(out.scalarBefore, "POUND", version .. " scalar input is canonical")
  T.eq(out.scalarSource, "weather", version .. " public source is not mistaken for a move")
  T.eq(legacy.moveId, generation == 3 and 57 or "SURF", version .. " legacy hook sees native changed ID")

  for _, hook in ipairs({ "encounter.roll", "encounter.species" }) do
    for _, change in ipairs({ false, true }) do
      out.changeEncounter = change
      local native = { species = generation == 3 and 16 or "PIDGEY", level = 5 }
      local calls = 0
      local values = pack(Runtime.call(hook, function()
        calls = calls + 1
        return native, nil, "tail"
      end, hook == "encounter.roll" and {} or native, { mapId = "FR_ROUTE_1" }))
      T.eq(calls, 1, version .. " " .. hook .. " vanilla once")
      T.eq(values.n, 3, version .. " " .. hook .. " return count")
      T.eq(values[2], nil, version .. " " .. hook .. " nil middle return")
      T.eq(values[3], "tail", version .. " " .. hook .. " trailing result")
      if not change then
        T.check(values[1] == native, version .. " " .. hook .. " keeps unchanged native record identity")
      end
      T.eq(values[1].species, generation == 3 and (change and 151 or 16)
        or (change and "MEW" or "PIDGEY"), version .. " " .. hook .. " native species return")
      T.eq(hook == "encounter.roll" and out.rollSpecies or out.speciesAfter,
        "PIDGEY", version .. " " .. hook .. " post-next receives canonical record")
    end
    for _, mode in ipairs({ "before", "after" }) do
      out.encounterMode, out.changeEncounter = mode, true
      local native = { species = generation == 3 and 16 or "PIDGEY", level = 5 }
      local calls = 0
      local values = pack(Runtime.call(hook, function()
        calls = calls + 1
        return native, nil, "kept"
      end, hook == "encounter.roll" and {} or native, {}))
      T.eq(calls, 1, version .. " " .. hook .. " " .. mode .. " error executes vanilla once")
      T.check(values[1] == native, version .. " " .. hook .. " " .. mode .. " error retains native identity")
      T.eq(native.species, generation == 3 and 16 or "PIDGEY",
        version .. " " .. hook .. " " .. mode .. " error discards public changes")
      T.same({ n = values.n, [2] = values[2], [3] = values[3] },
        { n = 3, [3] = "kept" }, version .. " " .. hook .. " " .. mode .. " error preserves tuple")
    end
    out.encounterMode = nil
    local absent = pack(Runtime.call(hook, function() return nil, "absent", nil end,
      {}, {}))
    T.same(absent, { n = 3, [2] = "absent" }, version .. " " .. hook .. " nil encounter tuple")
  end
  local party = { nativeMon(generation) }
  local partyCalls = 0
  out.changeParty = true
  local returned = pack(Runtime.call("trainer.party", function(_, _, native)
    partyCalls = partyCalls + 1
    return native, nil, "party-tail"
  end, "RIVAL", 1, party))
  T.eq(partyCalls, 1, version .. " trainer vanilla once")
  T.eq(out.partyBefore, "PIDGEY", version .. " trainer input species canonical")
  T.eq(out.partyAfter, "PIDGEY", version .. " trainer downstream species canonical")
  T.eq(returned[1][1].species, generation == 3 and 151 or "MEW", version .. " trainer native species")
  local rawMove = returned[1][1].moves[1]
  T.eq(type(rawMove) == "table" and rawMove.id or rawMove,
    generation == 3 and 57 or "SURF", version .. " trainer native move")
  T.same({ n = returned.n, [2] = returned[2], [3] = returned[3] },
    { n = 3, [3] = "party-tail" }, version .. " trainer extra returns")

  out.emit("mod.a_callbacks.once", {})
  out.emit("mod.a_callbacks.once", {})
  T.eq(out.onceCalls, 1, version .. " once listener retires")
  out.unsubscribe(); out.unsubscribe()
  out.emit("mod.a_callbacks.removed", {})
  T.eq(out.removedCalls, 0, version .. " repeated unsubscribe is safe")
  out.emit("mod.a_callbacks.once_error", {})
  out.emit("mod.a_callbacks.once_error", {})
  T.eq(out.onceErrors, 1, version .. " throwing once listener also retires")
  local foreign = { species = 16, marker = true }
  Runtime.emit("mod.foreign.pulse", foreign)
  T.check(out.foreign == foreign, version .. " foreign custom subscription is legal and opaque")
  for _, name in ipairs({ "mod.foreign.pulse", "battle.move_used", "mod.a_callbacks." }) do
    T.eq(pcall(out.emit, name, {}), false, version .. " rejects forged event " .. name)
  end

  for _, mode in ipairs({ "pass", "twice", "before", "after", "nil", "empty" }) do
    out.mode = mode
    local calls = 0
    local values = pack(Runtime.call("core.update", function(game, middle, last)
      calls = calls + 1
      T.check(game == loader.game, version .. " " .. mode .. " preserves game handle")
      T.eq(middle, nil, version .. " " .. mode .. " preserves nil argument")
      T.eq(last, "argument", version .. " " .. mode .. " preserves third argument")
      return nil, "vanilla", nil
    end, loader.game, nil, "argument"))
    T.eq(calls, (mode == "nil" or mode == "empty") and 0 or 1,
      version .. " " .. mode .. " vanilla execution count")
    T.same(values, mode == "empty" and { n = 0 }
      or { n = 3, [2] = mode == "nil" and "blocked" or "vanilla" },
      version .. " " .. mode .. " preserves nil and multiple results")
  end
  for _, mode in ipairs({ "pass", "before", "after", "swallow" }) do
    out.mode = mode
    local calls = 0
    local ok = pcall(Runtime.call, "core.update", function()
      calls = calls + 1
      error("intentional vanilla error")
    end, loader.game)
    T.eq(ok, false, version .. " " .. mode .. " propagates vanilla failure")
    T.eq(calls, 1, version .. " " .. mode .. " never retries throwing vanilla")
  end
  out.unhook(); out.unhook()
  T.eq(Runtime.wantsHook("core.update"), false, version .. " hook unsubscribe removes empty chain")
  T.sdk.restoreRuntime()
end

for _, version in ipairs(VERSIONS) do checkCallbacks(version) end

T.same(Callbacks.catalog(), expectedCatalog, "catalog retains authoritative introduction generations")
local detachedCatalog = Callbacks.catalog()
detachedCatalog.hooks["pokemon.level_visible"] = nil
detachedCatalog.events["game.ready"] = 3
T.same(Callbacks.catalog(), expectedCatalog, "catalog metadata is detached")

for _, version in ipairs(VERSIONS) do
  local generation = GameVersion.generation(version)
  local files = {}
  addMod(files, "a_catalog", 3, REGISTRATION)
  local loader, result = load(files, generation, version)
  T.eq(result, true, version .. " unchanged catalog source loads")
  T.eq(#loader.errors, 0, version .. " catalog registration has no errors")
  local out = loader.exports.a_catalog
  if out then
    for surface, names in pairs(expectedCatalog) do
      local bus = surface == "events" and loader.events.listeners or loader.hooks.chains
      for name, introduction in pairs(names) do
        local entry = out.catalog[surface][name]
        T.check(entry ~= nil, version .. " registers " .. surface .. " " .. name)
        local expected = CallSites[surface][name] ~= nil and CallSites[surface][name][generation] == true
        if GEN2_ONLY[name] then expected = generation == 2 end
        T.eq(entry and entry.supported, expected,
          version .. " native capability " .. name)
        local subscriptions = bus[name] or {}
        T.eq(#subscriptions, surface == "hooks" and 1 or name == "mods.loaded" and 1 or 2,
          version .. " native bus subscription keys " .. name)
        for _, subscription in ipairs(subscriptions) do
          T.eq(subscription.owner, "a_catalog", version .. " subscription owner " .. name)
        end
      end
      T.eq(out.unknown[surface].ok, false, version .. " unknown " .. surface .. " rejected")
      T.check(tostring(out.unknown[surface].reason):find("battle.no_such_callback", 1, true) ~= nil,
        version .. " unknown callback diagnostic names the callback")
      T.eq(bus["battle.no_such_callback"], nil, version .. " unknown callback leaves no bus key")
    end
    T.eq(out.unknownOnce, false, version .. " unknown once callback rejected")
    local spawned = out.catalog.events["world.npc_spawned"]
    Runtime.emit("world.npc_spawned", { mapId = "ROUTE_1", object = { id = "ROUTE_1_obj_1" } })
    Runtime.emit("world.npc_spawned", { mapId = "ROUTE_1", object = { id = "ROUTE_1_obj_2" } })
    T.eq(spawned.calls, 2, version .. " known event reaches on subscription")
    T.eq(spawned.onceCalls, 1, version .. " known event once subscription retires")

    for _, name in ipairs({ "shiny.roll", "gender.roll" }) do
      local def = generation == 3
        and { baseStats = Merge.deepCopy(loader.game.data.gen3Pokemon._stats[16]) }
        or Merge.deepCopy(loader.game.data.pokemon.PIDGEY)
      def.id, def.genderRatio = generation == 3 and 16 or "PIDGEY", 127
      local dvs = { attack = 2, defense = 10, speed = 10, special = 10 }
      local ctx = { species = def.id, def = def, dvs = dvs, level = 5 }
      if name == "gender.roll" then ctx.ratio = 127 end
      local rolled = name == "gender.roll" and "female" or false
      local calls = 0
      local values = pack(Runtime.call(name, function(native)
        calls = calls + 1
        T.check(native == ctx, version .. " roll keeps native context identity")
        T.check(native.dvs == dvs and native.def == def, version .. " roll keeps native named records")
        return rolled, nil, "roll-tail"
      end, ctx))
      T.eq(calls, 1, version .. " manual roll calls vanilla once " .. name)
      T.same(values, { n = 3, [1] = rolled, [3] = "roll-tail" }, version .. " roll tuple " .. name)
      local public = out.contexts[name]
      T.check(public ~= nil and public ~= ctx, version .. " named roll context reaches wrapper " .. name)
      if public then
        T.eq(public.species, "PIDGEY", version .. " roll species is canonical " .. name)
        T.eq(public.def.id, "PIDGEY", version .. " roll species definition is canonical " .. name)
        T.same(public.dvs, dvs, version .. " roll DVs need no move or PP fields " .. name)
        T.eq(public.level, 5, version .. " roll level survives " .. name)
        T.eq(public.ratio, ctx.ratio, version .. " roll ratio survives " .. name)
      end
    end
    for surface, entries in pairs(out.catalog) do
      local bus = surface == "events" and loader.events.listeners or loader.hooks.chains
      for name, entry in pairs(entries) do
        entry.remove(); entry.remove()
        if entry.removeOnce then entry.removeOnce(); entry.removeOnce() end
        T.eq(bus[name], nil, version .. " repeated unsubscribe removes known callback " .. name)
      end
    end
    Runtime.emit("world.npc_spawned", { mapId = "ROUTE_1", object = {} })
    T.eq(spawned.calls, 2, version .. " removed known event stays retired")
    local calls = out.catalog.hooks["shiny.roll"].calls
    T.eq(Runtime.call("shiny.roll", function() return true end, {}), true,
      version .. " unsubscribed hook leaves vanilla result")
    T.eq(out.catalog.hooks["shiny.roll"].calls, calls, version .. " removed known hook stays retired")
    T.eq(#loader.errors, 0, version .. " manual catalog dispatch has no errors")
  end
  T.sdk.restoreRuntime()
end

for _, version in ipairs(VERSIONS) do
  local files = filesFor()
  addMod(files, "z_failure", 3, REGISTRATION .. [[
    local mod = ...
    mod.events:on("game.ready", function() error("leaked event") end)
    mod.hooks:wrap("core.quit_to_launcher", function() error("leaked hook") end)
    error("intentional callback rollback")
  ]])
  local loader, result = load(files, GameVersion.generation(version), version)
  T.eq(result, false, version .. " failed mod returns complete load failure")
  T.eq(#loader.errors, 1, version .. " reports only intentional entry failure")
  T.check(tostring(loader.errors[1]):find("intentional callback rollback", 1, true) ~= nil,
    version .. " failure reaches intended rollback point")
  T.eq(loader.exports.z_failure, nil, version .. " failed exports removed")
  T.eq(loader.events.listeners["game.ready"], nil, version .. " failed event removed")
  T.eq(loader.hooks.chains["core.quit_to_launcher"], nil, version .. " failed hook removed")
  for surface, names in pairs(expectedCatalog) do
    local bus = surface == "events" and loader.events.listeners or loader.hooks.chains
    for name in pairs(names) do
      for _, subscription in ipairs(bus[name] or {}) do
        T.check(subscription.owner ~= "z_failure", version .. " failed catalog owner removed " .. name)
      end
    end
  end
  T.check(loader.exports.a_callbacks ~= nil, version .. " earlier callback mod survives rollback")
  T.sdk.restoreRuntime()
end

do
  local loader, result = load(filesFor(), 3, "firered")
  T.eq(result, true, "menu fixture loads")
  local out = loader.exports.a_callbacks
  local StartMenu = require("src.ui.game3.start_menu")
  local Stack = require("src.ui.game3.stack")
  local RomText = require("src.core.game3.rom_text")
  local originalAt, originalLayers = RomText.at, Stack._layers
  RomText.at = function(_, index) return "ROW " .. tostring(index) end
  Stack._layers = {}
  local session = { version = "firered", name = "RED", party = {},
    map = "FR_ROUTE_1", dex = { seen = {}, owned = {} } }
  loader.game.session = session
  out.menuMode = "replace"
  StartMenu.show({ game = loader.game, session = session, cursor = 1 })
  T.eq(Stack.top().mod, StartMenu, "show pushes the real start menu")
  StartMenu.confirm()
  T.eq(out.selected, "replaced", "replaced built-in row executes its callback")
  T.eq(out.selectedArgs, 0, "replacement receives zero arguments as in Gen 1")
  T.check(out.selectedGame == loader.game, "replacement captures the hook game")
  StartMenu.cursor = #StartMenu.ENTRIES
  StartMenu.confirm()
  T.eq(out.selected, "added", "added row executes its callback")
  T.eq(out.selectedArgs, 0, "added callback receives zero arguments as in Gen 1")
  T.check(out.selectedGame == loader.game, "added callback captures the hook game")
  StartMenu.close(true)
  out.menuMode = "legacy"
  StartMenu.show({ game = loader.game, session = session, cursor = 1 })
  T.eq(StartMenu.ENTRIES[1].onSelect, nil, "legacy ID-only row stays usable")
  StartMenu.confirm()
  T.eq(StartMenu._confirmExit, true, "legacy exit ID invokes real native selection")
  StartMenu.close(true)
  out.menuMode = nil
  StartMenu.show({ game = loader.game, session = session, cursor = 1 })
  local vanilla = {}
  for i, row in ipairs(StartMenu.ENTRIES) do vanilla[i] = { id = row.id, label = row.label } end
  StartMenu.close(true)
  for _, invalid in ipairs({ false, "invalid", { { label = "BAD", onSelect = false } },
      { { label = "BAD" } }, { [2] = { id = "exit", label = "GAP" } },
      { extra = { id = "exit", label = "KEY" } } }) do
    out.menuMode, out.invalidRows = "invalid", invalid
    StartMenu.show({ game = loader.game, session = session, cursor = 1 })
    local actual = {}
    for i, row in ipairs(StartMenu.ENTRIES) do actual[i] = { id = row.id, label = row.label } end
    T.same(actual, vanilla, "invalid hook result keeps pristine vanilla menu rows")
    T.eq(type(StartMenu.ENTRIES[1].onSelect), "function", "fallback retains native callbacks")
    StartMenu.close(true)
  end
  out.invalidRows = nil
  StartMenu.show({ game = loader.game, session = session, cursor = 1 })
  T.eq(StartMenu.ENTRIES[1].label, vanilla[1].label, "nil return falls back to vanilla")
  StartMenu.close(true)

  out.menuMode = "replace"
  StartMenu.show({ game = loader.game, session = session, cursor = 1 })
  local originalGame = loader.game
  loader.game = { data = originalGame.data, generation = 3, phase = "field", session = session }
  out.selected, out.selectedArgs = nil, nil
  StartMenu.confirm()
  T.eq(out.selected, nil, "retained custom callback retires when the game provider changes")
  T.eq(out.selectedArgs, nil, "changed provider does not enter the custom callback")
  loader.game = originalGame
  StartMenu.confirm()
  T.eq(out.selected, "replaced", "retained callback runs with its original game restored")
  T.eq(out.selectedArgs, 0, "restored context still receives zero arguments")
  out.unhookMenu(); out.unhookMenu()
  T.eq(Runtime.wantsHook("ui.start_menu.items"), false, "menu hook unsubscribe removes the chain")
  out.selected, out.selectedArgs = nil, nil
  StartMenu.confirm()
  T.eq(out.selected, "replaced", "individual unsubscribe preserves a retained custom callback")
  T.eq(out.selectedArgs, 0, "unsubscribed retained callback receives zero arguments")
  loader:_rollback("a_callbacks")
  out.selected, out.selectedArgs = nil, nil
  StartMenu.confirm()
  T.eq(out.selected, nil, "owner rollback retires a retained custom callback")
  T.eq(out.selectedArgs, nil, "rolled-back owner does not enter the custom callback")
  StartMenu.close(true)
  RomText.at, Stack._layers = originalAt, originalLayers
  T.sdk.restoreRuntime()
end

do
  GameVersion.set("firered")
  local Compat = require("src.mods.Gen3Compat")
  local Pokemon = require("src.core.game3.pokemon")
  local Moves = require("src.core.game3.battle.moves")
  local Items = require("src.core.game3.items_data")
  local undo = {}
  local function set(object, key, value)
    undo[#undo + 1] = { object = object, key = key, value = object[key] }
    object[key] = value
  end
  local data = T.sdk.gen3Data()
  set(Pokemon, "_names", data.gen3Pokemon._names)
  set(Pokemon, "_byName", { MEW = 151, PIDGEY = 16 })
  set(Pokemon, "_moveNames", data.gen3Pokemon._moveNames)
  set(Pokemon, "_romMoveNames", data.gen3Pokemon._moveNames)
  set(Moves, "_numByName", { POUND = 1, SURF = 57 })
  set(Items, "_bagModel", {})
  set(Items, "_byId", data.gen3Items._byId)
  set(Items, "_byName", { POTION = 13 })
  local native = { { species = 16, moves = { 1, 57, 0 }, heldItem = 13, level = 5 } }
  local pristine = Merge.deepCopy(native)
  local once = Compat.partyNames(native)
  local twice = Compat.partyNames(once)
  T.same(twice, once, "partyNames is stable across repeated normalization")
  T.eq(twice[1].speciesId, 16, "repeated party view retains numeric species metadata")
  T.same(twice[1].moveIds, { 1, 57, 0 }, "repeated party view retains numeric move metadata")
  T.eq(twice[1].heldItemId, 13, "repeated party view retains numeric item metadata")
  local roundtrip = Compat.partyNums(twice)
  T.eq(roundtrip[1].species, 16, "repeated party view restores native species")
  T.eq(roundtrip[1].moves[2], 57, "repeated party view restores native moves")
  T.eq(roundtrip[1].heldItem, 13, "repeated party view restores native held item")
  T.same(native, pristine, "legacy party conversions leave input records detached")
  local runtimeName = "src.core.game3.runtime"
  local originalRuntime = package.loaded[runtimeName]
  local session = { party = {}, dex = { seen = { [16] = true, ["16"] = true },
    owned = { [16] = true, ["16"] = true } } }
  package.loaded[runtimeName] = { getSession = function() return session end }
  Compat.bind(function() return { session = session, data = data, phase = "field" } end)
  local Game = Compat.resolve("src.core.Game", "callback_fixture")
  T.eq(Game.save.pokedex.seen.PIDGEY, true, "legacy dex reads stored string and numeric keys")
  Game.save.pokedex.seen.PIDGEY = false
  Game.save.pokedex.caught.PIDGEY = nil
  T.eq(next(session.dex.seen), nil, "clearing seen removes both native key forms")
  T.eq(next(session.dex.owned), nil, "clearing caught removes both native key forms")
  T.eq(Game.save.pokedex.seen.PIDGEY, nil, "cleared dex entry cannot reappear through string key")
  package.loaded[runtimeName] = originalRuntime
  Compat.bind(nil)
  for i = #undo, 1, -1 do
    local row = undo[i]
    row.object[row.key] = row.value
  end
end

do
  GameVersion.set("gold")
  local Compat = require("src.mods.Gen2Compat")
  local Native = require("src.ui.gen2.PartyMenu")
  local Party = Compat.resolve("src.ui.PartyMenu", "callback_fixture")
  local coverage = Compat.coverage("src.ui.PartyMenu")
  T.eq(coverage.members.new, "backed", "Gen 2 party constructor is published backed")
  coverage.members.new = "absent"
  T.eq(Compat.coverage("src.ui.PartyMenu").members.new, "backed", "constructor coverage is detached")
  local captured, originalNative = Party.new, Native.new
  local calls, chosen, chosenMenu, pops = 0, nil, nil, 0
  local game = { data = {}, stack = {} }
  local current
  game.stack.top = function() return current end
  game.stack.pop = function() pops = pops + 1; current = nil end
  Compat.bind(function() return game end)
  local wrapper = function(...) calls = calls + 1; return captured(...) end
  Party.new = wrapper
  T.check(Party.new == wrapper and Native.new == wrapper, "legacy constructor write reaches native class")
  local mon = { species = "PIDGEY" }
  local menu = Party.new(game, { party = { mon }, onSwitch = function(value, instance)
    chosen, chosenMenu = value, instance
  end })
  current = menu
  T.eq(calls, 1, "captured constructor avoids recursive monkey patch")
  T.eq(menu.wantsSubmenu, false, "onSwitch construction uses direct party choice")
  menu.onChoose(1, mon)
  T.check(chosen == mon and chosenMenu == menu, "native choice reaches legacy mon/menu callback")
  T.eq(pops, 1, "legacy constructor choice closes its own screen once")
  local battleMenu = Party.new(game, { party = { mon }, battle = true,
    onSwitch = function() end })
  T.eq(battleMenu.wantsBattleSubmenu, true, "Gen 2 constructor accepts battle choice mode")
  local forced = Party.new(game, { party = { mon }, forceSwitch = true })
  T.eq(forced.prompt, Native.PROMPTS.which, "Gen 2 constructor accepts forceSwitch prompt")
  local itemMenu = Party.new(game, { party = { mon }, pickOnly = true, itemUse = true })
  T.eq(itemMenu.prompt, Native.PROMPTS.useItem, "Gen 2 constructor accepts item choice prompt")
  T.eq(itemMenu.wantsSubmenu, false, "Gen 2 item choice skips field submenu")
  T.eq(calls, 4, "every supported constructor mode reaches the captured constructor once")
  Party.new, Native.new = captured, originalNative
  Compat.bind(nil)
end

do
  local loader, result = load({}, 3, "firered")
  T.eq(result, true, "no-mod callback fixture loads")
  local calls, record = 0, { species = 16, level = 5 }
  local values = pack(Runtime.call("encounter.species", function(value)
    calls = calls + 1
    return value, nil, "native"
  end, record, {}))
  T.eq(calls, 1, "no-mod vanilla executes once")
  T.check(values[1] == record, "no-mod result retains native identity")
  T.same({ n = values.n, [3] = values[3] }, { n = 3, [3] = "native" }, "no-mod nil tuple preserved")
  T.eq(next(loader.mods), nil, "no-mod fixture discovers no mods")
  T.sdk.restoreRuntime()
end

GameVersion.set(originalVersion)
T.finish("unified_callbacks")
