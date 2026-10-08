local Origin = {}

Origin.KEY = "unionOrigin"

local FIELDS = { map = "string", x = "number", y = "number" }

local function valid(o)
  if type(o) ~= "table" then return false end
  for k, t in pairs(FIELDS) do
    if type(o[k]) ~= t then return false end
  end
  return o.gen == 1 or o.gen == 2 or o.gen == 3
end

function Origin.record(save, o)
  if type(save) ~= "table" then return nil end
  local rec = {
    gen = o.gen, version = o.version, map = o.map, warp = o.warp,
    x = o.x, y = o.y, facing = o.facing, at = o.at or os.time(),
  }
  if not valid(rec) then return nil end
  save[Origin.KEY] = rec
  return rec
end

function Origin.get(save)
  local o = type(save) == "table" and save[Origin.KEY] or nil
  if valid(o) then return o end
  return nil
end

function Origin.clear(save)
  if type(save) == "table" then save[Origin.KEY] = nil end
end

return Origin
