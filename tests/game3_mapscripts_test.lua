#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local function done()
  if failed > 0 then
    print("[test] FAILED " .. failed)
    os.exit(1)
  end
  print("[test] all passed")
  os.exit(0)
end

local Space = require("src.core.game3.scripting.space")

local function call(name, ...)
  if type(Space[name]) ~= "function" then return nil end
  return Space[name](...)
end

print("[test] 1. the three unrun map script slots have entry points")
check(type(Space.runOnResume) == "function", "Space.runOnResume exists")
check(type(Space.runOnWarpIntoMap) == "function", "Space.runOnWarpIntoMap exists")
check(type(Space.runOnReturnToField) == "function", "Space.runOnReturnToField exists")
check(type(Space.returnToField) == "function",
  "Space.returnToField exists (ResumeMap + ReloadObjectsAndRunReturnToFieldMapScript)")

local BattleBridge = require("src.core.game3.battle_bridge")
local Battle = require("src.core.game3.battle")

local Cache = require("tests.game3_cache")
local cacheRoot = Cache.mount("scripts/events.lua", { native = true })
if not cacheRoot then
  print("[skip] game3_mapscripts_test: " .. tostring(Cache.reason))
  done()
end
print("[info] FireRed cache at " .. cacheRoot)

local ExtractScripts = require("src.import.gba.extract_scripts")
Space.bundle = ExtractScripts.loadBundle(Cache.cache(), cacheRoot, { allowIncomplete = true })
check(Space.bundle ~= nil, "script bundle loads")

print("[test] 2. every map that owns one of the three slots decodes its body")
local resume, warpInto, returnTo, rows, undecoded = {}, {}, {}, 0, 0
for mapId, ev in pairs(Space.bundle.events or {}) do
  local ms = ev.mapScripts or {}
  if type(ms.onResume) == "string" then
    resume[#resume + 1] = mapId
    if not Space.bundle.scripts[ms.onResume] then undecoded = undecoded + 1 end
  end
  if type(ms.onReturnToField) == "string" then
    returnTo[#returnTo + 1] = mapId
    if not Space.bundle.scripts[ms.onReturnToField] then undecoded = undecoded + 1 end
  end
  if type(ms.onWarpIntoMap) == "table" and #ms.onWarpIntoMap > 0 then
    warpInto[#warpInto + 1] = mapId
    for _, row in ipairs(ms.onWarpIntoMap) do
      rows = rows + 1
      if not Space.bundle.scripts[row.script] then undecoded = undecoded + 1 end
    end
  end
end
table.sort(resume)
table.sort(warpInto)
table.sort(returnTo)
print(("[info] ON_RESUME %d, ON_WARP_INTO_MAP %d maps / %d rows, ON_RETURN_TO_FIELD %d")
  :format(#resume, #warpInto, rows, #returnTo))
check(#resume == 47, "47 maps carry ON_RESUME, got " .. #resume)
check(#warpInto == 33, "33 maps carry ON_WARP_INTO_MAP, got " .. #warpInto)
check(rows == 148, "148 ON_WARP_INTO_MAP rows, got " .. rows)
check(#returnTo == 2, "2 maps carry ON_RETURN_TO_FIELD, got " .. #returnTo)
check(undecoded == 0, "every slot's script body decoded, missing=" .. undecoded)

local Dataset = require("src.core.game3.dataset")
local Runtime = require("src.core.game3.runtime")
local Map = require("src.core.game3.map")
local Objects = require("src.core.game3.objects")
local Player = require("src.core.game3.player")
local Flags = require("src.core.game3.scripting.flags")

local game = { data = {} }
Dataset.hydrate(game)
local session = { map = "FR_PALLET_TOWN", x = 12, y = 20, facing = "down", flags = {}, vars = {} }
game.session = session
Runtime.start(nil, game, session, { reason = "new_game" })

local function warpTo(mapId, x, y, facing, opts)
  Map.load(nil, game, mapId, { x = x, y = y, facing = facing or "down",
    seamless = opts and opts.seamless, enterVia = opts and opts.enterVia })
  for _ = 1, 256 do
    if not Space.vm:isRunning() then break end
    Space.vm:tick()
  end
end
local function var(id) return Flags.getVar(Space.store, Space.vm.ctx, id) end
local function flag(id) return Flags.getFlag(Space.store, Space.vm.ctx, id) end

local VAR_MAP_SCENE_PLAYERS_HOUSE_2F = 0x4056
local VAR_TEMP_1 = 0x4001
local VAR_STARTER_MON = 0x4031
local TRAINER_CHAMPION_FIRST_SQUIRTLE = 438

print("[test] 3. ON_WARP_INTO_MAP faces the player north in the bedroom")
local BEDROOM = "FR_PLAYERS_HOUSE_2F"
Flags.setVar(Space.store, Space.vm.ctx, VAR_MAP_SCENE_PLAYERS_HOUSE_2F, 0)
warpTo(BEDROOM, 4, 1, "down")
check(Player.facing == "up",
  "the first warp in turns the player north, facing=" .. tostring(Player.facing))
check(var(VAR_MAP_SCENE_PLAYERS_HOUSE_2F) == 1,
  "the scene var advanced to 1, got " .. var(VAR_MAP_SCENE_PLAYERS_HOUSE_2F))

print("[test] 4. the table only matches once (var 1 no longer selects a row)")
warpTo("FR_PALLET_TOWN", 12, 20, "down")
warpTo(BEDROOM, 4, 1, "down")
check(Player.facing == "down",
  "a later warp in leaves the player facing where the warp put them, got "
  .. tostring(Player.facing))

print("[test] 5. a connection crossing runs ON_RESUME but never ON_WARP_INTO_MAP")
Flags.setVar(Space.store, Space.vm.ctx, VAR_MAP_SCENE_PLAYERS_HOUSE_2F, 0)
warpTo("FR_PALLET_TOWN", 12, 20, "down")
warpTo(BEDROOM, 4, 1, "down", { seamless = true })
check(var(VAR_MAP_SCENE_PLAYERS_HOUSE_2F) == 0,
  "pokefirered LoadMapFromCameraTransition has no TryRunOnWarpIntoMapScript, got "
  .. var(VAR_MAP_SCENE_PLAYERS_HOUSE_2F))
check(Player.facing == "down", "and the player is not turned")

print("[test] 6. a Continue entry skips ON_WARP_INTO_MAP too")
warpTo("FR_PALLET_TOWN", 12, 20, "down")
session.objectEvents = { mapId = BEDROOM, list = {} }
warpTo(BEDROOM, 4, 1, "down", { enterVia = "continue" })
check(var(VAR_MAP_SCENE_PLAYERS_HOUSE_2F) == 0,
  "CB2_ContinueSavedGame reaches the field through CB2_ReturnToField, got "
  .. var(VAR_MAP_SCENE_PLAYERS_HOUSE_2F))
check(session.objectEvents == nil, "the Continue entry consumes the saved object events")

print("[test] 6b. a snapshot for another map (continue-game warp) warps in like CB2_LoadMap")
warpTo("FR_PALLET_TOWN", 12, 20, "down")
session.objectEvents = { mapId = "FR_PALLET_TOWN", list = {} }
warpTo(BEDROOM, 4, 1, "down", { enterVia = "continue" })
check(var(VAR_MAP_SCENE_PLAYERS_HOUSE_2F) == 1,
  "a continue-game warp runs the target's ON_WARP_INTO_MAP, got " .. var(VAR_MAP_SCENE_PLAYERS_HOUSE_2F))
check(session.objectEvents == nil, "and the foreign snapshot is dropped")

print("[test] 6c. a save from before object events were saved runs ON_WARP_INTO_MAP once")
warpTo("FR_PALLET_TOWN", 12, 20, "down")
session.objectEvents = nil
warpTo(BEDROOM, 4, 1, "down", { enterVia = "continue" })
check(var(VAR_MAP_SCENE_PLAYERS_HOUSE_2F) == 1,
  "the legacy Continue places the scene like a warp in, got " .. var(VAR_MAP_SCENE_PLAYERS_HOUSE_2F))

print("[test] 6d. Continue restores the saved object events over the templates")
local Schema = require("src.core.game3.save_schema_firered")
local SaveData = require("src.core.SaveData")
local PALLET = "FR_PALLET_TOWN"
warpTo(BEDROOM, 4, 1, "down")
warpTo(PALLET, 12, 20, "down")
local oak = Objects.find(3)
check(oak ~= nil and oak.hidden == true, "Oak starts hidden by his template flag")
local oakFlag = oak and tonumber(oak.def and oak.def.flag) or 0
check(oakFlag ~= 0 and flag(oakFlag) == true, "and that flag is set")
local untouched = Objects.snapshot()
local u1 = untouched and untouched.list[1]
check(type(untouched) == "table" and untouched.mapId == PALLET and #untouched.list == 1 and u1 and u1.l == 1
  and u1.x == 5 and u1.y == 15 and u1.m == 7 and u1.f == "up" and u1.h == nil,
  "only the contextually placed NPC gets a row on an untouched map, got " .. tostring(untouched and #untouched.list))
Objects.addObject(3)
Objects.setObjectXY(3, 11, 9)
Objects.turnObject(3, 4)
Objects.removeObject(1)
local disk = SaveData.decode(SaveData.encode(Schema.toSaveTable(session)))
local snap = disk and disk.objectEvents
check(type(snap) == "table" and snap.mapId == PALLET and #snap.list == 2,
  "the save carries only the changed object events, got " .. tostring(snap and #snap.list))
local rows = {}
for _, r in ipairs(snap and snap.list or {}) do rows[r.l] = r end
check(rows[3] ~= nil and rows[3].x == 11 and rows[3].y == 9 and rows[3].hx == 11 and rows[3].hy == 9
  and rows[3].f == "right" and rows[3].h == nil and rows[3].m == nil and rows[3].e == nil and rows[3].i == nil,
  "Oak's row carries cell, home and facing with short keys and nothing at its template value")
check(rows[1] ~= nil and rows[1].h == 1 and rows[1].x == nil and rows[1].f == nil,
  "the removed NPC's row is just the hidden mark")
warpTo(BEDROOM, 4, 1, "down")
session.objectEvents = Schema.fromSaveTable(disk).objectEvents
warpTo(PALLET, 12, 20, "down", { enterVia = "continue" })
oak = Objects.find(3)
check(oak ~= nil and oak.visible == true and oak.hidden ~= true,
  "addobject's Oak survives Continue although his flag is set")
check(oak ~= nil and oak.cellX == 11 and oak.cellY == 9,
  "at the saved cell, got " .. tostring(oak and oak.cellX) .. "," .. tostring(oak and oak.cellY))
check(oak ~= nil and oak.facing == "right", "facing the saved way, got " .. tostring(oak and oak.facing))
local removed = Objects.find(1)
check(removed ~= nil and removed.hidden == true, "a removeobject'd NPC without a flag stays removed")
warpTo(BEDROOM, 4, 1, "down")
warpTo(PALLET, 12, 20, "down")
oak = Objects.find(3)
check(oak ~= nil and oak.hidden == true, "an ordinary warp back still builds from the templates")

print("[test] 7. the Elite Four rooms share the same turn-north ON_WARP_INTO_MAP")
local LORELEI = "FR_POKEMON_LEAGUE_LORELEIS_ROOM"
warpTo("FR_PALLET_TOWN", 12, 20, "down")
warpTo(LORELEI, 6, 11, "down")
check(Player.facing == "up",
  "Lorelei's room turns the player north on entry, facing=" .. tostring(Player.facing))

print("[test] 8. ON_RESUME runs on map enter (Union Room hides the link NPCs)")
local UNION = "FR_UNION_ROOM"
if Space.bundle.events[UNION] and game.data.maps[UNION] then
  warpTo("FR_PALLET_TOWN", 12, 20, "down")
  warpTo(UNION, 5, 8, "down")
  local set = 0
  for fid = 99, 106 do
    if flag(fid) then set = set + 1 end
  end
  check(set == 8, "ON_RESUME set all 8 union-room flags, got " .. set)
  local eo = Objects.find(3)
  check(eo == nil or eo.visible == false,
    "ON_RESUME removed union-room object 3")
else
  check(false, "FR_UNION_ROOM is in the bundle and the map set")
end

print("[test] 9. ON_RESUME on return to field stops the Champion scene re-firing")
local CHAMPION = "FR_POKEMON_LEAGUE_CHAMPIONS_ROOM"
warpTo("FR_PALLET_TOWN", 12, 20, "down")
warpTo(CHAMPION, 6, 12, "down")
check(Player.facing == "up", "VAR_TEMP_1 is 0 on entry, so the room turns the player north")
check(var(VAR_TEMP_1) == 0, "and the ON_FRAME trigger var is still 0")
Flags.setVar(Space.store, Space.vm.ctx, VAR_STARTER_MON, 2)
Flags.setFlag(Space.store, Space.vm.ctx,
  Flags.trainerFlagId(TRAINER_CHAMPION_FIRST_SQUIRTLE), true)
check(call("returnToField") == true, "returnToField reports the Champion ON_RESUME ran")
check(var(VAR_TEMP_1) == 1,
  "a beaten Champion sets VAR_TEMP_1 so the entry scene cannot replay, got "
  .. var(VAR_TEMP_1))

print("[test] 10. ON_RETURN_TO_FIELD re-adds the Trainer Tower lobby staff")
local LOBBY = "FR_TRAINER_TOWER_LOBBY"
if Space.bundle.events[LOBBY] and game.data.maps[LOBBY] then
  warpTo("FR_PALLET_TOWN", 12, 20, "down")
  warpTo(LOBBY, 9, 10, "down")
  local present = 0
  for lid = 1, 5 do
    local eo = Objects.find(lid)
    if eo and eo.visible then present = present + 1 end
  end
  check(present > 0, "the lobby spawns its staff, got " .. present)
  Objects.removeObject(3)
  local gone = Objects.find(3)
  check(gone == nil or gone.visible == false, "removeobject hid the receptionist")
  check(call("runOnReturnToField") == true, "ON_RETURN_TO_FIELD ran on the lobby")
  local back = Objects.find(3)
  check(back ~= nil and back.visible == true,
    "SpawnObjectEventsOnReturnToField + addobject brought the receptionist back")
else
  check(false, "FR_TRAINER_TOWER_LOBBY is in the bundle and the map set")
end

print("[test] 11. the immediate context does not disturb a waiting field script")
warpTo("FR_PALLET_TOWN", 12, 20, "down")
warpTo(CHAMPION, 6, 12, "down")
Space.vm.scripts["g3:test_waiting"] = {
  { op = "lockall" },
  { op = "delay", 1, delay = 240 },
  { op = "end" },
}
Space.vm:start("g3:test_waiting")
check(Space.vm:isRunning() == true, "a field script is parked on delay")
local key = Space.vm._scriptKey
check(call("runOnResume") == true, "ON_RESUME still runs while it waits")
check(Space.vm:isRunning() == true and Space.vm._scriptKey == key,
  "and the parked field script is untouched")
Space.vm:halt(true)

print("[test] 12. the battle return itself runs ON_RETURN_TO_FIELD")
local Party = require("src.core.game3.party")
Party.giveMon(session, 150, 100)
warpTo("FR_PALLET_TOWN", 12, 20, "down")
warpTo(LOBBY, 9, 10, "down")
Objects.removeObject(3)
local hidden = Objects.find(3)
check(hidden == nil or hidden.visible == false, "the receptionist is off the map again")
check(BattleBridge.start(nil, game, { species = 100, level = 34 },
  { wild = true, headless = true, fade = false }) == true, "a battle starts in the lobby")
if Battle.isActive and Battle.isActive() then BattleBridge.finishPending("win") end
for _ = 1, 256 do
  if not Space.vm:isRunning() then break end
  Space.vm:tick()
end
local returned = Objects.find(3)
check(returned ~= nil and returned.visible == true,
  "battle_bridge finish() ran the return-to-field map scripts and addobject put her back")

print("[test] 13. Game3:_enterField runs ON_RETURN_TO_FIELD on Continue")
local Game3 = require("src.core.Game3")
local ModRuntime = require("src.mods.Runtime")
local started = {}
local bus = { listeners = { ["script.started"] = true } }
function bus:emit(name, payload)
  if name == "script.started" and payload and payload.key then started[payload.key] = true end
end
function bus:removeOwner() end
local hooks = { call = function(_, _, vanilla, ...) return vanilla(...) end, removeOwner = function() end }
ModRuntime.install(bus, hooks)
local continued = { map = LOBBY, x = 9, y = 10, facing = "down", flags = {}, vars = {}, party = {} }
local okEnter = pcall(function() Game3.new():_enterField(continued, "continue") end)
ModRuntime.reset()
check(okEnter == true, "the Continue entry reached the field")
local lobbyReturnKey = Space.bundle.events[LOBBY].mapScripts.onReturnToField
check(started[lobbyReturnKey] == true,
  "the lobby's ON_RETURN_TO_FIELD script ran on Continue, key=" .. tostring(lobbyReturnKey))

done()
