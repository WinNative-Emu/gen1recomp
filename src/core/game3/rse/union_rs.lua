local Family = require("src.core.game3.link.family")

local UnionRs = {}

-- pokeruby/data/maps/OldaleTown_PokemonCenter_2F/map.json:63
UnionRs.BAY_DOOR = { x = 5, y = 1 }
-- pokeruby/data/maps/OldaleTown_PokemonCenter_2F/map.json:16
UnionRs.BAY_ATTENDANT = { x = 4, y = 2 }
UnionRs.DOOR = { x = 2, y = 1 }
UnionRs.ATTENDANT = { x = 1, y = 2 }
UnionRs.FRONT = { x = 2, y = 2 }
UnionRs.VOBJ_ID = 0x7D01
UnionRs.MIN_MONS = 2
UnionRs.LOCK = "union_rs"

UnionRs.centers = {}
UnionRs.flow = nil
UnionRs._task = nil

local DIR = { down = 1, up = 2, left = 3, right = 4 }
local OPPOSITE = { down = "up", up = "down", left = "right", right = "left" }
local DELTA = { down = { 0, 1 }, up = { 0, -1 }, left = { -1, 0 }, right = { 1, 0 } }

local function Strings(...) return require("src.core.Strings")(...) end
local function link() return require("src.core.game3.link") end
local function message() return require("src.ui.game3.message") end
local function plaza() return require("src.core.game3.link.union_plaza_map") end

function UnionRs.active()
  return Family.isRubySapphire(Family.activeVersion())
end

function UnionRs.text(key)
  if key == "welcome" then
    return Strings("Welcome to the UNION ROOM!\fTrainers from every POKéMON game meet here to battle and trade.\fWould you like to go in?")
  end
  if key == "come_again" then return Strings("Please come again!") end
  if key == "need_two" then return Strings("You need at least two POKéMON that aren't EGGS to go in.") end
  if key == "connect" then return Strings("The UNION ROOM is online.\nWould you like to connect?") end
  if key == "connecting" then return Strings("Connecting...") end
  if key == "save_first" then return Strings("Your progress will be saved before you go in.") end
  if key == "enjoy" then return Strings("Please enjoy the UNION ROOM!") end
  return ""
end

local function backLink(dest, mapId)
  for _, w in ipairs(type(dest) == "table" and dest.warps or {}) do
    if w.destMap == mapId then return true end
  end
  return false
end

function UnionRs.discover(maps)
  local colosseum = Family.mapId(nil, "colosseum2P")
  local out = {}
  for mapId, def in pairs(maps or {}) do
    local warps = type(def) == "table" and def.warps or nil
    local bay = false
    for _, w in ipairs(warps or {}) do
      if tonumber(w.x) == UnionRs.BAY_DOOR.x and tonumber(w.y) == UnionRs.BAY_DOOR.y and w.destMap == colosseum then
        bay = true
      end
    end
    if bay then
      local oneF
      for _, w in ipairs(warps) do
        local destId = w.destMap
        if type(destId) == "string" and destId ~= colosseum and backLink(maps[destId], mapId) then oneF = destId end
      end
      out[mapId] = { id = mapId, oneF = oneF }
    end
  end
  return out
end

local function copyCells(L)
  local cells = {}
  local w, h = L.width, L.height
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      local c = L:cellAt(x, y)
      cells[y * w + x + 1] = { mid = c.mid, coll = c.coll, elev = c.elev }
    end
  end
  return cells
end

function UnionRs.patchLayout(def, mapId)
  if def._unionRsDoor then return def.midLayout end
  local L = def.midLayout
  if not L then error("union room: " .. tostring(mapId) .. " has no layout in the cache; re-import the ROM", 2) end
  local cells = copyCells(L)
  local w = L.width
  local function put(dx, dy, sx, sy)
    local c = cells[sy * w + sx + 1]
    cells[dy * w + dx + 1] = { mid = c.mid, coll = c.coll, elev = c.elev }
  end
  put(UnionRs.DOOR.x, UnionRs.DOOR.y, UnionRs.BAY_DOOR.x, UnionRs.BAY_DOOR.y)
  put(UnionRs.DOOR.x, UnionRs.DOOR.y - 1, UnionRs.BAY_DOOR.x, UnionRs.BAY_DOOR.y - 1)
  local border = {}
  for i, m in ipairs(L.borderMids or { 0 }) do border[i] = m end
  local layout = require("src.core.game3.layout_native").fromDecoded({
    width = L.width, height = L.height, trueWidth = L.trueWidth, trueHeight = L.trueHeight,
    borderWidth = L.borderWidth, borderHeight = L.borderHeight, borderMids = border, cells = cells,
  }, mapId, L.pair or def.pair)
  def.midLayout = layout
  def._unionRsDoor = true
  return layout
end

function UnionRs.install(game)
  local maps = game and game.data and game.data.maps
  if type(maps) ~= "table" then return 0 end
  UnionRs._game = game
  UnionRs.centers = UnionRs.discover(maps)
  local n = 0
  for mapId in pairs(UnionRs.centers) do
    UnionRs.patchLayout(maps[mapId], mapId)
    n = n + 1
  end
  UnionRs.arm()
  return n
end

function UnionRs.isCenter(mapId)
  return type(mapId) == "string" and UnionRs.centers[mapId] ~= nil
end

local function maps()
  local game = link().game() or UnionRs._game
  return game and game.data and game.data.maps or {}
end

function UnionRs.attendantGfx(mapId)
  local def = maps()[mapId]
  for _, o in ipairs(def and def.objects or {}) do
    if tonumber(o.x) == UnionRs.BAY_ATTENDANT.x and tonumber(o.y) == UnionRs.BAY_ATTENDANT.y then
      return tonumber(o.graphicsId or o.graphics)
    end
  end
  return nil
end

function UnionRs.nurseFront(oneF)
  local def = maps()[oneF]
  if not def then return nil end
  local nurse = require("src.core.game3.constants").of(Family.activeVersion()):require("event_objects", "OBJ_EVENT_GFX_NURSE")
  local L = def.midLayout
  for _, o in ipairs(def.objects or {}) do
    if tonumber(o.graphicsId or o.graphics) == nurse then
      local x, y = tonumber(o.x), tonumber(o.y)
      for dy = 1, 3 do
        if L and L:collAt(x, y + dy) == 0 then return x, y + dy end
      end
    end
  end
  return nil
end

function UnionRs.originFor(centerId)
  local c = UnionRs.centers[centerId]
  if not (c and c.oneF) then return nil end
  local x, y = UnionRs.nurseFront(c.oneF)
  if not x then return nil end
  return { map = c.oneF, x = x, y = y, facing = "up" }
end

local function currentMap()
  local Map = package.loaded["src.core.game3.map"]
  return Map and Map.current or nil
end

local function player() return package.loaded["src.core.game3.player"] end

function UnionRs.spawnAttendant(mapId)
  local V = require("src.core.game3.virtual_objects")
  local vo = V.get(UnionRs.VOBJ_ID)
  if vo and vo.map == mapId then return vo end
  local gfx = UnionRs.attendantGfx(mapId)
  if not gfx then return nil end
  vo = V.spawn(UnionRs.VOBJ_ID, gfx, UnionRs.ATTENDANT.x, UnionRs.ATTENDANT.y, 3, DIR.down)
  vo.solid = true
  vo.map = mapId
  return vo
end

local function busy()
  local Space = package.loaded["src.core.game3.scripting.space"]
  if Space and Space.vm and Space.vm.isRunning and Space.vm:isRunning() then return true end
  local Field = package.loaded["src.core.game3.field"]
  if Field and Field.locked then return true end
  local Hud = package.loaded["src.ui.game3.hud"]
  if Hud and Hud.busy and Hud.busy() then return true end
  local Warp = package.loaded["src.core.game3.warp"]
  return (Warp and Warp.isBusy and Warp.isBusy()) and true or false
end

local function pressedA()
  local game = link().game()
  local input = game and game.input
  return input and input.wasPressed and input:wasPressed("a") and true or false
end

function UnionRs.facingAttendant()
  local P = player()
  if not P or P.moving then return false end
  local d = DELTA[P.facing or "down"]
  return d ~= nil and (tonumber(P.cellX) or 0) + d[1] == UnionRs.ATTENDANT.x
    and (tonumber(P.cellY) or 0) + d[2] == UnionRs.ATTENDANT.y
end

function UnionRs.tick()
  if not UnionRs.active() then return end
  if UnionRs.flow then return UnionRs.stepFlow() end
  local mapId = currentMap()
  if not UnionRs.isCenter(mapId) then return end
  local Warp = package.loaded["src.core.game3.warp"]
  if Warp and Warp.isBusy and Warp.isBusy() then return end
  UnionRs.spawnAttendant(mapId)
  if busy() or not pressedA() or not UnionRs.facingAttendant() then return end
  UnionRs.talk(mapId)
end

function UnionRs.arm()
  if UnionRs._task and not UnionRs._task.done then return end
  UnionRs._task = require("src.core.game3.task").spawn(function()
    local ok, err = pcall(UnionRs.tick)
    if not ok then
      print("[union_rs] " .. tostring(err))
      UnionRs.endFlow()
    end
    return false
  end)
end

function UnionRs.runFlow(steps)
  UnionRs.flow = { steps = steps, i = 1, started = false }
  UnionRs.stepFlow()
end

function UnionRs.stepFlow()
  for _ = 1, 16 do
    local f = UnionRs.flow
    if not f then return end
    local step = f.steps[f.i]
    if not step then
      if UnionRs.flow == f then UnionRs.endFlow() end
      return
    end
    if not f.started then
      f.started = true
      if step.start then step.start() end
      if UnionRs.flow ~= f then return end
    end
    if step.poll and not step.poll() then return end
    if UnionRs.flow ~= f then return end
    f.i = f.i + 1
    f.started = false
  end
end

function UnionRs.endFlow()
  UnionRs.flow = nil
  local Field = package.loaded["src.core.game3.field"]
  if Field and Field.unlock then Field.unlock(UnionRs.LOCK) end
  local vo = require("src.core.game3.virtual_objects").get(UnionRs.VOBJ_ID)
  if vo then vo.direction = DIR.down end
end

local function say(text)
  return {
    start = function() message().show(text) end,
    poll = function() return not message().isOpen() end,
  }
end

local function stay(text)
  return {
    start = function() message().show(text, { stay = true }) end,
    poll = function()
      local M = message()
      return M.isOpen() and M.isWaiting() and (M._page or 1) >= #(M._pages or {})
    end,
  }
end

local function yesNo(cb)
  local asked, answered = false, false
  return {
    poll = function()
      if answered then return true end
      local Choice = require("src.ui.game3.choice")
      if not asked and not Choice.isOpen() then
        asked = true
        Choice.yesNo(function(yes)
          answered = true
          message().close()
          cb(yes and true or false)
        end)
      end
      return answered
    end,
  }
end

local function act(fn) return { start = fn } end

local function bye()
  UnionRs.runFlow({ say(UnionRs.text("come_again")) })
end

function UnionRs.countMons(session)
  local n = 0
  for _, mon in ipairs(type(session) == "table" and session.party or {}) do
    if type(mon) == "table" and not (mon.isEgg or mon.egg) and (tonumber(mon.species) or 0) > 0 then n = n + 1 end
  end
  return n
end

function UnionRs.talk(mapId)
  local Field = require("src.core.game3.field")
  Field.lock(UnionRs.LOCK)
  local P = player()
  local vo = require("src.core.game3.virtual_objects").get(UnionRs.VOBJ_ID)
  if vo and P then vo.direction = DIR[OPPOSITE[P.facing or "down"]] or DIR.down end
  UnionRs.runFlow({
    stay(UnionRs.text("welcome")),
    yesNo(function(yes)
      if not yes then return bye() end
      UnionRs.checkParty(mapId)
    end),
  })
end

function UnionRs.checkParty(mapId)
  local session = link().session()
  if UnionRs.countMons(session) < UnionRs.MIN_MONS then
    return UnionRs.runFlow({ say(UnionRs.text("need_two")) })
  end
  if link().adapterConnected() then return UnionRs.askSave(mapId) end
  UnionRs.runFlow({
    stay(UnionRs.text("connect")),
    yesNo(function(yes)
      if not yes then return bye() end
      UnionRs.connect(mapId)
    end),
  })
end

function UnionRs.connect(mapId)
  local L = link()
  local ok, err = L.connect()
  if not ok then return UnionRs.runFlow({ say(L.reasonText(err)) }) end
  local failed
  UnionRs.runFlow({
    act(function() message().show(UnionRs.text("connecting"), { stay = true }) end),
    {
      poll = function()
        if L.adapterConnected() then return true end
        local state = L.connectState()
        if state == "error" or state == "offline" then
          failed = L.connectError() or state
          return true
        end
        return false
      end,
    },
    act(function()
      message().close()
      if failed then return UnionRs.runFlow({ say(L.reasonText(failed)) }) end
      UnionRs.askSave(mapId)
    end),
  })
end

function UnionRs.askSave(mapId)
  local saved
  UnionRs.runFlow({
    say(UnionRs.text("save_first")),
    act(function()
      local SaveMenu = require("src.ui.game3.save_menu")
      SaveMenu.show({
        session = link().session(), game = link().game(),
        onClose = function() saved = SaveMenu._phase == "saved" end,
      })
    end),
    { poll = function() return saved ~= nil end },
    act(function()
      if not saved then return bye() end
      UnionRs.runFlow({
        say(UnionRs.text("enjoy")),
        act(function() UnionRs.enter(mapId) end),
      })
    end),
  })
end

local ENTER = { surfing = false }

local function pathTo(fx, fy, tx, ty)
  local Coll = package.loaded["src.core.game3.collision"]
  local Objects = package.loaded["src.core.game3.objects"]
  local function free(x, y)
    if x == UnionRs.ATTENDANT.x and y == UnionRs.ATTENDANT.y then return false end
    if Objects and Objects.blocks and Objects.blocks(x, y) then return false end
    return Coll ~= nil and Coll.canEnter(link().game(), x, y, ENTER) == true
  end
  local key = function(x, y) return y * 1024 + x end
  local prev = { [key(fx, fy)] = false }
  local queue, head = { { fx, fy } }, 1
  while queue[head] do
    local c = queue[head]
    head = head + 1
    if c[1] == tx and c[2] == ty then
      local dirs = {}
      local k = key(tx, ty)
      while prev[k] do
        local p = prev[k]
        table.insert(dirs, 1, p.dir)
        k = key(p.x, p.y)
      end
      return dirs
    end
    for _, dir in ipairs({ "up", "left", "right", "down" }) do
      local d = DELTA[dir]
      local nx, ny = c[1] + d[1], c[2] + d[2]
      local nk = key(nx, ny)
      if prev[nk] == nil and math.abs(nx - fx) <= 4 and math.abs(ny - fy) <= 4 and free(nx, ny) then
        prev[nk] = { x = c[1], y = c[2], dir = dir }
        queue[#queue + 1] = { nx, ny }
      end
    end
  end
  return nil
end

function UnionRs.walkSteps(mapId)
  local P = player()
  local dirs = pathTo(tonumber(P.cellX) or 0, tonumber(P.cellY) or 0, UnionRs.FRONT.x, UnionRs.FRONT.y) or {}
  local steps = {}
  for _, dir in ipairs(dirs) do
    local done = false
    steps[#steps + 1] = {
      start = function()
        if not P.forceStep(dir, function() done = true end) then done = true end
      end,
      poll = function() return done end,
    }
  end
  steps[#steps + 1] = act(function()
    if P.scriptFace then P.scriptFace("up") else P.facing = "up" end
  end)
  return steps
end

function UnionRs.enter(mapId)
  local L = link()
  local session = L.session()
  require("src.core.game3.party").healAll(session.party)
  local origin = UnionRs.originFor(mapId)
  if origin then
    require("src.online.union.Origin").record(session, {
      gen = 3, version = Family.activeVersion(), map = origin.map, x = origin.x, y = origin.y,
      facing = origin.facing, warp = mapId,
    })
  end
  session.dynamicWarp = { map = mapId, warpId = 0xFF, x = UnionRs.DOOR.x, y = UnionRs.DOOR.y }
  local steps = UnionRs.walkSteps(mapId)
  local arrived = false
  steps[#steps + 1] = act(function()
    local rt = package.loaded["src.core.game3.runtime"]
    local P = plaza()
    local x, y = P.entry()
    require("src.core.game3.warp").scripted(rt and rt._mod, L.game(), "warpdoor", P.MAP_ID, x, y, "up",
      function() arrived = true end)
  end)
  steps[#steps + 1] = { poll = function() return arrived end }
  steps[#steps + 1] = act(function()
    UnionRs.endFlow()
    require("src.core.game3.field").unlock()
    L.union().run(nil)
  end)
  UnionRs.runFlow(steps)
end

function UnionRs.inRoom(session)
  return type(session) == "table" and session.map ~= nil and session.map == plaza().MAP_ID
end

function UnionRs.saveOrigin(session)
  local Origin = require("src.online.union.Origin")
  local o = Origin.get(session)
  if o and o.gen == 3 then return { map = o.map, x = o.x, y = o.y, facing = o.facing or "up" } end
  return nil
end

function UnionRs.reset()
  UnionRs.flow = nil
end

return UnionRs
