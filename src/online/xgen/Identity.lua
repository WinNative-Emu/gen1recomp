local Identity = {}

-- include/constants/pokemon.h:6
Identity.GEN3_TYPES = {
  [0] = "NORMAL", [1] = "FIGHTING", [2] = "FLYING", [3] = "POISON", [4] = "GROUND",
  [5] = "ROCK", [6] = "BUG", [7] = "GHOST", [8] = "STEEL", [9] = "MYSTERY",
  [10] = "FIRE", [11] = "WATER", [12] = "GRASS", [13] = "ELECTRIC", [14] = "PSYCHIC",
  [15] = "ICE", [16] = "DRAGON", [17] = "DARK",
}

Identity.TYPES = { "NORMAL", "FIGHTING", "FLYING", "POISON", "GROUND", "ROCK", "BUG", "GHOST",
  "STEEL", "FIRE", "WATER", "GRASS", "ELECTRIC", "PSYCHIC", "ICE", "DRAGON", "DARK" }

Identity.GEN1_TYPES = { "NORMAL", "FIGHTING", "FLYING", "POISON", "GROUND", "ROCK", "BUG", "GHOST",
  "FIRE", "WATER", "GRASS", "ELECTRIC", "PSYCHIC", "ICE", "DRAGON" }

local GEN3_TYPE_ID = {}
for id, name in pairs(Identity.GEN3_TYPES) do GEN3_TYPE_ID[name] = id end
Identity.GEN3_TYPE_ID = GEN3_TYPE_ID

local PHYSICAL = {}
-- include/battle.h:466
for id, name in pairs(Identity.GEN3_TYPES) do PHYSICAL[name] = id < 9 end
Identity.PHYSICAL = PHYSICAL

function Identity.normalize(name)
  if type(name) ~= "string" then return nil end
  local s = name:upper()
  s = s:gsub("\226\153\128", "F"):gsub("\226\153\130", "M")
  s = s:gsub("<F>", "F"):gsub("<M>", "M")
  s = s:gsub("\195\169", "E"):gsub("\195\137", "E")
  s = s:gsub("[^A-Z0-9]", "")
  if s == "" then return nil end
  return s
end

function Identity.canonType(value, generation)
  if generation == 3 or type(value) == "number" then
    return Identity.GEN3_TYPES[tonumber(value) or -1]
  end
  if type(value) ~= "string" then return nil end
  local s = value:upper():gsub("_TYPE$", "")
  if s == "CURSE" or s == "???" then return "MYSTERY" end
  if GEN3_TYPE_ID[s] then return s end
  return nil
end

function Identity.subsequence(short, long)
  if type(short) ~= "string" or type(long) ~= "string" then return false end
  local at = 1
  for i = 1, #short do
    local found = long:find(short:sub(i, i), at, true)
    if not found then return false end
    at = found + 1
  end
  return true
end

function Identity.category(typeName, power)
  if (tonumber(power) or 0) == 0 then return "status" end
  return PHYSICAL[typeName] and "physical" or "special"
end

function Identity.speciesOf(data, localKey)
  if type(data) ~= "table" or localKey == nil then return nil end
  local n = data.localToNational[localKey]
  if n == nil and data.generation == 3 then n = data.localToNational[tonumber(localKey)] end
  return n
end

function Identity.localSpecies(data, national)
  return data and data.nationalToLocal[tonumber(national) or -1] or nil
end

function Identity.moveOf(data, localKey)
  if type(data) ~= "table" or localKey == nil then return nil end
  local n = data.localToMove[localKey]
  if n == nil and data.generation == 3 then n = data.localToMove[tonumber(localKey)] end
  return n
end

function Identity.localMove(data, move)
  return data and data.moveToLocal[tonumber(move) or -1] or nil
end

function Identity.itemKey(data, localItem)
  if type(data) ~= "table" or localItem == nil or localItem == 0 then return nil end
  local row = data.items.byLocal[localItem]
  if row == nil and data.generation == 3 then row = data.items.byLocal[tonumber(localItem)] end
  return row and row.key or nil
end

function Identity.localItem(data, key)
  return data and key and data.items.byKey[key] or nil
end

function Identity.maps(data)
  return {
    species = { toCanonical = data.localToNational, toLocal = data.nationalToLocal },
    moves = { toCanonical = data.localToMove, toLocal = data.moveToLocal },
    types = { toCanonical = data.localToType, toLocal = data.typeToLocal },
    items = { toCanonical = data.items.byLocal, toLocal = data.items.byKey },
  }
end

local function compareNames(kind, a, b, out, max)
  local left = kind == "species" and a.species or a.moves
  local right = kind == "species" and b.species or b.moves
  local ids = {}
  for id in pairs(left) do
    if right[id] and id <= max then ids[#ids + 1] = id end
  end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local x, y = left[id].key, right[id].key
    if x ~= y and not Identity.subsequence(x, y) and not Identity.subsequence(y, x) then
      out[#out + 1] = { kind = kind, id = id, a = a.version, b = b.version, left = x, right = y }
    end
  end
end

function Identity.agree(a, b)
  local out = {}
  compareNames("species", a, b, out, math.min(a.dexMax, b.dexMax))
  compareNames("moves", a, b, out, math.min(a.moveMax, b.moveMax))
  return #out == 0, out
end

return Identity
