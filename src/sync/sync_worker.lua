require("love.thread")
require("love.filesystem")
require("love.data")

local function need(name)
  local loaded = package.loaded[name]
  if loaded ~= nil then return loaded end
  local mod = assert(love.filesystem.load(name:gsub("%.", "/") .. ".lua"))()
  package.loaded[name] = mod
  return mod
end

local ops = assert(love.filesystem.load("src/sync/SyncWorkOps.lua"))()(need)

local cmdCh = love.thread.getChannel("sync_work_cmd")
local resCh = love.thread.getChannel("sync_work_result")
local quitCh = love.thread.getChannel("sync_work_quit")

local function pack(...) return { n = select("#", ...), ... } end

while true do
  local job = cmdCh:demand()
  if quitCh:peek() ~= nil then break end
  if type(job) == "table" then
    if job.op == "quit" then break end
    local fn = ops[job.op]
    local args = type(job.args) == "table" and job.args or { n = 0 }
    local result = fn and pack(pcall(fn, unpack(args, 1, args.n or #args)))
    local reply
    if not fn then
      reply = { id = job.id, err = "unknown sync work " .. tostring(job.op) }
    elseif not result[1] then
      reply = { id = job.id, err = tostring(result[2]) }
    else
      local values = { n = result.n - 1 }
      for i = 2, result.n do values[i - 1] = result[i] end
      reply = { id = job.id, values = values }
    end
    if not pcall(resCh.push, resCh, reply) then
      resCh:push({ id = job.id, lost = true })
    end
  end
end
