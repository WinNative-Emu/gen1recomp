package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")
local T = require("tests.harness")
local Serializer = require("src.core.SaveSerializer")
local GameVersion = require("src.core.GameVersion")
local CacheFs = require("src.import.CacheFs")
local Catalog = require("src.box.Catalog")
local Recommend = require("src.recommend.Recommend")

local tables = {}
local function put(version, path, value)
  tables[GameVersion.cachePrefix(version) .. path] = Serializer.encode(value)
end
put("red", "data/generated/pokemon.lua", { SNORLAX = { dex = 143, name = "SNORLAX" } })
put("red", "data/generated/moves.lua", {
  BODY_SLAM = { name = "BODY SLAM", index = 34 },
  SELFDESTRUCT = { name = "SELFDESTRUCT", index = 120 },
  EARTHQUAKE = { name = "EARTHQUAKE", index = 89 },
})
put("emerald", "data/generated/gba/pokemon/names.lua", { [3] = "VENUSAUR" })
put("emerald", "data/generated/gba/pokemon/move_names.lua", {
  [0] = "-", [79] = "SLEEP POWDER", [202] = "GIGA DRAIN", [237] = "HIDDEN POWER",
  [185] = "FAINT ATTACK", [136] = "HI JUMP KICK",
})
CacheFs.readAt = function(path) return tables[path] end
Catalog.reset()

local function fakeClient(reply)
  local c = { sent = {}, polls = 0 }
  function c:send(method, path, body, opts)
    self.sent[#self.sent + 1] = { method = method, path = path, opts = opts }
    return #self.sent
  end
  function c:poll()
    self.polls = self.polls + 1
    if self.polls < 2 then return { status = "pending" } end
    return reply
  end
  function c:release() end
  return c
end

T.eq(Recommend.key("NIDORAN♂"), "nidoranm", "male symbol maps to the showdown id")
T.eq(Recommend.key("NIDORAN♀"), "nidoranf", "female symbol maps to the showdown id")
T.eq(Recommend.key("MR.MIME"), "mrmime", "punctuation is stripped")

local client = fakeClient({ status = "ok", code = 200, data = { sets = {
  snorlax = { generation = 1, species = "Snorlax",
    set = { moves = { "Self-Destruct", "Body Slam", "Earthquake", "Hyper Beam" } } },
} } })
local job = Recommend.request(1, { "SNORLAX", "MEW" }, { client = client })
T.eq(job.status, "pending", "uncached species start a request")
T.eq(client.sent[1].path, "/recommend/gen1", "request hits the generation path")
T.eq(client.sent[1].opts.params.species, "snorlax,mew", "species ids are batched")
T.check(client.sent[1].opts.noAuth == true, "request needs no sync account")
T.eq(Recommend.poll(job), "pending", "first poll is pending")
local status, result = Recommend.poll(job)
T.eq(status, "ok", "second poll finishes")
T.check(result.snorlax ~= nil and result.mew == nil, "known species returned, unknown omitted")

local keys, missing = Recommend.resolveMoves(Recommend.get(job, "SNORLAX"), "red")
T.eq(table.concat(keys, ","), "SELFDESTRUCT,BODY_SLAM,EARTHQUAKE", "gen 1 names resolve to native keys")
T.eq(table.concat(missing, ","), "Hyper Beam", "moves the cart lacks are reported")

local again = Recommend.request(1, "Snorlax", { client = fakeClient({ status = "error" }) })
T.eq(again.status, "ok", "cached species resolve without a request")
local none = Recommend.request(1, "Mew", { client = fakeClient({ status = "error" }) })
T.eq(none.status, "ok", "species the server lacks are cached as absent")
T.check(Recommend.get(none, "Mew") == nil, "absent species has no set")

local k3, m3, hp = Recommend.resolveMoves({ moves = {
  "Sleep Powder", "Giga Drain", "Hidden Power Fire", "Feint Attack" } }, "emerald")
T.eq(table.concat(k3, ","), "79,202,237,185", "gen 3 names and renamed moves resolve to move ids")
T.eq(#m3, 0, "nothing missing in gen 3")
T.eq(hp, "FIRE", "hidden power type is reported")

local down = Recommend.request(3, "Venusaur", { client = fakeClient({ status = "error", code = 503 }) })
Recommend.poll(down)
local s2, why = Recommend.poll(down)
T.eq(s2, "error", "server error surfaces")
T.eq(why, "server", "503 reads as a server failure")
T.eq(Recommend.request(4, "Venusaur").status, "error", "unknown generation refused")

T.finish()
