local ops = require("src.sync.SyncWorkOps")(require)

local Work = {}
Work.POOL = 2
Work.MIN_BYTES = 16 * 1024
Work.ops = ops

local CMD, RESULT, QUIT = "sync_work_cmd", "sync_work_result", "sync_work_quit"
local WORKER = "src/sync/sync_worker.lua"

local workers = {}
local cmdCh, resCh, quitCh
local ready
local results = {}
local nextId = 0
local owned = setmetatable({}, { __mode = "k" })
local waits = setmetatable({}, { __mode = "k" })

local function pack(...) return { n = select("#", ...), ... } end

local function start()
  if ready ~= nil then return ready end
  local thread = love and love.thread
  if type(thread) ~= "table" or type(thread.newThread) ~= "function"
      or type(thread.getChannel) ~= "function" then
    ready = false
    return false
  end
  local ok = pcall(function()
    cmdCh, resCh, quitCh = thread.getChannel(CMD), thread.getChannel(RESULT), thread.getChannel(QUIT)
    quitCh:clear(); cmdCh:clear(); resCh:clear()
  end)
  if not ok then
    cmdCh, resCh, quitCh, ready = nil, nil, nil, false
    return false
  end
  for _ = 1, Work.POOL do
    local made, th = pcall(thread.newThread, WORKER)
    if made and th and pcall(function() th:start() end) then workers[#workers + 1] = th end
  end
  ready = #workers > 0
  return ready
end

function Work.available()
  return start()
end

local function drain()
  if not resCh then return end
  local msg = resCh:pop()
  while msg do
    if type(msg) == "table" and msg.id and results[msg.id] == false then results[msg.id] = msg end
    msg = resCh:pop()
  end
  for _, th in ipairs(workers) do
    local err = th.getError and th:getError()
    if err then
      for id, r in pairs(results) do
        if r == false then results[id] = { id = id, lost = true } end
      end
      ready = false
      break
    end
  end
end

function Work.submit(op, ...)
  if not ops[op] or not start() then return nil end
  nextId = nextId + 1
  local id = nextId
  if not pcall(cmdCh.push, cmdCh, { id = id, op = op, args = pack(...) }) then return nil end
  results[id] = false
  return id
end

function Work.poll(id)
  drain()
  local r = results[id]
  if r == false then return nil end
  results[id] = nil
  return r or { id = id, lost = true }
end

function Work.forget(id)
  if id ~= nil then results[id] = nil end
end

function Work.finish(r, op, args)
  if not r or r.lost then return ops[op](unpack(args, 1, args.n)) end
  if r.err then error(r.err, 0) end
  local values = r.values or { n = 0 }
  return unpack(values, 1, values.n or #values)
end

function Work.spawn(fn)
  local co = coroutine.create(fn)
  owned[co] = true
  return co
end

function Work.abandon(co)
  for id in pairs(waits[co] or {}) do Work.forget(id) end
  waits[co] = nil
end

function Work.async()
  local co = coroutine.running()
  return co ~= nil and owned[co] == true and start() == true
end

local function heavy(args)
  local bytes = 0
  for i = 1, args.n do
    local v = args[i]
    if type(v) == "table" then return true end
    if type(v) == "string" then bytes = bytes + #v end
  end
  return bytes >= Work.MIN_BYTES
end

local function await(co, ids)
  local mine = waits[co] or {}
  waits[co] = mine
  for _, id in pairs(ids) do mine[id] = true end
  local out = {}
  while true do
    local pending = false
    for i, id in pairs(ids) do
      if out[i] == nil then
        local r = Work.poll(id)
        if r then out[i] = r; mine[id] = nil else pending = true end
      end
    end
    if not pending then return out end
    coroutine.yield()
  end
end

function Work.call(op, ...)
  local args = pack(...)
  if not heavy(args) or not Work.async() then return ops[op](...) end
  local id = Work.submit(op, ...)
  if not id then return ops[op](...) end
  return Work.finish(await(coroutine.running(), { id })[1], op, args)
end

function Work.batch(op, list)
  local out, ids = {}, {}
  local async = Work.async()
  for i, args in ipairs(list) do
    args.n = args.n or #args
    local id = async and heavy(args) and Work.submit(op, unpack(args, 1, args.n)) or nil
    if id then ids[i] = id else out[i] = pack(ops[op](unpack(args, 1, args.n))) end
  end
  if next(ids) then
    local done = await(coroutine.running(), ids)
    for i, r in pairs(done) do out[i] = pack(Work.finish(r, op, list[i])) end
  end
  return out
end

function Work.shutdown()
  if quitCh then quitCh:push(true) end
  if cmdCh then
    cmdCh:clear()
    for _ = 1, #workers do cmdCh:push({ op = "quit" }) end
  end
  for _, th in ipairs(workers) do pcall(function() th:wait() end) end
  workers = {}
  results = {}
  cmdCh, resCh, quitCh, ready = nil, nil, nil, nil
end

pcall(function() require("src.core.SessionLifecycle").registerProcessShutdown(Work.shutdown) end)

return Work
