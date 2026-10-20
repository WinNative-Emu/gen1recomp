package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Loader = require("src.mods.Loader")
local Schemas = require("src.mods.Schemas")
local Version = require("src.core.GameVersion")
local Versions = require("src.import.gba.versions")
local Profile = require("src.core.game3.profile")
local GameCache = require("tests.game3_cache")

local BODY = [[
local mod = ...
local fx = mod.content.move_effects
fx:register("MOD_SHOCK", { kind = "secondary", run = function(ctx)
  mod.exports.secondary = (mod.exports.secondary or 0) + 1
  ctx.damage(ctx.target, 3)
  return { "SHOCKED" }
end })
fx:register("MOD_BOOST", { kind = "primary", accuracyChecked = true, missText = "butItFailed",
  run = function(ctx)
    mod.exports.primary = (mod.exports.primary or 0) + 1
    local landed = ctx.inflict(ctx.target, "DROWSY")
    if landed.failed then return landed end
    return { "BOOSTED" }
  end })
fx:register("MOD_FULL", { kind = "full", run = function(ctx)
  mod.exports.full = (mod.exports.full or 0) + 1
  return { "FULLRAN" }
end })
fx:register("MOD_TOOLS", { kind = "primary", run = function(ctx)
  local burn = ctx.inflict(ctx.target, "BRN")
  mod.exports.nativeLanded = not burn.failed
  ctx.anim("MOD_ZAP")
  local stage = ctx.changeStage(ctx.user, "attack", 1)
  mod.exports.stageLanded = not stage.failed
  ctx.cure(ctx.user)
  return { "TOOLED" }
end })
fx:register("MOD_PRIM_ON_HIT", { kind = "primary", run = function(ctx)
  mod.exports.ignored = (mod.exports.ignored or 0) + 1
  return { "IGNORED" }
end })
mod.content.statuses:register("DROWSY", {
  label = "DRW",
  catchBonus = 20,
  statPenalty = { stat = "speed", div = 2 },
  beforeMove = function(battler, rng, battle)
    mod.exports.before = (mod.exports.before or 0) + 1
    return false, { "DROWSING" }
  end,
  residual = function(battler, rng, battle)
    battler.mon.hp = battler.mon.hp - 4
    return { "DROWSY RESIDUAL" }
  end,
  cureOnSwitch = true,
})
mod.content.statuses:register("LINGER", { label = "LNG", cureOnSwitch = false })
mod.content.ai_classes:register("PICKY", { kind = "brain", brain = function(view)
  return { slot = 2 }
end })
mod.content.ai_classes:register("LAYERED", { kind = "layer", score = function(view, move, score)
  if move.id == "SCRATCH" then return score + 50 end
  return score
end })
mod.content.ai_classes:register("MEDIC", { kind = "class", uses = 2, item = "POTION", hpBelow = 2 })
]]

local ANIMS = [[
local mod = ...
mod.content.battle_anims:register("MOD_ZAP", { seq = {
  { op = "delay", frames = 3 }, { op = "end" } } })
mod.content.trainers:register("901", { name = "ACE", class = 1, aiClass = "PICKY",
  aiMods = { "LAYERED" }, party = { { species = "MEW", level = 5 } } })
mod.content.battle_anims:register("TACKLE", { seq = {
  { op = "delay", frames = 9 }, { op = "end" } } })
]]

local versions = { "firered", "leafgreen", "ruby", "sapphire", "emerald" }
for _, version in ipairs(versions) do
  Version.set(version)
  Versions.select(version)
  Profile.reset()
  local data = T.sdk.gen3Data()
  T.sdk.captureRuntime()
  local files = {
    ["mods/regs/manifest.json"] = '{"id":"regs","name":"regs","version":"1.0.0","api":3,"games":["all"],"entry":"main.lua"}',
    ["mods/regs/main.lua"] = BODY,
    ["mods/anims/manifest.json"] = '{"id":"anims","name":"anims","version":"1.0.0","api":2,"games":["all"],"entry":"main.lua"}',
    ["mods/anims/main.lua"] = ANIMS,
  }
  local loader = Loader.new({ fs = T.sdk.memfs(files), generation = 3, version = version, dev = true })
  T.check(loader:load(data), version .. " loads")
  T.same(loader.errors, {}, version .. " no unavailable reports")
  T.check(data.gen3MoveEffects and data.gen3MoveEffects.MOD_SHOCK, version .. " move_effects merged")
  T.eq(data.gen3MoveEffects.MOD_BOOST.kind, "primary", version .. " effect kind kept")
  T.check(data.gen3Statuses and data.gen3Statuses.DROWSY, version .. " statuses merged")
  T.check(data.gen3AiClasses and data.gen3AiClasses.PICKY, version .. " ai_classes merged")
  T.check(data.gen3BattleAnims and data.gen3BattleAnims.MOD_ZAP, version .. " battle_anims merged")
  T.eq(data.gen3Trainers.trainers[901] and data.gen3Trainers.trainers[901].aiClass, "PICKY", version .. " trainer names an AI class")
  T.eq(data.statuses, nil, version .. " leaves the Gen 1 namespaces absent")
  T.eq(data.move_effects, nil, version .. " no Gen 1 move_effects")
  T.eq(Schemas.targetFor("statuses", Schemas.REGISTRIES.statuses, 3), "gen3Statuses", version .. " routing")
  T.eq(Schemas.gatedFor("battle_anims", 3), false, version .. " battle_anims is not gated")
  T.check(loader.content.statuses:get("BRN") == nil, version .. " no native statuses seeded")
  local ok = pcall(function()
    loader.content.battle_anims:register("BAD", { blocks = {} })
  end)
  T.check(not ok or loader.content.battle_anims:get("BAD") == nil,
    version .. " a Gen 1 block record is not a Gen 3 animation")
  T.sdk.restoreRuntime()
end

Version.set("firered")
Versions.select("firered")
Profile.reset()
local root = GameCache.mount()
if not root then
  print("[skip] unified_gen3_battle_registries battle section: " .. tostring(GameCache.reason))
  T.finish("unified_gen3_battle_registries")
  return
end

require("tests.fixture_data.game3_items").install()
local Moves = require("src.core.game3.battle.moves")
Moves.loadRomPack()
local State = require("src.core.game3.battle.state")
local Engine = require("src.core.game3.battle.engine")
local Adapter = require("src.core.game3.battle.adapter")
local Types = require("src.core.game3.battle.types")
local ModBattle = require("src.core.game3.battle.mod_registries")
local Ai = require("src.core.game3.battle.ai")
local Anim = require("src.core.game3.battle.anim")
local Residuals = require("src.core.game3.battle.residuals")
local Catching = require("src.core.game3.battle.catching")

local registry = {
  gen3MoveEffects = {}, gen3Statuses = {}, gen3AiClasses = {}, gen3BattleAnims = {},
}
local exports = {}
local function load()
  Version.set("firered")
  Versions.select("firered")
  Profile.reset()
  T.sdk.captureRuntime()
  local Pokemon = require("src.core.game3.pokemon")
  local ItemsData = require("src.core.game3.items_data")
  local data = {
    gen3Pokemon = Pokemon, gen3Moves = Moves, gen3Items = ItemsData,
    gen3Encounters = {}, gen3Trainers = {}, gen3Text = {}, gen3Scripts = {},
  }
  local files = {
    ["mods/regs/manifest.json"] = '{"id":"regs","name":"regs","version":"1.0.0","api":3,"games":["firered"],"entry":"main.lua"}',
    ["mods/anims/manifest.json"] = '{"id":"anims","name":"anims","version":"1.0.0","api":2,"games":["firered"],"entry":"main.lua"}',
    ["mods/anims/main.lua"] = ANIMS,
    ["mods/regs/main.lua"] = BODY .. [[
local moves = mod.content.moves
moves:register("MOD_SHOCK_HIT", { name = "MODSHOCK", index = 400, type = "NORMAL", power = 40,
  accuracy = 100, pp = 10, effect = "MOD_SHOCK" })
moves:register("MOD_BOOSTER", { name = "MODBOOST", index = 401, type = "NORMAL", power = 0,
  accuracy = 100, pp = 10, effect = "MOD_BOOST" })
moves:register("MOD_FULLER", { name = "MODFULL", index = 402, type = "NORMAL", power = 40,
  accuracy = 100, pp = 10, effect = "MOD_FULL" })
moves:register("MOD_TOOLER", { name = "MODTOOL", index = 404, type = "NORMAL", power = 0,
  accuracy = 100, pp = 10, effect = "MOD_TOOLS" })
moves:register("MOD_PRIMHIT", { name = "MODPRIM", index = 403, type = "NORMAL", power = 40,
  accuracy = 100, pp = 10, effect = "MOD_PRIM_ON_HIT" })
mod.exports.shockEffect = moves:get("MOD_SHOCK_HIT").effect
mod.exports.shockRaw = nil
]],
  }
  local loader = Loader.new({ fs = T.sdk.memfs(files), generation = 3, version = "firered", dev = true })
  local ok, err = loader:load(data)
  T.check(ok, "FireRed loads against the live move tables: " .. tostring(err))
  T.same(loader.errors, {}, "FireRed battle section loads clean")
  T.sdk.restoreRuntime()
  ModBattle.bind(data)
  exports = loader.exports.regs or {}
  registry = data
  return loader, data
end

local loader = load()
T.eq(exports.shockEffect, "MOD_SHOCK", "a mod move reads back its custom effect id")
T.eq(Moves.get(400)._modEffectId, "MOD_SHOCK", "the battle move row carries the custom effect id")
T.eq(tonumber(Moves.get(400).effect), 0, "and keeps a native effect byte")

local function mon(o)
  return {
    species = o.species or 1, level = 50, hp = o.hp or 100, maxHp = o.maxHp or 100,
    attack = 50, defense = 50, spAtk = 50, spDef = 50, speed = o.speed or 50, ability = 0,
    nickname = o.nickname, moves = o.moves, pp = { 20, 20, 20, 20 }, status = o.status,
  }
end

local function battle(p, e, extra)
  extra = extra or {}
  p.nickname, e.nickname = p.nickname or "ALPHA", e.nickname or "BRAVO"
  local party = { mon(p) }
  for _, x in ipairs(extra.bench or {}) do party[#party + 1] = mon(x) end
  local st = State.new({ wild = extra.wild ~= false, playerParty = party, foeParty = { mon(e) } })
  st.player.type1, st.enemy.type1 = Types.ID.NORMAL, Types.ID.NORMAL
  st.rng = function(lo, hi)
    if lo == 1 and hi == 100 then return 1 end
    return hi
  end
  return st, Adapter.new(st)
end

local function use(st, ad, user, move, slot)
  local target = user == st.player and st.enemy or st.player
  local out = {}
  Engine.resolveMove(user, target, move, slot or 1, ad, st, out)
  return table.concat(out, " || "), out
end

local function has(s, needle) return s:find(needle, 1, true) ~= nil end

do
  local st, ad = battle({ moves = { 400 } }, { hp = 200, maxHp = 200 })
  local text = use(st, ad, st.player, 400)
  T.check(has(text, "SHOCKED"), "secondary effect message is printed")
  T.eq(exports.secondary, 1, "secondary effect ran once")
  T.check(ad:hp(st.enemy) < 200 - 3, "secondary effect damage lands on top of the hit")
end

do
  local st, ad = battle({ moves = { 401 } }, { hp = 200, maxHp = 200 })
  local text = use(st, ad, st.player, 401)
  T.check(has(text, "BOOSTED"), "primary effect message is printed")
  T.eq(st.enemy.modStatus, "DROWSY", "ctx.inflict lands a mod status in the mod slot")
  T.eq(ad:status(st.enemy), nil, "and the native status bits stay clear")
  local again = use(st, ad, st.player, 401)
  T.check(not has(again, "BOOSTED"), "a second infliction fails: " .. again)
end

do
  local st, ad = battle({ moves = { 402 } }, { hp = 200, maxHp = 200 })
  local text = use(st, ad, st.player, 402)
  T.check(has(text, "FULLRAN"), "a full record runs after the hit, as on Gen 1")
  T.eq(exports.full, 1, "full ran once")
end

do
  local st, ad = battle({ moves = { 404 } }, { hp = 200, maxHp = 200 })
  st.player.modStatus = "LINGER"
  local text = use(st, ad, st.player, 404)
  T.check(has(text, "TOOLED"), "ctx tools run: " .. text)
  T.eq(ad:status(st.enemy), "BRN", "ctx.inflict reaches the native status path")
  T.eq(exports.stageLanded, true, "ctx.changeStage moves the stage")
  T.eq(st.player.stages.attack, 1, "and the stage changed")
  T.eq(st.player.modStatus, nil, "ctx.cure clears the mod slot")
  local played = false
  for _, ev in ipairs(ad:events()) do
    if ev.kind == "move" and ev.moveId == "MOD_ZAP" then played = true end
  end
  T.check(played, "ctx.anim queues a registered mod animation")
end

do
  local st, ad = battle({ moves = { 403 } }, { hp = 200, maxHp = 200 })
  local text = use(st, ad, st.player, 403)
  T.check(not has(text, "IGNORED"), "a primary record never runs on a damaging move")
  T.eq(exports.ignored, nil, "primary callback not invoked")
end

do
  local st, ad = battle({ moves = { 33 } }, { hp = 200, maxHp = 200, moves = { 33 } })
  st.player.modStatus = "DROWSY"
  local text = use(st, ad, st.player, 33)
  T.check(has(text, "DROWSING"), "beforeMove can stop the move and speak")
  T.eq(ad:hp(st.enemy), 200, "the stopped move dealt nothing")
  local speedBefore = Engine.speedOf(st.enemy, st, ad)
  st.enemy.modStatus = "DROWSY"
  T.eq(Engine.speedOf(st.enemy, st, ad), math.floor(speedBefore / 2), "statPenalty halves speed")
  st.enemy.modStatus = nil
  st.player.modStatus = "DROWSY"
  local hp = ad:hp(st.player)
  local events = Residuals.collectEvents(ad)
  local spoke = false
  for _, ev in ipairs(events) do
    for _, m in ipairs(ev.msgs or {}) do if has(m, "DROWSY RESIDUAL") then spoke = true end end
  end
  T.check(spoke, "residual runs in the end-of-turn sweep")
  T.eq(ad:hp(st.player), hp - 4, "and its damage lands")
end

do
  local st, ad = battle({ moves = { 33 } }, { moves = { 33 } }, { bench = { { moves = { 33 } }, { moves = { 33 } } } })
  st.player.modStatus = "DROWSY"
  st.playerParty[2].hp = 80
  Engine.performSwitch(st, ad, "player", 2)
  T.eq(st.player.modStatus, nil, "cureOnSwitch clears the slot on switch-out")
  st.player.modStatus = "LINGER"
  Engine.performSwitch(st, ad, "player", 1)
  Engine.performSwitch(st, ad, "player", 2)
  T.eq(st.player.modStatus, "LINGER", "a status without cureOnSwitch survives a round trip")
end

do
  local st = battle({ moves = { 33 } }, { moves = { 33 } })
  local base = Catching.catchOdds(4, st.enemy, st, nil)
  st.enemy.modStatus = "DROWSY"
  T.eq(Catching.catchOdds(4, st.enemy, st, nil), math.min(255, base + 20), "catchBonus raises the odds")
end

do
  T.eq(Anim.scriptForMove(400) ~= nil, true, "a mod move has a script")
  local zap = Anim.scriptForMove("MOD_ZAP")
  T.eq(zap and zap[1].frames, 3, "a mod animation id resolves to its sequence")
  local tackle = Anim.scriptForMove(33)
  T.eq(tackle and tackle[1].frames, 9, "a mod record replaces a native move animation")
end

do
  local st, ad = battle({ moves = { 33 } }, { moves = { 10, 33, 52, 0 } }, { wild = false })
  st.aiClass = "PICKY"
  st.aiFlags = 1
  local act = Ai.chooseMove(st, { battler = 1, rng = st.rng })
  T.eq(act and act.slot, 2, "a brain picks the move slot")
  st.aiClass = "LAYERED"
  local layered = Ai.chooseMove(st, { battler = 1, rng = st.rng })
  T.eq(layered and layered.slot, 1, "a layer scores moves after the cart scripts")
  st.aiClass = nil
  st.aiMods = { "LAYERED" }
  local mods = Ai.chooseMove(st, { battler = 1, rng = st.rng })
  T.eq(mods and mods.slot, 1, "aiMods name layers")
  st.aiMods = nil
  local plain = Ai.chooseMove(st, { battler = 1, rng = st.rng })
  T.check(plain ~= nil, "a trainer with no class still chooses natively")
end

do
  local st, ad = battle({ moves = { 33 } }, { hp = 40, maxHp = 100, moves = { 33 } }, { wild = false })
  st.trainerItems = { 13, 0, 0, 0 }
  st.aiClass = "MEDIC"
  st.enemy.mon.hp = 40
  local act = Ai.chooseAction(st, 1, { rng = st.rng })
  T.check(act and act.kind == "item", "a class acts before the cart's item logic")
end

loader = nil
T.finish("unified_gen3_battle_registries")
