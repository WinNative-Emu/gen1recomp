local DeferredWrite = { DELAY = 0.5 }

local pending = {}

function DeferredWrite.clock()
  local timer = love and love.timer
  if timer and timer.getTime then return timer.getTime() end
  return os.clock()
end

function DeferredWrite.schedule(key, fn, now)
  pending[key] = { fn = fn, at = (now or DeferredWrite.clock()) + DeferredWrite.DELAY }
end

local function run(key)
  local entry = pending[key]
  if not entry then return end
  pending[key] = nil
  pcall(entry.fn)
end

function DeferredWrite.tick(now)
  if next(pending) == nil then return end
  now = now or DeferredWrite.clock()
  local due
  for key, entry in pairs(pending) do
    if now >= entry.at then
      due = due or {}
      due[#due + 1] = key
    end
  end
  if due then
    for _, key in ipairs(due) do run(key) end
  end
end

function DeferredWrite.flush(key)
  if key ~= nil then return run(key) end
  local keys = {}
  for k in pairs(pending) do keys[#keys + 1] = k end
  for _, k in ipairs(keys) do run(k) end
end

function DeferredWrite.isPending(key)
  return pending[key] ~= nil
end

function DeferredWrite.cancel(key)
  pending[key] = nil
end

require("src.core.SessionLifecycle").registerProcessShutdown(function()
  DeferredWrite.flush()
end)

return DeferredWrite
