#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path
local G3 = require("tests.game3_cache")
local root = G3.rootOrSkip("game3_encounters_altering_cave_test", "encounters.lua")
G3.mount("encounters.lua")

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local SPECIES_ZUBAT = 41
local SPECIES_MAREEP = 179
local SPECIES_HOUNDOUR = 228
local SPECIES_SMEARGLE = 235
local VAR_ALTERING_CAVE_WILD_SET = 0x4024

local f = assert(io.open(root .. "/encounters.lua", "rb"))
local raw = assert(loadstring(f:read("*a")))()
f:close()

local cave = raw["1:122"]
check(type(cave) == "table", "Altering Cave (1:122) has a wild table")
check(cave and cave.land and cave.land.slots[1].species == SPECIES_ZUBAT,
  "default Altering Cave table is header 0 (Zubat)")
check(cave and type(cave.variants) == "table" and #cave.variants == 9, "all 9 Altering Cave tables kept")
check(cave and cave.variants[9].land.slots[1].species == SPECIES_SMEARGLE, "last variant is Smeargle")
local alias = raw.FR_SIX_ISLAND_ALTERING_CAVE or raw.SIX_ISLAND_ALTERING_CAVE
check(alias == nil or alias.land.slots[1].species == SPECIES_ZUBAT, "map-name alias also points at header 0")

local Space = require("src.core.game3.scripting.space")
local Flags = require("src.core.game3.scripting.flags")
local Encounters = require("src.core.game3.encounters")
require("src.import.gba.map_catalog").rebuildIndex()
Encounters.loadFromMod(nil)

Space.store = { flags = {}, vars = {} }
local function lead(n)
  Flags.setVar(Space.store, nil, VAR_ALTERING_CAVE_WILD_SET, n)
  local t = Encounters.tableFor("1:122")
  return t and t.land and t.land.slots[1].species
end
check(lead(0) == SPECIES_ZUBAT, "var 0 -> Zubat")
check(lead(1) == SPECIES_MAREEP, "var 1 -> Mareep")
check(lead(3) == SPECIES_HOUNDOUR, "var 3 -> Houndour")
check(lead(8) == SPECIES_SMEARGLE, "var 8 -> Smeargle")
check(lead(9) == SPECIES_ZUBAT, "var >= NUM_ALTERING_CAVE_TABLES falls back to header 0")

local r9 = Encounters.tableFor("3:27")
check(r9 and r9.variants == nil, "single-header maps carry no variants")

if failed > 0 then
  print(string.format("FAIL: %d check(s) failed", failed))
  os.exit(1)
end
print("PASS game3_encounters_altering_cave_test")
