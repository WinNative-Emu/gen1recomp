local Store = require("src.box.Store")
local Collection = {}

function Collection.dashboard(state, save)
  local result = { total = 0, species = 0, eggs = 0, shiny = 0, forms = {}, duplicates = {}, caught = 0,
    held = {}, byGame = {}, missing = {} }
  for b = 1, Store.BOXES do
    for _, entry in pairs(state.boxes[b].mons) do
      local d = entry.display
      result.total = result.total + 1
      if d.egg then result.eggs = result.eggs + 1
      else
        local dex = d.national
        if dex then result.held[dex] = (result.held[dex] or 0) + 1 end
        if d.shiny then result.shiny = result.shiny + 1 end
        if dex == 201 then
          local letter
          if entry.generation == 2 then
            local Unown = require("src.core.gen2.Unown")
            local index = Unown.index(entry.mon.unownLetter)
              or type(entry.mon.dvs) == "table" and Unown.letterFromDVs(entry.mon.dvs)
            letter = index and index - 1
          elseif type(entry.mon.personality) == "number" then
            letter = require("src.core.game3.pokemon").unownLetter(entry.mon.personality)
          end
          if letter then result.forms[tostring(letter)] = true end
        end
      end
      result.byGame[entry.version] = (result.byGame[entry.version] or 0) + 1
    end
  end
  for dex, count in pairs(result.held) do
    result.species = result.species + 1
    if count > 1 then result.duplicates[#result.duplicates + 1] = { dex = dex, count = count } end
  end
  table.sort(result.duplicates, function(a, b) return a.dex < b.dex end)
  local pokedex = save and (save.dex or save.pokedex) or {}
  local caught = {}
  local data = save and save.version and require("src.box.Catalog").get(save.version)
  local function national(key)
    if not data then return tostring(key) end
    local def = data.pokemon and data.pokemon[key]
    return tostring(def and def.dex or data.national and (data.national.toNational or {})[tonumber(key)] or key)
  end
  for _, field in ipairs({ "caught", "owned" }) do
    for key, value in pairs(pokedex[field] or {}) do if value then caught[national(key)] = true end end
  end
  local imported = save and save.modData and save.modData.cartImport
  for _, dex in ipairs(imported and imported.dexOwned or {}) do caught[tostring(dex)] = true end
  for _ in pairs(caught) do result.caught = result.caught + 1 end
  for dex = 1, 386 do if not result.held[dex] then result.missing[#result.missing + 1] = dex end end
  return result
end

return Collection
