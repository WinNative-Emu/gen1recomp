package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")
local T = require("tests.harness")
local Messages = require("src.online.xgen.Messages")

local codes = { "missing_import", "policy_mismatch", "proto_mismatch", "bad_record", "species_unknown", "move_unknown",
  "egg", "mail", "item_unknown", "item_unrepresentable", "species_missing", "species_not_in_ruleset",
  "move_not_in_ruleset", "move_unsupported", "move_not_legal", "move_missing", "replacement_not_legal",
  "no_legal_moves", "no_moves", "nickname_unencodable", "ot_unencodable", "ot_invalid",
  "personality_unrepresentable", "traits_unrepresentable", "choose_sit_out", "team_too_small",
  "native_needs_same_gen", "unknown_ruleset" }
local names = { species = function(n) return n == 252 and "TREECKO" or "No." .. n end,
  move = function(m) return m == 345 and "MAGICAL LEAF" or "MOVE" .. m end }
for _, code in ipairs(codes) do
  T.check(Messages.known(code), code .. " has text")
  local detail = { national = 252, dexMax = 151, move = 345, item = "PINK BOW", need = 1, size = 3 }
  for _, line in ipairs(Messages.render(code, 1, detail, names)) do
    T.check(#line <= Messages.GB_WIDTH, code .. " Gen 1 line fits: " .. line)
    T.eq(line, line:upper(), code .. " Gen 1 line is uppercase")
  end
  local gba = Messages.render(code, 3, detail, names)
  T.eq(#gba, 1, code .. " Gen 3 is one mixed-case string")
  T.check(gba[1]:find("%l") ~= nil, code .. " Gen 3 keeps lower case")
  T.check(not gba[1]:find("{", 1, true), code .. " placeholders filled")
end
local line = table.concat(Messages.render("species_not_in_ruleset", 3, { national = 252, dexMax = 151 }, names), " ")
T.check(line:find("TREECKO", 1, true) and line:find("151", 1, true), "species and dex max rendered")
T.check(#Messages.change({ field = "ribbons", kind = "loss" }, 2) > 0, "loss renders for Gen 2")
T.check(Messages.change({ field = "ribbons", kind = "loss" }, 3)[1]:find("lost", 1, true), "loss wording")

T.eq(Messages.about("PIKACHU", "move_not_legal", { national = 25, move = 57 },
  { species = function() return "PIKACHU" end, move = function() return "SURF" end }), "PIKACHU can't learn SURF.",
  "a per-move line names the Pokemon once")
T.eq(Messages.about("PIKACHU", "move_missing", { move = 57 }, { move = function() return "SURF" end }),
  "PIKACHU: SURF doesn't exist in the other game.", "a line without the species gets the name prefix")
for _, f in ipairs({ "caughtLevel", "caughtTime", "caughtLocation", "caughtByGender", "caughtGender",
    "fatefulEncounter", "modernFatefulEncounter", "championRibbon", "extra", "egg", "eggSteps", "eggCycles" }) do
  for _, kind in ipairs({ "change", "loss" }) do
    local text = Messages.change({ field = f, kind = kind }, 3)[1]
    T.check(not text:find("Some data", 1, true), f .. " " .. kind .. " has a field name: " .. text)
    local gb = Messages.change({ field = f, kind = kind }, 1)
    for _, l in ipairs(gb) do
      T.check(#l <= Messages.GB_WIDTH and l == l:upper(), f .. " Gen 1 line fits and is uppercase: " .. l)
    end
  end
end

T.finish("xgen_messages")
