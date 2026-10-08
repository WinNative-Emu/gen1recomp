package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")
local T = require("tests.harness")
local F = require("tests.engine._g3u_fixture")
local Table = require("src.battle.g3u.Table")
local Wire = require("src.battle.g3u.Wire")
local Rng = require("src.battle.g3u.Rng")
local Hash = require("src.battle.g3u.Hash")
local Json = require("src.link.Json")

local t1 = assert(Table.build(F.gen1()))

local function rt(m) return Json.decode(Json.encode(m)) end
local function valid(m, ctx)
  local raw = Json.encode(m)
  ctx = ctx or {}
  ctx.bytes = #raw
  return Wire.validate(Json.decode(raw), ctx)
end

T.check(valid(Wire.table(t1), { gen = 1 }), "a built table passes g3u_table")
T.check(not valid(Wire.table(t1), { gen = 2 }), "g3u_table refuses a table of the wrong gen")
local big = Wire.table(t1)
T.check(not Wire.validate(rt(big), { gen = 1, bytes = Wire.MAX_BYTES.g3u_table + 1 }), "g3u_table over the byte cap is refused")

local party = { F.record(t1, 25, { 84, 85 }, 50, { nickname = "SPARKY" }), F.record(t1, 143, { 33 }) }
T.check(valid(Wire.party(party), { table = t1 }), "a sane party passes g3u_party")
T.check(Json.encode(Wire.party(party)):len() < Wire.MAX_BYTES.g3u_party, "a party fits its byte cap")
local six = {}
for i = 1, 6 do six[i] = F.record(t1, 150, { 94, 105, 86, 85 }, 100, { nickname = "MEWTWO" .. i }) end
T.check(#Json.encode(Wire.party(six)) <= Wire.MAX_BYTES.g3u_party, "a full six-mon party fits its byte cap")

local function bad(label, mutate)
  local p = rt(Wire.party(party))
  mutate(p.records[1], p)
  T.check(not valid(p, { table = t1 }), "g3u_party refuses " .. label)
end
bad("species 0", function(r) r.species = 0 end)
bad("a species past the dex", function(r) r.species = 152 end)
bad("level 101", function(r) r.level = 101 end)
bad("hp above max", function(r) r.hp = r.maxHp + 1 end)
bad("a stat past the level cap", function(r) r.atk = 9999 end)
bad("fractional speed", function(r) r.speed = 10.5 end)
bad("no moves", function(r) r.moves = {} end)
bad("five moves", function(r) for i = 1, 5 do r.moves[i] = { id = i, pp = 1, ppUps = 0 } end end)
bad("a move past the table", function(r) r.moves[1].id = 166 end)
bad("a duplicate move", function(r) r.moves[2] = { id = r.moves[1].id, pp = 1, ppUps = 0 } end)
bad("too much pp", function(r) r.moves[1].pp = 64 end)
bad("four pp ups", function(r) r.moves[1].ppUps = 4 end)
bad("a long nickname", function(r) r.nickname = "ABCDEFGHIJK" end)
bad("an unknown key", function(r) r.item = 3 end)
bad("an iv of 32", function(r) r.ivs.hp = 32 end)
bad("gender 3", function(r) r.gender = 3 end)
bad("seven mons", function(_, p) for i = 3, 7 do p.records[i] = p.records[1] end end)
T.check(not Wire.validate(rt(Wire.party(party)), {}), "g3u_party needs the match table to check against")

local cases = {
  { Wire.action(3, { kind = "move", slot = 2 }), true, "a move action" },
  { Wire.action(3, { kind = "move", slot = 0 }), true, "a Struggle action" },
  { Wire.action(3, { kind = "switch", index = 4 }), true, "a switch action" },
  { Wire.action(3, { kind = "forfeit" }), true, "a forfeit" },
  { { type = "g3u_action", turn = 3, kind = "move", slot = 5 }, false, "slot 5" },
  { { type = "g3u_action", turn = 0, kind = "move", slot = 1 }, false, "turn 0" },
  { { type = "g3u_action", turn = 3, kind = "switch", index = 7 }, false, "switch index 7" },
  { { type = "g3u_action", turn = 3, kind = "run" }, false, "a run action" },
  { { type = "g3u_action", turn = 3, kind = "move", slot = 1, index = 2 }, false, "a move with an index" },
  { Wire.replace(4, 2), true, "a replacement" },
  { { type = "g3u_replace", turn = 4, index = 0 }, false, "replacement index 0" },
  { Wire.hash(4, "0a1b2c3d"), true, "a hash" },
  { { type = "g3u_hash", turn = 4, hash = "xyz" }, false, "a malformed hash" },
  { Wire.bye("desync"), true, "a desync bye" },
  { { type = "g3u_bye", why = "because" }, false, "an unknown bye reason" },
  { { type = "g3u_other" }, false, "an unknown inner type" },
}
for _, c in ipairs(cases) do
  local got = valid(c[1]) and true or false
  T.eq(got, c[2], "validator on " .. c[3])
  if c[2] then
    T.check(#Json.encode(c[1]) <= Wire.MAX_BYTES[c[1].type], c[3] .. " fits its byte cap")
  end
end
T.same(Wire.toAction(Wire.action(2, { kind = "switch", index = 3 })), { kind = "switch", index = 3 },
  "toAction turns a wire action back into a Match action")
T.same(Wire.TYPES, { "g3u_table", "g3u_party", "g3u_action", "g3u_replace", "g3u_hash", "g3u_bye" },
  "the inner message list the relay must allow")

local LB = require("src.core.game3.link.battle")
T.eq(LB.makeRng, Rng.make, "link battles still use the same LCG")
local a, b = Rng.make(0xC0FFEE), LB.makeRng(0xC0FFEE)
local seq = {}
for i = 1, 8 do seq[i] = a(0, 99) end
local seqB = {}
for i = 1, 8 do seqB[i] = b(0, 99) end
T.same(seq, seqB, "the extracted LCG draws the same sequence")
T.same(seq, { 27, 84, 66, 52, 16, 87, 54, 47 }, "ISO_RANDOMIZE1 from 0xC0FFEE keeps the draws HEAD's LB.makeRng made")
local counter = { n = 0 }
local c = Rng.make(1, counter)
c(1, 6); c(); c(10)
T.eq(counter.n, 3, "the draw counter counts every draw")
T.eq(LB.fnv, Hash.fnv, "link battles hash with the shared fnv")
T.eq(Hash.fnv("abc"), LB.fnv("abc"), "fnv agrees")
T.same(LB.HASH_PARTS, Hash.PARTS, "link battles keep the same hash parts")

T.finish("g3u wire")
