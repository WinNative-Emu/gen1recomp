package.path = package.path .. ";./?.lua;./?/init.lua;./tools/save-editor/?.lua;./tools/save-editor/panels/?.lua"
love = require("tests.love_stub")
local T = require("tests.harness")
local Ops = require("Ops")

local unown = { id = "UNOWN", name = "UNOWN", species = 201, speciesId = 201 }
local abra = { id = "ABRA", name = "ABRA", species = 63, speciesId = 63 }
local function state(generation, party)
  return {
    version = generation == 3 and "firered" or generation == 2 and "gold" or "red",
    save = { generation = generation, party = party, player = { map = "X", x = 0, y = 0 } },
    data = { pokemon = { [201] = unown, UNOWN = unown, [63] = abra, ABRA = abra,
      MR_MIME = { id = "MR_MIME", name = "MR.MIME" }, NIDORAN_F = { id = "NIDORAN_F", name = "NIDORAN♀" } } },
    mapId = "FR_PALLET_TOWN",
    mapClickCell = { cx = 2, cy = 15 },
  }
end

local S3 = state(3, { { species = 201, level = 25 }, { species = 63, level = 5 } })
Ops.selectParty(S3, 1)
T.eq(S3.note, "Selected party slot 1 (UNOWN)", "Gen 3 selection narrates the species name, not its number")
Ops.selectParty(S3, 2)
T.eq(S3.note, "Selected party slot 2 (ABRA)", "Gen 3 selection names ABRA, not 63")
T.eq(Ops.speciesName(S3, 201), "UNOWN", "speciesName resolves a Gen 3 species number")
T.eq(Ops.speciesName(S3, "MR_MIME"), "MR.MIME", "speciesName resolves a Gen 1 id to its display name")
T.eq(Ops.speciesName(S3, "NIDORAN_F"), "NIDORAN♀", "speciesName resolves the gendered Nidoran id")
T.eq(Ops.speciesName(S3, "NOT_A_MON"), "NOT_A_MON", "an unknown id falls back to itself")

Ops.partyMove(S3, -1)
T.eq(S3.status, "Moved ABRA to slot 1", "partyMove names the species")
T.eq(S3.toast and S3.toast.text, S3.status, "the move toast carries the same text")

local S1 = state(1, { { species = "MR_MIME", level = 5 } })
Ops.selectParty(S1, 1)
T.eq(S1.note, "Selected party slot 1 (MR.MIME)", "Gen 1 selection shows the display name")

T.check(Ops.setLastHeal(S3), "Gen 3 heal writes")
T.eq(S3.status, "Heal location set to FR_PALLET_TOWN (2,15)", "Gen 3 heal toast is plain words")
T.check(Ops.setPlayerHere(S3), "Gen 3 player writes")
T.eq(S3.status, "Player set to FR_PALLET_TOWN (2,15)", "player toast is plain words")

local S2 = state(2, {})
S2.mapId = "NEW_BARK_TOWN"
T.check(Ops.setLastHeal(S2), "Gen 2 spawn writes")
T.eq(S2.status, "Spawn point set to NEW_BARK_TOWN", "Gen 2 spawn toast is plain words")

S1.mapId, S1.save.visited = "PALLET_TOWN", { PALLET_TOWN = true }
T.check(Ops.setLastHeal(S1), "Gen 1 heal writes")
T.eq(S1.status, "Last heal set to PALLET_TOWN (2,15)", "Gen 1 heal toast is plain words")
local map = { id = "PALLET_TOWN", def = { tileset = "OVERWORLD", connections = {} } }
T.check(Ops.setLastOutdoor(S1, map), "Gen 1 outdoor writes")
T.eq(S1.status, "Last outdoor map set to PALLET_TOWN (2,15)", "Gen 1 outdoor toast is plain words")

for _, s in ipairs({ S1.status, S2.status, S3.status }) do
  T.check(not s:find("%l%u"), "no internal field name leaks into: " .. s)
end

T.finish("save_editor_status_words_s6")
