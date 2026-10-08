package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.load()
local GameVersion = require("src.core.GameVersion")
local OW = require("src.world.OverworldController")
local PikachuFollower = require("src.world.PikachuFollower")

Data.text._CableClubNPCWelcomeText = "WELCOME"
Data.text._CableClubNPCMakingPreparationsText = "PREPARATIONS"
Data.text._CableClubNPCPleaseApplyHereHaveToSaveText = "APPLY"
Data.text._LooksContentText = "CONTENT"

local function setUpvalue(fn, name, val)
  local i = 1
  while true do
    local n = debug.getupvalue(fn, i)
    if not n then return false end
    if n == name then debug.setupvalue(fn, i, val) return true end
    i = i + 1
  end
end

local pushed = {}
local fakeGame = {
  data = Data,
  save = { flags = { EVENT_GOT_POKEDEX = true }, party = {} },
  stack = { push = function(_, item) pushed[#pushed + 1] = item end },
}
local textBoxStub = {
  new = function(_, text, onDone, opts) return { text = text, onDone = onDone, opts = opts } end,
}
T.check(setUpvalue(OW.cableClubReceptionist, "TextBox", textBoxStub), "TextBox upvalue")
T.check(setUpvalue(OW.cableClubReceptionist, "Game", fakeGame), "Game upvalue")

local previous = GameVersion.get()
GameVersion.set("yellow")

local function talk(mapId, sleeping)
  pushed = {}
  local ow = setmetatable({ map = { id = mapId }, npcs = {}, entities = {},
                            pikachuPewterSleepScene = sleeping or nil }, { __index = OW })
  ow:cableClubReceptionist(function() end)
  return pushed[1] or {}
end

local box = talk("PEWTER_POKECENTER", true)
T.eq(box.text, "WELCOME\fPREPARATIONS",
  "Pewter with Pikachu asleep: CableClubNPC welcomes then takes the didNotConnect path")
box = talk("POKECENTER_2F", true)
T.eq(box.text, "WELCOME\fPREPARATIONS", "the shared 2F desk reads the same follower state")
box = talk("POKECENTER_2F", false)
T.eq(box.text, "WELCOME\fAPPLY", "an awake follower gets the apply prompt on 2F")
T.check(box.opts and box.opts.choice ~= nil, "and the YES/NO")
box = talk("PEWTER_POKECENTER", false)
T.eq(box.text, "WELCOME\fAPPLY", "Pewter with Pikachu awake gets the apply prompt")

local ow = { map = { id = "POKECENTER_2F" }, npcs = {}, entities = {}, pikachuPewterSleepScene = true }
PikachuFollower.onMapEntered({ save = { flags = {}, party = {} }, data = Data }, ow, nil, true)
T.eq(ow.pikachuPewterSleepScene, nil, "a map load re-enables following, so the stairs end the sleep scene")
ow.pikachuPewterSleepScene = true
PikachuFollower.onMapEntered({ save = { flags = {}, party = {} }, data = Data }, ow, nil, false)
T.eq(ow.pikachuPewterSleepScene, true, "a scripted respawn without a map load keeps it")

GameVersion.set(previous)
T.finish("union_yellow_receptionist")
