local Table = require("src.battle.g3u.Table")

local Scope = {}

Scope.trips = {}

local PRELOAD = {
  "src.core.game3.rng", "src.core.game3.rom_text", "src.import.CacheFs", "src.core.game3.dataset",
  "src.core.game3.pokemon", "src.mods.Runtime", "src.core.game3.battle.link_guard",
  "src.core.game3.battle.profile", "src.core.game3.battle.battle_text", "src.core.game3.battle.types",
  "src.core.game3.battle.moves", "src.core.game3.battle.damage", "src.core.game3.battle.state",
  "src.core.game3.battle.adapter", "src.core.game3.battle.rules", "src.core.game3.battle.effect_ids",
  "src.core.game3.battle.effects", "src.core.game3.battle.effects.hit",
  "src.core.game3.battle.effects._helpers", "src.core.game3.battle.effects.secondary",
  "src.core.game3.battle.effects.hazards", "src.core.game3.battle.effects.special",
  "src.core.game3.battle.residuals", "src.core.game3.battle.residual_handlers",
  "src.core.game3.battle.held_items", "src.core.game3.battle.abilities", "src.core.game3.battle.kinds",
  "src.core.game3.battle.oak_advice", "src.core.game3.battle.commands",
  "src.core.game3.battle.effect_ctx", "src.core.game3.battle.switch_seq", "src.core.game3.battle.engine",
  "src.core.game3.rs.enigma", "src.mods.Gen3Compat",
}

local M = {}
local loaded = false

local function load()
  if loaded then return end
  for _, name in ipairs(PRELOAD) do M[name] = require(name) end
  loaded = true
end

function Scope.modules()
  load()
  return M
end

local SPECIAL_KEYS = {
  [0] = "STRINGID_INTROMSG", [1] = "STRINGID_INTROSENDOUT", [2] = "STRINGID_RETURNMON",
  [3] = "STRINGID_SWITCHINMON", [4] = "STRINGID_USEDMOVE", [5] = "STRINGID_BATTLEEND",
}

function Scope.textKey(id)
  if type(id) == "number" then return SPECIAL_KEYS[id] or ("STRINGID_" .. id) end
  return tostring(id)
end

local function token(kind)
  return setmetatable({}, { __index = function(_, k)
    local n = tonumber(k)
    if not n then return nil end
    return "{" .. kind .. ":" .. n .. "}"
  end })
end

local function identity()
  return setmetatable({}, { __index = function(_, k) return tonumber(k) end })
end

local function trip(where)
  return function()
    Scope.trips[#Scope.trips + 1] = where
    error("g3u scope: " .. where .. " during a match", 2)
  end
end

local prepared = setmetatable({}, { __mode = "k" })

local function prepare(t)
  local p = prepared[t]
  if p then return p end
  p = { rows = {}, types = {}, stats = {}, byNum = {}, byName = {} }
  for id = 1, t.moveMax do
    p.rows[id] = Table.engineRow(t, id)
    local key = "G3U_" .. id
    p.byNum[id] = key
    p.byName[key] = id
  end
  p.byName.STRUGGLE = 165
  for n = 1, t.dexMax do
    p.types[n] = Table.speciesTypes(t, n)
    p.stats[n] = Table.baseStats(t, n)
  end
  prepared[t] = p
  return p
end

local function guardModule(list, mod, name, keep)
  for k, v in pairs(mod) do
    if type(v) == "function" and not (keep and keep[k]) then
      list[#list + 1] = { mod, k, trip(name .. "." .. k) }
    end
  end
end

local function swaps(t)
  load()
  local p = prepare(t)
  if p.list then return p.list end
  local Pokemon = M["src.core.game3.pokemon"]
  local Moves = M["src.core.game3.battle.moves"]
  local Runtime = M["src.mods.Runtime"]
  local BattleText = M["src.core.game3.battle.battle_text"]
  local Types = M["src.core.game3.battle.types"]
  local Profile = M["src.core.game3.battle.profile"]
  local Adapter = M["src.core.game3.battle.adapter"]
  local SwitchSeq = M["src.core.game3.battle.switch_seq"]
  local Rng32 = M["src.core.game3.rng"]
  local guardCache = { read = trip("cache:read") }
  local function noop() end
  local function defaults() return Profile.DEFAULTS end
  local list = {
    { Pokemon, "_cache", guardCache },
    { Pokemon, "_names", token("species") },
    { Pokemon, "_types", p.types },
    { Pokemon, "_stats", p.stats },
    { Pokemon, "_abilities", {} },
    { Pokemon, "_abilityNames", token("ability") },
    { Pokemon, "_romAbilityNames", token("ability") },
    { Pokemon, "_moveNames", token("move") },
    { Pokemon, "_romMoveNames", token("move") },
    { Pokemon, "_speciesMeta", {} },
    { Pokemon, "_national", { toNational = identity(), toSpecies = identity() } },
    { Pokemon, "_byName", {} },
    { Pokemon, "_manifest", {} },
    { Pokemon, "_learnsets", {} },
    { Pokemon, "_eggMoves", {} },
    { Pokemon, "_evolutions", {} },
    { Pokemon, "_tmhm", {} },
    { Pokemon, "_dex", {} },
    { Pokemon, "_battleMoves", p.rows },
    { Pokemon, "install", trip("Pokemon.install") },
    { Pokemon, "adjustFriendshipOnBattleFaint", noop },
    { Pokemon, "currentMapSec", noop },
    { Moves, "_rom", p.rows },
    { Moves, "_romLoaded", true },
    { Moves, "_linkRows", false },
    { Moves, "BY_NUM", p.byNum },
    { Moves, "_numByName", p.byName },
    { Moves, "loadRomPack", trip("Moves.loadRomPack") },
    { Runtime, "wants", function() return false end },
    { Runtime, "wantsHook", function() return false end },
    { Runtime, "emit", noop },
    { Runtime, "call", function(_, vanilla, ...) return vanilla(...) end },
    { BattleText, "get", function(id) return Scope.textKey(id) end },
    { BattleText, "key", function(id, fill) return Scope.textKey(id), fill end },
    { BattleText, "ir", trip("BattleText.ir") },
    { BattleText, "context", trip("BattleText.context") },
    { Types, "name", function(id) return "{type:" .. tostring(tonumber(id)) .. "}" end },
    { Types, "get", function(id) return "{type:" .. tostring(tonumber(id)) .. "}" end },
    { Profile, "get", defaults },
    { Profile, "of", defaults },
    { Adapter, "textSink", Scope.textKey },
    { SwitchSeq, "switchInFill", function(_, b) return { side = b and b.side, switchBattler = b and b.id } end },
    { math, "random", trip("math.random") },
    { math, "randomseed", trip("math.randomseed") },
  }
  for _, k in ipairs({ "Random", "Random32", "Random2", "compat", "step", "mod", "WildEncounterRandom" }) do
    list[#list + 1] = { Rng32, k, trip("rng." .. k) }
  end
  guardModule(list, M["src.core.game3.rom_text"], "RomText", { key = true })
  guardModule(list, M["src.import.CacheFs"], "CacheFs")
  list[#list + 1] = { M["src.core.game3.dataset"], "cache", trip("Dataset.cache") }
  list[#list + 1] = { M["src.core.game3.dataset"], "hydrate", trip("Dataset.hydrate") }
  p.list = list
  return list
end

function Scope.newStack()
  local pool, depth = {}, 0
  local S = {}
  function S.push(adapter, user, target, move, moveId, rng, opts)
    depth = depth + 1
    local ctx = pool[depth] or {}
    pool[depth] = ctx
    ctx.adapter, ctx.user, ctx.target, ctx.move, ctx.moveId, ctx.rng, ctx.opts =
      adapter, user, target, move, moveId, rng, opts
    return ctx
  end
  function S.pop()
    assert(depth > 0, "effect context stack underflow")
    local ctx = pool[depth]
    ctx.adapter, ctx.user, ctx.target, ctx.move, ctx.moveId, ctx.rng, ctx.opts = nil, nil, nil, nil, nil, nil, nil
    pool[depth] = nil
    depth = depth - 1
  end
  function S.current() return depth > 0 and pool[depth] or nil end
  function S.depth() return depth end
  function S.reset() while depth > 0 do S.pop() end end
  return S
end

local depth = 0

function Scope.run(t, fn, stack)
  if depth > 0 then return fn() end
  local list = swaps(t)
  if stack then
    local all = {}
    for i, s in ipairs(list) do all[i] = s end
    local EffectCtx = M["src.core.game3.battle.effect_ctx"]
    for _, k in ipairs({ "push", "pop", "current", "depth", "reset" }) do all[#all + 1] = { EffectCtx, k, stack[k] } end
    list = all
  end
  local saved = {}
  for i, s in ipairs(list) do
    saved[i] = { s[1], s[2], rawget(s[1], s[2]) }
    rawset(s[1], s[2], s[3])
  end
  local Guard = M["src.core.game3.battle.link_guard"]
  local wasActive, wasTripped = Guard.active, Guard.tripped
  Guard.arm()
  depth = depth + 1
  local res = { pcall(fn) }
  depth = depth - 1
  local guardTrip = Guard.tripped
  Guard.active, Guard.tripped = wasActive, wasTripped
  for i = #saved, 1, -1 do
    local s = saved[i]
    rawset(s[1], s[2], s[3])
  end
  if guardTrip then Scope.trips[#Scope.trips + 1] = "link_guard:" .. tostring(guardTrip) end
  if not res[1] then error(res[2], 0) end
  return unpack(res, 2, table.maxn(res))
end

function Scope.resetTrips()
  Scope.trips = {}
end

return Scope
