package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")
local T = require("tests.harness")
local F = require("tests.engine._g3u_fixture")
local Table = require("src.battle.g3u.Table")
local Match = require("src.battle.g3u.Match")
local Scope = require("src.battle.g3u.Scope")

local function deep(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for k, v in pairs(a) do if not deep(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

local function legalSame(a, b)
  for seat = 0, 1 do
    if not deep(a:legalActions(seat), b:legalActions(seat)) then return false end
  end
  return true
end

local function battle(t, seed)
  local rnd = F.lcg(seed)
  local p0, p1 = F.randomParty(t, rnd, rnd(4)), F.randomParty(t, rnd, rnd(4))
  local opts = { table = t, parties = { [0] = p0, [1] = p1 }, seed = seed * 7919 }
  local a, b = Match.new(opts), Match.new(opts)
  local ea, eb = a:start(), b:start()
  if not deep(ea, eb) then return false, "start events differ" end
  local steps, hashes = 0, 0
  while a.phase ~= "over" do
    steps = steps + 1
    if steps > 600 then return false, "battle did not end" end
    if a.phase ~= b.phase then return false, "phase differs" end
    if not legalSame(a, b) then return false, "legal actions differ at turn " .. a.turn end
    if a.phase == "choose" then
      local acts = { [0] = F.pick(a, 0, rnd), [1] = F.pick(a, 1, rnd) }
      ea, eb = a:submit(acts), b:submit(acts)
    else
      local picks = {}
      for seat = 0, 1 do
        if a:needs(seat) then
          local l = a:legalActions(seat)
          picks[seat] = l[rnd(#l)].index
        end
      end
      ea, eb = a:replace(picks), b:replace(picks)
    end
    if not deep(ea, eb) then return false, "events differ at turn " .. a.turn end
    if a:hash() ~= b:hash() then return false, "hash differs at turn " .. a.turn end
    hashes = hashes + 1
  end
  if b.phase ~= "over" or not deep(a.result, b.result) then return false, "result differs" end
  for turn = 0, a.turn do
    if a:hash(turn) == nil or a:hash(turn) ~= b:hash(turn) then return false, "turn hash " .. turn end
  end
  return true, a.turn
end

local function run(label, t, count, base)
  Scope.resetTrips()
  local ok, turns, failure = 0, 0, nil
  for i = 1, count do
    local good, info = battle(t, base + i)
    if good then
      ok = ok + 1
      turns = turns + info
    elseif not failure then
      failure = ("seed %d: %s"):format(base + i, tostring(info))
    end
  end
  T.eq(ok, count, label .. ": every battle stays in lockstep " .. tostring(failure or ""))
  T.check(turns > count * 3, label .. ": battles run real turns (" .. turns .. ")")
  T.eq(#Scope.trips, 0, label .. ": no cache, text or math.random read during a match " .. tostring(Scope.trips[1]))
end

local t1 = assert(Table.build(F.gen1()))
local t2 = assert(Table.build(F.gen2()))
run("gen1 fixture", t1, 120, 1000)
run("gen2 fixture", t2, 80, 5000)

local function solo(t, seed, script)
  local rnd = F.lcg(seed)
  local p0, p1 = F.randomParty(t, rnd, 3), F.randomParty(t, rnd, 3)
  local m = Match.new({ table = t, parties = { [0] = p0, [1] = p1 }, seed = script and script.seed or seed })
  m:start()
  local log, i = { steps = {}, seed = seed }, 0
  while m.phase ~= "over" and i < 400 do
    i = i + 1
    local step = script and script.steps[i]
    if m.phase == "choose" then
      step = step or { [0] = F.pick(m, 0, rnd), [1] = F.pick(m, 1, rnd) }
      if script and not (m:isLegal(0, step[0]) and m:isLegal(1, step[1])) then break end
      m:submit(step)
    else
      if not step then
        step = {}
        for s = 0, 1 do if m:needs(s) then step[s] = m:legalActions(s)[1].index end end
      end
      local okR = pcall(m.replace, m, step)
      if not okR then break end
    end
    log.steps[i] = step
  end
  local hashes = {}
  for turn = 0, m.turn do hashes[turn] = m:hash(turn) end
  return log, hashes
end

local log, first = solo(t1, 77)
local _, again = solo(t1, 77, log)
T.same(again, first, "a replay run after the first match finished reproduces every turn hash")
local _, other = solo(t1, 77, { seed = 78, steps = log.steps })
T.check(other[1] ~= first[1] or other[2] ~= first[2] or other[3] ~= first[3],
  "a different seed changes the turn hashes")

for _, pair in ipairs({ { "red", "g1r-red" }, { "gold", "g1r-gold" } }) do
  local data = F.real(pair[1], pair[2])
  if data then
    run(pair[1] .. " cache", assert(Table.build(data)), 60, 9000)
  else
    print("[skip] " .. pair[1] .. " cache not imported")
  end
end

T.finish("g3u lockstep")
