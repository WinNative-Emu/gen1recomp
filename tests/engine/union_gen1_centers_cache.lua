package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local UnionCenters = require("src.world.gen1.UnionCenters")
local Map = require("src.world.Map")
local UnionSafety = require("src.world.gen1.UnionSafety")

local MODULES = { "maps", "tilesets", "text_pointers", "field", "audio" }

local function cacheRoot(version)
  local home = os.getenv("HOME")
  if not home or home == "" then return nil end
  local ids = {}
  local env = os.getenv("POKEPORT_IDENTITY")
  if env and env ~= "" then ids[#ids + 1] = env end
  ids[#ids + 1] = "g1r-" .. version
  ids[#ids + 1] = "pokeport-test-caches"
  for _, base in ipairs({ home .. "/Library/Application Support/LOVE", home .. "/.local/share/love" }) do
    for _, id in ipairs(ids) do
      local root = base .. "/" .. id .. "/" .. version .. "/data/generated/"
      local f = io.open(root .. "maps.lua", "rb")
      if f then f:close() return root end
    end
  end
  return nil
end

local function loadData(root)
  local data = {}
  for _, name in ipairs(MODULES) do
    local f = io.open(root .. name .. ".lua", "rb")
    if not f then return nil end
    local chunk = load(f:read("*a"), "@" .. name, "t", {})
    f:close()
    local ok, mod = pcall(chunk)
    if not ok then return nil end
    data[name] = mod
  end
  return data
end

local found = 0
for _, version in ipairs({ "red", "blue", "yellow" }) do
  local root = cacheRoot(version)
  local data = root and loadData(root)
  if data then
    found = found + 1
    local r, why = UnionCenters.apply(data)
    check(r ~= nil, version .. ": apply on the real cache: " .. tostring(why))
    if r then
      eq(#r.order, #UnionCenters.EXPECTED, version .. ": every Gen 1 center planned")
      for _, id in ipairs(UnionCenters.EXPECTED) do
        local plan = r.plans[id]
        check(plan and plan.verified, ("%s: %s matches the expected desk pattern (%s)")
          :format(version, id, tostring(r.refused[id])))
        if plan then
          local ts = data.tilesets[plan.tileset]
          local m = Map.new(data.maps[id], ts)
          check(m:isWarpTileCell(plan.stairs.x, plan.stairs.y), version .. ": " .. id .. " stairs are a warp tile")
          check(not m:isWalkableCell(plan.desk.bx * 2, plan.desk.by * 2 - 1), version .. ": " .. id .. " nurse side sealed")
          check(m:isWalkableCell(plan.front.x, plan.front.y), version .. ": " .. id .. " desk front walkable")
          local pcOk = false
          for _, h in ipairs(data.field.hiddenExtras.pcTiles[id] or {}) do
            if h.x == plan.pc.x and h.y == plan.pc.y then pcOk = true end
          end
          check(pcOk and not m:isWalkableCell(plan.pc.x, plan.pc.y), version .. ": " .. id .. " PC kept")
          local front = UnionSafety.nurseFront(data, id)
          check(front and m:isWalkableCell(front.x, front.y) and m:isCounterCell(front.x, front.y - 1),
                version .. ": " .. id .. " nurse front is a walkable cell across the counter")
          check(UnionSafety.townOf(data, id) ~= nil, version .. ": " .. id .. " has a town door for lastOutdoor")
          check(UnionSafety.centerOfTown(data, (UnionSafety.townOf(data, id))) == id,
                version .. ": " .. id .. " is found again from its town")
        end
      end
      for id, reason in pairs(r.refused) do
        check(false, ("%s: unexpected refusal %s: %s"):format(version, id, reason))
      end
      local indigo = r.plans.INDIGO_PLATEAU_LOBBY
      eq(indigo and indigo.stairs.x .. "," .. indigo.stairs.y, "15,5", version .. ": Indigo stairs cell")
      eq(indigo and indigo.receptionist.x .. "," .. indigo.receptionist.y, "13,6", version .. ": Indigo desk position")
      check(data.maps[UnionCenters.FLOOR_2F] and data.maps[UnionCenters.UNION_ROOM], version .. ": added maps present")
    end
  end
end

if found == 0 then
  print("[skip] union_gen1_centers_cache: no Gen 1 cache")
  os.exit(0)
end

T.finish("union_gen1_centers_cache")
