local Store = require("src.box.Store")
local Catalog = require("src.box.Catalog")
local GameVersion = require("src.core.GameVersion")
local Items = { MAX = 999 }

function Items.family(generation) return generation == 3 and "gen3" or "gen12" end

local function placeholder(name)
  return type(name) ~= "string" or name == "" or name:match("^%?+$") ~= nil or name == "TERU-SAMA"
end

local function nameOf(def, id)
  if type(def) == "table" then return def.name or tostring(id) end
  return def or tostring(id)
end

local function technical(name) return tostring(name):upper():match("^[TH]M%s*%d") ~= nil end

function Items.key(generation, def, id)
  local name = nameOf(def, id)
  local key = tostring(name):upper():gsub("[%s_%p]", "")
  if generation < 3 and technical(name) then key = "G" .. generation .. ":" .. key end
  return key
end

function Items.isMail(def, id) return tostring(nameOf(def, id)):upper():find("MAIL", 1, true) ~= nil end

function Items.depositable(generation, data, id)
  local def = data.items and data.items[id]
  if type(def) ~= "table" or placeholder(def.name) or id == 0 then return false end
  if generation == 1 then
    return not def.keyItem and not tostring(id):find("BADGE", 1, true)
  elseif generation == 2 then
    return def.pocket ~= "KEY_ITEM" and def.canToss ~= false
  end
  return def.pocket ~= "KEY_ITEMS" and (tonumber(def.importance) or 0) == 0
end

local function withGen3(version, fn)
  return require("src.box.GameContext").withItems(version, fn)
end

function Items.bag(save, version)
  local generation, data = GameVersion.generation(version), Catalog.get(version)
  local counts = {}
  if generation == 3 then
    for _, slots in pairs(type(save.bag) == "table" and save.bag.pockets or {}) do
      for _, slot in ipairs(slots) do
        local id = tonumber(slot.id) or slot.id
        if id and (tonumber(slot.qty) or 0) > 0 then counts[id] = (counts[id] or 0) + slot.qty end
      end
    end
  else
    for id, count in pairs(save.inventory or {}) do
      if type(count) == "number" and count > 0 then counts[id] = count end
    end
  end
  local rows = {}
  for id, count in pairs(counts) do
    if Items.depositable(generation, data, id) then
      rows[#rows + 1] = { id = id, count = count, name = nameOf(data.items[id], id) }
    end
  end
  table.sort(rows, function(a, b) return a.name < b.name end)
  return rows
end

function Items.locker(state, family)
  local rows = {}
  for key, row in pairs(state.items and state.items[family] or {}) do
    rows[#rows + 1] = { key = key, name = row.name, count = row.count }
  end
  table.sort(rows, function(a, b) return a.name < b.name end)
  return rows
end

function Items.find(version, key)
  local generation, data = GameVersion.generation(version), Catalog.get(version)
  for id, def in pairs(data.items or {}) do
    if type(def) == "table" and not placeholder(def.name) and Items.key(generation, def, id) == key
        and Items.depositable(generation, data, id) then return id, def end
  end
end

local function add(state, family, key, name, count)
  state.items = state.items or {}
  state.items[family] = state.items[family] or {}
  local row = state.items[family][key]
  local total = (row and row.count or 0) + count
  if total > Items.MAX then return nil, "The locker holds at most " .. Items.MAX .. " of each item." end
  state.items[family][key] = { name = row and row.name or name, count = total }
  return true
end

local function take(state, family, key, count)
  local row = state.items and state.items[family] and state.items[family][key]
  if not row or row.count < count then return nil, "The locker does not have enough of that item." end
  row.count = row.count - count
  if row.count == 0 then state.items[family][key] = nil end
  return true
end

local function bagRemove(save, version, id, count)
  if GameVersion.generation(version) == 3 then
    return withGen3(version, function()
      local Bag = require("src.core.game3.bag")
      if type(save.bag) ~= "table" or not Bag.has(save.bag, id, count) then return nil end
      return Bag.remove(save.bag, id, count) or nil
    end)
  end
  if (save.inventory and save.inventory[id] or 0) < count then return nil end
  require("src.inventory.Bag").remove(save, id, count, Catalog.get(version))
  return true
end

local function bagAdd(save, version, id, count)
  if GameVersion.generation(version) == 3 then
    return withGen3(version, function()
      local Bag = require("src.core.game3.bag")
      save.bag = type(save.bag) == "table" and save.bag or Bag.new()
      if not Bag.canAdd(save.bag, id, count) then return nil end
      local ok, placed = Bag.add(save.bag, id, count)
      return ok and placed == count or nil
    end)
  end
  return require("src.inventory.Bag").add(save, id, count, Catalog.get(version)) or nil
end

function Items.deposit(state, save, version, id, count)
  local generation, data = GameVersion.generation(version), Catalog.get(version)
  count = math.floor(tonumber(count) or 0)
  if count < 1 then return nil, "Choose how many to deposit." end
  if not data.ready then return nil, "Import this game's ROM first." end
  if not Items.depositable(generation, data, id) then return nil, "Key items and badges stay in the game." end
  local nextState, nextSave = Store.copy(state), Store.copy(save)
  if not bagRemove(nextSave, version, id, count) then return nil, "The bag does not have that many." end
  local ok, why = add(nextState, Items.family(generation), Items.key(generation, data.items[id], id),
    nameOf(data.items[id], id), count)
  if not ok then return nil, why end
  nextState.revision = state.revision + 1
  return nextState, nextSave
end

function Items.withdraw(state, save, version, key, count)
  local generation = GameVersion.generation(version)
  count = math.floor(tonumber(count) or 0)
  if count < 1 then return nil, "Choose how many to withdraw." end
  if not Catalog.get(version).ready then return nil, "Import this game's ROM first." end
  local id = Items.find(version, key)
  if id == nil then return nil, "This game has no item by that name." end
  local nextState, nextSave = Store.copy(state), Store.copy(save)
  local ok, why = take(nextState, Items.family(generation), key, count)
  if not ok then return nil, why end
  if not bagAdd(nextSave, version, id, count) then return nil, "That bag pocket is full." end
  nextState.revision = state.revision + 1
  return nextState, nextSave
end

local function holder(state, ref)
  local entry = Store.at(state, ref and ref.box, ref and ref.slot)
  if not entry then return nil, "Choose a Pokémon in Box storage." end
  if entry.generation == 1 then return nil, "Gen 1 Pokémon cannot hold items." end
  if entry.mon.isEgg then return nil, "Eggs cannot hold items." end
  return entry
end

local function refresh(entry)
  entry.display = Catalog.describe(entry.version, entry.mon)
  entry.gciRaw, entry.gciOriginal = nil, nil
end

local function heldId(entry)
  local item = entry.mon.heldItem or entry.mon.item
  if item == 0 then return nil end
  return item
end

local function stash(state, entry)
  local item = heldId(entry)
  if item == nil then return true end
  local data = Catalog.get(entry.version)
  if Items.isMail(data.items[item], item) then return nil, "Mail stays with its Pokémon. Take it off in the game." end
  if not Catalog.knownItem(data, item) then return nil, "The held item is unknown." end
  local ok, why = add(state, Items.family(entry.generation), Items.key(entry.generation, data.items[item], item),
    nameOf(data.items[item], item), 1)
  if not ok then return nil, why end
  if entry.generation == 3 then entry.mon.heldItem = 0 else entry.mon.item = nil end
  return true
end

function Items.give(state, ref, key)
  local nextState = Store.copy(state)
  local entry, why = holder(nextState, ref)
  if not entry then return nil, why end
  local id, def = Items.find(entry.version, key)
  if id == nil then return nil, "This Pokémon's game has no item by that name." end
  if Items.isMail(def, id) then return nil, "Mail needs a message. Give it in the game." end
  local ok, err = stash(nextState, entry)
  if not ok then return nil, err end
  ok, err = take(nextState, Items.family(entry.generation), key, 1)
  if not ok then return nil, err end
  if entry.generation == 3 then entry.mon.heldItem = id else entry.mon.item = id end
  refresh(entry)
  nextState.revision = state.revision + 1
  return nextState
end

function Items.takeHeld(state, ref)
  local nextState = Store.copy(state)
  local entry, why = holder(nextState, ref)
  if not entry then return nil, why end
  if heldId(entry) == nil then return nil, "This Pokémon is not holding anything." end
  local ok, err = stash(nextState, entry)
  if not ok then return nil, err end
  refresh(entry)
  nextState.revision = state.revision + 1
  return nextState
end

function Items.balls(state)
  local rows = {}
  for _, row in ipairs(Items.locker(state, "gen3")) do
    if row.name:upper():find("BALL", 1, true) then rows[#rows + 1] = row end
  end
  return rows
end

function Items.swapBall(state, ref, key)
  local nextState = Store.copy(state)
  local entry = Store.at(nextState, ref and ref.box, ref and ref.slot)
  if not entry then return nil, "Choose a Pokémon in Box storage." end
  if entry.generation ~= 3 then return nil, "Only Gen 3 Pokémon remember their ball." end
  if entry.mon.isEgg then return nil, "Eggs have no ball yet." end
  local id, def = Items.find(entry.version, key)
  if id == nil or type(def) ~= "table" or def.pocket ~= "POKE_BALLS" then return nil, "Choose a ball." end
  if tonumber(entry.mon.pokeball) == id then return nil, "It is already in that ball." end
  local ok, why = take(nextState, "gen3", key, 1)
  if not ok then return nil, why end
  entry.mon.pokeball = id
  refresh(entry)
  nextState.revision = state.revision + 1
  return nextState
end

function Items.validate(items)
  if items == nil then return true end
  if type(items) ~= "table" then return false end
  for family, rows in pairs(items) do
    if (family ~= "gen12" and family ~= "gen3") or type(rows) ~= "table" then return false end
    for key, row in pairs(rows) do
      if type(key) ~= "string" or #key == 0 or #key > 64 or type(row) ~= "table"
          or type(row.name) ~= "string" or #row.name == 0 or #row.name > 64
          or type(row.count) ~= "number" or row.count % 1 ~= 0 or row.count < 1 or row.count > Items.MAX then
        return false
      end
    end
  end
  return true
end

return Items
