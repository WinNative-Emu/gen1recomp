package.path = package.path .. ";./?.lua;./?/init.lua;./tools/save-editor/?.lua;./tools/save-editor/panels/?.lua"
love = require("tests.love_stub")
local T = require("tests.harness")
local bit = require("bit")
local Version = require("src.core.GameVersion")
local Serializer = require("src.core.SaveSerializer")
local K = require("tests.save_compat._codec")
local D = require("tests.save_compat._gen3_decode")
local G3 = require("tests.fixtures.save.gen3_build")
local G2 = require("tests.fixtures.save.gen2_build")
local Gen2Save = require("src.save_convert.Gen2Save")
local PokemonG3 = require("src.core.game3.pokemon")
local Unown = require("src.core.gen2.Unown")
local Gen, Ops, MonOps = require("Gen"), require("Ops"), require("MonOps")
local State = require("State")
local Legality = require("Legality")

local function shinyOf(p, tid, sid)
  return bit.bxor(bit.bxor(tid, sid), bit.bxor(math.floor(p / 65536), p % 65536)) < 8
end

do
  local rng = 2726
  local function rand(n)
    rng = (rng * 1103515245 + 12345) % 2147483648
    return rng % n
  end
  local bad = 0
  for _ = 1, 120 do
    local pid = rand(65536) * 65536 + rand(65536)
    local tid, sid = rand(65536), rand(65536)
    local nature = pid % 25
    for letter = 0, 27 do
      for _, shiny in ipairs({ false, true }) do
        local p = MonOps.unownPid(pid, letter, nature, shiny, tid, sid)
        if not (p and PokemonG3.unownLetter(p) == letter and p % 25 == nature and shinyOf(p, tid, sid) == shiny) then
          bad = bad + 1
          if bad <= 5 then
            T.check(false, ("unownPid pid=%08x tid=%d sid=%d letter=%d shiny=%s -> %s")
              :format(pid, tid, sid, letter, tostring(shiny), tostring(p)))
          end
        end
      end
    end
  end
  T.eq(bad, 0, "gen3 unownPid keeps nature and shininess for every letter")
  for tsv89 = 0, 3 do
    for letter = 0, 27 do
      local p = MonOps.unownPid(0x12345678, letter, 7, true, tsv89 * 256, 0)
      T.check(p and PokemonG3.unownLetter(p) == letter, ("shiny letter %d reachable with tsv bits %d"):format(letter, tsv89))
    end
  end
  local rewritten = 0
  for _ = 1, 300 do
    local pid = rand(65536) * 65536 + rand(65536)
    local tid, sid = rand(65536), rand(65536)
    if MonOps.unownPid(pid, PokemonG3.unownLetter(pid), pid % 25, shinyOf(pid, tid, sid), tid, sid) ~= pid then
      rewritten = rewritten + 1
    end
    local low = rand(65536)
    local spid = bit.bxor(low, bit.bxor(tid, sid), rand(8)) * 65536 + low
    if MonOps.unownPid(spid, PokemonG3.unownLetter(spid), spid % 25, true, tid, sid) ~= spid then
      rewritten = rewritten + 1
    end
  end
  T.eq(rewritten, 0, "gen3 unownPid leaves a PID that already fits unchanged (plain and shiny)")
end


local function g3state(version, mons)
  Version.set(version)
  local w = G3.base(version)
  G3.setParty(w, mons)
  local s = State.new()
  s.save, s.version = assert(K.import(3, version, G3.emit(w))), version
  s.save.pcItems = s.save.pcItems or {}
  Gen.ensureBoxes(s.save)
  return s
end

local UNOWN_F = 0x00000105
assert(PokemonG3.unownLetter(UNOWN_F) == 5)

do
  local s = g3state("firered", { G3.mon({ species = 201, pid = UNOWN_F, tid = 0x1234, sid = 0x5678 }) })
  local mon = s.save.party[1]
  T.eq(PokemonG3.unownLetter(mon.personality), 5, "fixture unown is F")
  local natureBefore = mon.personality % 25
  MonOps.setNature(s.data, mon, (natureBefore + 3) % 25, 3)
  T.eq(PokemonG3.unownLetter(mon.personality), 5, "setNature keeps unown letter")
  T.eq(mon.personality % 25, (natureBefore + 3) % 25, "setNature still sets the nature")
  MonOps.setShiny(s.data, mon, true, 3)
  T.eq(PokemonG3.unownLetter(mon.personality), 5, "setShiny(true) keeps unown letter")
  T.check(shinyOf(mon.personality, 0x1234, 0x5678), "setShiny(true) makes the PID shiny")
  MonOps.setShiny(s.data, mon, false, 3)
  T.eq(PokemonG3.unownLetter(mon.personality), 5, "setShiny(false) keeps unown letter")
  T.check(not shinyOf(mon.personality, 0x1234, 0x5678), "setShiny(false) clears shiny")
  MonOps.setAbility(s.data, mon, 0, 3)
  T.eq(PokemonG3.unownLetter(mon.personality), 5, "setAbility keeps unown letter")
  local before = mon.personality
  MonOps.setAbility(s.data, mon, 0, 3)
  T.eq(mon.personality, before, "setAbility to the current slot keeps the Unown PID")
  MonOps.setShiny(s.data, mon, false, 3)
  T.eq(mon.personality, before, "setShiny to the current state keeps the Unown PID")
  MonOps.setNature(s.data, mon, before % 25, 3)
  T.eq(mon.personality, before, "setNature to the current nature keeps the Unown PID")
end

for _, v in ipairs({ "firered", "emerald" }) do
  local fam = v == "emerald" and "emerald" or "frlg"
  local s = g3state(v, { G3.mon({ species = 201, pid = UNOWN_F, tid = 0x1234, sid = 0x5678, ability = 1,
    ivs = { 31, 2, 17, 4, 25, 6 }, moves = { 237, 0, 0, 0 }, pp = { 15, 0, 0, 0 } }) })
  local mon = s.save.party[1]
  local before = assert(D.deep(assert(K.export(3, v, Serializer.decode(Serializer.encode(s.save)), nil)), fam)).party[1]
  T.eq(Ops.setUnownForm(s, mon, 27), true, v .. " setUnownForm accepted ?")
  T.eq(s.status, "UNOWN is now ?", v .. " status names the form")
  T.eq(#s.undoStack, 1, v .. " one history entry")
  T.eq(PokemonG3.unownLetter(mon.personality), 27, v .. " editor mon is ?")
  local out = assert(K.export(3, v, Serializer.decode(Serializer.encode(s.save)), nil))
  local after = assert(D.deep(out, fam)).party[1]
  T.check(after.checksumOk, v .. " substruct checksum valid after PID change")
  T.eq(after.species, 201, v .. " species decrypts as UNOWN")
  T.eq(PokemonG3.unownLetter(after.pid), 27, v .. " written PID spells ?")
  T.eq(after.pid % 25, UNOWN_F % 25, v .. " nature kept")
  T.eq(after.shiny, false, v .. " still not shiny")
  T.eq(after.ability, 1, v .. " abilityNum bit kept")
  T.eq(table.concat(after.ivs, ","), table.concat(before.ivs, ","), v .. " IVs kept")
  T.eq(table.concat(after.moves, ","), table.concat(before.moves, ","), v .. " moves kept")
  T.eq(after.exp, before.exp, v .. " exp kept")
  local back = assert(K.import(3, v, out))
  T.eq(PokemonG3.unownLetter(back.party[1].personality), 27, v .. " re-import reads ?")
  T.eq(Ops.setUnownForm(s, mon, 27), false, v .. " same form is a no-op")
end

do
  local s = g3state("firered", { G3.mon({ species = 4 }) })
  T.eq(Ops.setUnownForm(s, s.save.party[1], 3), false, "non-unown refuses a form")
  T.eq(s.status, "Only an Unown has a form", "and says why")
end

local UNOWN_DEF = {
  id = "UNOWN", name = "UNOWN", dex = 201, index = 201, types = { "PSYCHIC" },
  baseStats = { hp = 48, attack = 72, defense = 48, speed = 48, specialAttack = 72, specialDefense = 48 },
  catchRate = 225, baseExp = 61, growthRate = "MEDIUM_FAST", genderRatio = 255,
}
local g2data = {
  pokemon = { UNOWN = UNOWN_DEF, CYNDAQUIL = { id = "CYNDAQUIL", name = "CYNDAQUIL", dex = 155, index = 155 } },
  items = K.gen2Data.items, maps = K.gen2Data.maps, moves = {},
}

local function g2state(version, dvs)
  Version.set(version)
  local bytes = G2.build({ version = version, party = { G2.mon({ species = 201, nick = "UNOWN", dvs = dvs }) } })
  local s = State.new()
  s.data = g2data
  s.save, s.version = assert(Gen2Save.decode(bytes, version, g2data)), version
  Gen.ensureBoxes(s.save)
  return s
end

local function dvsOf(t) return { attack = t[1], defense = t[2], speed = t[3], special = t[4] } end

for _, v in ipairs({ "gold", "crystal" }) do
  local start = { 9, 4, 13, 6 }
  for letter = 1, 26 do
    local s = g2state(v, start)
    local mon = s.save.party[1]
    T.eq(mon.species, "UNOWN", v .. " fixture decodes as UNOWN")
    local hp = mon.dvs.hp
    local ok = Ops.setUnownForm(s, mon, letter)
    if letter == Unown.letterFromDVs(dvsOf(start)) then
      T.eq(ok, false, v .. " setting the current letter is a no-op")
    else
      T.eq(ok, true, v .. " set letter " .. letter)
    end
    T.eq(Unown.letterFromDVs(mon.dvs), letter, v .. " DVs spell letter " .. letter)
    T.eq(Unown.monLetter(mon), letter, v .. " stored letter " .. letter)
    T.eq(mon.dvs.hp, hp, v .. " HP DV kept for " .. letter)
    for i, k in ipairs({ "attack", "defense", "speed", "special" }) do
      T.eq(mon.dvs[k] % 2, start[i] % 2, v .. " bit 0 of " .. k .. " kept")
      T.eq(math.floor(mon.dvs[k] / 8), math.floor(start[i] / 8), v .. " bit 3 of " .. k .. " kept")
    end
    local report = Legality.mon(s, mon)
    local issues = Legality.highlights(report, mon)
    T.check(issues.fields.form == nil and issues.fields.shiny == nil, v .. " no form/shiny issue for " .. letter)
    local out = assert(Gen2Save.encode(s.save, v, nil, g2data))
    local L = Gen2Save.layoutFor(v)
    T.eq(Gen2Save.checksumValid(out, L), true, v .. " checksum valid for " .. letter)
    local dvHi, dvLo = out:byte(L.wPartyMons + 0x15 + 1), out:byte(L.wPartyMons + 0x16 + 1)
    T.eq(Unown.letterFromDVs(dvsOf({ math.floor(dvHi / 16), dvHi % 16, math.floor(dvLo / 16), dvLo % 16 })), letter,
      v .. " DV bytes at +0x15 spell " .. letter)
    local back = assert(Gen2Save.decode(out, v, g2data))
    T.eq(Unown.monLetter(back.party[1]), letter, v .. " re-read letter " .. letter)
  end

  local s = g2state(v, { 2, 10, 10, 10 })
  local mon = s.save.party[1]
  T.eq(Unown.monLetter(mon), 9, v .. " shiny fixture is I")
  T.eq(require("src.battle.gen2.Mon").vanillaShiny(mon.dvs), true, v .. " and shiny")
  Ops.setUnownForm(s, mon, 22)
  T.eq(Unown.monLetter(mon), 22, v .. " shiny I -> V")
  T.eq(mon.shiny, true, v .. " V stays shiny")
  Ops.setUnownForm(s, mon, 1)
  T.eq(Unown.monLetter(mon), 1, v .. " shiny V -> A")
  T.eq(mon.shiny, false, v .. " A is not shiny")
  T.eq(s.status, "UNOWN is now A (no longer shiny: only I and V can be shiny)", v .. " status warns about shininess")
  local out, why = Gen2Save.encode(s.save, v, nil, g2data)
  T.check(out ~= nil, v .. " a former shiny now A still writes: " .. tostring(why))

  for _, letter in ipairs({ 9, 22 }) do
    local s2 = g2state(v, { 9, 8, 12, 14 })
    local m2 = s2.save.party[1]
    T.eq(require("src.battle.gen2.Mon").vanillaShiny(m2.dvs), false, v .. " plain fixture not shiny")
    Ops.setUnownForm(s2, m2, letter)
    T.eq(Unown.monLetter(m2), letter, v .. " plain -> " .. letter)
    T.eq(m2.shiny, false, v .. " plain never becomes shiny at " .. letter)
  end
end

T.finish()
