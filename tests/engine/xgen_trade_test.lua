package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")
local T = require("tests.harness")
local F = require("tests.engine._xgen_fixture")
local TradeConvert = require("src.online.xgen.TradeConvert")
local Compat = require("src.online.xgen.Compat")
local Project = require("src.online.xgen.Project")
local Messages = require("src.online.xgen.Messages")

local function convert(src, dst, mon, adjustments)
  return TradeConvert.convert({ source = { data = src }, target = { data = dst }, mon = mon, adjustments = adjustments })
end

local function accountedAll(report, rec, label)
  local missing = {}
  for key in pairs(rec) do
    if report.accounting[key] == nil then missing[#missing + 1] = key end
  end
  T.eq(#missing, 0, label .. ": every source field is carried, changed, derived or lost (" .. table.concat(missing, ",") .. ")")
  local reported = {}
  for _, c in ipairs(report.changes) do reported[c.field] = c.kind end
  for key, fate in pairs(report.accounting) do
    if fate == "lost" then T.eq(reported[key], "loss", label .. ": lost field " .. key .. " reported as a loss") end
    if fate == "changed" then T.eq(reported[key], "change", label .. ": changed field " .. key .. " reported as a change") end
  end
end

local red, gold, silver, emerald = F.data("red"), F.data("gold"), F.data("silver"), F.data("emerald")

local g1 = { species = "PIKACHU", level = 25, exp = 15625, hp = 10, status = "PAR", nickname = "ZAPPY", ot = "RED", otId = 4242,
  dvs = { attack = 10, defense = 10, speed = 10, special = 10 }, statExp = { hp = 100, attack = 400, defense = 0, speed = 900, special = 2500 },
  moves = { { id = "THUNDERSHOCK", pp = 10, ppUps = 1 }, { id = "GROWL", pp = 40 } }, catchRate = 163,
  stats = { hp = 50 }, extra = { mod = 1 } }
local snap = F.copy(g1)
local r13 = convert(red, emerald, g1)
local r13b = convert(red, emerald, g1)
T.check(r13.ok, "Gen 1 Pikachu converts to Gen 3")
T.check(F.deepEqual(g1, snap), "conversion does not mutate the source")
T.eq(r13.canonical, r13b.canonical, "Gen 1 -> Gen 3 conversion is byte-deterministic")
T.check(not F.shares(g1, r13.result), "converted record shares no table with the source")
local out = r13.result
T.eq(out.personality % 25, 0, "personality gives a neutral (Hardy) nature")
T.eq(out.personality % 2, 0, "ability slot 0 parity")
T.check(Project.shiny3(out.personality, out.otId, out.otSecretId), "DV shininess kept in the personality")
T.eq(Project.gender3(127, out.personality), Project.genderDv(127, g1.dvs), "DV gender kept in the personality")
T.eq(out.ivs.atk, 21, "IV = 2*DV+1")
T.eq(out.ivs.spa, 21, "SpA IV from Special")
T.eq(out.evs.spa, 50, "SpA EV from Special Stat Exp")
T.eq(out.evs.spd, 50, "SpD EV from Special Stat Exp")
T.eq(out.metLocation, 0xFE, "met in a trade")
T.eq(out.metGame, 3, "met game is the destination game")
T.eq(out.abilityNum, 0, "ability slot 0")
T.eq(out.nickname, "ZAPPY", "nickname kept")
T.eq(out.otName, "RED", "OT kept")
T.eq(out.moves[1].ppUps, 1, "PP Ups kept")
T.eq(out.moves[1].pp, 30 + 6, "PP full at destination max")
T.eq(out.status, "", "status cleared")
T.eq(out.friendship, 70, "Gen 1 -> Gen 3 friendship is the species base")
accountedAll(r13, g1, "Gen 1 -> Gen 3")
local lostExtra = false
for _, c in ipairs(r13.changes) do if c.field == "extra" and c.kind == "loss" then lostExtra = true end end
T.check(lostExtra, "mod extra data reported lost across generations")

local back = convert(emerald, red, out)
T.check(back.ok, "and back to Gen 1")
T.check(F.deepEqual(back.result.dvs, { attack = 10, defense = 10, speed = 10, special = 10, hp = 0 }), "DVs round-trip through Gen 3")
accountedAll(back, out, "Gen 3 -> Gen 1")

local r12 = convert(red, gold, g1)
T.check(r12.ok, "Gen 1 -> Gen 2")
T.eq(r12.result.item, "LIGHT_BALL", "Gen 1 catch rate 163 becomes the Time Capsule held item")
T.eq(r12.result.happiness, 70, "Gen 1 -> Gen 2 friendship 70")
T.eq(r12.result.caughtLevel, 0, "Time Capsule clears caught data")
accountedAll(r12, g1, "Gen 1 -> Gen 2")

local g2 = { species = "UMBREON", level = 40, experience = 64000, nickname = "MOON", ot = "GOLD", otId = 9,
  dvs = { attack = 15, defense = 10, speed = 3, special = 7 }, statExp = { hp = 65535, attack = 0, defense = 0, speed = 0, special = 400 },
  moves = { { id = "TACKLE", pp = 35, maxPp = 35 }, { id = "CRUNCH", pp = 1, maxPp = 15 } }, item = "LEFTOVERS",
  happiness = 255, pokerus = 0x31, caughtLevel = 25, caughtTime = 1, caughtLocation = 4, caughtByGender = 1 }
local r23 = convert(gold, emerald, g2)
T.check(r23.ok, "Gen 2 Umbreon -> Gen 3")
T.eq(r23.result.item, 200, "Leftovers kept by canonical name")
T.eq(r23.result.friendship, 255, "friendship kept")
T.eq(r23.result.pokerus, 0x31, "Pokerus kept")
T.eq(r23.result.otGender, 1, "Crystal-style caught gender becomes OT gender")
accountedAll(r23, g2, "Gen 2 -> Gen 3")
local r21 = convert(gold, red, g2)
T.eq(r21.blocks[1].code, "species_missing", "Umbreon cannot go to Gen 1")
local g2b = F.copy(g2); g2b.species = "PIKACHU"; g2b.moves = { { id = "THUNDERSHOCK", pp = 30 } }; g2b.item = "LIGHT_BALL"
local r21b = convert(gold, red, g2b)
T.check(r21b.ok, "Gen 2 Pikachu -> Gen 1")
T.eq(r21b.result.catchRate, 163, "Gen 2 held item stored as Gen 1 catch rate")
accountedAll(r21b, g2b, "Gen 2 -> Gen 1")
local lost = {}
for _, c in ipairs(r21b.changes) do if c.kind == "loss" then lost[c.field] = true end end
T.check(lost.happiness and lost.pokerus and lost.caughtLevel, "friendship, Pokerus and caught data reported lost in Gen 1")

local g2mail = F.copy(g2); g2mail.item = "FLOWER_MAIL"
T.eq(convert(gold, emerald, g2mail).blocks[1].code, "mail", "mail refused")
local g2bow = F.copy(g2); g2bow.item = "PINK_BOW"
local bow = convert(gold, emerald, g2bow)
T.eq(bow.blocks[1].code, "item_unrepresentable", "item missing in the destination refused until removed")
T.eq(bow.result, nil, "no result while blocked")
local g2egg = F.copy(g2); g2egg.isEgg = true
T.eq(convert(gold, emerald, g2egg).blocks[1].code, "egg", "eggs refused")
local g2nick = F.copy(g2); g2nick.nickname = "MOON\226\130\172"
local nick = convert(gold, emerald, g2nick)
local hasNick = false
for _, b in ipairs(nick.blocks) do if b.code == "nickname_unencodable" then hasNick = true end end
T.check(hasNick, "a nickname the destination cannot write is refused, never truncated")
local g2long = F.copy(g2); g2long.ot = "ABCDEFGHIJ"
local long = convert(gold, emerald, g2long)
T.eq(long.blocks[1].code, "ot_unencodable", "an OT name longer than 7 is refused")

local g2same = convert(gold, silver, g2)
T.check(g2same.ok, "Gen 2 cross-version (different learnset layout)")
T.eq(g2same.result.caughtLevel, 25, "same-gen keeps caught data")
accountedAll(g2same, g2, "Gold -> Silver")

local g3 = { species = 25, level = 30, exp = 27000, personality = 0xABCD1234, otId = 77, otSecretId = 88, otName = "May",
  nickname = "Volt", ivs = { hp = 31, atk = 20, def = 21, spe = 30, spa = 19, spd = 5 }, evs = { hp = 4, atk = 0, def = 0, spe = 252, spa = 252, spd = 0 },
  moves = { 84, 98, 345 }, pp = { 30, 30, 20 }, ppBonusesPacked = 0, heldItem = 202, friendship = 120, pokerus = 0,
  metLocation = 16, metLevel = 5, metGame = 3, pokeball = 4, otGender = 1, language = 2, markings = 3, ribbons = 1,
  contest = { cool = 10 }, abilityNum = 0, isEgg = false }
local r32 = convert(emerald, gold, g3)
T.eq(r32.blocks[1].code, "move_missing", "Magical Leaf does not exist in Gen 2")
T.check(r32.options.moves and r32.options.moves[3] and #r32.options.moves[3] > 0, "replacement moves offered")
for _, m in ipairs(r32.options.moves[3]) do
  T.check(require("src.online.xgen.Datasets").learnable(gold, 25, m, 30), "offered replacement is legal for the species in the destination")
end
local r32b = convert(emerald, gold, g3, { moves = { [3] = 0 } })
T.check(r32b.ok, "removing the move allows the trade")
local d = r32b.result.dvs
T.eq(Project.shinyDv(d), Project.shiny3(g3.personality, 77, 88), "shininess kept in DVs")
T.eq(Project.genderDv(127, d), Project.gender3(127, g3.personality), "gender kept in DVs")
T.eq(r32b.result.item, "LIGHT_BALL", "Light Ball kept by name")
T.eq(r32b.result.happiness, 120, "friendship kept")
accountedAll(r32b, g3, "Gen 3 -> Gen 2")
local lostRibbons = false
for _, c in ipairs(r32b.changes) do if c.field == "ribbons" and c.kind == "loss" then lostRibbons = true end end
T.check(lostRibbons, "ribbons reported lost")
local illegal = convert(emerald, gold, g3, { moves = { [3] = 57 } })
T.eq(illegal.blocks[1].code, "replacement_not_legal", "staged replacement must be legal for the species (no free editor)")

local cmp = Compat.report({ op = "trade", source = { data = emerald }, target = { data = gold }, mon = g3, adjustments = { moves = { [3] = 0 } } })
T.check(cmp.ok and cmp.canonical == r32b.canonical, "Compat.report op=trade matches TradeConvert")

local real, list = F.allReal()
local pick = { [1] = nil, [2] = nil, [3] = nil }
for _, v in ipairs(list) do
  local g = real[v].generation
  if not pick[g] then pick[g] = v end
end
local function sampleFor(data)
  local n = 25
  local sp = data.species[n]
  local moves = {}
  for _, row in ipairs(sp.levelMoves) do
    if row.level <= 20 and #moves < 2 and row.move <= 165 then moves[#moves + 1] = row.move end
  end
  if data.generation == 3 then
    return { species = sp.localKey, level = 20, exp = sp.exp[20], personality = 0x00C0FFEE, otId = 321, otSecretId = 654,
      otName = "ASH", nickname = "PIKA", ivs = { hp = 10, atk = 11, def = 12, spe = 13, spa = 14, spd = 15 },
      evs = { hp = 1, atk = 2, def = 3, spe = 4, spa = 5, spd = 6 }, moves = moves, friendship = 90, heldItem = 0,
      metLocation = 1, metLevel = 3, metGame = 4, pokeball = 4, otGender = 0, language = 2, ribbons = 0, contest = {} }
  end
  local list2 = {}
  for _, m in ipairs(moves) do list2[#list2 + 1] = { id = data.moves[m].localKey, pp = 1, ppUps = 0 } end
  local rec = { species = sp.localKey, level = 20, nickname = "PIKA", ot = "ASH", otId = 321,
    dvs = { attack = 9, defense = 8, speed = 7, special = 6 }, statExp = { hp = 1, attack = 4, defense = 9, speed = 16, special = 25 },
    moves = list2 }
  if data.generation == 2 then rec.experience = sp.exp[20]; rec.happiness = 80 else rec.exp = sp.exp[20] end
  return rec
end
local combos = 0
for gs = 1, 3 do
  for gd = 1, 3 do
    local sv, dv = pick[gs], pick[gd]
    if sv and dv then
      local s, dd = real[sv], real[dv]
      local rec = sampleFor(s)
      local rep = convert(s, dd, rec)
      if gs == gd and sv == dv then
        local other
        for _, v in ipairs(list) do if v ~= sv and real[v].generation == gs then other = v break end end
        if other then dv, dd = other, real[other]; rep = convert(s, dd, rec) end
      end
      T.check(rep.ok, ("%s -> %s converts a level 20 Pikachu (%s)"):format(sv, dv, rep.blocks[1] and rep.blocks[1].code or "ok"))
      if rep.ok then
        combos = combos + 1
        T.eq(rep.canonical, convert(s, dd, rec).canonical, sv .. " -> " .. dv .. " deterministic")
        accountedAll(rep, rec, sv .. " -> " .. dv)
        local view = Project.read(rep.result, dd)
        T.check(view ~= nil and view.national == 25, sv .. " -> " .. dv .. " result reads back as Pikachu in the destination")
      end
    end
  end
end
if combos == 0 then print("[skip] xgen trade: no imported caches for the 9 combos") end
local cross = { { "red", "yellow" }, { "gold", "crystal" }, { "firered", "emerald" }, { "ruby", "firered" }, { "emerald", "ruby" } }
for _, pair in ipairs(cross) do
  local s, dd = real[pair[1]], real[pair[2]]
  if s and dd then
    local rec = sampleFor(s)
    local rep = convert(s, dd, rec)
    T.check(rep.ok, pair[1] .. " -> " .. pair[2] .. " same-gen cross-version")
    if rep.ok then accountedAll(rep, rec, pair[1] .. " -> " .. pair[2]) end
  end
end

for _, rep in ipairs({ r21, bow, nick, long, r32, illegal }) do
  for _, b in ipairs(rep.blocks) do T.check(Messages.known(b.code), "message exists for " .. b.code) end
end

T.finish("xgen_trade")
