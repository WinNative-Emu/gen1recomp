package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local version, seat, outFile, inFile = arg[1], tonumber(arg[2]), arg[3], arg[4]
local GameVersion = require("src.core.GameVersion")
require("src.core.game3.profile").reset()
GameVersion.set(version)
require("src.import.gba.versions").select(version)
require("src.core.game3.pokemon").install(nil)

local Json = require("src.link.Json")
local Wire = require("src.link.Wire")
local Schema = require("src.core.game3.save_schema_firered")
local Flags = require("src.core.game3.scripting.flags")
local Space = require("src.core.game3.scripting.space")
local RecordMix = require("src.core.game3.link.record_mix")

local other = version == "emerald" and "ruby" or "emerald"
local s = Schema.newGame({ version = version, name = version == "emerald" and "MAY" or "BRENDAN", rngSeed = 7 + seat })
s.trainerId, s.secretId, s.gender = 0x1000 + seat, 0, seat % 2
s.party = { { species = 1, level = 5, nickname = "", heldItem = 0 } }
Space.store = Flags.newStore()
local partners = {}
partners[seat + 1] = { seat = seat, version = version }
partners[2 - seat] = { seat = 1 - seat, version = other }

local mine = RecordMix.packet(s, seat, partners)
local text = Json.encode({ type = RecordMix.MSG.PACKET, spot = seat, packet = RecordMix.toWire(mine) })
local f = assert(io.open(outFile, "wb"))
f:write(text)
f:close()
print("bytes " .. #text)
print("layout " .. tostring(mine.recordLayout))
if not inFile then return end
local g = assert(io.open(inFile, "rb"))
local theirs = Wire.sanitize(Json.decode(g:read("*a")))
g:close()
local list = {}
list[seat + 1] = mine
list[2 - seat] = RecordMix.fromWire(theirs.packet)
local applied = RecordMix.receive(s, list, seat + 1)
print("unsupported " .. tostring(applied and applied.unsupportedReason))
for _, key in ipairs({ "secretBases", "tvShows", "pokeNews", "oldMan", "dewfordTrends", "daycareMail", "battleTower" }) do
  print(key .. " " .. tostring(applied and applied[key]))
end
