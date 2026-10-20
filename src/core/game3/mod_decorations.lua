local ModDecorations = {}

local undo = {}

function ModDecorations.reset()
  for i = #undo, 1, -1 do undo[i]() end
  undo = {}
end

-- pokeemerald/src/data/decoration/header.h:1
function ModDecorations.install(records)
  ModDecorations.reset()
  if type(records) ~= "table" or next(records) == nil then return end
  local DecorInv = require("src.core.game3.rse.decoration_inventory")
  local Decor = require("src.core.game3.rse.decoration")
  local rows = DecorInv.data().decorations
  local tiles = Decor.manifest().decorTiles
  local list = {}
  for key, record in pairs(records) do
    if type(record) == "table" and tonumber(record.index) then
      list[#list + 1] = { key = tostring(key), index = tonumber(record.index), record = record }
    end
  end
  table.sort(list, function(a, b)
    if a.index ~= b.index then return a.index < b.index end
    return a.key < b.key
  end)
  local top = Decor.NUM_DECORATIONS
  for _, item in ipairs(list) do
    local index, record = item.index, item.record
    local previousRow, previousTiles = rows[index], tiles[index]
    rows[index] = {
      id = index, name = record.name, permission = record.permission,
      shape = record.shape, category = record.category,
      price = record.price, description = record.description,
    }
    tiles[index] = record.tiles
    undo[#undo + 1] = function()
      rows[index], tiles[index] = previousRow, previousTiles
    end
    if index > top then top = index end
  end
  local previousTop = Decor.NUM_DECORATIONS
  Decor.NUM_DECORATIONS = top
  undo[#undo + 1] = function() Decor.NUM_DECORATIONS = previousTop end
end

return ModDecorations
