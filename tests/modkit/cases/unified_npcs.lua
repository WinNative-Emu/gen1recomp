package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.harness").suite("unified NPCs")
local Runtime = require("src.mods.Runtime")
local Hooks = require("src.mods.Hooks")
local Events = require("src.mods.Events")
local GameVersion = require("src.core.GameVersion")
local Compat = require("src.mods.Gen3Compat")
local UnifiedWorld = require("src.mods.UnifiedWorld")
local NativeWorld = require("src.world.game3.WorldAPI")
local Data = require("src.core.Data")
local MapScripts = require("src.script.MapScripts")
local FrlgFont = require("src.ui.game3.frlg_font")
local savedRuntime = { Runtime.events, Runtime.hooks, Runtime.errors }
local savedVersion = GameVersion.get()
local savedMapScripts = Data.map_scripts
local savedModules = {}
local function install(name, value)
  if not savedModules[name] then savedModules[name] = { package.loaded[name] } end
  package.loaded[name] = value
end

install("src.import.gba.map_catalog", { groupNumFor = function() return 1, 1 end })
install("src.ui.game3.rs.font_faces", { load = function(_, name, language, _, _, _, textMode)
  local widths, quads = {}, {}
  for glyph = 0, 511 do
    widths[glyph] = textMode == 1 and 8 or 6
    quads[glyph] = love.graphics.newQuad(glyph % 16 * 16,
      math.floor(glyph / 16) * 16, widths[glyph], 16, 256, 512)
  end
  return { name = name, language = language, nativeIndexed = true,
    fg = love.graphics.newCanvas(256, 512), sh = love.graphics.newCanvas(256, 512),
    widths = widths, quads = quads, boundaryQuads = {}, glyphs = 512,
    height = 16, pitch = 16, letterSpacing = 0 }
end })
FrlgFont.invalidate()
Data.map_scripts = {}
local Objects = require("src.core.game3.objects")
local Collision = require("src.core.game3.collision")
local Player = require("src.core.game3.player")
local Field = require("src.core.game3.field")
local Message = require("src.ui.game3.message")
local Prepare = require("src.core.game3.object_prepare")

local function rejected(value, reason, label)
  T.eq(value, nil, label .. " returns nil")
  T.check(type(reason) == "string" and #reason > 0, label .. " explains refusal")
end

local function contains(list, value)
  for _, entry in ipairs(list) do if entry == value then return true end end
  return false
end

local function actor(id, pool)
  for _, lid in ipairs(pool and pool.order or Objects._order) do
    local eo = (pool and pool.byId or Objects._byId)[lid]
    if eo and eo.id == id then return eo end
  end
end

local function nativeTalkToken()
  local token
  for lock in pairs(Field._locks) do
    if type(lock) == "table" and lock.scriptHandle then
      assert(token == nil, "registered talk owns a unique native field token")
      token = lock
    end
  end
  return token
end

local function mapDef(id)
  local layout = { width = 12, height = 12, pair = "unified_npcs" }
  function layout:elevAt() return 3 end
  function layout:collAt() return 0 end
  function layout:midAt() return 0 end
  function layout:collArray()
    local cells = {}
    for i = 1, self.width * self.height do cells[i] = 0 end
    return cells
  end
  return { id = id, width = 12, height = 12, midLayout = layout,
    pair = layout.pair, warps = {}, objects = {
      { index = 1, localId = 1, name = "IMPORTED", x = 8, y = 8,
        graphicsId = 16, movementType = 8, flag = 77 },
    } }
end

for _, version in ipairs({ "firered", "leafgreen", "ruby", "sapphire", "emerald" }) do
  GameVersion.set(version)
  Objects.reset()
  Message.close()
  local home, away = "NPC_HOME", "NPC_AWAY"
  local maps = { [home] = mapDef(home), [away] = mapDef(away) }
  local pristine = Prepare.freeze({ maps[home].objects, maps[away].objects })
  local save = { version = version, map = home, flags = {}, vars = {}, party = {},
    position = {}, options = {} }
  local game = { phase = "field", save = save, session = save, data = {
    maps = maps, text = { NPC_HELLO = "Hello from the native field." },
    gen3Text = { NPC_OTHER = "A second native greeting." },
    sprites = { SPRITE_YOUNGSTER = {}, SPRITE_LASS = {} },
  } }
  local live = game
  local errors, hooks, events = {}, Hooks.new(), Events.new()
  Runtime.install(events, hooks, errors)
  Compat.bind(function() return live end)
  local map = { current = home, world = {} }
  function map.currentDef() return maps[map.current] end
  local space = { active = true, mapId = home, store = { flags = {}, vars = {} },
    bundle = { events = { [home] = { objects = maps[home].objects },
      [away] = { objects = maps[away].objects } }, text = {} },
    vm = { isRunning = function() return false end, tick = function() end },
    runOnFrame = function() end,
    startScript = function() error("fixture has no ROM scripts") end,
  }
  function space.ensureBundle() return space.bundle end
  install("src.core.game3.scripting.space", space)
  install("src.core.game3.map", map)
  install("src.core.game3.runtime", { session = save,
    getSession = function() return live and live.session end,
    uiBusy = function() return Message.isOpen() end,
  })
  Field.running, Field._game, Field._session = true, game, save
  Field._locks = {}
  Player.cellX, Player.cellY, Player.facing = 2, 3, "right"
  Player.targetX, Player.targetY = 2, 3
  Player.moving, Player.surfing, Player.boulderPush = false, false, nil
  local function load(id)
    map.current, save.map, space.mapId = id, id, id
    local currentGame = live or game
    currentGame.session.map = id
    Collision.bindMap(currentGame, id, maps[id])
    Objects.loadMap(currentGame, id, maps[id])
  end
  load(home)
  local api = UnifiedWorld.new(function() return live end, 3, version, "npc_probe")
  local other = UnifiedWorld.new(function() return live end, 3, version, "other_probe")
  local native = NativeWorld.new(game, "npc_probe")
  local spawned = {}
  local stopSpawn = events:on("world.npc_spawned", function(payload)
    if type(payload.npcId) == "string" then spawned[#spawned + 1] = payload end
  end)
  local def = { name = "GUIDE", x = 3, y = 3, sprite = "SPRITE_YOUNGSTER",
    movement = "STAY", facing = "LEFT", text = "NPC_HELLO",
    radius = { x = 1, y = 1 }, extra = { marker = "original" } }
  local id, why = api:spawnNpc(home, def)
  T.check(type(id) == "string", version .. " spawns through the unified/native adapters: " .. tostring(why))
  T.check(type(id) == "string" and id:match("^" .. home .. "_obj_%d+$") ~= nil,
    version .. " retains the Gen 1 public ID shape")
  local eo = actor(id)
  T.check(eo ~= nil, version .. " spawn enters the actual native actor store")
  assert(eo, "native runtime actor required for behavioral checks")
  T.check(eo.localId > 1 and eo.localId < 0xC0, "allocation avoids templates and reserved local IDs")
  T.eq(Objects.find(eo.localId), eo, "native localId lookup reaches the actor")
  T.eq(Objects.at(3, 3), eo, "native interaction lookup reaches the actor")
  T.check(contains(Objects._order, eo.localId), "actor belongs to native update order")
  T.check(contains(Objects.forDraw(), eo), "actor belongs to native draw collection")
  T.eq(Objects.blocks(3, 3), true, "runtime actor participates in native collision")
  T.eq(eo.sprite, "SPRITE_YOUNGSTER", "Gen 1 sprite reaches the native actor")
  T.eq(eo.facing, "left", "Gen 1 facing reaches the native actor")
  T.eq(eo.movement, "STAY", "Gen 1 movement reaches the native actor")
  T.eq(eo.owner, "npc_probe", "native actor retains mod ownership")
  T.eq(#spawned, 1, "actual materialization emits one native spawn event")
  T.eq(spawned[1].npcId, id, "spawn event uses the stable public ID")
  T.eq(spawned[1].runtime, eo, "spawn event identifies the actual actor")
  T.eq(spawned[1].mapId, home, "spawn event identifies the native map")
  def.x, def.radius.x, def.extra.marker = 9, 9, "changed"
  T.eq(eo.cellX, 3, "caller coordinate mutation cannot move the actor")
  T.eq(eo.def.radius.x, 1, "nested radius is detached from the caller")
  T.eq(eo.def.extra.marker, "original", "nested definition data is detached")
  T.eq(Objects.runtimeByMap[home][1].extra.marker, "original", "runtime registry owns its definition")
  T.eq(def.id, nil, "spawn leaves the caller definition untouched")
  T.same({ maps[home].objects, maps[away].objects }, pristine, "spawn never appends to ROM templates")

  local handle = api:npc(home, id)
  assert(handle, "unified native NPC handle required")
  T.eq(handle.id, id, "unified handle exposes the Gen 1 public ID")
  T.eq(native:npc(home, id).id, id, "native handle exposes the same ID")
  T.eq(api:npc(home, "GUIDE").id, id, "name lookup resolves the runtime actor")
  T.eq(api:npc(home, eo.def.index).id, id, "index lookup resolves the runtime actor")
  T.eq(handle:face("up"), true, "portable face dispatch succeeds")
  T.eq(eo.facing, "up", "face changes the actual native actor")
  T.eq(handle:setAppearance("SPRITE_LASS"), true, "inherited appearance operation succeeds")
  T.eq(eo.sprite, "SPRITE_LASS", "appearance changes the drawable actor")
  T.eq(eo.graphicsId, nil, "sprite appearance clears the native graphics override")
  T.eq(handle:placeAt(4, 4, "right"), true, "portable placement succeeds")
  local x, y = handle:position()
  T.eq(x, 4, "position reads native x")
  T.eq(y, 4, "position reads native y")
  T.eq(eo.px, 64, "placement changes native pixel coordinates")
  T.eq(Objects.at(4, 4), eo, "placement changes the interaction pool position")
  T.eq(handle:setPassable(true), true, "portable passability succeeds")
  T.eq(Objects.blocks(4, 4), false, "passability changes native collision")
  T.eq(handle:setPassable(false), true, "native collision can be restored")
  local completed = 0
  T.eq(handle:scriptMove("right", 2, function() completed = completed + 1 end), true,
    "portable route starts a native movement track")
  T.check(Objects._tracks[eo.localId] ~= nil, "route is stored by actual localId")
  T.eq(handle:isMoving(), true, "native actor starts stepping")
  Objects.update(game)
  T.check(eo.px > 64, "native update advances actual actor pixels")
  Objects.loadMap(game, home, maps[home])
  T.eq(actor(id), eo, "same-map reload retains the runtime actor")
  T.eq(#Objects._order, 2, "same-map reload has no duplicate runtime entry")
  T.eq(#spawned, 1, "same-map reload does not announce an existing actor again")
  for _ = 1, 80 do Objects.update(game) end
  T.eq(eo.cellX, 6, "native route completes both steps")
  T.eq(eo.cellY, 4, "native route keeps the other coordinate")
  T.eq(completed, 1, "native route completion runs once")
  T.eq(handle:isMoving(), false, "native route finishes motion")
  Objects.unfreeze(eo.localId)

  T.eq(handle:placeAt(3, 3, "up"), true, "place the native actor for actual field interaction")
  local talks, interactions = 0, 0
  local stopTalk = hooks:wrap("world.talk", function(nextFn, ownerGame, target)
    talks = talks + 1
    T.eq(ownerGame, game, "native talk hook receives the live game")
    T.eq(target, eo, "native talk hook receives the actual actor")
    local result = nextFn(ownerGame, target)
    T.eq(nextFn(ownerGame, target), result, "repeated continuation preserves the talk result")
    return result
  end, 0, "npc_probe")
  local stopInteract = events:on("world.interacted", function(payload)
    interactions = interactions + 1
    T.eq(payload.target, eo, "native interaction event contains the actor")
    T.eq(payload.kind, "npc", "native interaction event has the NPC kind")
    T.eq(payload.mapId, home, "native interaction event has the active map")
  end)
  T.eq(Field.interact(game), true, "real Field.interact opens runtime NPC text")
  T.eq(Message.currentPage(), game.data.text.NPC_HELLO, "actual native message resolves Gen 1 text keys")
  T.eq(Message.isOpen(), true, "actual native message is open")
  T.eq(Field.locked, true, "native dialogue locks field input")
  T.eq(eo.frozen, true, "native dialogue freezes its actor")
  T.eq(eo.facing, "left", "native dialogue faces the player")
  T.eq(talks, 1, "field interaction raises one talk hook")
  T.eq(interactions, 1, "field interaction raises one native event")
  T.eq(Field.interact(game), false, "open dialogue refuses interaction reentry")
  local finish = Message._done
  T.check(type(finish) == "function", "native dialogue installs a completion callback")
  Message.close()
  T.eq(Field.locked, false, "native message completion unlocks field input")
  T.eq(eo.frozen, false, "native message completion restores actor movement")
  finish()
  T.eq(Field.locked, false, "repeated native completion stays unlocked")
  T.eq(Message.isOpen(), false, "repeated native completion does not reopen text")
  stopTalk()
  stopInteract()
  for _, text in ipairs({ "NPC_OTHER", "A literal native greeting." }) do
    eo.def.text = text
    T.eq(Field.interact(game), true, "native field accepts Gen 3 text keys and literal text")
    T.eq(Message.currentPage(), game.data.gen3Text[text] or text, "native printer resolves the requested text")
    Message.close()
    T.eq(Field.locked, false, "each native dialogue completion releases its field lock")
  end

  local rows = { { "show_text", "First registered greeting." },
    { "show_text", "Second registered greeting." }, { "set_flag", "mod:talk_done" } }
  local pristineRows = Prepare.freeze(rows)
  local contribution = { talk = { NPC_SCRIPT = rows,
    NPC_CANCEL = { { "show_text", "Cancel this greeting." },
      { "set_flag", "mod:talk_cancelled" } } } }
  Data.map_scripts[home] = { contribution, owners = { { modId = "script_probe" } } }
  MapScripts.invalidate(home)
  local function update(action)
    return hooks:call("core.update", function(owner)
      T.eq(owner, game, "script continuation receives the native game")
      if action then action() end
      return "updated"
    end, game, 1 / 60)
  end
  eo.def.text = "NPC_SCRIPT"
  T.eq(Field.interact(game), true, "native field starts the registered talk script")
  local token = nativeTalkToken()
  assert(type(token) == "table" and token.scriptHandle, "registered talk owns a native field token")
  local scriptHandle = token.scriptHandle
  T.eq(scriptHandle:isRunning(), true, "registered talk keeps its native bridge running")
  T.eq(Message.currentPage(), rows[1][2], "registered talk opens its first native message")
  T.eq(Field.locked, true, "registered talk retains its own field lock")
  T.eq(eo.frozen, true, "registered talk freezes its native actor")
  T.eq(hooks.chains["core.update"][1].owner, "script_probe", "continuation belongs to the script contributor")
  local firstDone = Message._done
  assert(type(firstDone) == "function", "registered first message requires native completion")
  T.eq(update(function()
    Message.close()
    T.eq(Message.isOpen(), false, "native completion waits for update to unwind")
    T.eq(Field.locked, true, "between script rows player input stays locked")
  end), "updated", "script continuation preserves the native update result")
  T.eq(Message.currentPage(), rows[2][2], "second native message starts after update")
  firstDone()
  T.eq(Message.currentPage(), rows[2][2], "duplicate first completion cannot replace the second message")
  local secondDone = Message._done
  assert(type(secondDone) == "function", "registered second message requires native completion")
  update(function()
    Message.close()
    T.eq(save.modData, nil, "private flag waits until the native update unwinds")
  end)
  T.eq(save.modData.script_probe.worldFlags.talk_done, true, "registered script writes its contributor's private flag")
  T.eq(save.modData.npc_probe, nil, "script flags do not use the NPC owner's bucket")
  update()
  T.eq(scriptHandle:isRunning(), false, "registered talk completes after its final row")
  T.eq(token.done, true, "registered talk completes its field token")
  T.eq(Field.locked, false, "registered talk completion releases field input")
  T.eq(eo.frozen, false, "registered talk completion restores native actor movement")
  secondDone()
  token.finish()
  T.eq(update(), "updated", "updates continue after duplicate script completion")
  T.eq(hooks.chains["core.update"], nil, "completed talk retires its continuation")
  T.eq(Message.isOpen(), false, "duplicate script completion cannot reopen dialogue")
  T.same(rows, pristineRows, "registered talk leaves the original script rows unchanged")

  local doneCalls = 0
  local direct, directReason = Compat.runTalkScript(rows, { game = game, mapId = home,
    owner = "npc_probe", source = { modId = "script_probe" }, onDone = function(ok, err)
      doneCalls = doneCalls + 1
      T.eq(ok, true, "native script completion reports success")
      T.eq(err, nil, "native script completion has no failure reason")
    end })
  assert(direct, "native completion probe requires a bridge: " .. tostring(directReason))
  Message.close()
  update()
  local directDone = Message._done
  assert(type(directDone) == "function", "completion probe requires a second native callback")
  Message.close()
  update()
  update()
  directDone()
  direct:cancel()
  update()
  T.eq(doneCalls, 1, "native script completion runs exactly once despite repeated completion and cancellation")

  local cancelCalls, cancelReason = 0, "native talk cancelled explicitly"
  local explicit, explicitReason = Compat.runTalkScript(contribution.talk.NPC_CANCEL,
    { game = game, mapId = home, owner = "npc_probe", source = { modId = "script_probe" },
      onDone = function(ok, err)
        cancelCalls = cancelCalls + 1
        T.eq(ok, false, "explicit native cancellation reports failure")
        T.eq(err, cancelReason, "explicit native cancellation preserves the exact reason")
      end })
  assert(explicit, "native cancellation probe requires a bridge: " .. tostring(explicitReason))
  local explicitDone = Message._done
  assert(type(explicitDone) == "function", "explicit cancellation requires native message completion")
  explicit:cancel(cancelReason)
  T.eq(cancelCalls, 1, "explicit cancellation reports its reason immediately")
  T.eq(explicit:isRunning(), false, "explicitly cancelled native script stops running")
  T.eq(Message.isOpen(), false, "explicit cancellation closes its native message")
  T.eq(hooks.chains["core.update"], nil, "explicit cancellation retires its continuation")
  explicitDone()
  explicit:cancel("a later cancellation reason")
  update()
  T.eq(cancelCalls, 1, "explicit cancellation reports its reason exactly once despite stale completion")
  T.eq(save.modData.script_probe.worldFlags.talk_cancelled, nil, "explicit cancellation prevents later rows")

  eo.def.text = "NPC_CANCEL"
  for _, change in ipairs({ "provider", "map", "session", "hooks", "explicit", "owner" }) do
    local unrelatedCalls = 0
    local stopUnrelated = hooks:wrap("core.update", function(nextFn, ...)
      unrelatedCalls = unrelatedCalls + 1
      return nextFn(...)
    end, 0, change == "owner" and "other_probe" or "script_probe")
    local unrelated = hooks.chains["core.update"][1]
    T.eq(Field.interact(game), true, change .. " cancellation starts a real registered talk")
    local cancelledToken = nativeTalkToken()
    assert(type(cancelledToken) == "table" and cancelledToken.scriptHandle,
      "cancellation probe requires the native field token")
    local cancelledHandle, staleDone = cancelledToken.scriptHandle, Message._done
    assert(type(staleDone) == "function", "cancellation probe requires native message completion")
    if change == "provider" then live = nil
    elseif change == "map" then map.current, save.map, space.mapId = away, away, away
    elseif change == "session" then game.session = { version = version, map = home }
    elseif change == "hooks" then Runtime.install(events, Hooks.new(), errors)
    elseif change == "owner" then
      hooks:removeOwner("script_probe")
      T.eq(Runtime.hooks, hooks, "owner removal keeps the same native hook bus")
    else cancelledHandle:cancel(cancelReason) end
    if change == "explicit" then
      T.eq(#hooks.chains["core.update"], 1, "explicit cancellation immediately retires only its own handler")
    end
    update(function() if change == "owner" then Field.update(1 / 60) end end)
    T.eq(cancelledHandle:isRunning(), false, change .. " cancels the native bridge")
    T.eq(cancelledToken.done, true, change .. " cancellation completes its native field token")
    T.eq(next(Field._locks), nil, change .. " cancellation removes its native field lock")
    T.eq(Field.locked, false, change .. " cancellation releases the native field lock")
    T.eq(eo.frozen, false, change .. " cancellation restores native actor movement")
    T.eq(Message.isOpen(), false, change .. " cancellation closes its native message")
    T.eq(save.modData.script_probe.worldFlags.talk_cancelled, nil, change .. " cancellation prevents later rows")
    T.eq(#hooks.chains["core.update"], 1, change .. " cancellation removes the script continuation")
    T.eq(hooks.chains["core.update"][1], unrelated, change .. " preserves another handler owned by "
      .. (change == "owner" and "other_probe" or "script_probe"))
    live, game.session = game, save
    map.current, save.map, space.mapId = home, home, home
    Runtime.install(events, hooks, errors)
    Message.show("Unrelated native dialogue.")
    staleDone()
    cancelledHandle:cancel()
    update(function() if change == "owner" then Field.update(1 / 60) end end)
    T.eq(Message.currentPage(), "Unrelated native dialogue.", change .. " stale completion leaves unrelated UI open")
    T.eq(Field.locked, false, change .. " stale completion leaves field input unlocked")
    T.eq(eo.frozen, false, change .. " stale completion leaves native actor movement restored")
    T.eq(save.modData.script_probe.worldFlags.talk_cancelled, nil, change .. " stale completion cannot apply later rows")
    T.eq(unrelatedCalls, 2, change .. " keeps unrelated updates active")
    Message.close()
    stopUnrelated()
    T.eq(hooks.chains["core.update"], nil, change .. " leaves no cancelled script handler")
  end
  eo.def.text = "NPC_HELLO"

  local value, reason = other:removeNpc(id)
  rejected(value, reason, "foreign-owner runtime removal")
  T.eq(actor(id), eo, "foreign-owner refusal preserves the actor")
  value, reason = api:removeNpc(1)
  rejected(value, reason, "API 3 imported numeric removal")
  value, reason = api:removeNpc(home .. "_obj_1")
  rejected(value, reason, "API 3 imported public ID removal")
  T.eq(Objects.find(1).visible, true, "API 3 refusal keeps imported actors visible")
  T.same(space.store.flags, {}, "API 3 refused removals never alter native flags")

  local before = #Objects._order
  for _, bad in ipairs({ { x = -1, y = 0 }, { x = 0 / 0, y = 0 },
      { x = 1, y = 1, facing = "sideways" }, { x = 1, y = 1, radius = { x = -1, y = 1 } } }) do
    value, reason = api:spawnNpc(home, bad)
    rejected(value, reason, "invalid definition")
    T.eq(#Objects._order, before, "invalid definition leaves the native pool intact")
    T.eq(#Objects.runtimeByMap[home], 1, "invalid definition leaves the registry intact")
  end
  local collisionLid = eo.localId + 1
  local collisionPool = Objects.spawnFromDefs({ { localId = collisionLid,
    index = collisionLid, x = 7, y = 7, graphicsId = 16, movementType = 8 } }, maps[home], home)
  local reserved = collisionPool.byId[collisionLid]
  local collisionId = api:spawnNpc(home, { x = 6, y = 6, movement = "STAY" })
  local collisionActor = actor(collisionId)
  T.check(collisionActor ~= nil and collisionActor.localId ~= collisionLid,
    "allocation avoids local IDs occupied only in another native pool")
  T.eq(collisionPool.byId[collisionLid], reserved, "allocation never overwrites another pool's actor")
  T.check(actor(collisionId, collisionPool) ~= nil, "collision-safe allocation reaches every registered native pool")
  T.eq(api:removeNpc(collisionId), true, "collision-safe actor retains owner-scoped removal")
  T.eq(actor(collisionId, collisionPool), nil, "removal cleans the collision-test native pool")

  local pool = Objects.spawnFromDefs(maps[away].objects, maps[away], away)
  local awayId = native:spawnNpc(away, { x = 5, y = 5, sprite = "SPRITE_YOUNGSTER",
    movement = "STAY", facing = "down", text = "NPC_OTHER" })
  local neighbor = actor(awayId, pool)
  T.check(neighbor ~= nil, "native spawn materializes into an existing inactive map pool")
  assert(neighbor, "inactive native actor required")
  T.eq(actor(awayId), nil, "inactive map actor does not pollute the active pool")
  T.check(contains(Objects.poolForDraw(pool), neighbor), "inactive native actor enters its draw pool")
  Objects.tickPool(pool, game)
  T.eq(neighbor.spawnElevation, nil, "inactive pool update processes the actual actor")
  local unloaded = 0
  T.eq(handle:scriptMove("down", 2, function() unloaded = unloaded + 1 end), true,
    "start native movement before map unload")
  local unloadedFacing = eo.facing
  load(away)
  T.eq(next(Objects._tracks), nil, "map unload cancels native movement tracks")
  for _ = 1, 80 do Objects.update(game) end
  T.eq(unloaded, 0, "unloaded route never reports successful completion")
  T.check(actor(awayId) ~= nil, "map visit materializes the owned registry definition")
  T.eq(actor(awayId).owner, "npc_probe", "map visit preserves runtime ownership")
  T.eq(api:removeNpc(awayId), true, "owned removal succeeds after map visit")
  T.eq(actor(awayId), nil, "owned removal cleans the active pool")
  T.eq(actor(awayId, pool), nil, "owned removal cleans previously materialized pools")
  T.eq(Objects.runtimeByMap[away], nil, "last removal cleans its map registry")
  load(home)
  local revisited = actor(id)
  T.check(revisited ~= nil and revisited ~= eo, "revisit reconstructs the session runtime actor")
  T.eq(api:npc(home, id).id, id, "revisit preserves the public ID")
  T.eq(handle:face("right"), true, "old unified handle resolves the revisited actor")
  T.eq(revisited.facing, "right", "old handle changes the current actor")
  T.eq(eo.facing, unloadedFacing, "old handle leaves the unloaded actor untouched")
  local cancelled = 0
  T.eq(handle:scriptMove("down", 2, function() cancelled = cancelled + 1 end), true,
    "start a route before owned removal")
  local removedLid = revisited.localId
  T.eq(api:removeNpc(id), true, "owned public ID removal succeeds")
  T.eq(Objects._byId[removedLid], nil, "removal cleans the native byId store")
  T.eq(contains(Objects._order, removedLid), false, "removal cleans native update order")
  T.eq(Objects._tracks[removedLid], nil, "removal cancels the native movement track")
  for _ = 1, 80 do Objects.update(game) end
  T.eq(cancelled, 0, "cancelled route never reports successful completion")
  T.eq(Objects.runtimeByMap[home], nil, "owned removal cleans the registry")
  T.eq(contains(Objects.forDraw(), revisited), false, "removed actor leaves native draw collection")
  T.same(space.store.flags, {}, "owned runtime removal never changes native hide flags")
  T.same({ maps[home].objects, maps[away].objects }, pristine, "reload and removal preserve pristine ROM templates")
  T.eq(native:removeNpc(1), true, "legacy native numeric removal remains available to API 1/2")
  T.eq(Objects.find(1).visible, false, "legacy numeric removal still hides its imported actor")
  T.eq(space.store.flags[77], true, "legacy numeric removal retains its native hide flag behavior")

  local oldId = api:spawnNpc(home, { x = 5, y = 5, movement = "STAY" })
  local stale = api:npc(home, oldId)
  live = nil
  value, reason = stale:face("up")
  rejected(value, reason, "handle with missing game provider")
  Objects.reset()
  T.eq(next(Objects.runtimeByMap), nil, "session reset clears all runtime registry maps")
  T.eq(next(Objects._byId), nil, "session reset clears native actors")
  T.eq(actor(oldId, collisionPool), nil, "session reset removes runtime actors from registered inactive pools")
  T.eq(#pool.order, 1, "session cleanup leaves only the inactive pool's imported actor")
  local replacement = { phase = "field", data = game.data,
    session = { version = version, map = home, party = {}, flags = {}, vars = {} } }
  live = replacement
  Field._game, Field._session = replacement, replacement.session
  load(home)
  local freshId = api:spawnNpc(home, { x = 5, y = 5, movement = "STAY" })
  T.check(type(freshId) == "string" and freshId ~= oldId, "public IDs are not reused across session replacement")
  value, reason = stale:face("up")
  rejected(value, reason, "stale handle after provider replacement")
  T.eq(actor(freshId).facing, "down", "stale handle cannot change the replacement actor")
  Objects.clear()
  T.check(Objects.runtimeByMap[home] ~= nil, "map unload retains session runtime definitions")
  load(home)
  T.check(actor(freshId) ~= nil, "map reload materializes retained definitions")
  Objects.reset()

  local full = mapDef("NPC_FULL")
  full.objects = {}
  for lid = 1, 0xBF do
    full.objects[#full.objects + 1] = { localId = lid, index = lid,
      x = 8, y = 8, graphicsId = 16, movementType = 8 }
  end
  maps.NPC_FULL = full
  map.current = "NPC_FULL"
  Collision.bindMap(replacement, map.current, full)
  Objects.loadMap(replacement, map.current, full)
  value, reason = api:spawnNpc(map.current, { x = 1, y = 1, movement = "STAY" })
  rejected(value, reason, "native localId exhaustion")
  T.eq(#Objects._order, 0xBF, "exhaustion leaves the native actor order intact")
  T.eq(next(Objects.runtimeByMap), nil, "exhaustion does not create a runtime registry entry")
  T.eq(#full.objects, 0xBF, "exhaustion never appends a ROM template")
  T.eq(Objects.find(0xC0), nil, "exhaustion never consumes a foreign-object ID")
  T.eq(Objects._byId[0xFF], nil, "exhaustion never consumes the player ID")
  T.eq(#errors, 0, version .. " native NPC paths report no runtime errors")
  stopSpawn()
  Message.close()
  Objects.reset()
  Field.running, Field._game, Field._session = false, nil, nil
  Field._locks = {}
  Compat.endSession()
end

Data.map_scripts = savedMapScripts
MapScripts.invalidate()
FrlgFont.invalidate()
FrlgFont._syncVersion = nil
for name, saved in pairs(savedModules) do package.loaded[name] = saved[1] end
GameVersion.set(savedVersion)
Runtime.install(savedRuntime[1], savedRuntime[2], savedRuntime[3])
T.finish()
