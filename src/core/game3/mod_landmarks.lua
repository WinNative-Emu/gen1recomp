local ModLandmarks = {}

local undo = {}

local function remember(fn)
  undo[#undo + 1] = fn
end

function ModLandmarks.reset()
  for i = #undo, 1, -1 do undo[i]() end
  undo = {}
end

local function sorted(records)
  local list = {}
  for id, record in pairs(records) do
    if type(record) == "table" and tonumber(record.index) then
      list[#list + 1] = { key = id, record = record, index = tonumber(record.index) }
    end
  end
  table.sort(list, function(a, b)
    if a.index ~= b.index then return a.index < b.index end
    return tostring(a.key) < tostring(b.key)
  end)
  return list
end

local function setCell(grid, row, col, value)
  local line = grid[row]
  if type(line) ~= "table" then return end
  local previous = line[col]
  if previous == nil then return end
  line[col] = value
  remember(function() line[col] = previous end)
end

-- pokefirered/src/data/region_map/region_map_entries.h:9
local function installFrlg(item)
  local Sections = require("src.import.gba.map_sections_extract")
  local Region = require("src.import.gba.region_map_extract")
  pcall(Sections.ensureGenerated)
  pcall(Region.ensureGenerated)
  local index, record = item.index, item.record
  local previous = Sections.SECTIONS[index]
  local symbol = (previous and previous.id) or record.id or ("MAPSEC_MOD_" .. index)
  Sections.SECTIONS[index] = {
    id = symbol, name = record.name,
    theme = record.theme or (previous and previous.theme) or "marble",
  }
  local hadId = Sections.ID_TO_SECTION[symbol]
  Sections.ID_TO_SECTION[symbol] = index
  local hadName = Region.SECTION_NAMES[symbol]
  Region.SECTION_NAMES[symbol] = record.name
  remember(function()
    Sections.SECTIONS[index] = previous
    Sections.ID_TO_SECTION[symbol] = hadId
    Region.SECTION_NAMES[symbol] = hadName
  end)
  if record.x and record.y and Region.LAYOUTS then
    local layout = Region.LAYOUTS[record.region or 0]
    local grid = layout and layout.map
    for dy = 0, (record.height or 1) - 1 do
      for dx = 0, (record.width or 1) - 1 do
        if grid then setCell(grid, record.y + dy, record.x + dx, index) end
      end
    end
  end
end

-- pokeemerald/src/data/region_map/region_map_entries.h:207
local function installRse(item)
  local Mapsec = require("src.ui.game3.rse.mapsec")
  local pack = Mapsec.pack()
  local index, record = item.index, item.record
  local previous = pack.sections[index]
  local entry = {}
  for key, value in pairs(previous or {}) do entry[key] = value end
  entry.name = record.name
  entry.id = (previous and previous.id) or record.id
  entry.theme = record.theme or entry.theme
  entry.themeId = nil
  for _, key in ipairs({ "x", "y", "width", "height" }) do
    if record[key] ~= nil then entry[key] = record[key] end
  end
  entry.x, entry.y = entry.x or 0, entry.y or 0
  entry.width, entry.height = entry.width or 1, entry.height or 1
  pack.sections[index] = entry
  local count = pack.count
  if type(count) == "number" and index >= count then pack.count = index + 1 end
  remember(function()
    pack.sections[index] = previous
    pack.count = count
  end)
  if record.x and record.y then
    local RegionMap = require("src.ui.game3.rse.region_map")
    local layout = RegionMap.manifest().layout
    for dy = 0, entry.height - 1 do
      for dx = 0, entry.width - 1 do
        setCell(layout, entry.y + dy + 1, entry.x + dx + 1, index)
      end
    end
  end
end

function ModLandmarks.install(records, family)
  ModLandmarks.reset()
  if type(records) ~= "table" or next(records) == nil then return end
  for _, item in ipairs(sorted(records)) do
    if family == "rse" then installRse(item) else installFrlg(item) end
  end
end

return ModLandmarks
