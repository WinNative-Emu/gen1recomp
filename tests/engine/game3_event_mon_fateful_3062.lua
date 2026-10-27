package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.harness")
local check, eq = T.check, T.eq

local GameVersion = require("src.core.GameVersion")
local Flags = require("src.core.game3.scripting.flags")
local Space = require("src.core.game3.scripting.space")
local Enc = require("src.core.game3.encounters")
local Gen3Save = require("src.save_convert.Gen3Save")

local FATEFUL = 2147483648

local function fatefulBit(mon)
  local r = Gen3Save.fromPortMon(mon, {}, true).ribbons
  return math.floor((tonumber(r) or 0) / FATEFUL) % 2 == 1
end

local session = { version = "firered", name = "RED", trainerId = 1, secretId = 2, party = {},
  store = Flags.newStore(), map = "FR_NAVEL_ROCK_BASE" }
package.loaded["src.core.game3.runtime"] = {
  getSession = function() return session end,
  isActive = function() return true end,
}

-- pokefirered/data/maps/NavelRock_Base/scripts.inc:56
GameVersion.set("firered")
Space.store = Flags.newStore()
local Std = require("src.core.game3.scripting.stdscripts")
local Events = require("src.core.game3.scripting.natives_events")
local ctx = { specialVars = {} }
Flags.setVar(Space.store, ctx, 0x8004, 249)
Flags.setVar(Space.store, ctx, 0x8005, 70)
Flags.setVar(Space.store, ctx, 0x8006, 0)
Enc.takePendingWild()
Events.HANDLERS[Std.SPECIAL.CreateEnemyEventMon](ctx, {})
local frFoe = Enc.takePendingWild()
eq(frFoe and frFoe.species, 249, "FireRed CreateEnemyEventMon queues Lugia")
eq(frFoe and frFoe.modernFatefulEncounter, true, "FireRed event mon carries modernFatefulEncounter")
eq(frFoe and frFoe.fatefulEncounter, nil, "FireRed event mon has no legacy fatefulEncounter key")

-- pokeemerald/data/maps/BirthIsland_Exterior/scripts.inc:82
local Islands = require("src.core.game3.scripting.natives_event_islands")
local emCtx = { specialVars = {} }
Flags.setVar(Space.store, emCtx, 0x8004, 410)
Flags.setVar(Space.store, emCtx, 0x8005, 30)
Flags.setVar(Space.store, emCtx, 0x8006, 0)
Islands.BY_NAME.CreateEnemyEventMon(emCtx)
local emFoe = Enc.takePendingWild()
eq(emFoe and emFoe.species, 410, "Emerald CreateEnemyEventMon queues Deoxys")
eq(emFoe and emFoe.modernFatefulEncounter, true, "Emerald event mon carries modernFatefulEncounter")
eq(emFoe and emFoe.fatefulEncounter, nil, "Emerald event mon has no legacy fatefulEncounter key")

-- pokefirered/src/pokemon.c:3396
check(fatefulBit({ species = 249, level = 70, modernFatefulEncounter = true }),
  "export sets ribbons bit 31 for a modernFatefulEncounter mon")
check(not fatefulBit({ species = 249, level = 70, modernFatefulEncounter = false }),
  "export clears ribbons bit 31 without the flag")

do
  local F = require("tests.engine._xgen_fixture")
  local TradeConvert = require("src.online.xgen.TradeConvert")
  local pika = { species = "PIKACHU", level = 25, exp = 15625, hp = 10, status = "", nickname = "ZAPPY", ot = "RED",
    otId = 4242, dvs = { attack = 10, defense = 10, speed = 10, special = 10 },
    statExp = { hp = 0, attack = 0, defense = 0, speed = 0, special = 0 },
    moves = { { id = "THUNDERSHOCK", pp = 10 } }, catchRate = 190, stats = { hp = 50 } }
  local r = TradeConvert.convert({ source = { data = F.data("red") }, target = { data = F.data("emerald") }, mon = pika })
  check(r.ok, "Gen 1 Pikachu converts to Gen 3")
  eq(r.result and r.result.modernFatefulEncounter, false, "Gen 1 -> Gen 3 non-Mew has the flag clear")
end

local Cache = require("tests.game3_cache")
require("src.import.gba.versions").select("firered")
if Cache.mount("pokemon/battle_moves.lua") then
  local Battle = require("src.core.game3.battle.init")
  local Catching = require("src.core.game3.battle.catching")
  local Engine = require("src.core.game3.battle.engine")
  local Adapter = require("src.core.game3.battle.adapter")
  local Schema = require("src.core.game3.save_schema_firered")
  local SaveData = require("src.core.SaveData")
  local Rng = require("src.core.game3.rng")

  local function catchFrom(foe, label)
    Rng.SeedRng(0x3062)
    local s = { version = "firered", name = "RED", trainerId = 1, secretId = 2, party = {
      { species = 6, level = 80, hp = 250, maxHp = 250, otId = 1, otSecretId = 2,
        moves = { 33, 0, 0, 0 }, pp = { 35, 0, 0, 0 } } } }
    session = s
    Battle.start({ headless = true, autoFight = false, session = s, playerParty = s.party, foe = foe,
      wild = true, legendary = true })
    local st = assert(Battle.getState())
    eq(st.enemy.mon.modernFatefulEncounter, true, label .. " battle foe keeps modernFatefulEncounter")
    local res = Catching.storeCaught(s, st.enemy, 1)
    Battle.reset()
    check(res and res.success, label .. " is stored")
    local mon = res and res.mon or {}
    eq(mon.modernFatefulEncounter, true, label .. " caught mon keeps modernFatefulEncounter")
    check(fatefulBit(mon), label .. " exported ribbons word has bit 31")
    local save = SaveData.decode(SaveData.encode(Schema.toSaveTable(s)))
    local back = Schema.fromSaveTable(save)
    eq(back.party[2] and back.party[2].modernFatefulEncounter, true, label .. " flag survives native save and load")
  end

  catchFrom(frFoe, "FireRed Lugia")
  catchFrom(emFoe, "Emerald Deoxys")

  -- pokefirered/src/battle_util.c:3133
  local function obeys(fateful, label)
    local mew = { species = 151, level = 70, hp = 200, maxHp = 200, attack = 80, defense = 80, spAtk = 80, spDef = 80,
      speed = 80, ability = 0, nickname = "MEW", otId = 1, otSecretId = 2, otName = "RED",
      modernFatefulEncounter = fateful, moves = { 33, 0, 0, 0 }, pp = { 35, 0, 0, 0 } }
    local s = { version = "firered", name = "RED", trainerId = 1, secretId = 2, party = { mew } }
    session = s
    Space.store = Flags.newStore()
    Battle.start({ headless = false, autoFight = false, session = s, playerParty = s.party,
      foe = { species = 19, level = 2 }, wild = true,
      rng = function(lo, hi) if lo == 1 and hi == 100 then return 1 end return hi end })
    local st = assert(Battle.getState())
    st.badges, st.playerTrainerId, st.playerOtName = {}, 1, "RED"
    local out = {}
    Engine.resolveMove(st.player, st.enemy, 33, 1, Adapter.new(st), st, out)
    local ok = out._anim == nil or out._anim.cancelled ~= true
    Battle.reset()
    eq(ok, fateful, label)
  end
  obeys(true, "own Mew with the fateful flag obeys")
  obeys(false, "own Mew without the fateful flag disobeys")
else
  print("[skip] battle and catch section: " .. tostring(Cache.reason))
end

T.finish("game3_event_mon_fateful_3062")
