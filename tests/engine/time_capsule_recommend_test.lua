package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")
local T = require("tests.harness")
local Convert = require("src.online.Convert")
local Recommend = require("src.recommend.Recommend")
local Mon = require("src.battle.gen2.Mon")
local Stats = require("src.pokemon.Stats")
local Growth = require("src.pokemon.Growth")

local gen1Data = {
  pokemon = {
    TESTMON = { id = "TESTMON", name = "TESTMON", index = 1, dex = 1, types = { "GRASS", "POISON" },
      baseStats = { hp = 45, attack = 49, defense = 49, speed = 45, special = 65 },
      catchRate = 45, growthRate = "MEDIUM_SLOW" },
  },
  moves = {
    TACKLE = { id = "TACKLE", name = "TACKLE", index = 33, pp = 35 },
    VINE_WHIP = { id = "VINE_WHIP", name = "VINE WHIP", index = 22, pp = 10 },
    BODY_SLAM = { id = "BODY_SLAM", name = "BODY SLAM", index = 34, pp = 15 },
  },
}

local gen2Data = {
  pokemon = {
    TESTMON = { id = "TESTMON", name = "TESTMON", types = { "GRASS", "POISON" },
      baseStats = { hp = 45, attack = 49, defense = 49, speed = 45, specialAttack = 65, specialDefense = 65 },
      growthRate = "GROWTH_MEDIUM_SLOW", genderRatio = 0x1f },
    growthRates = {
      GROWTH_MEDIUM_SLOW = { numerator = 6, denominator = 5, squared = -15, linear = 100, constant = 140 },
    },
  },
  moves = {
    TACKLE = { id = "TACKLE", name = "TACKLE", pp = 35 },
    VINE_WHIP = { id = "VINE_WHIP", name = "VINE WHIP", pp = 10 },
    BODY_SLAM = { id = "BODY_SLAM", name = "BODY SLAM", pp = 15 },
    GIGA_DRAIN = { id = "GIGA_DRAIN", name = "GIGA DRAIN", pp = 5 },
    SWEET_SCENT = { id = "SWEET_SCENT", name = "SWEET SCENT", pp = 20 },
  },
  items = {},
}

local DVS = { attack = 15, defense = 14, speed = 13, special = 12 }

local function gen2Mon(moves)
  local dvs = {}
  for k, v in pairs(DVS) do dvs[k] = v end
  dvs.hp = Mon.hpDV(dvs)
  local statExp = { hp = 0, attack = 0, defense = 0, speed = 0, special = 0 }
  local stats = Mon.stats(gen2Data.pokemon.TESTMON.baseStats, dvs, 30, statExp)
  return { species = "TESTMON", level = 30,
    experience = Mon.experienceForLevel(Mon.growthFor(gen2Data, "GROWTH_MEDIUM_SLOW"), 30),
    dvs = dvs, statExp = statExp, stats = stats, hp = stats.hp, maxHp = stats.hp,
    happiness = 128, pokerus = 0, caughtLevel = 5, moves = moves,
    nickname = "SPROUT", ot = "GOLD", otName = "GOLD", otId = 4321, traded = false, isEgg = false }
end

local function gen1Mon()
  local def = gen1Data.pokemon.TESTMON
  local dvs = {}
  for k, v in pairs(DVS) do dvs[k] = v end
  dvs.hp = Mon.hpDV(dvs)
  local statExp = { hp = 0, attack = 0, defense = 0, speed = 0, special = 0 }
  local stats = Stats.calc(def, 30, dvs, statExp)
  return { species = "TESTMON", level = 30, exp = Growth.expForLevel(def.growthRate, 30), dvs = dvs,
    statExp = statExp, stats = stats, hp = stats.hp, catchRate = 45,
    moves = { { id = "TACKLE", pp = 35, ppUps = 0 } }, nickname = "SPROUT", ot = "RED", otId = 1234 }
end

local illegal = gen2Mon({ { id = "TACKLE", pp = 35, maxPp = 35 }, { id = "GIGA_DRAIN", pp = 5, maxPp = 5 } })

do
  local out, reason = Convert.toGen1(illegal, gen2Data, gen1Data)
  T.check(out == nil and reason == "move_too_new", "a Gen 2 move refuses the Time Capsule trade")
  local fixed, report = Convert.toGen1(illegal, gen2Data, gen1Data,
    { moves = { "BODY_SLAM", "SWEET_SCENT", "VINE_WHIP", "BODY_SLAM" } })
  T.check(fixed ~= nil, "the recommended moveset lets it through")
  local ids = {}
  for _, mv in ipairs(fixed and fixed.moves or {}) do ids[#ids + 1] = mv.id end
  T.eq(table.concat(ids, ","), "BODY_SLAM,VINE_WHIP", "moves Gen 1 lacks and duplicates are dropped")
  T.eq(fixed and fixed.moves[1].pp, 15, "replacement moves start at full PP")
  T.eq(fixed and fixed.moves[1].ppUps, 0, "and no PP Ups")
  local said = false
  for _, row in ipairs(report and report.changed or {}) do
    if row.kind == "moves" then said = true end
  end
  T.check(said, "the conversion report lists the replaced moveset")
  T.eq(#illegal.moves, 2, "the source record is not modified")
  local lines, legal = Convert.preview(illegal, 2, 1, gen2Data, gen1Data, { moves = { "BODY_SLAM" } })
  T.check(legal and table.concat(lines, "|"):find("RECOMMENDED", 1, true) ~= nil, "the preview uses the replacement")
  local still, why = Convert.toGen1(illegal, gen2Data, gen1Data, { moves = { "GIGA_DRAIN" } })
  T.check(still == nil and why == "move_too_new", "a set with no Gen 1 move keeps the refusal")
end

local OnlinePanel = require("src.import.OnlinePanel")

package.loaded["src.box.Catalog"] = { get = function() return { moves = gen1Data.moves } end }

local planned = {}
package.loaded["src.online.Trade"] = {
  withDataset = function(version, fn)
    return fn(version == "red" and gen1Data or gen2Data)
  end,
  plan = function(req)
    local monA, monB = req.from.party[req.fromIndex], req.to.party[req.toIndex]
    local intoB, whyB = req.convert(monA, req.from.generation, req.to.generation)
    if not intoB then return nil, whyB end
    local intoA, whyA = req.convert(monB, req.to.generation, req.from.generation)
    if not intoA then return nil, whyA end
    planned[#planned + 1] = { a = intoA, b = intoB }
    return { sides = { { role = "a", handle = req.from, sent = monA, received = intoA },
      { role = "b", handle = req.to, sent = monB, received = intoB } }, warnings = {} }
  end,
}

local function fakeClient(sets, opts)
  opts = opts or {}
  local c = { sent = {}, polls = 0 }
  function c:send(method, path, _, req)
    if opts.offline then error("no transport") end
    self.sent[#self.sent + 1] = { method = method, path = path, species = req and req.params and req.params.species }
    return #self.sent
  end
  function c:poll()
    self.polls = self.polls + 1
    if self.polls <= (opts.pendingPolls or 0) then return { status = "pending" } end
    return { status = "ok", data = { sets = sets } }
  end
  function c:release() end
  return c
end

local function setup(mon)
  local imp = {}
  local tr = OnlinePanel.tradeState(imp)
  local a = { version = "gold", slotId = "s1", label = "GOLD" }
  local b = { version = "red", slotId = "s2", label = "RED" }
  tr.sides.a, tr.sides.b = a, b
  tr.handles.a = { entry = a, handle = { version = "gold", generation = 2, party = { mon } } }
  tr.handles.b = { entry = b, handle = { version = "red", generation = 1, party = { gen1Mon() } } }
  tr.picks.a, tr.picks.b = 1, 1
  return imp, tr
end

local SETS = { testmon = { generation = 1, species = "Testmon",
  set = { moves = { "Body Slam", "Hyper Beam", "Vine Whip" } } } }

do
  Recommend.reset()
  local client = fakeClient(SETS, { pendingPolls = 1 })
  OnlinePanel.recommendClient = client
  local imp, tr = setup(illegal)
  T.check(not OnlinePanel.tradeModalPreview(imp), "the Gen 2 move stops the preview")
  T.eq(tr.status, "Some moves can't come along. Replace them with the recommended moveset?", "the player is asked")
  T.check(tr.recommendAsk ~= nil, "a yes/no prompt is up")
  T.check(OnlinePanel.tradeRecommendAnswer(imp, true), "yes starts the fetch")
  T.eq(client.sent[1] and client.sent[1].path, "/recommend/gen1", "it asks for the Gen 1 set")
  T.eq(client.sent[1] and client.sent[1].species, "testmon", "for the species being sent")
  T.check(tr.recommendJob ~= nil and OnlinePanel.tradeModal(imp) == nil, "the fetch is still pending")
  OnlinePanel.pumpTradeRecommend(imp)
  T.check(tr.recommendJob == nil, "the update loop finishes the fetch")
  T.check(OnlinePanel.tradeModal(imp) ~= nil, "the trade preview opens with the recommended moves")
  local got = planned[#planned]
  local ids = {}
  for _, mv in ipairs(got and got.b.moves or {}) do ids[#ids + 1] = mv.id end
  T.eq(table.concat(ids, ","), "BODY_SLAM,VINE_WHIP", "Red receives the recommended Gen 1 moves")
  OnlinePanel.tradeModalClose(imp)
  OnlinePanel.tradePick(imp, "a", 1)
  T.check(tr.recommendMoves == nil, "changing the pick drops the override")
end

do
  Recommend.reset()
  OnlinePanel.recommendClient = fakeClient(SETS)
  local imp, tr = setup(illegal)
  OnlinePanel.tradeModalPreview(imp)
  T.check(OnlinePanel.tradeRecommendAnswer(imp, false), "no is accepted")
  T.check(tr.status:find("MOVE ILLEGAL IN GEN 1", 1, true) ~= nil, "no keeps the old refusal: " .. tostring(tr.status))
  OnlinePanel.tradeModalPreview(imp)
  T.check(tr.recommendAsk == nil, "the question is not asked twice for the same mon")
end

do
  Recommend.reset()
  OnlinePanel.recommendClient = fakeClient({}, { offline = true })
  local imp, tr = setup(illegal)
  OnlinePanel.tradeModalPreview(imp)
  OnlinePanel.tradeRecommendAnswer(imp, true)
  T.check(tr.recommendJob == nil and OnlinePanel.tradeModal(imp) == nil, "offline does not open the preview")
  T.check(tr.status:find("Couldn't reach the server", 1, true) ~= nil
    and tr.status:find("MOVE ILLEGAL IN GEN 1", 1, true) ~= nil, "offline gives a short reason and the refusal: " .. tr.status)
end

do
  Recommend.reset()
  local eggMon = gen2Mon({ { id = "GIGA_DRAIN", pp = 5 } })
  eggMon.isEgg = true
  OnlinePanel.recommendClient = fakeClient(SETS)
  local imp, tr = setup(eggMon)
  OnlinePanel.tradeModalPreview(imp)
  T.check(tr.recommendAsk == nil, "other refusals never ask about moves")
end

T.finish("time_capsule_recommend")
