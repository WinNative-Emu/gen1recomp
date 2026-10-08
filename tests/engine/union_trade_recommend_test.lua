package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")
local T = require("tests.harness")
local F = require("tests.engine._xgen_fixture")
local U = require("tests.engine._union_trade_fixture")
local Model = require("src.online.union.TradePrepModel")
local Txn = require("src.online.union.TradeTxn")
local Open = require("src.ui.union.prep.OpenTrade")
local Recommend = require("src.recommend.Recommend")

love.timer.getTime = function() return U.CLOCK.t end
local fixtures = { red = F.data("red"), gold = F.data("gold"), emerald = F.data("emerald") }
Model.datasetSource = function(version) return fixtures[version] end

package.loaded["src.box.Catalog"] = {
  get = function(version) return { moves = F.raw(version).moves } end,
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
    if opts.serverError then return { status = "error", code = 503 } end
    return { status = "ok", data = { sets = sets } }
  end
  function c:release() end
  return c
end

local function text(pg)
  return table.concat(pg.lines or {}, " | ")
end

local function has(ctl, id)
  for _, it in ipairs(ctl:page().items) do
    if it.id == id then return true end
  end
  return false
end

local function pick(ctl, id)
  local pg = ctl:page()
  for i, it in ipairs(pg.items) do
    if it.id == id then
      ctl.cursor = i
      ctl:input("a")
      return true
    end
  end
  return false
end

local function run(w, a, b, n)
  for _ = 1, n or 3 do
    w:pump()
    a:poll(0)
    b:poll(0)
  end
end

local function bulba(moves)
  local mon = U.bulba2()
  mon.moves = moves
  return mon
end

local function goldGame(mon)
  local g = U.g2game()
  g.save.party = { mon }
  return g
end

local SETS = {
  bulbasaur = { generation = 1, species = "Bulbasaur",
    set = { moves = { "Razor Leaf", "Body Slam", "Toxic", "Sleep Powder" }, level = 100 } },
}

do
  Recommend.reset()
  Txn.reset()
  local w, ra, rb = U.pair("red", "gold")
  local ga = U.g1game()
  local gb = goldGame(bulba({ { id = "TACKLE", pp = 35, maxPp = 35 }, { id = "GIGA_DRAIN", pp = 5, maxPp = 5 } }))
  local client = fakeClient(SETS, { pendingPolls = 1 })
  local a = Open.controller(ga, ra, ra:prep(), { version = "red" })
  local b = Open.controller(gb, rb, rb:prep(), { version = "gold", recommendClient = client })
  run(w, a, b)
  pick(a, "mon"); pick(a, "offer")
  run(w, a, b)
  pick(b, "mon")
  local pg = b:page()
  T.eq(pg.step, "offer", "the Gold side previews its Bulbasaur for Red")
  T.check(text(pg):find("Some moves can't come along. Replace them with the recommended moveset?", 1, true) ~= nil,
    "a blocked move asks about the recommended moveset: " .. text(pg))
  T.check(has(b, "recommend"), "the offer page has a recommended-moveset choice")
  T.check(has(b, "moves"), "the per-slot fix is still offered")
  T.check(pick(b, "recommend"), "the player takes the recommended moveset")
  T.eq(#client.sent, 1, "one request goes to the server")
  T.eq(client.sent[1].path, "/recommend/gen1", "the request asks for the destination generation")
  T.eq(client.sent[1].species, "bulbasaur", "for the offered species")
  T.check(text(b:page()):find("Getting the recommended moveset", 1, true) ~= nil, "the page says it is fetching")
  T.check(not has(b, "recommend"), "the choice is one-shot while the fetch runs")
  run(w, a, b)
  pg = b:page()
  T.check(has(b, "offer"), "the recommended moves clear the block: " .. text(pg))
  local staged = b.model:stagedMoves()
  T.eq(#staged, 2, "both existing slots are filled")
  T.eq(staged[1] and staged[1].move, 34, "slot 1 takes Body Slam (Razor Leaf is not learnable in Red at this level)")
  T.eq(staged[2] and staged[2].move, 92, "slot 2 takes Toxic")
  pick(b, "offer")
  run(w, a, b, 5)
  T.eq(a.step, "confirm", "the Red side accepts the adjusted offer (" .. tostring(a.closedText) .. ")")
  T.eq(b.step, "confirm", "both seats agree")
  T.check(a.model.peer and a.model.peer.digest16 == b.model.mine.digest16,
    "the receiver re-derives the same offer digest from the sent adjustments")
  pick(a, "trade")
  run(w, a, b)
  pick(b, "trade")
  run(w, a, b, 6)
  T.eq(a.step, "done", "the trade finishes (" .. tostring(a.closedText) .. ")")
  local got = ga.save.party[1]
  T.eq(got.species, "BULBASAUR", "Red holds the Bulbasaur")
  local ids = {}
  for _, mv in ipairs(got.moves or {}) do ids[#ids + 1] = mv.id end
  T.eq(table.concat(ids, ","), "BODY_SLAM,TOXIC", "it arrives with the recommended moves")
end

do
  Recommend.reset()
  local a = Model.new({ version = "gold", peerVersion = "red",
    owned = { { ref = { where = "party", index = 1 },
      rec = bulba({ { id = "GIGA_DRAIN", pp = 5 }, { id = "SWEET_SCENT", pp = 20 } }) } } })
  local r = a:choose(1)
  T.check(not r.ok and a:movesBlocked(), "two Gen 2 moves block the offer")
  local target = a:recommendTarget()
  T.eq(target and target.species, "BULBASAUR", "the target is the destination species")
  T.eq(target and target.generation, 1, "in the destination generation")
  local report = a:applyRecommended({ set = { moves = { "Body Slam", "Surf" } } }, target)
  T.check(report and not report.ok, "a short legal set leaves the other slot blocked")
  T.eq(a.mine.adjust.moves[1], 34, "the legal recommended move fills slot 1")
  T.eq(a.mine.adjust.moves[2], nil, "the unlearnable Surf is dropped and slot 2 stays with the per-slot flow")
  T.check(a:moveOptions(2) ~= nil, "slot 2 still offers per-slot replacements")
  local none, code = a:applyRecommended({ set = { moves = { "Surf", "Hyper Beam" } } }, target)
  T.check(none == nil and code == "none_legal", "a set with no legal move changes nothing")
end

do
  Recommend.reset()
  Txn.reset()
  local w, ra, rb = U.pair("red", "gold")
  local ga = U.g1game()
  local gb = goldGame(bulba({ { id = "TACKLE", pp = 35, maxPp = 35 }, { id = "GIGA_DRAIN", pp = 5, maxPp = 5 } }))
  local a = Open.controller(ga, ra, ra:prep(), { version = "red" })
  local b = Open.controller(gb, rb, rb:prep(), { version = "gold", recommendClient = fakeClient({}, { offline = true }) })
  run(w, a, b)
  pick(b, "mon")
  pick(b, "recommend")
  local pg = b:page()
  T.check(text(pg):find("Couldn't reach the server", 1, true) ~= nil, "offline says why: " .. text(pg))
  T.check(not has(b, "recommend") and has(b, "moves"), "offline keeps the per-slot flow and does not ask again")
  T.check(not has(b, "offer"), "the offer stays blocked")

  local c = fakeClient({}, {})
  b.recommendClient = c
  pick(b, "back")
  pick(b, "mon")
  T.check(has(b, "recommend"), "choosing the mon again offers the recommended moveset again")
  pick(b, "recommend")
  T.check(text(b:page()):find("There's no recommended moveset for BULBASAUR", 1, true) ~= nil,
    "a species the server has no set for says so: " .. text(b:page()))
end

T.finish("union_trade_recommend")
