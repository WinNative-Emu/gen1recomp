local INNER = assert(os.getenv("HITCH_INNER"), "HITCH_INNER=tests/drivers/<driver>.lua")
local LIMIT_MS = tonumber(os.getenv("HITCH_MS") or "8") or 8
local DEPTH = tonumber(os.getenv("HITCH_DEPTH") or "10") or 10
if os.getenv("HITCH_JIT") ~= "1" and jit then jit.off(); jit.flush() end

local okProf, profile = pcall(require, "jit.profile")
if os.getenv("HITCH_STACKS") == "0" then okProf = false end
local frame, stacks, vm, samples = 0, {}, {}, 0
local hitches, all, known = {}, {}, {}
local frameStart, stuckShown
local clock = love.timer.getTime

local function top(map, n)
  local rows = {}
  for k, v in pairs(map) do rows[#rows + 1] = { k, v } end
  table.sort(rows, function(a, b) return a[2] > b[2] end)
  local out = {}
  for i = 1, math.min(n, #rows) do out[i] = rows[i] end
  return out
end

if okProf then
  profile.start("i1", function(th, n, state)
    samples = samples + n
    vm[state] = (vm[state] or 0) + n
    local s = profile.dumpstack(th, "pl < ", DEPTH)
    stacks[s] = (stacks[s] or 0) + n
    if frameStart and clock() - frameStart > 5 and not stuckShown then
      stuckShown = true
      print("HITCH_STUCK " .. profile.dumpstack(th, "pl\n", 40))
    end
  end)
end

local function reset() stacks, vm, samples = {}, {}, 0 end

local baseUpdate, baseDraw = love.update, love.draw
local tu, td, kb0
love.update = function(dt)
  frame = frame + 1
  reset()
  kb0 = collectgarbage("count")
  local t = clock()
  frameStart = t
  baseUpdate(dt)
  tu = (clock() - t) * 1000
end
love.draw = function()
  local t = clock()
  baseDraw()
  td = (clock() - t) * 1000
  local total = (tu or 0) + td
  all[#all + 1] = total
  if os.getenv("HITCH_STATUS") and frame % 60 == 0 then
    local B = package.loaded["src.core.game3.battle"]
    local T = package.loaded["src.core.game3.battle_transition"]
    print(string.format("HITCH_STATUS frame=%d battle=%s phase=%s transition=%s",
      frame, tostring(B and B.isActive and B.isActive()), tostring(B and B._phase),
      tostring(T and T._transitionId)))
  end
  for name in pairs(package.loaded) do
    if not known[name] then
      known[name] = true
      if frame > 1 then print(string.format("LAZY_REQUIRE frame=%d %s", frame, name)) end
    end
  end
  if total >= LIMIT_MS then
    local Map = package.loaded["src.core.game3.map"]
    hitches[#hitches + 1] = total
    print(string.format("HITCH frame=%d total=%.1fms update=%.1f draw=%.1f gcKB=%+.0f heapKB=%.0f map=%s samples=%d vm[N=%d I=%d C=%d G=%d J=%d]",
      frame, total, tu or 0, td, collectgarbage("count") - (kb0 or 0), collectgarbage("count"),
      tostring(Map and Map.current), samples, vm.N or 0, vm.I or 0, vm.C or 0, vm.G or 0, vm.J or 0))
    for _, row in ipairs(top(stacks, 6)) do
      print(string.format("  %3d  %s", row[2], row[1]))
    end
  end
end

local quit = love.event.quit
love.event.quit = function(...)
  table.sort(all)
  local n = #all
  local function p(q) return all[math.max(1, math.ceil(n * q))] or 0 end
  print(string.format("HITCH_SUMMARY frames=%d hitches=%d p50=%.2f p95=%.2f p99=%.2f max=%.2f jit=%s",
    n, #hitches, p(.5), p(.95), p(.99), all[n] or 0, tostring(jit and jit.status())))
  local foreign = {}
  for name in pairs(package.loaded) do
    if name:find("^src%.[%w_]+%.gen2%.") or name:find("^src%.[%w_]+%.gen2$")
        or name == "src.core.Game" or name == "src.core.Game2" or name == "src.world.OverworldController"
        or name == "src.battle.BattleState" then
      foreign[#foreign + 1] = name
    end
  end
  table.sort(foreign)
  print(string.format("FOREIGN_MODULES n=%d %s", #foreign, table.concat(foreign, " ")))
  if okProf then profile.stop() end
  return quit(...)
end

return assert(loadfile(INNER))()
