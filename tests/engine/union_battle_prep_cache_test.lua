package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")
local T = require("tests.harness")
local F = require("tests.engine._xgen_fixture")
local Model = require("src.online.union.BattlePrepModel")
local Identity = require("src.online.xgen.Identity")

local real, list = F.allReal()
if #list == 0 then
  print("[skip] union_battle_prep_cache_test: no imported game cache")
  os.exit(0)
end

local function rulesFor(moveGen, ownGen)
  local lim = { [1] = { 151, 165 }, [2] = { 251, 251 } }
  return { ruleset = "g3u", dexMax = lim[moveGen][1], moveMax = lim[moveGen][2], moveGen = moveGen,
    gens = { moveGen, ownGen == moveGen and 3 or ownGen } }
end

local function sampleMon(data, national, level)
  local gen = data.generation
  local sp = data.species[national]
  local moves = {}
  for _, row in ipairs(sp.levelMoves) do
    if row.level <= level and #moves < 4 then moves[#moves + 1] = row.move end
  end
  if gen == 3 then
    return { species = sp.localKey, level = level, personality = 0, otId = 1, ivs = {}, evs = {}, moves = moves }
  end
  local rows = {}
  for i, id in ipairs(moves) do rows[i] = { id = data.moveToLocal[id], pp = data.moves[id].pp } end
  return { species = sp.localKey, level = level, dvs = { attack = 1, defense = 2, speed = 3, special = 4 },
    statExp = {}, moves = rows }
end

for _, version in ipairs(list) do
  local data = real[version]
  local gen = data.generation
  for moveGen = 1, math.min(gen, 2) do
    local m = Model.new({ version = version, gen = gen, data = data, rules = rulesFor(moveGen, gen),
      owned = { party = { sampleMon(data, 25, 30) }, generation = gen } })
    local cov = m:rentalCoverage()
    local want = moveGen == 1 and #Identity.GEN1_TYPES or #Identity.TYPES
    T.eq(#cov, want, version .. " g3u-gen" .. moveGen .. " lists every ordinary type")
    local missing = {}
    for _, row in ipairs(cov) do
      if not row.rental then missing[#missing + 1] = row.type end
      if row.rental then
        T.check(row.rental.record.rental == true, version .. " " .. row.type .. " rental record is tagged")
        T.eq(row.rental.level, 50, version .. " " .. row.type .. " rental is level 50")
      end
    end
    T.eq(table.concat(missing, ","), "", version .. " g3u-gen" .. moveGen .. " has a rental for every type")
    T.eq(#m.rentalSet.excluded, 0, version .. " g3u-gen" .. moveGen .. " excludes no rental")
  end
end

local em = real.emerald or real.firered or real.ruby
if em then
  local treecko = sampleMon(em, 252, 5)
  local pika = sampleMon(em, 25, 30)
  local before = F.copy({ treecko, pika })
  local m = Model.new({ version = em.version, gen = 3, data = em, rules = rulesFor(1, 3),
    owned = { party = { treecko, pika }, generation = 3 }, opponent = { name = "RED", version = "red" } })
  m:input("a")
  T.eq(m.step, "problems", em.version .. ": rules then problems")
  m:input("a")
  T.eq(m.step, "substitute", em.version .. ": Treecko needs a substitute under Gen 1 rules")
  local pg = m:page()
  local rentals = 0
  for _, it in ipairs(pg.items) do if it.id == "swap_rental" then rentals = rentals + 1 end end
  T.eq(rentals, 15, em.version .. ": all 15 Gen 1 rentals are offered")
  T.eq(pg.items[1].id, "swap_rental", em.version .. ": a grass rental ranks first when no owned mon fits")
  T.check(pg.items[1].label:find("VENUSAUR", 1, true) ~= nil, em.version .. ": the grass rental shares Treecko's type")
  m.cursor = 1
  m:input("a")
  T.check(m.step == "moves" or m.step == "size", em.version .. ": the rental needs no move changes")
  T.check(F.deepEqual({ treecko, pika }, before), em.version .. ": the save records are untouched")
end

local Gen1 = require("src.ui.union.prep.Gen1BattlePrep")
for _, version in ipairs(list) do
  local data = real[version]
  if data.generation <= 2 then
    local m = Model.new({ version = version, gen = data.generation, data = data, rules = rulesFor(1, data.generation),
      owned = { party = { sampleMon(data, 25, 30), sampleMon(data, 1, 12) }, generation = data.generation },
      opponent = { name = "MAY", version = "emerald" } })
    local worst = 0
    for _ = 1, 6 do
      local pg = m:page()
      local L = Gen1.layout(pg, m)
      T.check(#L.lines <= L.infoH - 3, version .. " " .. pg.step .. ": text fits its box")
      for _, line in ipairs(L.lines) do worst = math.max(worst, #line) end
      m:input("a")
    end
    T.check(worst <= 19, version .. ": no wrapped line is wider than the box (" .. worst .. ")")
  end
end

T.finish()
