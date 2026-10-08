package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")
local T = require("tests.harness")
local F = require("tests.engine._g3u_fixture")
local Table = require("src.battle.g3u.Table")
local Match = require("src.battle.g3u.Match")
local Scope = require("src.battle.g3u.Scope")

local M = Scope.modules()
local Pokemon, Moves = M["src.core.game3.pokemon"], M["src.core.game3.battle.moves"]
local Guard = M["src.core.game3.battle.link_guard"]

Pokemon._types = { [81] = { 13, 8 }, [143] = { 0, 0 } }
Pokemon._names = { [81] = "MAGNEMITE", [143] = "SNORLAX" }
Pokemon._cache = { read = function() return nil end }
Moves._rom = { [33] = { power = 40, type = 0, accuracy = 100, pp = 35, effect = 0, secondaryChance = 0,
  target = 0, priority = 0, flags = 51 } }
Moves._romLoaded = true
Moves.BY_NUM[33] = "TACKLE"
Moves._numByName = { TACKLE = 33 }

local WATCH = {
  "src.core.game3.pokemon", "src.core.game3.battle.moves", "src.core.game3.battle.battle_text",
  "src.core.game3.battle.types", "src.core.game3.battle.profile", "src.mods.Runtime",
  "src.core.game3.battle.adapter", "src.core.game3.rom_text", "src.import.CacheFs", "src.core.game3.dataset",
  "src.core.game3.battle.link_guard", "src.core.game3.rng", "src.core.game3.battle.effect_ctx",
  "src.core.game3.battle.switch_seq",
}

local function snap(v, depth, seen)
  if type(v) ~= "table" then return v end
  if depth > 3 then return v end
  if seen[v] then return seen[v] end
  local out = { __ref = v, __mt = getmetatable(v) }
  seen[v] = out
  for k, x in pairs(v) do out[k] = snap(x, depth + 1, seen) end
  return out
end

local function snapshot()
  local s = {}
  for _, name in ipairs(WATCH) do s[name] = snap(M[name], 0, {}) end
  s.math = { random = math.random, randomseed = math.randomseed }
  return s
end

local function deep(a, b, path, seen)
  seen = seen or {}
  if type(a) ~= type(b) then return false, path end
  if type(a) ~= "table" then
    if a ~= b and not (a ~= a and b ~= b) then return false, path end
    return true
  end
  if seen[a] then return true end
  seen[a] = true
  for k, v in pairs(a) do
    local ok, where = deep(v, b[k], path .. "." .. tostring(k), seen)
    if not ok then return false, where end
  end
  for k in pairs(b) do
    if a[k] == nil then return false, path .. "." .. tostring(k) end
  end
  return true
end

local t1 = assert(Table.build(F.gen1()))
local before = snapshot()

local m = Match.new({ table = t1, parties = { [0] = { F.record(t1, 81, { 33, 84 }), F.record(t1, 25, { 33 }) },
  [1] = { F.record(t1, 143, { 33, 89 }) } }, seed = 5 })
m:start()
T.eq(m.st.player.type1, 13, "Magnemite battles as Electric")
T.eq(m.st.player.type2, nil, "the live Gen 3 Electric/Steel row is not used")
local rnd = F.lcg(3)
local guard = 0
while m.phase ~= "over" and guard < 200 do
  guard = guard + 1
  if m.phase == "choose" then
    m:submit({ [0] = F.pick(m, 0, rnd), [1] = F.pick(m, 1, rnd) })
  else
    local p = {}
    for s = 0, 1 do if m:needs(s) then p[s] = m:legalActions(s)[1].index end end
    m:replace(p)
  end
end
T.eq(m.phase, "over", "the match finished")

local after = snapshot()
local ok, where = deep(before, after, "")
T.check(ok, "every swapped module is restored after a match (first difference " .. tostring(where) .. ")")
T.same(Pokemon.types(81), { 13, 8 }, "the live Gen 3 typing is back after the match")
T.eq(Moves.constName(33), "TACKLE", "the live move names are back after the match")
T.eq(Pokemon.name(81), "MAGNEMITE", "the live species names are back after the match")

local okErr, err = pcall(Scope.run, t1, function() error("boom") end)
T.check(not okErr and tostring(err):find("boom", 1, true), "an error inside the scope propagates")
local ok2, where2 = deep(before, snapshot(), "")
T.check(ok2, "an error inside the scope still restores everything (" .. tostring(where2) .. ")")

local Engine = M["src.core.game3.battle.engine"]
local real = Engine.planTurnFromActions
local m2 = Match.new({ table = t1, parties = { [0] = { F.record(t1, 81, { 33 }) }, [1] = { F.record(t1, 143, { 33 }) } },
  seed = 1 })
m2:start()
Engine.planTurnFromActions = function() error("mid-turn failure") end
local okMid = pcall(m2.submit, m2, { [0] = { kind = "move", slot = 1 }, [1] = { kind = "move", slot = 1 } })
Engine.planTurnFromActions = real
T.check(not okMid, "a failure in the middle of a turn raises")
local ok3, where3 = deep(before, snapshot(), "")
T.check(ok3, "a failure in the middle of a turn still restores everything (" .. tostring(where3) .. ")")

Scope.resetTrips()
local RomText = M["src.core.game3.rom_text"]
T.raises(function() Scope.run(t1, function() return RomText.plain("sText_FoePkmnPrefix") end) end,
  "g3u scope", "a RomText read during a match raises")
T.raises(function() Scope.run(t1, function() return math.random(1, 6) end) end, "math.random",
  "math.random during a match raises")
T.raises(function() Scope.run(t1, function() return M["src.import.CacheFs"].readAt("red/data/generated/moves.lua") end) end,
  "CacheFs", "a cache file read during a match raises")
T.raises(function() Scope.run(t1, function() return M["src.core.game3.dataset"].cache() end) end,
  "Dataset.cache", "a dataset cache lookup during a match raises")
T.raises(function() Scope.run(t1, function() return Pokemon._cache:read("x") end) end,
  "cache:read", "a species pack read during a match raises")
local caught = Scope.run(t1, function() return (pcall(RomText.plain, "sText_FoePkmnPrefix")) end)
T.eq(caught, false, "a guarded read stays an error under pcall")
T.check(#Scope.trips >= 6, "every guarded read is recorded even when a pcall swallows it")
T.eq(Scope.run(t1, function() return Guard.active end), true, "link_guard is armed inside a match")
T.eq(Guard.active, false, "link_guard is disarmed again afterwards")
T.check(type(math.random()) == "number", "math.random works again after the scope")

T.finish("g3u scope")
