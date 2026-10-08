package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")
local T = require("tests.harness")
local F = require("tests.engine._xgen_fixture")
local Identity = require("src.online.xgen.Identity")
local Datasets = require("src.online.xgen.Datasets")

T.eq(Identity.normalize("NIDORAN\226\153\128"), "NIDORANF", "female symbol normalizes")
T.eq(Identity.normalize("MR. MIME"), Identity.normalize("MR.MIME"), "punctuation and spaces ignored")
T.eq(Identity.normalize("POK\195\169 BALL"), "POKEBALL", "accented e normalizes")
T.eq(Identity.canonType("PSYCHIC_TYPE", 1), "PSYCHIC", "Gen 1 PSYCHIC_TYPE is PSYCHIC")
T.eq(Identity.canonType("CURSE_TYPE", 2), "MYSTERY", "Gen 2 curse type is MYSTERY")
T.eq(Identity.canonType(13, 3), "ELECTRIC", "Gen 3 type id 13 is ELECTRIC")
T.eq(Identity.category("FIRE", 90), "special", "fire is special")
T.eq(Identity.category("DARK", 80), "special", "dark is special")
T.eq(Identity.category("GHOST", 30), "physical", "ghost is physical")
T.eq(Identity.category("NORMAL", 0), "status", "zero power is status")

local red, gold, silver, emerald = F.data("red"), F.data("gold"), F.data("silver"), F.data("emerald")
T.eq(Identity.speciesOf(red, "PIKACHU"), 25, "Gen 1 local key maps to national")
T.eq(Identity.localSpecies(emerald, 252), 277, "Gen 3 national 252 maps to internal 277")
T.eq(Identity.speciesOf(emerald, 277), 252, "Gen 3 internal maps to national")
T.eq(Identity.moveOf(red, "PSYCHIC_M"), 94, "Gen 1 move key maps to canonical id")
T.eq(Identity.localMove(gold, 202), "GIGA_DRAIN", "canonical id maps back to local key")
T.eq(red.moves[94].type, "PSYCHIC", "move type canonical")
T.eq(emerald.species[25].types[1], "ELECTRIC", "Gen 3 species types canonical and deduped")
T.eq(#emerald.species[25].types, 1, "single-type species has one type")
T.eq(#emerald.problems, 0, "fixture Gen 3 type names agree with canonical")

local okA = Identity.agree(red, emerald)
T.check(okA, "fixture Gen 1 and Gen 3 identities agree")
local okB = Identity.agree(gold, silver)
T.check(okB, "two Gen 2 learnset layouts agree on identity")

local function sameLevel(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do if a[i].level ~= b[i].level or a[i].move ~= b[i].move then return false end end
  return true
end
for _, n in ipairs({ 1, 2, 25, 152 }) do
  T.check(sameLevel(gold.species[n].levelMoves, silver.species[n].levelMoves), "levelMoves and learnset layouts give the same level-up list for " .. n)
  T.check(F.deepEqual(gold.species[n].egg, silver.species[n].egg), "egg moves agree across layouts for " .. n)
end
T.check(Datasets.learnable(red, 2, 22, 30), "Ivysaur keeps Bulbasaur's Vine Whip through the evolution chain")
T.check(not Datasets.learnable(red, 1, 22, 5), "level gate applies to level-up moves")
T.check(Datasets.learnable(red, 1, 33, 1), "level 1 moves are legal")
T.check(Datasets.learnable(gold, 1, 75, 5), "Gen 2 egg moves are legal")
T.check(Datasets.learnable(gold, 2, 75, 30), "prevo egg moves are legal")
T.check(Datasets.learnable(emerald, 25, 85, 5), "Gen 3 TM bitfield decoded")
T.check(Datasets.learnable(emerald, 25, 34, 5), "Gen 3 tutor bitfield decoded")
T.check(not Datasets.learnable(emerald, 25, 57, 5), "unset tutor bit is not legal")

local real, list = F.allReal()
if #list < 2 then
  print("[skip] xgen identity: fewer than two imported caches")
else
  for i = 1, #list do
    local d = real[list[i]]
    T.eq(#d.problems == 0 or d.generation == 1, true, list[i] .. " dataset builds without identity problems")
    for j = i + 1, #list do
      local ok, mismatches = Identity.agree(d, real[list[j]])
      T.check(ok, ("%s and %s agree on species and move identity (%d mismatches)"):format(list[i], list[j], #mismatches))
    end
  end
  for _, v in ipairs(list) do
    local d = real[v]
    local count = 0
    for _ in pairs(d.species) do count = count + 1 end
    T.eq(count, d.dexMax, v .. " has every national dex entry up to its dex max")
  end
end

T.finish("xgen_identity")
