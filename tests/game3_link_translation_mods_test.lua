#!/usr/bin/env luajit
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
if not _G.love then _G.love = require("tests.love_stub") end

local Cache = require("tests.game3_cache")
if not Cache.mount("meta.json") then
  print("[skip] game3_link_translation_mods_test: " .. tostring(Cache.reason))
  os.exit(0)
end

local files = {}
local memfs = {
  getInfo = function(name) return files[name] and { type = "file" } or nil end,
  read = function(name) return files[name] end,
  write = function(name, body) files[name] = body return true end,
  remove = function(name) files[name] = nil return true end,
  createDirectory = function() return true end,
  getDirectoryItems = function() return {} end,
}
local SaveData = require("src.core.SaveData")
SaveData.portableFs = function() return memfs end

require("src.core.GameVersion").set("firered")
local ArenaData = require("src.online.ArenaData")
local Handshake = require("src.link.Handshake")
local Fingerprint = require("src.link.Fingerprint")
local Protocol = require("src.link.Protocol")
local Pokemon = require("src.core.game3.pokemon")
Pokemon.install(nil)

local vanilla = ArenaData.liveProfile3({ data = { generation = 3 }, version = "firered" })
T.check(vanilla ~= nil, "a vanilla FireRed has a live profile")

local function ops(list)
  local out = {}
  for _, row in ipairs(list) do
    out[row.registry] = out[row.registry] or { ops = {} }
    local reg = out[row.registry].ops
    reg[row.id] = reg[row.id] or {}
    local l = reg[row.id]
    l[#l + 1] = { op = row.op, value = row.value, owner = row.owner }
  end
  return out
end

local function loader(id, content, extra)
  extra = extra or {}
  return {
    mods = { [id] = { manifest = { id = id, permissions = extra.permissions or {} } } },
    content = content,
    hooks = { chains = extra.chains or {} },
    events = { listeners = {} },
    migrations = {}, modInput = {}, stepsQueues = {},
    status = function()
      return { loaded = { { id = id, version = "1.0", affects_link = extra.affectsLink == true } } }
    end,
  }
end

local function game(mods)
  return { data = { generation = 3 }, version = "firered", mods = mods }
end

local translation = loader("espanol", ops({
  { registry = "rom_text", id = "gText_UR_EggTrade", op = "override", value = "HUEVO", owner = "espanol" },
  { registry = "strings", id = "Connect to the Wireless Club?", op = "override", value = "Conectar?", owner = "espanol" },
  { registry = "pokemon", id = "BULBASAUR", op = "patch", value = { name = "BULBIZARRE" }, owner = "espanol" },
  { registry = "moves", id = "TACKLE", op = "patch", value = { name = "PLACAJE" }, owner = "espanol" },
  { registry = "items", id = "POTION", op = "patch", value = { name = "POCION", description = "Cura 20 PS." }, owner = "espanol" },
}))

T.eq(ArenaData.modTouchesGameplay(translation, "espanol"), false, "names and text are cosmetic")
local live, why = ArenaData.liveProfile3(game(translation))
T.check(live ~= nil, "a translation mod keeps the game online: " .. tostring(why))
T.eq(live and live.fingerprint, vanilla and vanilla.fingerprint, "and leaves the dataset fingerprint alone")

local rebalance = loader("rebalance", ops({
  { registry = "pokemon", id = "BULBASAUR", op = "patch", value = { name = "BULBA", baseStats = { hp = 99 } }, owner = "rebalance" },
}))
T.eq(ArenaData.modTouchesGameplay(rebalance, "rebalance"), true, "a stat change is gameplay")
local none, noneWhy = ArenaData.liveProfile3(game(rebalance))
T.eq(none, nil, "a gameplay mod still blocks online")
T.eq(noneWhy, "mods", "with the mods reason")

local encounters = loader("wild", ops({
  { registry = "encounters", id = "ROUTE1", op = "override", value = {}, owner = "wild" },
}))
T.eq(select(2, ArenaData.liveProfile3(game(encounters))), "mods", "an encounter table is gameplay too")

local hooked = loader("hooky", ops({
  { registry = "strings", id = "Hi", op = "override", value = "Hola", owner = "hooky" },
}), { chains = { ["battle.damage"] = { { owner = "hooky" } } } })
T.eq(select(2, ArenaData.liveProfile3(game(hooked))), "mods", "a text mod that also hooks code blocks")

local permitted = loader("net", ops({}), { permissions = { "network" } })
T.eq(select(2, ArenaData.liveProfile3(game(permitted))), "mods", "a mod asking for permissions blocks")

local claimed = loader("overhaul", ops({}), { affectsLink = true })
T.eq(select(2, ArenaData.liveProfile3(game(claimed))), "mods", "a mod that says it affects link blocks")

local data = { generation = 3 }
local hello = Handshake.hello({ data = data, mods = translation }, nil)
ArenaData.stripCosmeticMods(hello, { data = data, mods = translation })
T.eq(hello.linkModified, false, "the room hello does not flag a translation as link-modified")
T.eq(#hello.mods, 0, "and lists no link mods")
T.eq(hello.fingerprint, Fingerprint.compute(data, {}, 3), "and hashes like vanilla")
local plainHello = Handshake.hello({ data = data }, nil)
T.eq(Handshake.checkCompat(hello, plainHello), "full", "so it pairs fully with a vanilla game")

local gameplayHello = Handshake.hello({ data = data, mods = rebalance }, nil)
ArenaData.stripCosmeticMods(gameplayHello, { data = data, mods = rebalance })
T.eq(gameplayHello.linkModified, true, "a gameplay mod still flags the hello")

local mon = { species = 1, nickname = "", level = 5, personality = 1, otId = 1, otName = "RED" }
local packed = Protocol.packMon3(mon)
T.eq(packed.species, 1, "a traded mon travels as its species id")
T.eq(packed.nickname, "", "an unnamed mon sends no species name text")

T.finish()
