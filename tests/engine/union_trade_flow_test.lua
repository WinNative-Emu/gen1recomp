package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")
local T = require("tests.harness")
local F = require("tests.engine._xgen_fixture")
local U = require("tests.engine._union_trade_fixture")
local Model = require("src.online.union.TradePrepModel")
local Txn = require("src.online.union.TradeTxn")
local Open = require("src.ui.union.prep.OpenTrade")

love.timer.getTime = function() return U.CLOCK.t end
local fixtures = { red = F.data("red"), gold = F.data("gold"), emerald = F.data("emerald") }
Model.datasetSource = function(version) return fixtures[version] end

local function text(pg)
  return table.concat(pg.lines or {}, " | ")
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

Txn.reset()
local w, ra, rb = U.pair("red", "gold")
local ga, gb = U.g1game(), U.g2game()
local a = Open.controller(ga, ra, ra:prep(), { version = "red" })
local b = Open.controller(gb, rb, rb:prep(), { version = "gold" })
run(w, a, b)
T.eq(a.opponent.version, "gold", "the controller reads the peer's game from the room")
local pg = a:page()
T.eq(pg.step, "pick", "the trade opens on the pick page")
T.check(text(pg):find("Pokémon Gold", 1, true) ~= nil, "the pick page names the other player's game")
T.check(#pg.items == 3, "both party mons and STOP are listed")
T.check(pick(a, "mon"), "seat 0 picks its first mon")
pg = a:page()
T.eq(pg.step, "offer", "the offer page previews the conversion")
T.check(text(pg):find("In Pokémon Gold it becomes", 1, true) ~= nil, "the destination form is stated")
T.check(text(pg):find("Permanent changes", 1, true) ~= nil, "permanent changes are listed before offering")
pick(a, "offer")
T.eq(a.step, "wait", "offered, waiting for the peer")
run(w, a, b)
pick(b, "mon")
pick(b, "offer")
run(w, a, b, 5)
T.eq(a.step, "confirm", "both offers bring seat 0 to the final check")
T.eq(b.step, "confirm", "and seat 1")
local conf = text(a:page())
T.check(conf:find("You send PIKACHU", 1, true) ~= nil, "the final page shows what is sent")
T.check(conf:find("You get BULBASAUR", 1, true) ~= nil, "and what is received")
T.check(conf:find("feature of this app", 1, true) ~= nil, "the page says this is an app feature, not cart behaviour")
T.check(conf:find("gone from your game for good", 1, true) ~= nil, "the page says the trade is final")
T.check(not text(b:page()):find("Some data", 1, true), "every permanent change is named")
local before = ga.save.party[1].species
pick(a, "trade")
run(w, a, b)
T.eq(a.step, "ready", "seat 0 waits for agreement")
T.eq(ga.save.party[1].species, before, "agreeing alone changes nothing")
pick(b, "trade")
run(w, a, b, 6)
T.eq(a.step, "done", "seat 0 finishes the trade (" .. tostring(a.closedText) .. ")")
T.eq(b.step, "done", "seat 1 finishes the trade (" .. tostring(b.closedText) .. ")")
T.eq(ga.save.party[1].species, "BULBASAUR", "Red holds the Bulbasaur")
T.eq(gb.save.party[1].species, "PIKACHU", "Gold holds the Pikachu")
T.check(text(a:page()):find("B sent BULBASAUR", 1, true) ~= nil, "the result page names the received mon")
pick(a, "again")
T.eq(a.step, "pick", "another round starts from the pick page")
T.eq(#a.model.owned, 2, "the owned list is rebuilt after the trade")
pick(a, "stop")
run(w, a, b)
T.check(a.done, "STOP ends seat 0's screen")
T.eq(b.step, "closed", "the peer is told trading stopped")

do
  Txn.reset()
  local w2, rc, rd = U.pair("red", "gold")
  local gc, gd = U.g1game(), U.g2game()
  local c = Open.controller(gc, rc, rc:prep(), { version = "red" })
  local d = Open.controller(gd, rd, rd:prep(), { version = "gold" })
  run(w2, c, d)
  pick(c, "mon"); pick(c, "offer")
  run(w2, c, d)
  pick(d, "mon"); pick(d, "offer")
  run(w2, c, d, 5)
  pick(c, "trade")
  run(w2, c, d)
  pick(d, "change")
  pick(d, "mon")
  d.model:stage(2, false)
  pick(d, "offer")
  run(w2, c, d, 6)
  T.eq(c.step, "confirm", "a changed peer offer sends the agreed player back to the final check")
  T.check(text(c:page()):find("An offer changed", 1, true) ~= nil, "and says why")
  T.eq(gc.save.party[1].species, "PIKACHU", "nothing was traded")
end

do
  Txn.reset()
  local w3, re, rf = U.pair("red", "gold")
  local ge, gf = U.g1game(), U.g2game()
  local e = Open.controller(ge, re, re:prep(), { version = "red" })
  local f = Open.controller(gf, rf, rf:prep(), { version = "gold" })
  run(w3, e, f)
  pick(e, "mon"); pick(e, "offer")
  run(w3, e, f)
  pick(f, "mon")
  f.model.peerVersion = "blue"
  pick(f, "offer")
  run(w3, e, f, 6)
  T.eq(e.step, "closed", "a refused offer closes the refusing side")
  local mine = text(e:page())
  T.check(mine:find("B's offer can't be accepted here", 1, true) and mine:find("meant for another game", 1, true),
    "the refusing side says why: " .. mine)
  T.eq(f.step, "closed", "the sender is told")
  local theirs = text(f:page())
  T.check(theirs:find("A can't accept your offer", 1, true) and theirs:find("meant for another game", 1, true),
    "the sender sees the reason: " .. theirs)
  T.eq(ge.save.party[1].species, "PIKACHU", "nothing was traded")
end

T.finish("union_trade_flow")
