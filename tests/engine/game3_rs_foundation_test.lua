package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local Constants = require("src.core.game3.constants")
local Builds = require("src.import.gba.rs_builds")
local GameVersion = require("src.core.GameVersion")
local Versions = require("src.import.gba.versions")
local C = Constants.of("ruby")
T.eq(Constants.of("sapphire"), C, "RS share their constant numbering")
for _, kind in ipairs(Constants.KINDS) do
  T.check(next(C[kind].byName) ~= nil, "RS " .. kind .. " is populated")
end
T.eq(C.script_cmds.count, 198, "RS has 198 opcodes, not Emerald's table")
T.eq(C.specials.count, 342, "RS has 342 specials")
T.eq(C.battle_string_ids.byName.BATTLESTRINGS_ID_ADDER, 12, "RS battle text starts at id 12")
T.eq(C.species.byName.HOENN_DEX_COUNT, 202, "RS Hoenn dex count")
T.eq(C.map_groups.byName.MAP_BATTLE_FRONTIER_BATTLE_TOWER_LOBBY, nil, "RS has no Frontier map")

local L = require("src.import.gba.layouts.ruby")
T.eq(require("src.import.gba.layouts.registry").of("ruby"), L, "registry selects RS layout")
T.eq(require("src.import.gba.layouts.sapphire"), L, "Sapphire shares RS structs")
T.eq(L.pokedexEntry.size, 36, "RS dex entry size")
T.eq(L.pokedexEntry.desc2, 20, "RS second dex page pointer")
T.eq(L.trainerNameLen, 12, "RS trainer name size")
T.eq(L.tutorLearnsetBytes, 0, "RS has no tutor compatibility table")
T.same(require("src.import.gba.layouts.registry").pockets(L),
  { "ITEMS", "POKE_BALLS", "TM_HM", "BERRIES", "KEY_ITEMS" }, "RS pocket ids")

local offsets = {
  ruby = { 0x308588, 0x1FEC18 }, ruby11 = { 0x3085A0, 0x1FEC30 }, ruby12 = { 0x3085A0, 0x1FEC30 },
  sapphire = { 0x308518, 0x1FEBA8 }, sapphire11 = { 0x308530, 0x1FEBC0 }, sapphire12 = { 0x308530, 0x1FEBC0 },
}
for _, game in ipairs({ "ruby", "sapphire" }) do
  local V = require("src.import.gba.games." .. game)
  for _, revision in ipairs(Builds[game]) do
    T.eq(GameVersion.forSha1(revision.sha1), game, "registry identifies " .. revision.build)
    T.eq(GameVersion.revisionLabel(game, revision.sha1), revision.label, "registry identifies revision")
    Versions.select(revision.sha1)
    T.eq(Versions.module(), V, "global facade selects RS module")
    local row = assert(V.lookup(revision.sha1))
    T.eq(V.BUILD, revision.build, "selected " .. revision.build)
    T.eq(row.build, revision.build, "lookup carries native build")
    T.eq(row.g_map_groups, offsets[revision.build][1], "native map groups")
    T.eq(V.SPECIES_INFO, offsets[revision.build][2], "native base stats")
    T.eq(V.SYMS.game, revision.build, "native symbols selected")
    T.eq(V.NUM_SPECIES, 412, "RS species table")
    T.eq(V.MOVES_COUNT, 355, "RS moves table")
    T.eq(V.ABILITIES_COUNT, 78, "RS ability count excludes name alignment padding")
    T.eq(V.TRAINERS_COUNT, 694, "RS trainer count")
    T.eq(V.POKEDEX_ENTRY_SIZE, L.pokedexEntry.size, "RS dex layout")
    T.eq(V.NATIONAL_DEX_COUNT, 386, "RS national dex")
    T.eq(V.SPECIALS_COUNT, C.specials.count, "RS specials ROM count")
    T.eq(V.SCRIPT_CMD_COUNT, C.script_cmds.count, "RS opcode ROM count")
    T.eq(V.FRONTIER, nil, "RS does not inherit Emerald Frontier data")
    T.eq(V.MON_STILL_FRONT_PIC_TABLE, nil, "RS uses its static front table")
    T.eq(V.ITEM_ICON_TABLE, nil, "RS has no Emerald item icon table")
    T.eq(V.TUTOR_MOVE_COUNT, 0, "RS does not inherit Emerald tutors")
  end
  local lastBuild = V.BUILD
  T.check(not pcall(V.select, Builds[game == "ruby" and "sapphire" or "ruby"][1].sha1),
    "an edition rejects the other edition's hash")
  T.eq(V.BUILD, lastBuild, "failed selection preserves native build")
  T.eq(V.lookup("unknown"), nil, "unknown lookup is refused")
  V.select(game)
  T.eq(V.BUILD, game, "game id restores base build")
end
T.eq(GameVersion.gameCode("ruby"), 2, "Ruby cartridge origin id")
T.eq(GameVersion.gameCode("sapphire"), 1, "Sapphire cartridge origin id")
Versions.select("firered")
T.finish("game3_rs_foundation_test")
