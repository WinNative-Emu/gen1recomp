-- #2748: completing Mossdeep Gym before Matt must not strand the hideout story.
package.path = './?.lua;./?/init.lua;' .. package.path
local T = require('tests.harness')
local check, eq = T.check, T.eq
local GameVersion = require('src.core.GameVersion')
GameVersion.set('emerald')
local Profile = require('src.core.game3.profile')
Profile.reset()
local C = require('src.core.game3.constants').of('emerald')
local Flags = require('src.core.game3.scripting.flags')
local Vm = require('src.core.game3.scripting.vm')
local Adapters = require('src.core.game3.scripting.adapters')
local Space = require('src.core.game3.scripting.space')
local Objects = require('src.core.game3.objects')
local Player = require('src.core.game3.player')
local Field = require('src.core.game3.field')
local Collision = require('src.core.game3.collision')
local Trainers = require('src.core.game3.scripting.trainers')
-- Avoid an unrelated ROM party dependency; this test exercises VM continuation,
-- not battle simulation. The result comes from an explicit battle callback.
Trainers._pack = { trainers = {} }
local Schema = require('src.core.game3.save_schema_firered')
local HIDE = C.flags.byName.FLAG_HIDE_AQUA_HIDEOUT_GRUNTS
local ESCAPED = C.flags.byName.FLAG_TEAM_AQUA_ESCAPED_IN_SUBMARINE
local BADGE = C.flags.byName.FLAG_BADGE07_GET
local SUB_HIDE = C.flags.byName.FLAG_HIDE_AQUA_HIDEOUT_B2F_SUBMARINE_SHADOW
local MATT = C.trainers.byName.TRAINER_MATT
local MAP = 'EM_AQUA_HIDEOUT_B2F'
local mapDef = { midLayout = { width = 40, height = 25 } }
-- Canonical template and flag operations from pokeemerald data/maps/
-- AquaHideout_B2F/{map.json,scripts.inc} and MossdeepCity_Gym/scripts.inc.
local objects = {
  { localId = 1, graphicsId = 117, x = 23, y = 19, elevation = 3,
    movementType = 9, trainerType = 0, scriptKey = 'matt', flag = HIDE },
  { localId = 2, graphicsId = 117, x = 23, y = 10, movementType = 45, flag = HIDE },
  { localId = 4, graphicsId = 141, x = 19, y = 20, elevation = 1,
    movementType = 9, flag = SUB_HIDE },
}
local scripts = {
  gym = {
    { op = 'setflag', [1] = BADGE }, { op = 'setflag', [1] = HIDE }, { op = 'end' },
  },
  matt = {
    { op = 'trainerbattle', type = 2, trainer = MATT, localId = 0, eventScript = 'escape' },
    { op = 'end' },
  },
  escape = {
    { op = 'setvar', [1] = 0x8009, [2] = 4 },
    { op = 'removeobject', [1] = 0x8009 },
    { op = 'setflag', [1] = ESCAPED }, { op = 'end' },
  },
}
local movements = {}
local root = os.getenv('POKEPORT_EMERALD_CACHE')
if root and root ~= '' then
  local function loadRel(name)
    return assert(loadfile(root .. '/data/generated/gba/scripts/' .. name .. '.lua'))()
  end
  local imported, events, labels = loadRel('scripts'), loadRel('events'), loadRel('labels')
  movements = loadRel('movements')
  local ev = assert(events[MAP])
  objects = ev.objects
  eq(objects[1].localId, 1, 'ROM Matt local id')
  eq(objects[1].flag, HIDE, 'ROM Matt uses the shared hideout-grunts hide flag')
  eq(objects[1].x, 23, 'ROM Matt x')
  eq(objects[1].y, 19, 'ROM Matt y')
  local gymKey = assert(labels.MossdeepCity_Gym_EventScript_TateAndLizaDefeated)
  local gymFlags = {}
  for _, row in ipairs(assert(imported[gymKey])) do
    if row.op == 'setflag' and (row[1] == BADGE or row[1] == HIDE) then
      gymFlags[#gymFlags + 1] = row
    end
  end
  eq(#gymFlags, 2, 'ROM gym defeat script sets both Mind Badge and shared hide flag')
  gymFlags[#gymFlags + 1] = { op = 'end' }
  -- Execute the exact imported flag writes, without unrelated gym UI/specials.
  imported.gym = gymFlags
  imported['std:4'] = { { op = 'return' } } -- instant msgbox adapter for headless VM
  scripts = imported
  print('[info] canonical Emerald B2F scripts from ' .. root)
else
  print('[info] ROM-free canonical flag/continuation fixture (set POKEPORT_EMERALD_CACHE for full B2F scripts)')
end
local bundle = { events = { [MAP] = { objects = objects } }, scripts = scripts, movements = movements }
local battles, removed, moves, result = 0, {}, {}, 'win'
local function legacySave()
  return { version = 'emerald', map = MAP, x = 24, y = 19, facing = 'left',
    flags = { [tostring(BADGE)] = true, [tostring(HIDE)] = true }, vars = {} }
end
local function adapter()
  return Adapters.stub({
    startTrainerBattle = function(foe, done, opts)
      battles = battles + 1
      eq(opts.trainerId, MATT, 'interaction starts Matt battle')
      eq(foe.trainerId, MATT, 'Matt foe routes through trainer lookup')
      done(result)
    end,
    lookupMovement = function(k) return movements[k] end,
    applyMovement = function(lid, actions)
      moves[#moves + 1] = { lid = lid, actions = actions }
    end,
    pollMovement = function() return true end,
    removeObject = function(lid) removed[#removed + 1] = lid; Objects.removeObject(lid) end,
    onFlagChanged = function(id, hidden) Objects.syncFlagVisibility(id, hidden) end,
  })
end
local function bind(store)
  Space.store, Space.bundle, Space.mapId, Space.active = store, bundle, MAP, true
  Space.vm = Vm.new({ version = 'emerald', store = store, scripts = scripts, adapters = adapter() })
  Field._session = store
  Field._game = { data = {} }
  Field.running = true
  Field.unlock()
  Collision._mapDef = nil
end
local function drain(vm)
  for _ = 1, 2048 do if not vm:isRunning() then break end; vm:tick() end
  check(not vm:isRunning(), 'VM completed bounded script drain')
end
local function enter(store, keepTemps)
  bind(store)
  Flags.onMapLoad(store, keepTemps)
  Objects.reset()
  Objects.loadMap(nil, MAP, mapDef)
  Player.reset(24, 19, 'left')
end
local function drawable(lid)
  for _, eo in ipairs(Objects.forDraw()) do if eo.localId == lid then return true end end
  return false
end
local function accessible(label)
  local matt = Objects.find(1)
  check(matt and matt.visible and not matt.hidden and not matt.invisible, label .. ': Matt visible')
  check(drawable(1), label .. ': Matt in draw list')
  check(Objects.at(23, 19) == matt, label .. ': Matt selectable for field interaction')
end
local fresh = Flags.newStore()
enter(fresh)
accessible('normal pre-gym visit')
-- Source-local reproducer: the canonical gym writes have no escape prerequisite.
Space.vm:start('gym'); drain(Space.vm)
check(Flags.getFlag(fresh, nil, BADGE), 'gym awarded Mind Badge')
check(Flags.getFlag(fresh, nil, HIDE), 'gym set the shared hideout flag')
check(not Flags.getFlag(fresh, nil, ESCAPED), 'gym does not complete Matt submarine escape')
-- Capture the old, hidden template snapshot before repairing its flag store.
Objects.reset()
Objects.loadMap(nil, MAP, mapDef)
local legacySnapshot = Objects.snapshot()
check(Objects.find(1).hidden, 'unrepaired gym flag is the source of Matt hiding')
-- This is where the original implementation strands the player.
enter(fresh)
accessible('out-of-order gym completion')
check(not Flags.getFlag(fresh, nil, ESCAPED), 'recovery does not invent story completion')
check(Flags.getFlag(fresh, nil, BADGE), 'recovery preserves earned badge')
check(not Flags.isTrainerDefeated(fresh, nil, MATT), 'recovery does not invent Matt victory')
local serialized = Flags.serialize(fresh)
local restored = Flags.newStore()
Flags.loadInto(restored, serialized)
enter(restored, true)
accessible('save/continue')
local snap = Objects.snapshot()
enter(restored, true)
check(Objects.restoreSnapshot(snap), 'object snapshot restored on same map')
accessible('object snapshot restore')
check(Objects.restoreSnapshot(legacySnapshot), 'pre-repair hidden-template snapshot accepted')
accessible('legacy object snapshot restore')
-- Test the actual Lua save decoder as well as the script-side flag store.
local oldSave = legacySave()
oldSave.objectEvents = legacySnapshot
local decoded = Schema.fromSaveTable(oldSave)
check(not Flags.getFlag(decoded, nil, HIDE), 'Lua save decoder repairs legacy early-gym flags')
check(Flags.getFlag(decoded, nil, BADGE), 'Lua save decoder preserves Mind Badge')
check(not Flags.getFlag(decoded, nil, ESCAPED), 'Lua save decoder does not grant escape')
local luaRoundtrip = Schema.fromSaveTable(Schema.toSaveTable(decoded))
check(not Flags.getFlag(luaRoundtrip, nil, HIDE), 'recovery survives Lua save export/reimport')
local sidecar = Flags.newStore()
Flags.loadInto(sidecar, legacySave())
check(not Flags.getFlag(sidecar, nil, HIDE), 'legacy script-side flag store repairs on loadInto')
-- Exercise the real field interaction entry point, not a direct escape flag edit.
check(Field.interact(Field._game), 'A-button interaction accepts Matt')
drain(Space.vm)
eq(battles, 1, 'one Matt battle started')
check(Flags.isTrainerDefeated(restored, nil, MATT), 'win records Matt defeat')
check(Flags.getFlag(restored, nil, ESCAPED), 'win continuation completes submarine escape')
eq(removed[#removed], 4, 'continuation removes submarine localId4, not Matt')
if root and root ~= '' then
  eq(#moves, 5, 'full imported escape continuation applies all five movements')
  local submarineMoved = false
  for _, move in ipairs(moves) do if move.lid == 4 then submarineMoved = true end end
  check(submarineMoved, 'VAR_0x8009 movement resolves to submarine localId4')
end
enter(restored)
check(Flags.getFlag(restored, nil, HIDE), 'completed gym plus completed escape restores late-story hiding')
check(not drawable(1) and Objects.at(23, 19) == nil, 'post-story Matt remains hidden/unselectable')
-- Cover all four ordering states and idempotence without rewriting unrelated data.
for _, badge in ipairs({ false, true }) do
  for _, escaped in ipairs({ false, true }) do
    local store = Flags.newStore()
    Flags.setFlag(store, nil, BADGE, badge)
    Flags.setFlag(store, nil, ESCAPED, escaped)
    Flags.setFlag(store, nil, HIDE, badge)
    Flags.setFlag(store, nil, 0x430, true)
    Flags.setVar(store, nil, 0x4048, 123)
    enter(store)
    local expectedHidden = badge and escaped
    eq(Objects.find(1).hidden, expectedHidden,
      'visibility matches completed gym/escape: ' .. tostring(badge) .. '/' .. tostring(escaped))
    check(Flags.getFlag(store, nil, 0x430), 'unrelated item flag preserved')
    eq(Flags.getVar(store, nil, 0x4048), 123, 'unrelated ash variable preserved')
    enter(store)
    eq(Objects.find(1).hidden, expectedHidden, 'repeated map entry is idempotent')
  end
end
-- Losing must not resolve the pending story or hide Matt on re-entry.
local losing = Flags.newStore()
Flags.setFlag(losing, nil, BADGE, true)
Flags.setFlag(losing, nil, HIDE, true)
enter(losing)
result = 'lose'
check(Field.interact(Field._game), 'losing encounter can still start')
drain(Space.vm)
eq(battles, 2, 'second Matt battle invokes the losing callback')
check(not Flags.getFlag(losing, nil, ESCAPED), 'loss does not advance escape')
check(not Flags.isTrainerDefeated(losing, nil, MATT), 'loss does not record Matt victory')
enter(losing)
accessible('retry after loss')
-- Without the gym marker, do not overwrite explicit/custom hiding.
local explicit = Flags.newStore()
Flags.setFlag(explicit, nil, HIDE, true)
Flags.onMapLoad(explicit)
check(Flags.getFlag(explicit, nil, HIDE), 'no Mind Badge: unrelated/custom hiding is preserved')
-- Numeric, decimal-string and hexadecimal keys all occur in imported/old saves.
for _, key in ipairs({ HIDE, tostring(HIDE), string.format('0x%X', HIDE) }) do
  local store = { flags = { [BADGE] = true, [key] = true }, vars = {} }
  Flags.onMapLoad(store, true)
  check(not Flags.getFlag(store, nil, HIDE), 'early-gym repair clears hide flag key ' .. tostring(key))
end
for _, version in ipairs({ 'firered', 'leafgreen', 'ruby', 'sapphire' }) do
  GameVersion.set(version)
  local store = Flags.newStore()
  Flags.loadInto(store, legacySave())
  check(Flags.getFlag(store, nil, HIDE), version .. ': same numeric flags are not subjected to Emerald recovery')
end
GameVersion.set('emerald')
local quick = assert(io.open('tests/quick.list', 'r'))
local list = quick:read('*a'); quick:close()
check(list:find('tests/emerald_matt_2748_test.lua', 1, true) ~= nil, 'regression registered in quick suite')
T.finish()
