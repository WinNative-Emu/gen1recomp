package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")
local T = require("tests.harness").suite("gen2 battle rules extraction")
local Extractor = require("src.import.RomExtractorGen2")
local addresses = { Moves = 0, MoveNames = 20, MoveDescriptions = 40,
  TypeMatchups = 60, TypeNames = 80, CriticalHitChances = 100,
  AccuracyLevelMultipliers = 120, CriticalHitMoves = 150,
  FlailReversalPower = 160, PresentPower = 180, MoveEffectsPointers = 200,
  MoveEffects = 220 }
local bytes = {}
local function put(address, values)
  for index, value in ipairs(values) do bytes[address + index - 1] = value end
end
put(0, { 1, 0, 12, 0, 231, 8, 77 })
put(40, { 20, 0 })
put(60, { 255 })
put(80, { 20, 0 })
put(100, { 19, 30, 45, 60, 75, 90, 105 })
for index = 0, 12 do put(120 + index * 2, { 50 + index, 100 }) end
put(150, { 1, 255 })
put(160, { 2, 190, 4, 140, 8, 90, 16, 70, 32, 30, 48, 10 })
put(180, { 101, 41, 178, 81, 204, 121, 255 })
put(200, { 220, 0 })
put(220, { 1, 2, 255 })
local rom = {}
function rom:byte(_, address) return assert(bytes[address], tostring(address)) end
function rom:word(bank, address)
  return self:byte(bank, address) + self:byte(bank, address + 1) * 256
end
function rom:bytes(bank, address, count)
  local out = {}
  for index = 0, count - 1 do out[#out + 1] = self:byte(bank, address + index) end
  return out
end
function rom:readString() return "fixture", 1 end
local symbols = {}
for name, address in pairs(addresses) do symbols[name] = { 0, address } end
local writes = {}
local extractor = setmetatable({ rom = rom, symbols = symbols, stage = 0,
  manifest = { constants = {
    moveOrder = { "SYNTHETIC_MOVE" }, moveEffectOrder = { "SYNTHETIC_EFFECT" },
    types = { NORMAL = 0 }, battleCommandOrder = { "damagecalc", "kingsrock" },
  } }, write = function(_, name, value) writes[name] = value end,
}, Extractor)
extractor:extractMoves()
local rules = assert(writes.type_chart.battleRules, "ROM rules must be extracted")
T.eq(rules.criticalChances[0], 19, "crit chance is read from ROM")
T.eq(rules.criticalChances[6], 105, "last crit stage")
T.eq(rules.accuracyMultipliers[-6][1], 50, "negative accuracy stage")
T.eq(rules.accuracyMultipliers[6][1], 62, "positive accuracy stage")
T.eq(rules.highCriticalMoves.SYNTHETIC_MOVE, true, "crit move ID resolves")
T.eq(rules.flailPower[1][2], 190, "Flail power is ROM owned")
T.eq(rules.presentPower[3][2], 121, "Present power is ROM owned")
T.eq(#rules.presentPower, 3, "Present terminator")
T.eq(rules.moveScripts.SYNTHETIC_EFFECT[2], "kingsrock", "script commands resolve")
T.eq(writes.moves.SYNTHETIC_MOVE.accuracyRaw, 231, "accuracy byte retained")
T.eq(writes.moves.SYNTHETIC_MOVE.effectChanceRaw, 77, "secondary byte retained")
T.finish()
