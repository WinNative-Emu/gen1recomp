local Catalog = require("src.box.Catalog")
local Context = {}

local function capture(t, nested)
  local rows = {}
  for k, v in pairs(t) do
    rows[k] = nested and type(v) == "table" and { table = v, rows = capture(v) } or { value = v }
  end
  return rows
end

local function restore(t, rows)
  for k in pairs(t) do t[k] = nil end
  for k, row in pairs(rows) do
    if row.rows then restore(row.table, row.rows); t[k] = row.table else t[k] = row.value end
  end
end

local function upvalue(fn, wanted)
  for i = 1, math.huge do
    local name, value = debug.getupvalue(fn, i)
    if name == nil then return nil end
    if name == wanted then return value end
  end
end

function Context.withItems(version, operation)
  local Items = require("src.core.game3.items_data")
  local tables = {}
  for _, key in ipairs({ "POCKET", "POCKET_RESULT", "POCKET_ORDER", "BAG_POCKET_ORDER",
      "CAPACITY", "PACK_POCKET", "CONTAINERS", "BAG_MODEL" }) do
    if type(Items[key]) == "table" then tables[#tables + 1] = { Items[key], capture(Items[key], key == "BAG_MODEL") } end
  end
  local labels = upvalue(Items.applyProfile, "LABEL_KEYS")
  if type(labels) == "table" then tables[#tables + 1] = { labels, capture(labels) } end
  local fields = capture(Items)
  local ok, a, b = pcall(function()
    local data = Catalog.get(version)
    if not data.ready then return nil, "Import this game's ROM before receiving an event." end
    Items.applyProfile(version)
    Items.installPack({ items = data.items })
    return operation()
  end)
  for _, row in ipairs(tables) do restore(row[1], row[2]) end
  restore(Items, fields)
  if not ok then return nil, tostring(a) end
  return a, b
end
return Context
