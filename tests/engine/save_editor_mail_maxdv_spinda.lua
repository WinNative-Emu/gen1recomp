package.path = package.path .. ";./?.lua;./?/init.lua;./tools/save-editor/?.lua;./tools/save-editor/panels/?.lua"
love = require("tests.love_stub")
local T = require("tests.harness")
local bit = require("bit")
local Version = require("src.core.GameVersion")
local Serializer = require("src.core.SaveSerializer")
local K = require("tests.save_compat._codec")
local D = require("tests.save_compat._gen3_decode")
local B = require("tests.fixtures.save.bytes")
local G3 = require("tests.fixtures.save.gen3_build")
local G2 = require("tests.fixtures.save.gen2_build")
local Gen2Save = require("src.save_convert.Gen2Save")
local PokemonG3 = require("src.core.game3.pokemon")
local Unown = require("src.core.gen2.Unown")
local Mon2 = require("src.battle.gen2.Mon")
local Gen, Ops, MonOps = require("Gen"), require("Ops"), require("MonOps")
local State = require("State")
require("tests.game3_cache").mount()

local BEAD_MAIL = 127
local UNOWN_F = 0x00000105

local function g3mailState(version, fam)
  Version.set(version)
  local w = G3.base(version)
  G3.setParty(w, { G3.mon({ species = 201, pid = UNOWN_F, tid = 0x1234, sid = 0x5678, item = BEAD_MAIL, mail = 0 }) })
  local o = D.FULL[fam].mail
  for k = 0, 8 do B.le(w.sb1, o + k * 2, 0xFFFF, 2) end
  local name = G3.text("RED", 8)
  for i = 1, 8 do w.sb1[o + 17 + i] = name[i] end
  B.le(w.sb1, o + 26, 0x1234 + 0x5678 * 65536, 4)
  B.le(w.sb1, o + 30, 30005, 2)
  B.le(w.sb1, o + 32, BEAD_MAIL, 2)
  local s = State.new()
  s.save, s.version = assert(K.import(3, version, G3.emit(w))), version
  s.save.pcItems = s.save.pcItems or {}
  Gen.ensureBoxes(s.save)
  return s
end

local function export3(s, v, fam)
  local out = assert(K.export(3, v, Serializer.decode(Serializer.encode(s.save)), nil))
  return out, assert(D.deep(out, fam))
end

for _, v in ipairs({ "firered", "emerald" }) do
  local fam = v == "emerald" and "emerald" or "frlg"
  local s = g3mailState(v, fam)
  local mon = s.save.party[1]
  T.eq(mon.mail, 0, v .. " fixture unown holds mail 0")
  T.eq(s.save.mail[1].species, 30005, v .. " fixture mail shows UNOWN F")
  T.eq(Ops.setUnownForm(s, mon, 25), true, v .. " form set to Z")
  T.eq(s.save.mail[1].species, 30025, v .. " editor mail species follows the form")
  local out, deep = export3(s, v, fam)
  T.eq(deep.mail[1].species, 30025, v .. " exported mail species is UNOWN Z")
  T.eq(deep.mail[1].itemId, BEAD_MAIL, v .. " exported mail keeps the item")
  T.eq(deep.party[1].mail, 0, v .. " exported mon still points at mail 0")
  T.eq(PokemonG3.unownLetter(deep.party[1].pid), 25, v .. " exported PID is Z")
  local back = assert(K.import(3, v, out))
  T.eq(back.mail[1].species, 30025, v .. " re-import reads mail species UNOWN Z")

  s.data = s.data or {}
  s.data.pokemon = s.data.pokemon or {}
  s.data.pokemon[25] = { name = "PIKACHU", speciesId = 25 }
  local ok = Ops.setSpecies(s, mon, 25)
  if ok then
    T.eq(s.save.mail[1].species, 25, v .. " species edit restamps mail species")
    local _, deep2 = export3(s, v, fam)
    T.eq(deep2.mail[1].species, 25, v .. " exported mail species follows a species edit")
  else
    print("[skip] " .. v .. " setSpecies needs species data: " .. tostring(s.status))
  end
end

local UNOWN_DEF = {
  id = "UNOWN", name = "UNOWN", dex = 201, index = 201, types = { "PSYCHIC" },
  baseStats = { hp = 48, attack = 72, defense = 48, speed = 48, specialAttack = 72, specialDefense = 48 },
  catchRate = 225, baseExp = 61, growthRate = "MEDIUM_FAST", genderRatio = 255,
}
local CYNDA_DEF = {
  id = "CYNDAQUIL", name = "CYNDAQUIL", dex = 155, index = 155, types = { "FIRE" },
  baseStats = { hp = 39, attack = 52, defense = 43, speed = 65, specialAttack = 60, specialDefense = 50 },
  catchRate = 45, baseExp = 65, growthRate = "MEDIUM_SLOW", genderRatio = 31,
}
local g2data = {
  pokemon = { UNOWN = UNOWN_DEF, CYNDAQUIL = CYNDA_DEF },
  items = K.gen2Data.items, maps = K.gen2Data.maps,
  moves = { HIDDEN_POWER = { id = "HIDDEN_POWER", name = "HIDDEN POWER", index = 237, pp = 15, power = 1, accuracy = 100, type = "NORMAL" } },
}

local function g2state(version, species, dvs)
  Version.set(version)
  local bytes = G2.build({ version = version, party = { G2.mon({ species = species, nick = "MON", dvs = dvs,
    moves = { 237, 0, 0, 0 }, pp = { 15, 0, 0, 0 }, ppUps = { 0, 0, 0, 0 } }) } })
  local s = State.new()
  s.data = g2data
  s.save, s.version = assert(Gen2Save.decode(bytes, version, g2data)), version
  Gen.ensureBoxes(s.save)
  return s
end

local function dvList(d) return { d.attack, d.defense, d.speed, d.special } end
local function dvsOf(t) return { attack = t[1], defense = t[2], speed = t[3], special = t[4] } end

local MAX_UNOWN = {
  { 9, 9, 11, 15 }, { 9, 9, 15, 15 }, { 9, 11, 13, 15 }, { 9, 11, 15, 15 }, { 9, 13, 15, 15 },
  { 9, 15, 13, 15 }, { 9, 15, 15, 15 }, { 11, 9, 15, 15 }, { 11, 11, 11, 15 }, { 11, 11, 15, 15 },
  { 11, 13, 13, 15 }, { 11, 13, 15, 15 }, { 11, 15, 15, 15 }, { 13, 9, 13, 15 }, { 13, 9, 15, 15 },
  { 13, 11, 15, 15 }, { 13, 13, 11, 15 }, { 13, 13, 15, 15 }, { 13, 15, 13, 15 }, { 13, 15, 15, 15 },
  { 15, 9, 15, 15 }, { 15, 11, 13, 15 }, { 15, 11, 15, 15 }, { 15, 13, 15, 15 }, { 15, 15, 11, 15 },
  { 15, 15, 15, 15 },
}

local function checkWritten(s, v, label, want)
  local out = assert(Gen2Save.encode(s.save, v, nil, g2data))
  local L = Gen2Save.layoutFor(v)
  T.eq(Gen2Save.checksumValid(out, L), true, label .. " checksum valid")
  local dvHi, dvLo = out:byte(L.wPartyMons + 0x15 + 1), out:byte(L.wPartyMons + 0x16 + 1)
  T.eq(("%d/%d/%d/%d"):format(math.floor(dvHi / 16), dvHi % 16, math.floor(dvLo / 16), dvLo % 16),
    table.concat(want, "/"), label .. " DV bytes at +0x15")
  return assert(Gen2Save.decode(out, v, g2data))
end

for _, v in ipairs({ "gold", "crystal" }) do
  for letter = 1, 26 do
    for _, how in ipairs({ "maxDvs", "maxMon" }) do
      local s = g2state(v, 201, dvList(Unown.dvsForLetter(letter) or MonOps.unownDvs(dvsOf({ 4, 6, 8, 2 }), letter)))
      local mon = s.save.party[1]
      T.eq(Unown.monLetter(mon), letter, v .. " fixture letter " .. letter)
      if how == "maxMon" then
        mon.statExp = mon.statExp or {}
        Ops.maxMon(s, mon)
        mon = s.save.party[1]
      else
        Ops.maxDvs(s, mon)
      end
      local label = ("%s %s letter %d"):format(v, how, letter)
      T.eq(Unown.letterFromDVs(mon.dvs), letter, label .. " keeps the letter")
      T.eq(table.concat(dvList(mon.dvs), "/"), table.concat(MAX_UNOWN[letter], "/"), label .. " max DVs for the letter")
      T.eq(mon.dvs.hp, 15, label .. " HP DV 15")
      local back = checkWritten(s, v, label, MAX_UNOWN[letter])
      T.eq(Unown.monLetter(back.party[1]), letter, label .. " re-read letter")
    end
  end

  for _, case in ipairs({ { 2, 10, 10, 10, 9, { 11, 10, 10, 10 } }, { 14, 10, 10, 10, 22, { 15, 10, 10, 10 } } }) do
    for _, how in ipairs({ "maxDvs", "maxMon" }) do
      local s = g2state(v, 201, { case[1], case[2], case[3], case[4] })
      local mon = s.save.party[1]
      T.eq(Unown.monLetter(mon), case[5], v .. " shiny fixture letter " .. case[5])
      if how == "maxMon" then Ops.maxMon(s, mon) mon = s.save.party[1] else Ops.maxDvs(s, mon) end
      local label = ("%s %s shiny unown %d"):format(v, how, case[5])
      T.eq(Unown.letterFromDVs(mon.dvs), case[5], label .. " keeps the letter")
      T.eq(mon.shiny, true, label .. " stays shiny")
      T.eq(table.concat(dvList(mon.dvs), "/"), table.concat(case[6], "/"), label .. " shiny max DVs")
      T.check(s.status:find("kept shiny", 1, true) ~= nil, label .. " status says kept shiny")
      checkWritten(s, v, label, case[6])
    end
  end

  for _, how in ipairs({ "maxDvs", "maxMon" }) do
    local s = g2state(v, 155, { 6, 10, 10, 10 })
    local mon = s.save.party[1]
    T.eq(Mon2.vanillaShiny(mon.dvs), true, v .. " shiny cyndaquil fixture")
    if how == "maxMon" then Ops.maxMon(s, mon) mon = s.save.party[1] else Ops.maxDvs(s, mon) end
    local label = v .. " " .. how .. " shiny cyndaquil"
    T.eq(mon.shiny, true, label .. " stays shiny")
    T.eq(table.concat(dvList(mon.dvs), "/"), "15/10/10/10", label .. " highest shiny DVs")
    T.check(s.status:find("kept shiny", 1, true) ~= nil, label .. " status says kept shiny")
    local back = checkWritten(s, v, label, { 15, 10, 10, 10 })
    T.eq(Mon2.vanillaShiny(back.party[1].dvs), true, label .. " re-read DVs are shiny")

    local s2 = g2state(v, 155, { 3, 7, 1, 12 })
    local m2 = s2.save.party[1]
    if how == "maxMon" then Ops.maxMon(s2, m2) m2 = s2.save.party[1] else Ops.maxDvs(s2, m2) end
    T.eq(table.concat(dvList(m2.dvs), "/"), "15/15/15/15", v .. " " .. how .. " plain cyndaquil gets 15s")
    T.eq(m2.shiny, false, v .. " " .. how .. " plain cyndaquil not shiny")
    T.check(s2.status:find("kept shiny", 1, true) == nil, v .. " " .. how .. " plain status has no shiny note")
  end
end

local SPINDA = PokemonG3.SPECIES_SPINDA
local function bytesMoved(a, b)
  local n = 0
  for i = 0, 3 do
    if bit.band(bit.rshift(a, 8 * i), 0xFF) ~= bit.band(bit.rshift(b, 8 * i), 0xFF) then n = n + 1 end
  end
  return n
end
local function isShiny(p, tsv) return bit.bxor(tsv, bit.bxor(math.floor(p / 65536), p % 65536)) < 8 end
local function genderOf(p) return (p % 256) < 127 and "F" or "M" end

do
  local meta = PokemonG3.speciesMeta and PokemonG3.speciesMeta(SPINDA)
  T.eq((meta and meta.genderRatio) or 127, 127, "spinda gender ratio is 127")
  local rng = 308
  local function rand(n)
    rng = (rng * 1103515245 + 12345) % 2147483648
    return math.floor(rng / 32768) % n
  end
  local one, plain, shinyTwo, shinyBases = 0, 0, 0, 0
  local onTwo, onFour, broken, kept, offOne = 0, 0, 0, 0, 0
  for _ = 1, 300 do
    local tid, sid = rand(65536), rand(65536)
    local tsv = bit.bxor(tid, sid)
    local pid = rand(65536) * 65536 + rand(65536)
    if pid == 0 then pid = 1 end
    local nature, shiny, gender, ab = pid % 25, isShiny(pid, tsv), genderOf(pid), pid % 2
    local function run(reqs)
      reqs.basePid = pid
      reqs.ability = reqs.ability or ab
      return MonOps.generatePid(SPINDA, tid, sid, reqs)
    end
    local function ok(p, n, g, sh)
      return p and p ~= 0 and p % 25 == n and genderOf(p) == g and isShiny(p, tsv) == sh and p % 2 == ab
    end
    if run({ nature = nature, gender = gender, shiny = shiny }) == pid then kept = kept + 1 end
    local n2 = (nature + 1 + rand(24)) % 25
    local p = run({ nature = n2, gender = gender, shiny = shiny })
    if not ok(p, n2, gender, shiny) then broken = broken + 1 end
    local function tally(q)
      if not q then return end
      if shiny then
        if bytesMoved(pid, q) <= 2 then shinyTwo = shinyTwo + 1 end
      elseif bytesMoved(pid, q) == 1 then
        one = one + 1
      end
    end
    if shiny then shinyBases = shinyBases + 1 else plain = plain + 1 end
    tally(p)
    local g2 = gender == "F" and "M" or "F"
    p = run({ nature = nature, gender = g2, shiny = shiny })
    if not ok(p, nature, g2, shiny) then broken = broken + 1 end
    tally(p)
    p = run({ nature = nature, gender = gender, shiny = not shiny })
    if not ok(p, nature, gender, not shiny) then broken = broken + 1 end
    if p then
      local m = bytesMoved(pid, p)
      if not shiny then
        if m <= 2 then onTwo = onTwo + 1 end
        if m == 4 then onFour = onFour + 1 end
      end
    end
    local spid = bit.bxor(pid % 65536, tsv, rand(8)) * 65536 + pid % 65536
    local sp = MonOps.generatePid(SPINDA, tid, sid, { nature = spid % 25, gender = genderOf(spid), shiny = false,
      ability = spid % 2, basePid = spid })
    if not (sp and sp % 25 == spid % 25 and genderOf(sp) == genderOf(spid) and not isShiny(sp, tsv)) then
      broken = broken + 1
    end
    if sp and bytesMoved(spid, sp) == 1 then offOne = offOne + 1 end
  end
  T.eq(broken, 0, "spinda generatePid always meets nature, gender, ability and shininess")
  T.eq(kept, 300, "spinda PID that already fits is returned unchanged")
  T.check(plain >= 250, "spinda sample is mostly non-shiny")
  T.eq(one, plain * 2, "spinda nature or gender edit moves exactly one spot")
  T.eq(shinyTwo, shinyBases * 2, "spinda nature or gender edit on a shiny moves at most two spots")
  T.eq(offOne, 300, "spinda shiny off moves exactly one spot")
  T.eq(onFour, 0, "spinda shiny on never moves all four spots")
  T.check(onTwo >= 150, ("spinda shiny on moves at most two spots in most cases (%d)"):format(onTwo))
end

do
  Version.set("firered")
  local w = G3.base("firered")
  G3.setParty(w, { G3.mon({ species = SPINDA, pid = 0x8A3C5E71, tid = 0x1234, sid = 0x5678 }) })
  local s = State.new()
  s.save, s.version = assert(K.import(3, "firered", G3.emit(w))), "firered"
  Gen.ensureBoxes(s.save)
  local mon = s.save.party[1]
  local before = mon.personality
  MonOps.setNature(s.data, mon, (before % 25 + 5) % 25, 3)
  T.eq(mon.personality % 25, (before % 25 + 5) % 25, "spinda setNature sets the nature")
  T.eq(bytesMoved(before, mon.personality), 1, "spinda setNature moves one spot")
  local out = assert(K.export(3, "firered", Serializer.decode(Serializer.encode(s.save)), nil))
  local deep = assert(D.deep(out, "frlg"))
  T.eq(deep.party[1].pid, mon.personality, "spinda PID round trips")
  T.check(deep.party[1].checksumOk, "spinda substruct checksum valid")
  local MonEditor = require("MonEditor")
  local k1 = MonEditor.spriteKey(s, SPINDA, mon)
  MonOps.setNature(s.data, mon, (mon.personality % 25 + 3) % 25, 3)
  T.check(k1 ~= MonEditor.spriteKey(s, SPINDA, mon), "editor sprite key follows the spinda PID")
  T.eq(MonEditor.spriteKey(s, 4, { personality = 1 }), 4, "non-spinda sprite key unchanged")
end

T.finish()
