local Recommend = {}

Recommend.PATH = "/recommend/gen"
Recommend.FETCH_SECONDS = 15
Recommend.MAX_BATCH = 64

Recommend.RENAMED = {
  FEINTATTACK = "FAINTATTACK",
  HIGHJUMPKICK = "HIJUMPKICK",
  SMELLINGSALTS = "SMELLINGSALT",
}

local RENAMED = Recommend.RENAMED
local store = {}

function Recommend.reset()
  store = {}
end

function Recommend.key(name)
  local s = tostring(name or ""):gsub("\226\153\130", "m"):gsub("\226\153\128", "f")
  return (s:lower():gsub("[^a-z0-9]", ""))
end

local function moveToken(name)
  return (tostring(name or ""):upper():gsub("[^A-Z0-9]", ""))
end

local function bucket(generation)
  store[generation] = store[generation] or {}
  return store[generation]
end

function Recommend.cached(generation, species)
  local hit = bucket(generation)[Recommend.key(species)]
  if hit == nil then return nil end
  return hit or nil, hit == false
end

local function remember(generation, keys, sets)
  local b = bucket(generation)
  for _, k in ipairs(keys) do
    local entry = type(sets) == "table" and sets[k] or nil
    if type(entry) == "table" and type(entry.set) == "table" and type(entry.set.moves) == "table" then
      b[k] = entry
    else
      b[k] = false
    end
  end
end

function Recommend.request(generation, species, opts)
  opts = opts or {}
  generation = tonumber(generation)
  if generation ~= 1 and generation ~= 2 and generation ~= 3 then
    return { status = "error", reason = "bad_generation" }
  end
  local list = type(species) == "table" and species or { species }
  local keys, seen, out = {}, {}, {}
  for _, name in ipairs(list) do
    local k = Recommend.key(name)
    if k ~= "" and not seen[k] then
      seen[k] = true
      local hit = bucket(generation)[k]
      if hit == nil then
        keys[#keys + 1] = k
      elseif hit then
        out[k] = hit
      end
    end
  end
  if #keys == 0 then
    return { status = "ok", generation = generation, result = out }
  end
  if #keys > Recommend.MAX_BATCH then
    return { status = "error", reason = "too_many" }
  end
  local client = opts.client
  if not client then
    local okS, SyncClient = pcall(require, "src.sync.SyncClient")
    if not okS then return { status = "error", reason = "offline" } end
    local okN, made = pcall(SyncClient.new, { transport = opts.transport })
    if not okN then return { status = "error", reason = "offline" } end
    client = made
  end
  local okR, handle = pcall(client.send, client, "GET", Recommend.PATH .. generation, nil, {
    noAuth = true, maxSeconds = Recommend.FETCH_SECONDS,
    params = { species = table.concat(keys, ",") },
  })
  if not okR or handle == nil then
    return { status = "error", reason = "offline" }
  end
  return { status = "pending", generation = generation, client = client, handle = handle,
    keys = keys, result = out }
end

function Recommend.poll(job)
  if type(job) ~= "table" then return "error", "offline" end
  if job.status == "ok" then return "ok", job.result end
  if job.status == "error" then return "error", job.reason end
  local ok, res = pcall(job.client.poll, job.client, job.handle)
  if not ok or type(res) ~= "table" then res = { status = "error" } end
  if res.status == "pending" then return "pending" end
  pcall(job.client.release, job.client, job.handle)
  job.handle = nil
  if res.status ~= "ok" or type(res.data) ~= "table" or type(res.data.sets) ~= "table" then
    job.status = "error"
    job.reason = (tonumber(res.code) or 0) >= 400 and "server" or "offline"
    return "error", job.reason
  end
  remember(job.generation, job.keys, res.data.sets)
  for _, k in ipairs(job.keys) do
    local hit = bucket(job.generation)[k]
    if hit then job.result[k] = hit end
  end
  job.status = "ok"
  return "ok", job.result
end

function Recommend.cancel(job)
  if type(job) ~= "table" or job.handle == nil then return end
  local transport = job.client and job.client.transport
  if transport and transport.cancel then pcall(transport.cancel, transport, job.handle) end
  pcall(job.client.release, job.client, job.handle)
  job.handle = nil
  job.status, job.reason = "error", "canceled"
end

function Recommend.get(job, species)
  return type(job) == "table" and type(job.result) == "table" and job.result[Recommend.key(species)] or nil
end

local function moveIndex(version)
  local data = require("src.box.Catalog").get(version)
  local index = {}
  for key, value in pairs(data.moves or {}) do
    local name = type(value) == "table" and (value.name or value.id) or value
    local token = moveToken(name)
    if token ~= "" and key ~= 0 then
      if index[token] == nil then index[token] = key else index[token] = false end
    end
  end
  return index, data
end

function Recommend.hiddenPowerType(name)
  local t = tostring(name or ""):match("^[Hh]idden [Pp]ower%s+(%a+)")
  return t and t:upper() or nil
end

function Recommend.resolveMoves(entry, version)
  local set = type(entry) == "table" and (entry.set or entry) or {}
  local index = moveIndex(version)
  local keys, missing, seen = {}, {}, {}
  local hpType
  for _, name in ipairs(set.moves or {}) do
    if type(name) == "table" then name = name[1] end
    local token = moveToken(name)
    local hp = Recommend.hiddenPowerType(name)
    if hp then
      token, hpType = "HIDDENPOWER", hp
    end
    token = RENAMED[token] and index[RENAMED[token]] ~= nil and RENAMED[token] or token
    local key = index[token]
    if key and not seen[key] then
      seen[key] = true
      keys[#keys + 1] = key
    elseif not key then
      missing[#missing + 1] = tostring(name)
    end
  end
  return keys, missing, hpType
end

return Recommend
