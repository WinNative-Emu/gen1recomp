local Merge = require("src.mods.Merge")
local Ids = {}
local aliases = { FARFETCH_D = "FARFETCHD", MR__MIME = "MR_MIME" }
local inverse = { FARFETCHD = "FARFETCH_D", MR_MIME = "MR__MIME" }
local typeAliases = { PSYCHIC = "PSYCHIC_TYPE", MYSTERY = "CURSE_TYPE" }
local typeInverse = { PSYCHIC_TYPE = "PSYCHIC", CURSE_TYPE = "MYSTERY" }
function Ids.canonical(id, kind, generation)
  if generation == 2 and kind == "species" then return aliases[id] or id end
  if generation == 3 and kind == "type" then return typeAliases[id] or id end
  return id
end
function Ids.native(id, kind, generation, contains)
  if generation == 3 and kind == "type" then return typeInverse[id] or id end
  local target = generation == 2 and kind == "species" and inverse[id]
  if target and (not contains or contains(target)) then return target end
  return id
end
local references = { species = true, into = true, fromSpecies = true, toSpecies = true }
function Ids.record(value, generation, toNative, contains, speciesRoot)
  local seen = {}
  local function visit(row, root)
    if type(row) ~= "table" or row == Merge.DELETE then return row end
    if seen[row] then return seen[row] end
    local out = {}; seen[row] = out
    for key, sub in pairs(row) do
      if key == "native" then out[key] = Merge.deepCopy(sub)
      elseif type(sub) == "string" and (references[key] or (root and key == "id")) then
        out[key] = toNative and Ids.native(sub, "species", generation, contains)
          or Ids.canonical(sub, "species", generation)
      else out[key] = visit(sub, false) end
    end
    return out
  end
  return visit(value, speciesRoot)
end
return Ids
