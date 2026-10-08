-- ../pokecrystal/engine/overworld/scripting.asm:467
-- ../pokecrystal/engine/battle_anims/anim_commands.asm:1191
--   tools/run_driver.sh crystal <identity> tests/drivers/crystal_sfx_prewarm_2732.lua <shotdir>
local U = require("tests.drivers.util")
local Sound = require("src.core.Sound")
local ChipAudio = require("src.core.ChipAudio")
local Mon = require("src.battle.gen2.Mon")

local SHOT_DIR = os.getenv("POKEPORT_SHOT_DIR")
  or ".bazinga/BSA/10-07-26-00-userreported/shots/crystal_sfx_prewarm_2732"

return function(game)
  local fails = 0
  local function say(line) print("[2732] " .. line) end
  local function ok(cond, line)
    if not cond then fails = fails + 1 end
    say((cond and "PASS " or "FAIL ") .. line)
    return cond
  end
  local function finish()
    say("stats " .. tostring(ChipAudio.stats().line))
    say(fails == 0 and "all claims passed" or (fails .. " claims failed"))
    love.event.quit(fails == 0 and 0 or 1)
    while true do U.wait(60) end
  end

  if jit and jit.off then jit.off() end

  local function drained(seconds)
    local stop = love.timer.getTime() + seconds
    while love.timer.getTime() < stop do
      local st = ChipAudio.stats()
      if (st.prewarmQueued or 0) + (st.prewarmInFlight or 0) == 0 then
        return true
      end
      U.wait(1)
    end
    return false
  end

  local events = {}
  local function watch(fnName)
    local real = Sound[fnName]
    Sound[fnName] = function(data, name, ...)
      local before = ChipAudio.stats().syncRenders or 0
      local src = real(data, name, ...)
      local after = ChipAudio.stats().syncRenders or 0
      events[#events + 1] = { kind = fnName, name = name,
        sync = after - before, ms = ChipAudio.stats().syncRenderMsMax }
      return src
    end
  end
  watch("play")
  watch("playStereo")

  U.wait(45)
  local world = game.world
  if not ok(world and world.map, "the crystal world booted") then finish() end
  if not ok(ChipAudio.stats().syncRenders ~= nil,
      "ChipAudio.stats() counts main-thread sfx renders") then
    finish()
  end
  ok(drained(20), "session sfx prewarm drained")

  world:warpToMapId("ROUTE_29", 48, 3, "up")
  U.wait(30)
  local ball
  for _, npc in ipairs(world.npcs or {}) do
    if npc.def and npc.def.itemball then ball = npc end
  end
  if not ok(ball ~= nil, "Route 29 has its POTION item ball") then finish() end
  world:warpToMapId("ROUTE_29", ball.cellX, ball.cellY + 1, "up")
  U.wait(30)
  ChipAudio.resetSyncStats()
  events = {}
  world:interact()
  local itemEvent
  for _ = 1, 600 do
    for _, e in ipairs(events) do
      if e.name == "Sfx_Item" then itemEvent = e end
    end
    if itemEvent then break end
    U.wait(1)
  end
  if ok(itemEvent ~= nil, "the item ball script played Sfx_Item") then
    ok(itemEvent.sync == 0, "Sfx_Item started with 0 sync renders (got "
      .. itemEvent.sync .. ")")
  end
  U.wait(60)
  U.still(game, SHOT_DIR .. "/2732_01_found_potion_chime.png")
  for _ = 1, 40 do
    if not world:busy() then break end
    U.tap(game, "a")
    U.wait(6)
  end

  local cyndaquil = Mon.new(game.data, "CYNDAQUIL", 20)
  game.save.party = { cyndaquil }
  ok(world:startBattle({ wild = Mon.new(game.data, "SENTRET", 12) }),
    "a wild battle started")
  local screen
  for _ = 1, 900 do
    local top = game.stack:top()
    if top and top.battle then screen = top break end
    U.wait(1)
  end
  if not ok(screen ~= nil, "the battle screen came up") then finish() end
  ok(drained(20), "battle sfx prewarm drained")
  ChipAudio.resetSyncStats()
  events = {}
  for _ = 1, 300 do
    if screen.phase == "menu" then break end
    if screen.anim == nil then U.tap(game, "a") end
    U.wait(4)
  end
  if not ok(screen.phase == "menu", "the battle menu came up") then finish() end
  local introSounds = #events
  U.tap(game, "a")
  U.wait(10)
  ok(screen.phase == "moves", "FIGHT opened the move list")
  local moveName = cyndaquil.moves[1] and cyndaquil.moves[1].id
  U.tap(game, "a")
  local moveEvent
  for _ = 1, 600 do
    for i = introSounds + 1, #events do
      local e = events[i]
      if e.kind == "playStereo" then moveEvent = moveEvent or e end
    end
    if moveEvent then break end
    U.wait(1)
  end
  if ok(moveEvent ~= nil, "the turn's first move animation played a sound ("
      .. tostring(moveName) .. " chosen)") then
    ok(moveEvent.sync == 0, ("%s started with 0 sync renders (got %d)")
      :format(moveEvent.name, moveEvent.sync))
  end
  U.still(game, SHOT_DIR .. "/2732_02_move_anim_sound.png")
  for _ = 1, 200 do
    if not (game.stack:top() or {}).battle then break end
    if screen.anim == nil then U.tap(game, "a") end
    U.wait(4)
  end
  local stereo, played = 0, 0
  for _, e in ipairs(events) do
    played = played + 1
    if e.kind == "playStereo" then stereo = stereo + 1 end
  end
  local st = ChipAudio.stats()
  ok(stereo > 0, "the turn played " .. stereo .. " anim sounds of " .. played)
  ok((st.syncRenders or 0) == 0, "0 sync sfx renders across the battle (last "
    .. tostring(st.syncRenderLast) .. ")")
  finish()
end
