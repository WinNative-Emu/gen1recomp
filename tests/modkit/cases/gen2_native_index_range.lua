package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Loader = require("src.mods.Loader")
local Merge = require("src.mods.Merge")
local Gen2Save = require("src.save_convert.Gen2Save")

local BODY = [[
local mod = ...
local function clone(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for key, row in pairs(value) do out[key] = clone(row) end
  return out
end
local bases = { pokemon = "MEW", moves = "POUND", items = "POTION" }
local function add(name, id, index)
  local row = clone(mod.content[name]:get(bases[name]))
  row.id, row.name, row.index, row.native = id, id, index, nil
  return mod.content[name]:register(id, row)
end
for _, name in ipairs({ "pokemon", "moves", "items" }) do
  for i = 1, 6 do
    local id = name .. "_" .. i
    add(name, id)
    local row = mod.content[name]:get(id)
    assert(type(row.index) == "number" and row.index > 250)
  end
  add(name, name .. "_MAX", 65535)
  assert(not pcall(add, name, name .. "_CLASH", 65535))
  for _, index in ipairs({ 0, -1, 1.5, 65536 }) do
    assert(not pcall(add, name, name .. "_BAD", index))
  end
  assert(not pcall(add, name, name .. "_RESERVED", name == "pokemon" and 253 or 255))
  assert(not pcall(function() mod.content[name]:patch(bases[name], { index = 300 }) end))
  assert(not pcall(function() mod.content[name]:patch(name .. "_1", { index = mod.DELETE }) end))
  local original = mod.content[name]:get(name .. "_1").index
  mod.content[name]:patch(name .. "_1", { name = "PATCHED" })
  assert(mod.content[name]:get(name .. "_1").index == original)
  mod.content[name]:remove(name .. "_1")
  assert(not pcall(add, name, name .. "_REUSED", original))
  add(name, name .. "_1")
  assert(mod.content[name]:get(name .. "_1").index == original)
end
]]

local function data()
  return {
    pokemon = { MEW = { id = "MEW", name = "MEW", index = 151, dex = 151,
      types = { "NORMAL" }, baseStats = { hp = 100, attack = 100, defense = 100,
        speed = 100, specialAttack = 100, specialDefense = 100 },
      catchRate = 45, baseExp = 64, growthRate = "MEDIUM_FAST", picSize = 5,
      levelMoves = { { level = 1, move = "POUND" } }, evolutions = {},
      spriteFront = "front.png", spriteBack = "back.png" } },
    moves = { POUND = { id = "POUND", name = "POUND", index = 1, type = "NORMAL",
      power = 40, accuracy = 100, pp = 35, effect = "EFFECT_NORMAL_HIT" } },
    items = { POTION = { id = "POTION", name = "POTION", index = 18, price = 300 } },
    type_chart = { types = { NORMAL = {} }, matchups = {} }, maps = {},
    growth_rates = { MEDIUM_FAST = { expForLevel = function(level) return level ^ 3 end } },
  }
end

for _, version in ipairs({ "gold", "silver", "crystal" }) do
  for _, api in ipairs({ 2, 3 }) do
    T.sdk.captureRuntime()
    local files = {}
    local function addMod(id, body)
      files["mods/" .. id .. "/manifest.json"] = ('{"id":"%s","name":"%s",'
        .. '"version":"1.0.0","api":%d,"games":["all"],"entry":"main.lua"}')
        :format(id, id, api)
      files["mods/" .. id .. "/main.lua"] = body
    end
    addMod("a_good", BODY)
    addMod("b_failed", [[local mod = ...
mod.content.items:register("ROLLBACK", { id = "ROLLBACK", name = "ROLLBACK", price = 1, index = 600 })
error("rollback fixture")]])
    addMod("c_after", [[local mod = ...
mod.content.items:register("SURVIVOR", { id = "SURVIVOR", name = "SURVIVOR", price = 1, index = 600 })]])
    local fixture = data()
    local pristine = Merge.deepCopy(fixture)
    local loader = Loader.new({ fs = T.sdk.memfs(files), generation = 2, version = version, dev = true })
    loader:load(fixture)
    local label = version .. " API " .. api .. " "
    T.eq(loader.mods.a_good.failed, nil, label .. "registers extended indices")
    T.eq(loader.mods.b_failed.failed, true, label .. "fails the intended owner")
    T.eq(loader.mods.c_after.failed, nil, label .. "releases failed owner reservation")
    T.eq(fixture.items.ROLLBACK, nil, label .. "rolled back item absent")
    T.eq(fixture.items.SURVIVOR and fixture.items.SURVIVOR.index, 600, label .. "later claim succeeds")
    for _, name in ipairs({ "pokemon", "moves", "items" }) do
      local used = {}
      for i = 1, 6 do
        local row = fixture[name][name .. "_" .. i]
        T.check(row and row.index and not used[row.index], label .. name .. " unique index " .. i)
        if row and row.index then used[row.index] = true end
      end
      T.check(fixture[name][name .. "_6"] and fixture[name][name .. "_6"].index > 255,
        label .. name .. " allocation crosses a byte")
      T.eq(fixture[name][name .. "_MAX"] and fixture[name][name .. "_MAX"].index, 65535,
        label .. name .. " accepts upper bound")
    end
    T.same(fixture.pokemon.MEW, pristine.pokemon.MEW, label .. "vanilla species unchanged")
    T.sdk.restoreRuntime()
  end
end

for _, what in ipairs({ "species", "move", "held item", "item", "mail species" }) do
  for _, index in ipairs({ 256, 300, 65535 }) do
    local ok, err = pcall(Gen2Save.util.indexOf, { MOD = index }, "MOD", what)
    T.check(not ok and type(err) == "table" and err.msg:find("cartridge byte", 1, true) ~= nil,
      what .. " refuses named index " .. index)
  end
end
T.eq(Gen2Save.util.indexOf({}, 252, "species"), 252, "raw glitch species remains byte exact")
T.eq(Gen2Save.util.indexOf({ VANILLA = 251 }, "VANILLA", "species"), 251, "native byte still exports")
T.finish("Gen 2 native index allocation")
