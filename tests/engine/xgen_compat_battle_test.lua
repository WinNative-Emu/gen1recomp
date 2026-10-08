package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")
local T = require("tests.harness")
local F = require("tests.engine._xgen_fixture")
local Compat = require("src.online.xgen.Compat")
local Policy = require("src.online.xgen.Policy")
local Messages = require("src.online.xgen.Messages")

local emerald = F.data("emerald")
local ruleset = { ruleset = "g3u-gen1", dexMax = 151, moveMax = 165 }

local function mon3(national, level, moves, extra)
  local m = { species = emerald.nationalToLocal[national], level = level, personality = 7, otId = 1, otSecretId = 0,
    otName = "MAY", ivs = { hp = 1, atk = 1, def = 1, spe = 1, spa = 1, spd = 1 }, evs = {}, moves = moves }
  for k, v in pairs(extra or {}) do m[k] = v end
  return m
end

local treecko = mon3(252, 20, { 33, 345 })
local pika = mon3(25, 20, { 84, 45, 98, 57 })
local bulba = mon3(1, 10, { 33 })
local owned = {
  { rec = mon3(197, 30, { 33 }), ref = "pc:1" },
  { rec = mon3(25, 18, { 84 }), ref = "pc:2" },
  { rec = mon3(152, 25, { 33 }), ref = "pc:3" },
  { rec = mon3(1, 22, { 33 }), ref = "pc:4" },
  { rec = mon3(2, 21, { 33 }), ref = "pc:5" },
  { rec = mon3(150, 60, { 94 }), ref = "pc:6" },
}

local args = { op = "battle", source = { game = "emerald", gen = 3, data = emerald }, target = ruleset,
  mons = { treecko, pika, bulba }, owned = owned, opponentSize = 3,
  versions = { policy = Policy.VERSION, proto = Policy.PROTO } }
local snapshot = F.copy(args.mons)
local r = Compat.report(args)
T.check(F.deepEqual(args.mons, snapshot), "report does not mutate the team")
T.check(not r.ok, "Treecko and an illegal move block the team")
local byCode = {}
for _, b in ipairs(r.blocks) do byCode[b.code] = byCode[b.code] or {}; table.insert(byCode[b.code], b) end
T.check(byCode.species_not_in_ruleset and byCode.species_not_in_ruleset[1].slot == 1, "Treecko is outside dex 1-151")
T.eq(byCode.species_not_in_ruleset[1].detail.dexMax, 151, "block explains the dex limit")
local reps = r.options.replacements[1]
T.check(reps and #reps > 0, "replacement candidates offered")
T.eq(reps[1].national, 2, "shares Treecko's grass type, closest level first (Ivysaur 21)")
T.eq(reps[2].national, 1, "then Bulbasaur 22")
T.eq(reps[3].sharesType, false, "non-sharing types after the sharing ones")
T.eq(reps[3].national, 25, "then by level closeness (Pikachu 18)")
local seen152 = false
for _, row in ipairs(reps) do if row.national == 152 then seen152 = true end end
T.check(not seen152, "Chikorita (dex 152) is not an eligible replacement")
local lastShares = true
local order_ok = true
for _, row in ipairs(reps) do
  if row.sharesType and not lastShares then order_ok = false end
  lastShares = row.sharesType
end
T.check(order_ok, "shares-type candidates are ranked before the rest")

local codesForPika = {}
for _, b in ipairs(r.blocks) do if b.slot == 2 then codesForPika[b.detail.index] = b.code end end
T.eq(codesForPika[4], "move_not_legal", "Surf exists in the ruleset but Pikachu cannot learn it")
T.eq(codesForPika[3], nil, "Quick Attack (98) is legal for Pikachu")
local trA = Compat.report({ op = "battle", source = args.source, target = ruleset, mons = { mon3(1, 10, { 33, 345 }) }, opponentSize = 1 })
T.eq(trA.blocks[1].code, "move_not_in_ruleset", "Magical Leaf (345) does not exist in a Gen 1 ruleset")
local sugg = r.options.moves[2][4]
T.check(sugg and #sugg > 0, "legal replacement moves suggested")
T.eq(sugg[1].move, 85, "no water move: same category and power band first (Thunderbolt)")
T.eq(sugg[2].move, 34, "then by name (Body Slam)")

local unsupported = Compat.report({ op = "battle", source = args.source, target = ruleset, mons = { mon3(25, 20, { 84, 85 }) },
  opponentSize = 1, unsupported = { 85 } })
T.eq(unsupported.blocks[1].code, "move_unsupported", "unsupported list from the match table makes a move illegal")

local fixed = Compat.report({ op = "battle", source = args.source, target = ruleset, mons = { treecko, pika, bulba },
  owned = owned, opponentSize = 3,
  adjustments = { replace = { [1] = { owned = 4 } }, moves = { [2] = { [4] = 0 } } } })
T.check(fixed.ok, "replacement plus an emptied slot makes the team legal")
T.eq(#fixed.result.team, 3, "three battlers")
T.eq(fixed.result.team[1].species, 1, "slot 1 replaced by Bulbasaur from the PC")
T.eq(#fixed.result.team[2].moves, 3, "emptied move slot dropped")
T.eq(fixed.result.team[2].moves[1].id, 84, "move order kept (1)")
T.eq(fixed.result.team[2].moves[3].id, 98, "move order kept (3)")
local emptied = false
for _, c in ipairs(fixed.changes) do if c.field == "moves" and c.to == 0 then emptied = true end end
T.check(emptied, "emptied move reported as a change")

local swapped = Compat.report({ op = "battle", source = args.source, target = ruleset, mons = { pika }, opponentSize = 1,
  adjustments = { moves = { [1] = { [4] = 85 } } } })
T.check(swapped.ok, "Thunderbolt (TM, learnable) can replace Surf")
T.eq(swapped.result.team[1].moves[4].id, 85, "replacement lands in the same slot")
local bad = Compat.report({ op = "battle", source = args.source, target = ruleset, mons = { pika }, opponentSize = 1,
  adjustments = { moves = { [1] = { [4] = 57 } } } })
T.eq(bad.blocks[1].code, "replacement_not_legal", "replacement must itself be legal")

local none = Compat.report({ op = "battle", source = args.source, target = ruleset, mons = { mon3(25, 20, { 57 }) }, opponentSize = 1,
  adjustments = { moves = { [1] = { [1] = 0 } } } })
T.eq(none.blocks[1].code, "no_legal_moves", "a battler needs at least one legal move")

local big = Compat.report({ op = "battle", source = args.source, target = ruleset, mons = { pika, bulba, mon3(25, 30, { 84 }) },
  opponentSize = 2 })
T.eq(big.blocks[1].code, "choose_sit_out", "larger roster must choose who sits out")
T.eq(big.blocks[1].detail.need, 1, "one must sit out")
T.eq(big.result, nil, "no team is auto-picked")
local sat = Compat.report({ op = "battle", source = args.source, target = ruleset, mons = { pika, bulba, mon3(25, 30, { 84 }) },
  opponentSize = 2, adjustments = { sitOut = { 1 }, moves = {} } })
T.check(sat.ok, "explicit sit-out resolves the size")
T.eq(sat.result.team[1].species, 1, "remaining order kept (Bulbasaur first)")
T.eq(sat.result.slots[1], 2, "slot indices recorded")
T.eq(Compat.teamSize(6, 3), 3, "equal teams default to the smaller roster")
T.eq(Compat.teamSize(6, 6, 4), 4, "both may agree a smaller size")
T.eq(Compat.teamSize(2, 6, 4), 2, "never above the smaller roster")

local version = Compat.report({ op = "battle", source = args.source, target = ruleset, mons = { bulba }, opponentSize = 1,
  versions = { policy = 99 } })
T.eq(version.blocks[1].code, "policy_mismatch", "policy version mismatch blocks")

local egg = Compat.report({ op = "battle", source = args.source, target = ruleset, mons = { mon3(1, 5, { 33 }, { isEgg = true }) }, opponentSize = 1 })
T.eq(egg.blocks[1].code, "egg", "eggs cannot battle")

for _, rep in ipairs({ r, trA, unsupported, bad, none, big, version, egg }) do
  for _, b in ipairs(rep.blocks) do
    T.check(Messages.known(b.code), "message exists for " .. b.code)
  end
end

T.finish("xgen_compat_battle")
