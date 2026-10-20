package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local PokedexText = require("src.core.gen2.PokedexText")
local PokedexMenu = require("src.ui.gen2.PokedexMenu")
local BattleState = require("src.ui.gen2.BattleState")
local Screens = require("src.ui.Screens")

local function vanilla()
  return {
    pokemon = {
      ABRA = { id = "ABRA", name = "ABRA", dex = 63 },
      RATTATA = { id = "RATTATA", name = "RATTATA", dex = 19 },
      ZUBAT = { id = "ZUBAT", name = "ZUBAT", dex = 41 },
      CELEBI = { id = "CELEBI", name = "CELEBI", dex = 251 },
      tmhmMoves = { "MEGA_PUNCH" },
      growthRates = { GROWTH_MEDIUM_FAST = {} },
    },
    gen2Pokedex = {
      entries = {
        ABRA = { id = "ABRA", dex = 63, kind = "PSI", height = 211, weight = 430 },
        RATTATA = { id = "RATTATA", dex = 19, kind = "RAT", height = 100, weight = 80 },
        ZUBAT = { id = "ZUBAT", dex = 41, kind = "BAT", height = 207, weight = 165 },
        CELEBI = { id = "CELEBI", dex = 251, kind = "TIMETRAVEL", height = 200, weight = 110 },
      },
      newOrder = { "RATTATA", "ZUBAT", "ABRA", "CELEBI" },
      alphabeticalOrder = { "ABRA", "CELEBI", "RATTATA", "ZUBAT" },
    },
  }
end

local function indexOf(list, value)
  for i, v in ipairs(list) do if v == value then return i end end
  return nil
end

do
  local data = vanilla()
  eq(PokedexText.apply(data), 0, "a mod-free dataset is left alone")
  eq(#data.gen2Pokedex.newOrder, 4, "no row is added for the vanilla species")
  eq(data.gen2Pokedex.entries.tmhmMoves, nil, "a data.pokemon table with no dex number gets no entry")
end

local data = vanilla()
data.pokemon.MODRAT = { id = "MODRAT", name = "MODRAT", dex = 252,
  dexEntry = { kind = "MOD RAT", text = "Page one.", text2 = "Page two.",
               height = 104, weight = 2205 } }
data.pokemon.BLANKMON = { id = "BLANKMON", name = "BLANKMON", dex = 300 }
PokedexText.apply(data)
local dex = data.gen2Pokedex
local entry = dex.entries.MODRAT
check(entry ~= nil, "a registered species with a dex number gets a #DEX entry")
eq(entry and entry.dex, 252, "carrying its dex number")
eq(entry and entry.kind, "MOD RAT", "and its kind")
eq(entry and entry.text, "Page one.", "and page one")
eq(entry and entry.text2, "Page two.", "and page two")
eq(entry and entry.height, 104, "and its height")
eq(entry and entry.weight, 2205, "and its weight")
eq(dex.entries.BLANKMON and dex.entries.BLANKMON.dex, 300,
  "a registered species with no dexEntry is still listed")
eq(dex.newOrder[5], "MODRAT", "NEW order lists it after the game's own")
eq(dex.newOrder[6], "BLANKMON", "registered species follow in dex order")
eq(indexOf(dex.alphabeticalOrder, "MODRAT"), 4, "A-Z order slots it in by name")
eq(indexOf(dex.alphabeticalOrder, "BLANKMON"), 2, "between the names either side of it")
eq(#dex.alphabeticalOrder, 6, "and keeps every vanilla row")

PokedexText.apply(data)
eq(#dex.newOrder, 6, "a second apply adds nothing twice")

do
  local metric = vanilla()
  for _, e in pairs(metric.gen2Pokedex.entries) do e.heightM, e.weightKg = 1, 1 end
  metric.pokemon.MODRAT = { id = "MODRAT", name = "MODRAT", dex = 252,
    dexEntry = { kind = "MOD RAT", heightM = 0.5, weightKg = 4.5 } }
  PokedexText.apply(metric)
  local m = metric.gen2Pokedex.entries.MODRAT
  eq(m and m.heightM, 0.5, "a metric dex keeps the registered metric height")
  eq(m and m.weightKg, 4.5, "and weight")
  eq(m and m.height, 108, "with the native height converted beside it")
end

local function rowsFor(modeIndex)
  local menu = PokedexMenu.new({ data = data, save = { pokedex = { seen = {}, caught = {} } } },
    { pokedex = dex })
  menu.modeIndex = modeIndex
  menu:rebuild()
  local species = {}
  for i, row in ipairs(menu.rows) do species[i] = row.species end
  return species
end

local new = rowsFor(1)
check(indexOf(new, "MODRAT") ~= nil, "the NEW listing shows the registered species")
local old = rowsFor(2)
eq(#old, 6, "the OLD listing shows every species past a gap in dex numbers")
eq(old[5], "MODRAT", "OLD lists in dex order")
eq(old[6], "BLANKMON", "up to the highest registered number")
eq(old[1], "RATTATA", "and still starts at the lowest")
check(indexOf(rowsFor(3), "MODRAT") ~= nil, "the A-Z listing shows it")

do
  local battle = { wild = true, enemy = { species = "MODRAT", level = 5, hp = 10, maxHp = 10 },
                   player = { species = "RATTATA", level = 5 } }
  local state = setmetatable({ game = { data = data }, battle = battle }, { __index = BattleState })
  eq(state:catchOptions("HEAVY_BALL").weight, 2205,
    "the catch reads the registered species' weight")
  battle.enemy.species = "ABRA"
  eq(state:catchOptions("HEAVY_BALL").weight, 430, "and a vanilla species' weight")
end

do
  local pushed
  local push = Screens.push
  Screens.push = function(_, id, opts) pushed = { id = id, opts = opts } end
  local state = setmetatable({ game = { data = data, stack = {} } }, { __index = BattleState })
  local advanced = false
  state.advanceQueue = function() advanced = true end
  state:openDexEntry("MODRAT")
  Screens.push = push
  eq(pushed and pushed.id, "Gen2PokedexMenu", "catching it opens the new #DEX data page")
  eq(pushed and pushed.opts.entrySpecies, "MODRAT", "on the registered species")
  check(not advanced, "instead of skipping straight past it")
end

T.finish("gen2 dex registered species")
