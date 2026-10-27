package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.harness")
local check, eq = T.check, T.eq

local Cache = require("tests.game3_cache")
if not Cache.mount("meta.json") then
  print("[skip] game3_link_fateful_3062: " .. tostring(Cache.reason))
  os.exit(0)
end

local GameVersion = require("src.core.GameVersion")
GameVersion.set("firered")
local Pokemon = require("src.core.game3.pokemon")
local Party = require("src.core.game3.party")
local Protocol = require("src.link.Protocol")
local Wire = require("src.link.Wire")
local Json = require("src.link.Json")
Pokemon.install(nil)

local FATEFUL = 2147483648

local session = { version = "firered", name = "RED", trainerId = 24680, secretId = 1357, gender = 0, party = {} }
local function give(species, level, extra)
  local holder = { name = "RED", trainerId = 24680, secretId = 1357, gender = 0, party = {} }
  local ok, _, mon = Party.giveMon(holder, species, level)
  assert(ok and mon, "giveMon " .. tostring(species))
  for k, v in pairs(extra or {}) do mon[k] = v end
  Pokemon.applyStats(mon)
  return mon
end
session.party = { give(1, 10), give(4, 12) }

package.loaded["src.core.game3.runtime"] = {
  getSession = function() return session end,
  isActive = function() return true end,
}
local Link = require("src.core.game3.link")
Link.session = function() return session end
local LT = require("src.core.game3.link.trade")

local function overWire(packed)
  local raw = Json.decode(Json.encode({ type = "game3_trade_mon", mon = packed }))
  return Wire.sanitize(raw).mon
end

local function partnerCode(received)
  LT.peer = nil
  LT.peerParty = { received }
  return LT.checkValidityOfTradeMons(1, 1)
end

for _, case in ipairs({ { 410, 30, "DEOXYS" }, { 151, 30, "MEW" } }) do
  local species, level, name = case[1], case[2], case[3]
  local legit = give(species, level, { modernFatefulEncounter = true })
  local packed = Protocol.packMon3(legit)
  eq(packed.modernFatefulEncounter, true, name .. " packs modernFatefulEncounter")
  eq(math.floor(packed.ribbons / FATEFUL) % 2, 1, name .. " packs ribbons bit 31")
  eq(packed.fatefulEncounter, true, name .. " packs the key older releases read as true")
  local wired = overWire(packed)
  eq(wired.fatefulEncounter, true, name .. " keeps the older-release key through Wire.sanitize")
  eq(wired.modernFatefulEncounter, true, name .. " keeps modernFatefulEncounter through Wire.sanitize")
  local got, why = LT.unpackMon(wired)
  check(got ~= nil, name .. " unpacks strictly: " .. tostring(why))
  eq(got and got.modernFatefulEncounter, true, name .. " received over link keeps modernFatefulEncounter")
  eq(got and got.fatefulEncounter, nil, name .. " received over link has no legacy fatefulEncounter key")
  eq(got and partnerCode(got), LT.BOTH_MONS_VALID, name .. " with the fateful flag from the partner is valid")
  eq(Protocol.packMon3(got).modernFatefulEncounter, true, name .. " keeps the flag when traded on again")

  local bad = LT.unpackMon(overWire(Protocol.packMon3(give(species, level, { modernFatefulEncounter = false }))))
  eq(bad and bad.modernFatefulEncounter, false, name .. " without the flag unpacks false")
  eq(bad and partnerCode(bad), LT.PARTNER_MON_INVALID, name .. " without the fateful flag is PARTNER_MON_INVALID")
end

do
  local legit = Protocol.packMon3(give(410, 30, { modernFatefulEncounter = true }))
  local older = {}
  for k, v in pairs(legit) do older[k] = v end
  older.fatefulEncounter = false
  local got = LT.unpackMon(overWire(older))
  eq(got and got.modernFatefulEncounter, true, "DEOXYS from an older release (legacy key false) keeps the flag")
  eq(got and partnerCode(got), LT.BOTH_MONS_VALID, "and is valid")
  older.modernFatefulEncounter = nil
  got = LT.unpackMon(overWire(older))
  eq(got and got.modernFatefulEncounter, true, "DEOXYS from a release without the modern key reads ribbons bit 31")
end

do
  local Trade = require("src.online.Trade")
  local handle = { generation = 3, version = "firered", data = { pokemon = Pokemon }, party = session.party }
  local link = { send = function() return true end, seat = function() return 0 end }
  local remote, why = Trade.remote(handle, link, {})
  check(remote ~= nil, "online Remote3 opens: " .. tostring(why))
  if remote then
    local mew = LT.unpackMon(overWire(Protocol.packMon3(give(151, 30, { modernFatefulEncounter = true }))))
    remote.session.theirParty, remote.session.theirPick = { mew }, 1
    eq(remote:_partnerMonValid(), true, "online: a partner MEW with the fateful flag is valid")
    local bad = LT.unpackMon(overWire(Protocol.packMon3(give(151, 30, { modernFatefulEncounter = false }))))
    remote.session.theirParty = { bad }
    eq(remote:_partnerMonValid(), false, "online: a partner MEW without the fateful flag is refused")
  end
end

do
  local Family = require("src.core.game3.link.family")
  local ok, deoxys = pcall(Family.species, "emerald", "SPECIES_DEOXYS")
  if ok and deoxys then
    local party = { give(410, 30, { modernFatefulEncounter = false }), give(1, 10) }
    eq(Family.canTradeSelectedMon("emerald", party, 0, { nationalDex = true }), Family.CANT_TRADE_INVALID_MON,
      "Emerald: own DEOXYS without the fateful flag can't be traded")
    party[1].modernFatefulEncounter = true
    check(Family.canTradeSelectedMon("emerald", party, 0, { nationalDex = true }) ~= Family.CANT_TRADE_INVALID_MON,
      "Emerald: own DEOXYS with the fateful flag can be traded")
  else
    print("[skip] Emerald constants: " .. tostring(deoxys))
  end
end

T.finish("game3_link_fateful_3062")
