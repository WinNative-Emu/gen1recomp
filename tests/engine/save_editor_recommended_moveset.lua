package.path = package.path .. ";./?.lua;./?/init.lua;./tools/save-editor/?.lua;./tools/save-editor/panels/?.lua"
love = require("tests.love_stub")
local T = require("tests.harness")
local Ops = require("Ops")
local Recommend = require("src.recommend.Recommend")
local Catalog = require("src.box.Catalog")

local catalogs = {}
Catalog.get = function(version)
  return catalogs[version] or { moves = {} }
end

local function fakeClient(sets, opts)
  opts = opts or {}
  local c = { sent = {}, polls = 0, released = 0 }
  function c.send(self, method, path, _, req)
    self.sent[#self.sent + 1] = { method = method, path = path, species = req.params.species }
    if opts.offline then return nil end
    return #self.sent
  end
  function c.poll(self)
    self.polls = self.polls + 1
    if self.polls < (opts.pendingPolls or 2) then return { status = "pending" } end
    if opts.code then return { status = "error", code = opts.code } end
    return { status = "ok", data = { sets = sets } }
  end
  function c.release(self)
    self.released = self.released + 1
  end
  return c
end

local function tick(S, limit)
  for _ = 1, limit or 10 do
    if not S.recommendJob then return end
    Ops.pollRecommendedMoves(S)
  end
end

local g1moves = {
  TACKLE = { id = "TACKLE", name = "TACKLE", pp = 35 },
  BODY_SLAM = { id = "BODY_SLAM", name = "BODY SLAM", pp = 15 },
  EARTHQUAKE = { id = "EARTHQUAKE", name = "EARTHQUAKE", pp = 10 },
  HYPER_BEAM = { id = "HYPER_BEAM", name = "HYPER BEAM", pp = 5 },
  REST = { id = "REST", name = "REST", pp = 10 },
  AMNESIA = { id = "AMNESIA", name = "AMNESIA", pp = 20 },
}
catalogs.red = { moves = g1moves }

local snorlax = { id = "SNORLAX", name = "SNORLAX" }
local S1 = {
  version = "red",
  save = { generation = 1, version = "red", party = {}, player = { name = "RED", id = 1 } },
  data = { pokemon = { SNORLAX = snorlax, MR_MIME = { id = "MR_MIME", name = "MR.MIME" } }, moves = g1moves },
}
local lax = {
  species = "SNORLAX", level = 50,
  moves = { { id = "TACKLE", pp = 3, ppUps = 3, maxPp = 56 }, { id = "REST", pp = 1, maxPp = 10 },
    { id = "AMNESIA", pp = 0, maxPp = 20 }, { id = "TACKLE", pp = 2, maxPp = 35 } },
  dvs = { attack = 15, defense = 15, speed = 15, special = 15, hp = 15 },
}
S1.save.party[1] = lax
S1.editingMon = lax

Recommend.reset()
S1.recommendClient = fakeClient({
  snorlax = { generation = 1, species = "Snorlax",
    set = { moves = { "Body Slam", "Earthquake", "Hyper Beam", "Splash Dance" } } },
})
T.eq(Ops.recommendState(S1, lax), "ready", "Gen 1 Snorlax starts ready")
T.eq(Ops.recommendMoves(S1, lax), "pending", "Gen 1 request goes async")
T.eq(S1.status, "Fetching recommended moveset...", "pending status line")
T.eq(Ops.recommendState(S1, lax), "pending", "button shows pending while fetching")
T.eq(S1.recommendClient.sent[1].path, "/recommend/gen1", "Gen 1 endpoint")
T.eq(S1.recommendClient.sent[1].species, "snorlax", "species key sent")
T.eq(S1.dirty, nil, "nothing changes before the reply")
local undoBefore = #(S1.undoStack or {})
tick(S1)
T.eq(S1.recommendJob, nil, "job finished")
T.eq(lax.moves[1].id, "BODY_SLAM", "Gen 1 slot 1 Body Slam")
T.eq(lax.moves[2].id, "EARTHQUAKE", "Gen 1 slot 2 Earthquake")
T.eq(lax.moves[3].id, "HYPER_BEAM", "Gen 1 slot 3 Hyper Beam")
T.eq(lax.moves[4], nil, "Gen 1 slot 4 cleared")
T.eq(lax.moves[1].pp, 15, "Body Slam PP is its max")
T.eq(lax.moves[1].ppUps, nil, "old PP Ups do not carry over")
T.eq(lax.moves[3].pp, 5, "Hyper Beam PP is its max")
T.eq(lax.dvs.attack, 15, "Gen 1 DVs untouched without Hidden Power")
T.eq(S1.dirty, true, "apply dirties the save")
T.eq(#S1.undoStack, undoBefore + 1, "apply records one undo entry")
T.check(tostring(S1.status):find("Applied recommended moveset to SNORLAX (3 moves)", 1, true) ~= nil,
  "status names the species and count: " .. tostring(S1.status))
T.check(tostring(S1.status):find("Splash Dance", 1, true) ~= nil, "status lists the skipped move")
require("History").undo(S1)
T.eq(S1.save.party[1].moves[1].id, "TACKLE", "undo restores the old moves")

local lax2 = S1.save.party[1]
S1.editingMon = lax2
local sends = #S1.recommendClient.sent
T.eq(Ops.recommendMoves(S1, lax2), "ok", "cached set applies synchronously")
T.eq(#S1.recommendClient.sent, sends, "cached set sends no request")
T.eq(lax2.moves[1].id, "BODY_SLAM", "cached set applied")

local mime = { species = "MR_MIME", level = 30, moves = { { id = "TACKLE", pp = 35 } },
  dvs = { attack = 15, defense = 15, speed = 15, special = 15, hp = 15 } }
S1.save.party[2], S1.editingMon = mime, mime
S1.recommendClient = fakeClient({})
T.eq(Ops.recommendMoves(S1, mime), "pending", "Mr. Mime request goes async")
T.eq(S1.recommendClient.sent[1].species, "mrmime", "ROM name MR.MIME keys as mrmime")
tick(S1)
T.eq(mime.moves[1].id, "TACKLE", "no set leaves moves alone")
T.eq(Ops.recommendState(S1, mime), "none", "button disables once the species has no set")
T.eq(Ops.recommendMoves(S1, mime), false, "disabled button is a no-op")

Recommend.reset()
S1.recommendClient = fakeClient({}, { offline = true })
Ops.recommendMoves(S1, lax2)
T.eq(S1.status, "Recommended moveset unavailable (offline)", "offline status line")
S1.recommendClient = fakeClient({}, { code = 500 })
Ops.recommendMoves(S1, lax2)
tick(S1)
T.eq(S1.status, "Recommended moveset unavailable (server)", "server error status line")
T.eq(Ops.recommendState(S1, lax2), "ready", "a failed fetch can be retried")

local g2moves = {
  TACKLE = { id = "TACKLE", name = "TACKLE", pp = 35 },
  HIDDEN_POWER = { id = "HIDDEN_POWER", name = "HIDDEN POWER", pp = 15 },
  THUNDERBOLT = { id = "THUNDERBOLT", name = "THUNDERBOLT", pp = 15 },
}
catalogs.gold = { moves = g2moves }
local jolteon = { id = "JOLTEON", name = "JOLTEON", dex = 135, index = 135, types = { "ELECTRIC" },
  baseStats = { hp = 65, attack = 65, defense = 60, speed = 130, specialAttack = 110, specialDefense = 95 },
  growthRate = "MEDIUM_FAST", genderRatio = 31 }
local S2 = {
  version = "gold",
  save = { generation = 2, version = "gold", party = {}, player = { name = "GOLD", id = 1 } },
  data = { pokemon = { JOLTEON = jolteon }, moves = g2moves },
}
local jolt = { species = "JOLTEON", level = 50, moves = { { id = "TACKLE", pp = 35 } },
  dvs = { attack = 15, defense = 15, speed = 15, special = 15, hp = 15 },
  statExp = { hp = 0, attack = 0, defense = 0, speed = 0, special = 0 } }
S2.save.party[1], S2.editingMon = jolt, jolt
S2.recommendClient = fakeClient({
  jolteon = { generation = 2, species = "Jolteon",
    set = { moves = { "Thunderbolt", "Hidden Power Ice" }, ivs = { atk = 26, def = 24 } } },
}, { pendingPolls = 1 })
T.eq(Ops.recommendMoves(S2, jolt), "ok", "Gen 2 immediate reply applies in the same call")
T.eq(jolt.moves[1].id, "THUNDERBOLT", "Gen 2 slot 1 Thunderbolt")
T.eq(jolt.moves[2].id, "HIDDEN_POWER", "Gen 2 slot 2 Hidden Power")
T.eq(jolt.dvs.attack, 13, "Gen 2 Atk DV is iv/2")
T.eq(jolt.dvs.defense, 12, "Gen 2 Def DV is iv/2")
T.eq(jolt.dvs.speed, 15, "Gen 2 missing Spe IV counts as 31")
T.eq(jolt.dvs.special, 15, "Gen 2 Special DV follows SpA")
T.eq(jolt.dvs.hp, 11,"Gen 2 HP DV derived from the others")

local g3names = { [33] = "TACKLE", [34] = "BODY SLAM", [89] = "EARTHQUAKE", [237] = "HIDDEN POWER",
  [156] = "REST" }
catalogs.firered = { moves = g3names }
local g3moves = {}
for id, name in pairs(g3names) do
  g3moves[id] = { id = name, name = name, moveId = id,
    pp = ({ [33] = 35, [34] = 15, [89] = 10, [237] = 15, [156] = 10 })[id] }
end
local S3 = {
  version = "firered",
  save = { generation = 3, version = "firered", party = {}, player = { name = "RED", id = 1 } },
  data = { pokemon = { [143] = { name = "SNORLAX", speciesId = 143 } }, moves = g3moves },
}
local lax3 = { species = 143, speciesId = 143, level = 50, moves = { 33, 156, 0, 0 },
  pp = { 1, 2 }, maxPp = { 35, 10 }, ivs = { hp = 31, atk = 31, def = 31, spa = 31, spd = 31, spe = 31 },
  evs = { hp = 0, atk = 0, def = 0, spa = 0, spd = 0, spe = 0 }, item = 5, nature = 3 }
S3.save.party[1], S3.editingMon = lax3, lax3
S3.recommendClient = fakeClient({
  snorlax = { generation = 3, species = "Snorlax",
    set = { moves = { "Body Slam", "Earthquake", "Hidden Power Ghost" },
      ivs = { hp = 31, atk = 31, def = 30, spa = 31, spd = 30, spe = 31 },
      evs = { hp = 252 }, item = "Leftovers", nature = "Adamant" } },
})
T.eq(Ops.recommendMoves(S3, lax3), "pending", "Gen 3 request goes async")
T.eq(S3.recommendClient.sent[1].path, "/recommend/gen3", "Gen 3 endpoint")
tick(S3)
T.eq(lax3.moves[1], 34, "Gen 3 slot 1 Body Slam native id")
T.eq(lax3.moves[2], 89, "Gen 3 slot 2 Earthquake native id")
T.eq(lax3.moves[3], 237, "Gen 3 slot 3 Hidden Power native id")
T.eq(lax3.moves[4], nil, "Gen 3 slot 4 cleared")
T.eq(lax3.pp[1], 15, "Gen 3 Body Slam PP max")
T.eq(lax3.pp[3], 15, "Gen 3 Hidden Power PP max")
T.eq(lax3.pp[4], nil, "Gen 3 slot 4 PP cleared")
T.eq(lax3.ivs.def, 30, "Hidden Power Def IV applied")
T.eq(lax3.ivs.spd, 30, "Hidden Power SpD IV applied")
T.eq(lax3.ivs.atk, 31, "other IVs kept at the set's values")
T.eq(lax3.evs.hp, 0, "EVs untouched")
T.eq(lax3.item, 5, "item untouched")
T.eq(lax3.nature, 3, "nature untouched")

local egg = { species = 143, speciesId = 143, level = 5, isEgg = true, moves = { 33, 0, 0, 0 }, pp = { 35 } }
S3.save.party[2], S3.editingMon = egg, egg
T.eq(Ops.recommendState(S3, egg), "egg", "Gen 3 egg is not eligible")
T.eq(Ops.recommendMoves(S3, egg), false, "Gen 3 egg is a no-op")
T.eq(egg.moves[1], 33, "egg moves unchanged")

S3.editingMon = lax3
Recommend.reset()
S3.recommendClient = fakeClient({
  snorlax = { generation = 3, species = "Snorlax", set = { moves = { "Tackle" } } },
})
Ops.recommendMoves(S3, lax3)
S3.editingMon = egg
tick(S3)
T.eq(lax3.moves[1], 34, "a reply after the selection changed is dropped")

T.finish("save_editor_recommended_moveset")
