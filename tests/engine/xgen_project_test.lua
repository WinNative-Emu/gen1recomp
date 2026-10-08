package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")
local T = require("tests.harness")
local F = require("tests.engine._xgen_fixture")
local Project = require("src.online.xgen.Project")
local TradeConvert = require("src.online.xgen.TradeConvert")

local red, gold, emerald = F.data("red"), F.data("gold"), F.data("emerald")

local gen1 = { species = "MEWTWO", level = 70, exp = 427000, nickname = "MEWTWO", ot = "RED", otId = 1234,
  dvs = { attack = 15, defense = 14, speed = 13, special = 12 },
  statExp = { hp = 65535, attack = 65535, defense = 40000, speed = 100, special = 10000 },
  moves = { { id = "PSYCHIC_M", pp = 3, ppUps = 2 } }, hp = 12, status = "PSN" }
local before = F.copy(gen1)
local a = Project.mon(gen1, red, { legacyPresent = true })
local b = Project.mon(gen1, red, { legacyPresent = true })
T.check(F.deepEqual(gen1, before), "projection leaves the Gen 1 record untouched")
T.eq(TradeConvert.canonical(a), TradeConvert.canonical(b), "same Gen 1 input gives byte-equal projection")
T.check(not F.shares(gen1, a), "projection shares no table with its input")
T.eq(a.ivs.atk, 31, "DV 15 -> IV 31")
T.eq(a.ivs.def, 29, "DV 14 -> IV 29")
T.eq(a.ivs.spa, 25, "Special DV 12 -> SpA IV 25")
T.eq(a.ivs.spd, 25, "Special DV 12 -> SpD IV 25")
T.eq(a.ivs.hp, Project.hpDv({ attack = 15, defense = 14, speed = 13, special = 12 }) * 2 + 1, "HP IV from the derived HP DV")
T.eq(a.evs.hp, 255, "Stat Exp 65535 -> 255 EV")
T.eq(a.evs.atk, 255, "Stat Exp 65535 -> 255 EV")
T.eq(a.evs.def, 0, "510 cap applied in slot order")
T.eq(a.evs.spa, 0, "cap reaches SpA")
T.eq(a.spAtk, a.spDef, "Gen 1 SpA and SpD both from Special")
T.eq(a.nature, 0, "nature neutral")
T.eq(a.ability, 0, "ability off")
T.eq(a.item, 0, "item off")
T.eq(a.types, nil, "battle record carries no typing")
T.eq(a.hp, a.maxHp, "HP full")
T.eq(a.status, nil, "status clear")
T.eq(a.moves[1].id, 94, "move by canonical id")
T.eq(a.moves[1].ppUps, 2, "PP Up count kept")
T.eq(a.moves[1].pp, 10 + 2 * 2, "PP is max PP with the same PP Up count")
T.eq(a.species, 150, "species is the national dex number")
local expectHp = math.floor(((2 * 106 + a.ivs.hp + math.floor(255 / 4)) * 70) / 100) + 70 + 10
T.eq(a.maxHp, expectHp, "Gen 3 HP formula from owner's base stats")

local gen3 = { species = 25, level = 30, exp = 27000, personality = 0x12345678 + 3, otId = 1000, otSecretId = 2,
  otName = "Max", nickname = "SPARKY", ivs = { hp = 31, atk = 10, def = 11, spe = 30, spa = 20, spd = 21 },
  evs = { hp = 4, atk = 0, def = 0, spe = 252, spa = 252, spd = 0 }, moves = { 84, 98 }, pp = { 1, 2 },
  ppBonusesPacked = 1 + 3 * 4, heldItem = 202, friendship = 200 }
local before3 = F.copy(gen3)
local c = Project.mon(gen3, emerald, { legacyPresent = true })
local d = Project.mon(gen3, emerald, { legacyPresent = false })
T.check(F.deepEqual(gen3, before3), "projection leaves the Gen 3 record untouched")
T.check(not F.shares(gen3, c), "Gen 3 projection shares no table with its input")
T.eq(c.ivs.spa, 20, "Gen 3 IVs kept")
T.eq(c.evs.spe, 252, "Gen 3 EVs kept")
T.eq(c.nature, 0, "legacy present: neutral nature")
T.eq(c.ability, 0, "legacy present: ability off")
T.eq(c.item, 0, "legacy present: item off")
T.eq(d.nature, gen3.personality % 25, "Gen 3 only: nature kept")
T.eq(d.item, 202, "Gen 3 only: item kept")
T.eq(d.ability, 9, "Gen 3 only: ability kept")
T.eq(c.moves[1].ppUps, 1, "packed PP Up slot 1")
T.eq(c.moves[2].ppUps, 3, "packed PP Up slot 2")
T.eq(c.moves[2].pp, 30 + 3 * 6, "PP Up 3 on 30 PP")
local neutral = Project.stats3({ hp = 50, atk = 50, def = 50, spe = 50, spa = 50, spd = 50 }, 50,
  { hp = 31, atk = 31, def = 31, spe = 31, spa = 31, spd = 31 }, { hp = 0, atk = 0, def = 0, spe = 0, spa = 0, spd = 0 }, 0, 1)
local adamant = Project.stats3({ hp = 50, atk = 50, def = 50, spe = 50, spa = 50, spd = 50 }, 50,
  { hp = 31, atk = 31, def = 31, spe = 31, spa = 31, spd = 31 }, { hp = 0, atk = 0, def = 0, spe = 0, spa = 0, spd = 0 }, 3, 1)
T.eq(neutral.atk, 70, "neutral Atk")
T.eq(adamant.atk, 77, "Adamant raises Atk")
T.eq(adamant.spa, 63, "Adamant lowers SpA")

local gen2 = { species = "UMBREON", level = 40, experience = 64000, dvs = { attack = 10, defense = 10, speed = 10, special = 10 },
  statExp = { hp = 0, attack = 0, defense = 0, speed = 0, special = 0 }, moves = { { id = "TACKLE", pp = 35 } },
  item = "LEFTOVERS", happiness = 255, ot = "GOLD", otId = 5 }
local e = Project.mon(gen2, gold, { legacyPresent = true })
T.check(e.shiny, "Gen 2 DV shiny rule")
T.eq(e.gender, Project.genderDv(31, gen2.dvs), "Gen 2 DV gender rule")
T.eq(e.item, 0, "Gen 2 held item off in g3u")

T.finish("xgen_project")
