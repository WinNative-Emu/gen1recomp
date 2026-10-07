local Wander = {}

Wander.CELL = 16
Wander.STEP_FRAMES = 32
Wander.FIRST_REST = 360
Wander.REST_MIN, Wander.REST_MAX = 240, 600
Wander.PAUSE_MIN, Wander.PAUSE_MAX = 40, 120
Wander.MAX_STEPS = 3
Wander.RADIUS = 1
Wander.GIVE_UP = 240

local ORDER = { "down", "up", "left", "right" }
local DELTA = { down = { 0, 1 }, up = { 0, -1 }, left = { -1, 0 }, right = { 1, 0 } }
local OPPOSITE = { down = "up", up = "down", left = "right", right = "left" }

Wander.DELTA = DELTA
Wander.OPPOSITE = OPPOSITE

local function nextRand(w)
  w.seed = (w.seed * 16807) % 2147483647
  return w.seed
end

local function randRange(w, lo, hi)
  return lo + nextRand(w) % (hi - lo + 1)
end

function Wander.new(seed, homeX, homeY)
  local s = math.floor(math.abs(tonumber(seed) or 1)) % 2147483647
  if s == 0 then s = 1 end
  local w = {
    seed = s, homeX = homeX, homeY = homeY, x = homeX, y = homeY,
    prevX = homeX, prevY = homeY, path = {}, mode = "rest", want = 0,
    moving = false, progress = 0, animClock = 0, stepFlip = false, blocked = 0,
    facing = false, px = false, py = false, timer = 0,
  }
  w.timer = Wander.FIRST_REST + randRange(w, 0, Wander.REST_MAX - Wander.REST_MIN)
  return w
end

function Wander.atHome(w)
  return w ~= nil and not w.moving and w.x == w.homeX and w.y == w.homeY
end

function Wander.away(w)
  return w ~= nil and not Wander.atHome(w)
end

local function inRange(w, x, y)
  return math.abs(x - w.homeX) <= Wander.RADIUS and math.abs(y - w.homeY) <= Wander.RADIUS
end

local function beginStep(w, dir)
  local d = DELTA[dir]
  w.prevX, w.prevY = w.x, w.y
  w.x, w.y = w.x + d[1], w.y + d[2]
  w.facing = dir
  w.moving, w.progress, w.animClock = true, 0, 0
  w.px, w.py = w.prevX * Wander.CELL, w.prevY * Wander.CELL
end

local function advance(w)
  w.progress = w.progress + 1
  w.animClock = w.animClock + 1
  local off = math.floor(Wander.CELL * math.min(w.progress, Wander.STEP_FRAMES) / Wander.STEP_FRAMES)
  w.px = w.prevX * Wander.CELL + (w.x - w.prevX) * off
  w.py = w.prevY * Wander.CELL + (w.y - w.prevY) * off
  if w.progress >= Wander.STEP_FRAMES then
    w.moving, w.progress, w.px, w.py = false, 0, false, false
    w.prevX, w.prevY = w.x, w.y
    w.stepFlip = not w.stepFlip
  end
end

local function clearPath(w)
  for i = #w.path, 1, -1 do w.path[i] = nil end
end

local function rest(w)
  clearPath(w)
  w.mode, w.want, w.blocked = "rest", 0, 0
  w.facing = false
  w.timer = randRange(w, Wander.REST_MIN, Wander.REST_MAX)
end

local function pickStep(w, free)
  local last = w.path[#w.path]
  local start = randRange(w, 1, #ORDER)
  for i = 0, #ORDER - 1 do
    local dir = ORDER[(start + i - 1) % #ORDER + 1]
    if dir ~= (last and OPPOSITE[last]) then
      local d = DELTA[dir]
      local tx, ty = w.x + d[1], w.y + d[2]
      if inRange(w, tx, ty) and free(tx, ty, w.x, w.y, dir) then return dir end
    end
  end
  return nil
end

function Wander.tick(w, env)
  if w.moving then
    advance(w)
    return true
  end
  env = env or {}
  if env.frozen then return false end
  local free = env.free or function() return false end
  if not env.canWander and w.mode ~= "rest" then w.mode = "back" end
  if w.mode == "rest" then
    if not Wander.atHome(w) then
      w.mode = "back"
      return false
    end
    if not env.canWander then return false end
    w.timer = w.timer - 1
    if w.timer > 0 then return false end
    clearPath(w)
    w.mode, w.want = "out", randRange(w, 1, Wander.MAX_STEPS)
  end
  if w.mode == "out" then
    local dir = #w.path < w.want and pickStep(w, free) or nil
    if not dir and #w.path == 0 then
      rest(w)
      return false
    end
    if not dir then
      w.mode = "pause"
      w.timer = randRange(w, Wander.PAUSE_MIN, Wander.PAUSE_MAX)
      local turn = ORDER[randRange(w, 1, #ORDER)]
      if turn ~= w.facing then
        w.facing = turn
        return true
      end
      return false
    end
    w.path[#w.path + 1] = dir
    beginStep(w, dir)
    return true
  end
  if w.mode == "pause" then
    w.timer = w.timer - 1
    if w.timer <= 0 then w.mode = "back" end
    return false
  end
  local last = w.path[#w.path]
  if not last then
    if w.x ~= w.homeX or w.y ~= w.homeY then
      if not free(w.homeX, w.homeY) then return false end
      w.x, w.y, w.prevX, w.prevY = w.homeX, w.homeY, w.homeX, w.homeY
    end
    rest(w)
    return true
  end
  local dir = OPPOSITE[last]
  local d = DELTA[dir]
  if free(w.x + d[1], w.y + d[2], w.x, w.y, dir) then
    w.path[#w.path] = nil
    w.blocked = 0
    beginStep(w, dir)
    return true
  end
  w.blocked = w.blocked + 1
  if w.blocked >= Wander.GIVE_UP and free(w.homeX, w.homeY) then
    w.x, w.y, w.prevX, w.prevY = w.homeX, w.homeY, w.homeX, w.homeY
    rest(w)
    return true
  end
  return false
end

return Wander
