package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.harness")
local GameVersion = require("src.core.GameVersion")
local Opcodes = require("src.core.game3.scripting.opcodes")
local Disasm = require("src.core.game3.scripting.disasm")
local TextIR = require("src.core.game3.scripting.text_ir")
local Native = require("src.core.game3.constants.ruby.script_cmds")
local Builds = require("src.import.gba.rs_builds")
local Movement = require("src.import.gba.movement_emerald")
local rs = Opcodes.forGame("ruby")
T.eq(Opcodes.forGame("sapphire"), rs, "both RS editions use native RS bytecode")
T.eq(rs.MAX, 0xC5, "RS ends at waitmoncry")
T.eq(rs:get(0xC6), nil, "Emerald's bufferboxname is absent in RS")
T.eq(rs.STD.REGISTER_MATCH_CALL, nil, "RS has no Match Call standard script")
T.eq(rs.STD.PUT_ITEM_AWAY, nil, "RS has no FRLG standard script 8")
T.eq(rs.brailleFormatSize, 6, "RS braille format is six bytes")
local moves = Movement.forGame("ruby")
local rawMoves = require("src.core.game3.constants").of("ruby").movement.byId.MOVEMENT_ACTION_
for id, name in pairs(rawMoves) do T.check(moves.toCanon[id] ~= nil, "native RS movement translates: " .. name) end
T.eq(moves.toCanon[0x2D], Movement.canonOf("MOVEMENT_ACTION_WALK_FASTER_DOWN"), "RS Fastest is cart Faster")
T.eq(moves.toCanon[0x61], Movement.canonOf("MOVEMENT_ACTION_WALK_DOWN_AFFINE"), "RS affine suffix has the same action")
for byte = 0, Native.count - 1 do
  if byte ~= 0x5C then
    T.eq(rs:get(byte).size, Native.byId[byte].size, "native width at opcode " .. byte)
  end
end

for _, spec in ipairs({
  { bytes = { 0x93, 1, 2 }, op = "showmoneybox", args = 2 },
  { bytes = { 0x95, 1, 2 }, op = "updatemoneybox", args = 2 },
  { bytes = { 0x72, 1, 2, 3, 4 }, op = "drawbox", args = 4 },
  { bytes = { 0xB1, 1, 2, 0, 3, 0, 4, 0 }, op = "addelevmenuitem", args = 4 },
}) do
  local stream = {}
  for _, b in ipairs(spec.bytes) do stream[#stream + 1] = b end
  for _, b in ipairs({ 0x16, 0, 0x40, 0x34, 0x12, 0x02 }) do stream[#stream + 1] = b end
  local rows = Disasm.decode(stream, 1, nil, rs)
  T.eq(rows[1].op, spec.op, "RS decodes " .. spec.op)
  T.eq(rows[1][spec.args], spec.bytes[#spec.bytes - (spec.op == "addelevmenuitem" and 1 or 0)], "last operand survives")
  T.eq(rows[2].op, "setvar", "next opcode stays aligned after " .. spec.op)
  T.eq(rows[2][2], 0x1234, "next value stays aligned after " .. spec.op)
  T.eq(rows[3].op, "end", "stream terminates after " .. spec.op)
end

local old = GameVersion.get()
for _, game in ipairs({ "ruby", "sapphire" }) do
  GameVersion.set(game)
  T.eq(Opcodes.active(), rs, game .. " selects the RS decoder")
  T.eq(TextIR.dialectOf(), "rs", game .. " selects native text dialect")
  local d = TextIR.dialect("rs")
  T.eq(d.B_TXT[2], "B_PLAYER_MON1_NAME", "RS code 2 is the player mon, not COPY_VAR_1")
  T.eq(d.B_TXT_CODE.B_CURRENT_MOVE, 0x11, "RS current move code")
  T.eq(d.B_TXT_CODE.B_BUFF3, 0x2A, "RS buffer 3 code")
  local ir = TextIR.decode({ 0xFD, 8, 0xFD, 9, 0xFF }, { dialect = "rs" })
  T.eq(ir[1].name, "EVIL_TEAM", "RS code 8 is the edition's evil team")
  T.eq(ir[2].name, "GOOD_TEAM", "RS code 9 is the edition's good team")
  local V = require("src.import.gba.games." .. game)
  for _, build in ipairs(Builds[game]) do
    V.select(build.sha1)
    T.eq(V.SYMS.game, build.build, "native symbol revision")
    T.eq(V.NAMED_SCRIPTS.EventScript_TV, V.sym("Event_TV"), "TV canonical alias uses native script")
    T.eq(V.TEXT_PLACEHOLDERS.EVIL_TEAM, V.sym("gExpandedPlaceholder_" .. (game == "ruby" and "Magma" or "Aqua")), "edition's evil team")
    T.eq(V.TEXT_PLACEHOLDERS.GOOD_LEGENDARY, V.sym("gExpandedPlaceholder_" .. (game == "ruby" and "Kyogre" or "Groudon")), "edition's other legendary")
    local found
    for _, row in ipairs(V.SCRIPT_LABELS()) do if row.name == "EventScript_PC" then found = row.off end end
    T.eq(found, V.sym("EventScript_PC"), "script labels preserve the active revision")
    local tableRow
    for _, row in ipairs(V.TEXT_TABLES) do if row.name == "gBattleStringsTable" then tableRow = row end end
    T.eq(tableRow and tableRow.count, 351, "all native battle strings")
    T.eq(tableRow and tableRow.ids, 12, "RS battle table starts at ID 12")
    T.eq(V.BATTLE_STRING_IDS[380], "STRINGID_TRAINER2WINTEXT", "last native battle text ID survives")
  end
  V.select(game)
end
GameVersion.set(old)
local Versions = require("src.import.gba.versions")
for _, game in ipairs({ "ruby", "sapphire" }) do
  for _, build in ipairs(Builds[game]) do
    Versions.select(game)
    Versions.selectCache(game, { read = function() return string.format('{"version":%q,"romSha1":%q,"md5":%q}', game, build.sha1, build.sha1) end })
    T.eq(Versions.BUILD, build.build, "runtime restores cached native revision")
  end
end
local previous = Versions.BUILD
for _, raw in ipairs({ '{}', '{"romSha1":"deadbeef"}',
    string.format('{"version":"ruby","romSha1":%q}', Builds.sapphire[1].sha1),
    string.format('{"romSha1":%q,"md5":%q}', Builds.ruby[1].sha1, Builds.ruby[2].sha1) }) do
  local ok = pcall(Versions.selectCache, "ruby", { read = function() return raw end })
  T.eq(ok, false, "reject missing, unknown, conflicting or other-edition native identity")
  T.eq(Versions.BUILD, previous, "bad cache does not change selected revision")
end
Versions.select("firered")
local Plans = require("src.import.gba.plans.registry")
local plan = Plans.of("ruby")
T.eq(plan, Plans.of("sapphire"), "RS editions share a native import plan")
T.eq(plan.id, "rs", "RS does not run Emerald's plan")
for _, module in ipairs(Plans.modules(plan)) do
  T.check(not module:find("frontier", 1, true) and not module:find("mon_anim", 1, true)
    and not module:find("mystery_gift", 1, true), "RS plan excludes Emerald-only extraction")
end
T.finish("game3_rs_scripts_test")
