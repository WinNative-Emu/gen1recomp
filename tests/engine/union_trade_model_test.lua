package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")
local T = require("tests.harness")
local F = require("tests.engine._xgen_fixture")
local Model = require("src.online.union.TradePrepModel")
local Json = require("src.link.Json")
local Wire = require("src.link.Wire")

local fixtures = { red = F.data("red"), gold = F.data("gold"), silver = F.data("silver"), emerald = F.data("emerald") }
Model.datasetSource = function(version) return fixtures[version] end

local function pika1()
  return { species = "PIKACHU", level = 25, exp = 15625, hp = 50, nickname = "ZAPPY", ot = "RED", otId = 4242,
    dvs = { attack = 10, defense = 10, speed = 10, special = 10 },
    statExp = { hp = 100, attack = 400, defense = 0, speed = 900, special = 2500 },
    moves = { { id = "THUNDERSHOCK", pp = 30, ppUps = 0 }, { id = "GROWL", pp = 40 } }, catchRate = 190 }
end

local function umbreon2(item)
  return { species = "UMBREON", level = 40, experience = 64000, nickname = "MOON", ot = "GOLD", otId = 9,
    dvs = { attack = 15, defense = 10, speed = 3, special = 7 }, statExp = { hp = 0, attack = 0, defense = 0, speed = 0, special = 0 },
    moves = { { id = "TACKLE", pp = 35 }, { id = "CRUNCH", pp = 15 } }, item = item, happiness = 200, pokerus = 0 }
end

local function g3pika()
  return { species = 25, level = 30, exp = 27000, personality = 0xABCD1234, otId = 77, otSecretId = 88, otName = "May",
    nickname = "Volt", ivs = { hp = 31, atk = 20, def = 21, spe = 30, spa = 19, spd = 5 },
    evs = { hp = 4, atk = 0, def = 0, spe = 252, spa = 252, spd = 0 }, moves = { { id = 84, pp = 30 }, { id = 98, pp = 30 }, { id = 345, pp = 20 } },
    item = 0, friendship = 120, pokerus = 0, metLocation = 16, metLevel = 5, metGame = 3, pokeball = 4, otGender = 1,
    language = 2, markings = 0, ribbons = 0, contest = { cool = 0, beauty = 0, cute = 0, smart = 0, tough = 0, sheen = 0 },
    abilityNum = 0, isEgg = false }
end

local function owned(list)
  local out = {}
  for i, rec in ipairs(list) do out[i] = { ref = { where = "party", index = i }, rec = rec } end
  return out
end

local function wireTrip(payload, digest16)
  local text = Json.encode({ type = "xg_offer", rev = 3, offerRev = 1, payload = payload, digest16 = digest16 })
  local clean = Wire.sanitize(Json.decode(text))
  return clean and clean.payload
end

do
  local a = Model.new({ version = "red", peerVersion = "emerald", owned = owned({ pika1() }) })
  local b = Model.new({ version = "emerald", peerVersion = "red", owned = owned({ g3pika() }) })
  local ra = a:choose(1)
  T.check(ra and ra.ok, "Gen 1 Pikachu is offerable to Emerald")
  T.check(ra.final and ra.final.friendship == 70, "the Gen 3 receiver's traded friendship rule is in the preview")
  local rb = b:choose(1)
  T.check(rb and not rb.ok and rb.blocks[1].code == "move_missing", "Magical Leaf blocks the Emerald offer to Red")
  T.check(b:moveOptions(3) ~= nil and #b:moveOptions(3) > 0, "legal replacements are offered for the blocked slot")
  T.check(b:payload() == nil, "a blocked offer has no payload")
  local bad = b:stage(3, 57)
  T.eq(bad.blocks[1] and bad.blocks[1].code, "replacement_not_legal", "staging a move the species cannot learn is refused (no free move editor)")
  local fixed = b:stage(3, 0)
  T.check(fixed.ok, "dropping the move makes the offer valid")
  local pa, da = a:payload()
  local pb, db = b:payload()
  T.check(pa ~= nil and pb ~= nil, "both payloads build")
  T.check(type(da) == "string" and #da == 16 and type(db) == "string", "offer digests are 16 hex")
  local okB, whyB = b:receive(wireTrip(pa, da))
  T.check(okB, "Emerald independently re-converts the Red offer and accepts it (" .. tostring(whyB) .. ")")
  local okA, whyA = a:receive(wireTrip(pb, db))
  T.check(okA, "Red independently re-converts the Emerald offer with the staged move (" .. tostring(whyA) .. ")")
  local digA = a:agreed(0, 1, 2)
  local digB = b:agreed(1, 2, 1)
  T.check(digA ~= nil and digA == digB, "both seats compute the same agreed digest")
  T.check(a:agreed(0, 1, 3) ~= digA, "a new peer offer revision changes the agreed digest")
  T.check(a:agreed(0, 2, 2) ~= digA, "a new own offer revision changes the agreed digest")
  local s = a:summary()
  T.check(s.mine and s.theirs and s.mine.ok and s.theirs.ok, "the summary shows both final exchanges")
  local losses = 0
  for _, c in ipairs(s.theirs.changes) do if c.kind == "loss" then losses = losses + 1 end end
  T.check(losses > 0, "Gen 3 -> Gen 1 losses are listed for the receiver")

  local tampered = Model.fromWire(pa)
  tampered.preview.nickname = "ZAPZAP"
  local okT, whyT = b:receive(Model.toWire(tampered))
  T.check(not okT and whyT == "preview_mismatch", "a claimed preview that differs from the re-conversion is refused")
  local lie = Model.fromWire(pa)
  lie.preview.level = 99
  T.eq(select(2, b:receive(Model.toWire(lie))), "preview_mismatch", "a claimed preview with a bumped level is refused")
  local wrong = Model.fromWire(pa)
  wrong.dst = "ruby"
  T.eq(select(2, b:receive(Model.toWire(wrong))), "wrong_destination", "an offer aimed at another game is refused")
  local imposter = Model.fromWire(pa)
  imposter.src = "gold"
  T.eq(select(2, b:receive(Model.toWire(imposter))), "wrong_source", "an offer claiming another source game is refused")
  local illegal = Model.fromWire(pb)
  illegal.adjust = { { slot = 3, move = 57 } }
  T.eq(select(2, a:receive(Model.toWire(illegal))), "replacement_not_legal", "a peer's illegal staged move is refused on receipt")
  local okV, whyV = b:receive(wireTrip(pa, da), function() return false, "not_valid_here" end)
  T.check(not okV and whyV == "not_valid_here", "the receiver's own validity check can refuse")
end

do
  local rental = pika1()
  rental.rental = true
  local m = Model.new({ version = "red", peerVersion = "gold", owned = owned({ rental }) })
  T.eq(m:choose(1).blocks[1].code, "rental", "rentals are untradeable")
  local proj = pika1()
  proj.sourceGen = 1
  local m2 = Model.new({ version = "red", peerVersion = "gold", owned = owned({ proj }) })
  T.eq(m2:choose(1).blocks[1].code, "projection", "battle projections are untradeable")
  local egg = umbreon2(nil)
  egg.isEgg = true
  local m3 = Model.new({ version = "gold", peerVersion = "emerald", owned = owned({ egg }) })
  T.eq(m3:choose(1).blocks[1].code, "egg", "eggs are refused")
  local m4 = Model.new({ version = "gold", peerVersion = "emerald", owned = owned({ umbreon2("FLOWER_MAIL") }) })
  T.eq(m4:choose(1).blocks[1].code, "mail", "mail is refused")
  local m5 = Model.new({ version = "gold", peerVersion = "red", owned = owned({ umbreon2(nil) }) })
  T.eq(m5:choose(1).blocks[1].code, "species_missing", "a species the recipient's game lacks must be swapped for another")
  local locked = owned({ pika1() })
  locked[1].locked = "pending"
  local m6 = Model.new({ version = "red", peerVersion = "gold", owned = locked })
  T.eq(m6:choose(1).blocks[1].code, "pending", "a mon held by an unsettled trade cannot be offered")
  local m7 = Model.new({ version = "red", peerVersion = "gold", owned = owned({ pika1() }) })
  local before = Model.plain(pika1())
  m7:choose(1)
  m7:payload()
  T.check(F.deepEqual(m7.owned[1].rec, before), "preparation never mutates the owned record")
end

do
  local nested = { a = { [0] = 1, [2] = 2, ["#x"] = 3 }, b = { 1, 2, 3 }, c = {} }
  local back = Model.fromWire(Json.decode(Json.encode(Model.toWire(nested))))
  T.eq(back.a[0], 1, "numeric keys survive the wire")
  T.eq(back.a["#x"], 3, "hash-prefixed string keys survive the wire")
  T.eq(back.b[3], 3, "arrays survive the wire")
  T.eq(select(2, Model.toWire({ s = ("x"):rep(300) })), "too_big", "strings past the relay cap are refused, never truncated")
end

do
  local d = Model.datasetSource
  Model.datasetSource = function(v) if v == "gold" then return nil end return d(v) end
  local m = Model.new({ version = "red", peerVersion = "gold", owned = owned({ pika1() }) })
  local r = m:choose(1)
  T.check(r.ok, "a same-generation dataset stands in when the exact peer game is not imported")
  T.eq(r.datasets.target, "silver", "the stand-in is reported")
  Model.datasetSource = function(v) if v == "gold" or v == "silver" then return nil end return d(v) end
  T.eq(m:choose(1).blocks[1].code, "missing_import", "no dataset for the peer's generation blocks the offer")
  Model.datasetSource = d
end

T.finish("union_trade_model")
