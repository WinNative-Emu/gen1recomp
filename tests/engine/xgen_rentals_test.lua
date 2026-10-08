package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")
local T = require("tests.harness")
local F = require("tests.engine._xgen_fixture")
local Rentals = require("src.online.xgen.Rentals")
local Identity = require("src.online.xgen.Identity")
local Policy = require("src.online.xgen.Policy")

T.eq(Rentals.VERSION, 1, "rental table version")
T.eq(Rentals.VERSION, Policy.RENTALS, "policy advertises the rental version")
local expected = { ["g3u-gen1"] = Identity.GEN1_TYPES, ["g3u-gen2"] = Identity.TYPES, ["g3u-gen3"] = Identity.TYPES }
for id, types in pairs(expected) do
  local defs = Rentals.DEFINITIONS[id]
  local ruleset = Policy.ruleset(id)
  T.eq(#defs, #types, id .. " has one rental per ordinary type")
  local byType, species = {}, {}
  for _, def in ipairs(defs) do
    byType[def.type] = (byType[def.type] or 0) + 1
    T.check(not species[def.species], id .. " rental species distinct: " .. def.species)
    species[def.species] = true
    T.check(def.species <= ruleset.dexMax, id .. " rental species within dex max")
    for _, m in ipairs(def.moves) do T.check(m <= ruleset.moveMax, id .. " rental move within move max: " .. m) end
  end
  for _, t in ipairs(types) do T.eq(byType[t], 1, id .. " covers " .. t) end
  T.eq(byType.MYSTERY, nil, id .. " has no ??? rental")
end

local fixture = F.data("red")
local built = Rentals.build("g3u-gen1", fixture)
T.check(#built.excluded > 0, "fixture data cannot support every rental")
local tauros
for _, ex in ipairs(built.excluded) do
  T.check(ex.code ~= nil and ex.type ~= nil, "excluded rental reports type and code")
  if ex.species == 128 then tauros = ex end
end
T.eq(tauros and tauros.code, "species_not_in_ruleset", "rental for a species missing from the data is excluded and reported")
local unknown = Rentals.build("g3u-nope", fixture)
T.eq(unknown.excluded[1].code, "unknown_ruleset", "unknown ruleset reported")

local real, list = F.allReal()
if #list == 0 then
  print("[skip] xgen rentals: no imported caches")
else
  for _, version in ipairs(list) do
    local d = real[version]
    for id, rs in pairs(Policy.RULESETS) do
      if d.generation >= rs.gen then
        local out = Rentals.build(id, d)
        T.eq(#out.excluded, 0, ("%s rentals all legal in %s"):format(id, version))
        for _, ex in ipairs(out.excluded) do print("  excluded", id, version, ex.type, ex.species, ex.code, ex.detail and ex.detail.move) end
        T.eq(#out.rentals, #Rentals.DEFINITIONS[id], ("%s full rental set in %s"):format(id, version))
        for _, r in ipairs(out.rentals) do
          T.eq(r.record.rental, true, "rental record tagged")
          T.eq(r.record.level, 50, "rental level 50")
          T.eq(#r.moves, #r.record.moves, "rental moves disclosed")
          T.check(r.stats.hp > 0 and r.stats.speed > 0, "rental stats disclosed")
        end
        local again = Rentals.build(id, d)
        T.eq(require("src.online.xgen.TradeConvert").canonical(again.rentals),
          require("src.online.xgen.TradeConvert").canonical(out.rentals), id .. " rental build deterministic in " .. version)
      end
    end
  end
end

T.finish("xgen_rentals")
