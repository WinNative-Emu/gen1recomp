package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")
local T = require("tests.harness")
local F = require("tests.engine._xgen_fixture")
local Datasets = require("src.online.xgen.Datasets")
local Rentals = require("src.online.xgen.Rentals")
local Recommend = require("src.recommend.Recommend")
local Model = require("src.online.union.BattlePrepModel")

local function ids(list)
  local out = {}
  for i, m in ipairs(list) do out[i] = tostring(type(m) == "table" and (m.id or m.move) or m) end
  return table.concat(out, ",")
end

local function fakeClient(reply, pending)
  local c = { sent = {}, polls = 0, released = 0 }
  function c:send(method, path, body, opts)
    self.sent[#self.sent + 1] = { method = method, path = path, body = body, opts = opts }
    return #self.sent
  end
  function c:poll()
    self.polls = self.polls + 1
    if self.polls <= (pending or 1) then return { status = "pending" } end
    return reply
  end
  function c:release() self.released = self.released + 1 end
  return c
end

local function find(pg, id, label)
  for i, it in ipairs(pg.items) do
    if it.id == id and (label == nil or it.label:find(label, 1, true)) then return i, it end
  end
  return nil
end

local function pick(m, id, label)
  local i = find(m:page(), id, label)
  assert(i, "no item " .. id .. " " .. tostring(label) .. " on " .. tostring(m:page().step))
  m.cursor = i
  m:input("a")
end

local saved = Rentals.DEFINITIONS["g3u-gen1"]
local savedGen3 = Rentals.DEFINITIONS["g3u-gen3"]
Rentals.DEFINITIONS["g3u-gen1"] = {
  { type = "GRASS", species = 1, moves = { 33, 45 } },
  { type = "ELECTRIC", species = 25, moves = { 84, 45 } },
}

do
  local red = F.data("red")
  local sets = { bulbasaur = { generation = 1, species = "Bulbasaur",
    set = { moves = { "Body Slam", "Psychic", "Vine Whip", "Splash" } } } }
  local out = Rentals.build("g3u-gen1", red, { sets = sets })
  T.eq(#out.rentals, 2, "both rentals build with a partial recommendation map")
  local bulba, pika = out.rentals[1], out.rentals[2]
  T.eq(bulba.source, "recommended", "a species with a set uses it")
  T.eq(ids(bulba.record.moves), "34,22,33,45", "legal recommended moves lead, the rest is filled from the rental's own legal moves")
  T.eq(ids(bulba.moves), ids(bulba.record.moves), "the disclosed moves are the record's moves")
  T.eq(#out.dropped, 2, "two recommended moves are dropped")
  T.eq(out.dropped[1].move .. ":" .. out.dropped[1].code, "Psychic:move_not_legal", "an unlearnable move is dropped and reported")
  T.eq(out.dropped[2].move .. ":" .. out.dropped[2].code, "Splash:move_unknown", "a move the data lacks is dropped and reported")
  T.eq(out.dropped[1].species, 1, "a drop names the rental species")
  T.eq(#out.padded, 2, "the filled moves are reported")
  T.eq(pika.source, "default", "a species without a set keeps its own moves")
  T.eq(ids(pika.record.moves), "84,45", "the default rental moves are unchanged")
  T.eq(out.defaulted[1] and out.defaulted[1].code, "no_set", "the missing set is reported")
  T.eq(bulba.record.ivs.hp, Rentals.IV, "a set without hidden power keeps the flat rental IVs")

  local none = Rentals.build("g3u-gen1", red, { sets = { bulbasaur = { set = { moves = { "Psychic", "Splash" } } } } })
  T.eq(ids(none.rentals[1].record.moves), "33,45", "a set with no legal move leaves the rental's own moves")
  T.eq(none.defaulted[1] and none.defaulted[1].code, "no_legal_moves", "the unusable set is reported")
  T.eq(#none.dropped, 2, "every unusable move is reported")

  local plain = Rentals.build("g3u-gen1", red)
  T.eq(ids(plain.rentals[1].record.moves), "33,45", "no recommendation map builds the defined rentals")
  T.eq(#plain.dropped, 0, "nothing is dropped without a map")
end

do
  for _, want in ipairs(Rentals.HIDDEN_POWER_TYPES) do
    local ivs = Rentals.hiddenPowerIvs(want, { hp = 31, atk = 31, def = 31, spe = 31, spa = 31, spd = 31 })
    T.eq(ivs and Rentals.hiddenPowerType(ivs), want, "hidden power IVs reach " .. want)
  end
  local fire = { hp = 31, atk = 30, def = 31, spe = 30, spa = 30, spd = 31 }
  T.eq(Rentals.hiddenPowerType(fire), "FIRE", "the usual hidden power fire spread is fire")
  T.eq(ids({ Rentals.hiddenPowerIvs("FIRE", fire).atk }), "30", "matching set IVs are kept as given")
  T.eq(Rentals.hiddenPowerIvs("NORMAL", fire), nil, "hidden power can't be normal")

  local raw = F.raw("emerald")
  raw.moveNames[237] = "HIDDEN POWER"
  raw.battleMoves.moves[237] = { type = 0, power = 1, pp = 15, accuracy = 100, priority = 0, effect = 0 }
  raw.tmhm.machines[9] = 237
  for internal, row in pairs(raw.tmhm.learnsets) do
    if raw.national.toNational[internal] == 1 then row.lo = row.lo + 2 ^ 9 end
  end
  local emerald = assert(Datasets.build("emerald", raw))
  Rentals.DEFINITIONS["g3u-gen3"] = { { type = "GRASS", species = 1, moves = { 33 } } }
  local all31 = { hp = 31, atk = 31, def = 31, spe = 31, spa = 31, spd = 31 }
  local out = Rentals.build("g3u-gen3", emerald, { sets = { bulbasaur = { set = {
    moves = { "Hidden Power Fire", "Giga Drain" }, ivs = all31 } } } })
  local r = out.rentals[1]
  T.eq(ids(r.record.moves), "237,202,33", "hidden power resolves to its move")
  T.eq(Rentals.hiddenPowerType(r.record.ivs), "FIRE", "the rental's IVs give the set's hidden power type")
  T.check(r.record.ivs.hp ~= Rentals.IV, "a hidden power rental does not keep the flat IVs")
  local bad = Rentals.build("g3u-gen3", emerald, { sets = { bulbasaur = { set = { moves = { "Hidden Power Normal" } } } } })
  T.eq(bad.dropped[1] and bad.dropped[1].code, "hidden_power_type", "an impossible hidden power type is dropped")
  Rentals.DEFINITIONS["g3u-gen3"] = savedGen3
end

local emerald = F.data("emerald")
local function mon3(national, level, moves)
  return { species = emerald.nationalToLocal[national], level = level, personality = 7, otId = 1, otSecretId = 0,
    otName = "MAY", ivs = { hp = 1, atk = 1, def = 1, spe = 1, spa = 1, spd = 1 }, evs = {}, moves = moves }
end
local RULES = { ruleset = "g3u", gen = 3, moveGen = 1, dexMax = 151, moveMax = 165, gens = { 3, 1 } }
local function source()
  return { generation = 3, party = { mon3(252, 20, { 33, 345 }), mon3(25, 20, { 84, 45 }) }, boxes = {} }
end

do
  Recommend.reset()
  local client = fakeClient({ status = "ok", code = 200, data = { sets = {
    bulbasaur = { generation = 1, species = "Bulbasaur", set = { moves = { "Vine Whip", "Body Slam", "Growl", "Splash" } } },
  } } }, 2)
  local m = Model.new({ version = "emerald", gen = 3, data = emerald, owned = source(), rules = RULES,
    recommend = { client = client } })
  T.eq(client.sent[1] and client.sent[1].path, "/recommend/gen1", "the prep asks for the ruleset generation's sets")
  T.eq(client.sent[1] and client.sent[1].opts.params.species, "bulbasaur,pikachu", "every rental species goes in one request")
  T.check(m.rentalSet.pending == true, "rentals wait for the recommendations")
  pick(m, "rentals")
  local pg = m:page()
  T.eq(#pg.items, 1, "no rental is offered while the request is pending")
  T.check(table.concat(pg.lines, " "):find("Getting the rental", 1, true) ~= nil, "the wait is shown")
  m:input("b")
  m:poll()
  T.check(m.rentalSet.pending == true, "still pending after one poll")
  m:poll()
  T.check(not m.rentalSet.pending, "the poll loop settles the rentals")
  T.eq(client.released, 1, "the request handle is released")
  local rental = m.rentalSet.rentals[1]
  T.eq(rental and rental.source, "recommended", "the settled rental uses the recommended set")
  T.eq(rental and ids(rental.record.moves), "22,34,45,33", "the rental's moves come from the set, legal ones only")
  pick(m, "rentals")
  T.eq(#m:page().items, 3, "both rentals are listed once settled")
  T.check(table.concat(m:page().info or {}, " "):find("VINE WHIP", 1, true) ~= nil, "the rental list shows the recommended moves")
  m:input("b")

  pick(m, "continue")
  pick(m, "continue")
  T.eq(m.step, "substitute", "treecko needs a substitute")
  pick(m, "swap_rental", "RENTAL BULBASAUR")
  local r = m:report(false)
  T.check(r.ok, "the team with the rental is valid")
  local team = r.result and r.result.team or {}
  T.check(team[1] and team[1].rental == true, "the rental fills the slot")
  T.eq(team[1] and ids(team[1].moves), "22,34,45,33", "the record that is disclosed carries the recommended moves")
  local Wire = require("src.online.union.BattleSession").wireRecord(team[1] or {})
  T.eq(ids(Wire.moves), "22,34,45,33", "the wire record sent to the peer carries the same moves")

  m:discard()
  m:poll()
  T.eq(#m.rentalSet.rentals, 0, "a discarded prep never rebuilds rentals")
end

do
  Recommend.reset()
  local client = fakeClient({ status = "error", code = 503 }, 0)
  local m = Model.new({ version = "emerald", gen = 3, data = emerald, owned = source(), rules = RULES,
    recommend = { client = client } })
  T.check(not m.rentalSet.pending, "a failed request settles at once")
  T.eq(m.rentalSet.offline, "server", "the failure reason is kept")
  T.eq(ids(m.rentalSet.rentals[1].record.moves), "33,45", "an unreachable server keeps the defined rental moves")
  T.eq(#m.rentalSet.rentals, 2, "every rental stays available offline")
end

do
  Recommend.reset()
  local client = fakeClient({ status = "ok", code = 200, data = { sets = {} } }, 5)
  local m = Model.new({ version = "emerald", gen = 3, data = emerald, owned = source(), rules = RULES,
    recommend = { client = client } })
  local key = m:page().step .. #m.rentalSet.rentals
  m:poll()
  m:discard()
  T.eq(m.rentalJob, nil, "discarding cancels the request")
  T.eq(key, "rules0", "nothing is offered before the request ends")
end

Rentals.DEFINITIONS["g3u-gen1"] = saved
T.finish("union_rental_recommend")
