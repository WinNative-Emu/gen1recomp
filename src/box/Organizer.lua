local Store = require("src.box.Store")
local Records = require("src.box.Records")
local Catalog = require("src.box.Catalog")
local GameVersion = require("src.core.GameVersion")
local Organizer = {}
Organizer.SORTS = { "species", "name", "level", "type", "nature", "ability", "trainer", "shiny", "egg", "friendship" }
Organizer.LABELS = { species = "Pokédex number", name = "Nickname", level = "Level", type = "Type",
  nature = "Nature", ability = "Ability", trainer = "Trainer", shiny = "Shiny", egg = "Egg", friendship = "Friendship" }
Organizer.FIELDS = { "shiny", "egg", "species", "type", "levelMin", "levelMax", "nature", "ability",
  "gender", "trainer", "game", "mark", "tag", "name", "move", "item" }
Organizer.FIELD_LABELS = { shiny = "Shiny", egg = "Egg", species = "Species", type = "Type",
  levelMin = "Level at least", levelMax = "Level at most", nature = "Nature", ability = "Ability",
  gender = "Gender", trainer = "Trainer", game = "Game", mark = "Marked", tag = "Tag contains",
  name = "Nickname", move = "Move", item = "Held item" }
function Organizer.available(field, version)
  if not version then return true end
  local generation = GameVersion.generation(version)
  if field == "tag" then return false end
  if generation < 3 and (field == "mark" or field == "nature" or field == "ability") then return false end
  if generation == 1 and (field == "gender" or field == "egg" or field == "item") then return false end
  return true
end
local function integer(n, lo, hi)
  return type(n) == "number" and n == math.floor(n) and n >= lo and n <= hi
end
local function contains(list, value)
  for _, item in ipairs(list) do if item == value then return true end end
  return false
end
local function array(list, max)
  if type(list) ~= "table" or #list > max then return false end
  for key in pairs(list) do if not integer(key, 1, #list) then return false end end
  return true
end
function Organizer.validate(config, count)
  count = count or Store.BOXES
  if type(config) ~= "table" or (config.mode ~= "sort" and config.mode ~= "rules")
      or not contains(Organizer.SORTS, config.sort)
      or type(config.descending) ~= "boolean"
      or config.box ~= nil and not integer(config.box, 1, count) then
    return nil, "Choose a valid sort and box."
  end
  if config.mode == "sort" then
    if config.rules ~= nil then
      local ruleConfig = Store.copy(config)
      ruleConfig.mode, ruleConfig.box = "rules", nil
      return Organizer.validate(ruleConfig)
    end
    return true
  end
  if config.box ~= nil or not array(config.rules, 24) or #config.rules == 0
      or (config.fallback ~= "keep" and config.fallback ~= "sort") then
    return nil, "Add a rule and choose what happens to the rest."
  end
  for index, rule in ipairs(config.rules) do
    if type(rule) ~= "table" or not integer(rule.firstBox, 1, count)
        or not integer(rule.lastBox, rule.firstBox, count) then
      return nil, "Rule " .. index .. " needs a destination available in this collection."
    end
    if not array(rule.conditions, 8) or #rule.conditions == 0
        or (rule.match ~= "all" and rule.match ~= "any") then
      return nil, "Rule " .. index .. " needs a condition."
    end
    for _, condition in ipairs(rule.conditions) do
      if type(condition) ~= "table" or not contains(Organizer.FIELDS, condition.field) then
        return nil, "A rule condition is invalid."
      end
      local field, value = condition.field, condition.value
      if field == "shiny" or field == "egg" then
        if type(value) ~= "boolean" then return nil, "Choose yes or no for this condition." end
      elseif field == "levelMin" or field == "levelMax" then
        if not integer(value, 0, 255) then return nil, "Choose a level from 0 to 255." end
      elseif type(value) ~= "string" or #value == 0 or #value > 128 or value:find("%c") then
        return nil, "Choose a value for this condition."
      elseif field == "game" and not GameVersion.VERSIONS[value]
          or field == "mark" and not contains({ "circle", "square", "triangle", "heart" }, value) then
        return nil, "Choose a valid game or marking."
      end
    end
  end
  return true
end

local function normalized(value) return require("src.box.Search").normalize(value) end
local function matches(entry, condition)
  local d, field, wanted = entry.display, condition.field, condition.value
  if field == "shiny" or field == "egg" then return (d[field] == true) == wanted end
  if field == "levelMin" then return tonumber(d.level) ~= nil and tonumber(d.level) >= wanted end
  if field == "levelMax" then return tonumber(d.level) ~= nil and tonumber(d.level) <= wanted end
  if field == "mark" then
    local mask = ({ circle = 1, square = 2, triangle = 4, heart = 8 })[wanted]
    local value = tonumber(entry.generation == 3 and entry.mon.markings or entry.markings) or 0
    return math.floor(value / mask) % 2 == 1
  end
  if field == "tag" then return normalized(entry.tags):find(normalized(wanted), 1, true) ~= nil end
  if field == "type" then
    for item in tostring(d.types or ""):gmatch("[^/]+") do
      if normalized(item:match("^%s*(.-)%s*$")) == normalized(wanted) then return true end
    end
    return false
  end
  if field == "move" then
    for item in tostring(d.moves or ""):gmatch("[^,]+") do
      if normalized(item:match("^%s*(.-)%s*$")) == normalized(wanted) then return true end
    end
    return false
  end
  local value = field == "game" and entry.version or d[field]
  return value ~= nil and normalized(value) == normalized(wanted)
end
local function ruleMatches(entry, rule)
  for _, condition in ipairs(rule.conditions) do
    local hit = matches(entry, condition)
    if rule.match == "any" and hit then return true end
    if rule.match == "all" and not hit then return false end
  end
  return rule.match == "all"
end
local function sortValue(entry, field)
  local d = entry.display
  if field == "species" then
    local national = tonumber(d.national)
    return national and national > 0 and national or nil
  end
  if field == "type" then return d.types and d.types ~= "" and normalized(d.types) or nil end
  if field == "shiny" or field == "egg" then return d[field] and 1 or 0 end
  if field == "level" or field == "friendship" then return tonumber(d[field]) end
  return d[field] and d[field] ~= "" and normalized(d[field]) or nil
end
local function compare(a, b, config)
  local av, bv = sortValue(a.entry, config.sort), sortValue(b.entry, config.sort)
  if av == nil or bv == nil then
    if av ~= bv then return av ~= nil end
  elseif av ~= bv then
    if config.descending then return av > bv end
    return av < bv
  end
  for _, key in ipairs({ "species", "name", "level" }) do
    av, bv = sortValue(a.entry, key), sortValue(b.entry, key)
    if av == nil or bv == nil then
      if av ~= bv then return av ~= nil end
    elseif av ~= bv then return av < bv end
  end
  return a.box < b.box or a.box == b.box and a.slot < b.slot
end

function Organizer.warehouse(state)
  local layout = { count = Store.BOXES, capacity = Store.SLOTS, rows = {}, names = {} }
  for b, box in ipairs(state.boxes) do
    layout.names[b] = box.name
    for slot = 1, Store.SLOTS do
      if box.mons[slot] then layout.rows[#layout.rows + 1] = { box = b, slot = slot, entry = box.mons[slot] } end
    end
  end
  return layout
end
function Organizer.game(save, version)
  if not GameVersion.VERSIONS[version] then return nil, "Choose a supported game." end
  local generation = GameVersion.generation(version)
  if not Catalog.get(version).ready then return nil, "Import this game's ROM before organizing its PC." end
  local layout = { count = generation == 1 and 12 or 14, capacity = generation == 3 and 30 or 20,
    rows = {}, names = {}, compact = generation < 3 }
  local boxes = Records.boxes(save, generation)
  if type(boxes) ~= "table" then return nil, "This save's PC could not be read." end
  for b, box in pairs(boxes) do
    if not integer(b, 1, layout.count) or type(box) ~= "table" then
      return nil, "This save has a PC box this tool cannot represent."
    end
  end
  for b = 1, layout.count do
    local list = Records.list(save, generation, b)
    if type(list) ~= "table" then return nil, "A PC box could not be read." end
    local seen = {}
    for key, mon in pairs(list) do
      local slot = tonumber(key)
      if not integer(slot, 1, layout.capacity) or type(mon) ~= "table" or seen[slot] then
        return nil, "A PC record is invalid or appears twice in one slot."
      end
      seen[slot] = true
    end
    local box = boxes[b]
    layout.names[b] = generation == 3 and box and box.name or save.boxNames and save.boxNames[b] or "BOX " .. b
    for slot = 1, layout.capacity do
      local mon = list[slot] or list[tostring(slot)]
      if mon then layout.rows[#layout.rows + 1] = { box = b, slot = slot,
        entry = { version = version, generation = generation, mon = mon, display = Catalog.describe(version, mon) } } end
    end
  end
  return layout
end

function Organizer.analyze(layout, config)
  local valid, why = Organizer.validate(config, layout.count)
  if not valid then return nil, why end
  local counts, reserved, rest = {}, {}, 0
  for i, rule in ipairs(config.mode == "rules" and config.rules or {}) do
    counts[i] = 0
    for b = rule.firstBox, rule.lastBox do reserved[b] = true end
  end
  for _, row in ipairs(layout.rows) do
    local found
    for i, rule in ipairs(config.mode == "rules" and config.rules or {}) do
      if ruleMatches(row.entry, rule) then counts[i], found = counts[i] + 1, true; break end
    end
    if not found then rest = rest + 1 end
  end
  local free = 0
  for b = 1, layout.count do if not reserved[b] then free = free + 1 end end
  return { ruleCounts = counts, remaining = rest, reserved = reserved, freeBoxes = free, total = #layout.rows }
end

function Organizer.plan(layout, config)
  local valid, why = Organizer.validate(config, layout.count)
  if not valid then return nil, why end
  local boxes, groups, rest, reserved = {}, {}, {}, {}
  local report = { total = #layout.rows, moved = 0, ruleCounts = {}, boxes = {}, assignments = {} }
  for b = 1, layout.count do
    boxes[b] = {}
    report.boxes[b] = { name = layout.names[b], before = 0, after = 0, capacity = layout.capacity, moved = 0 }
  end
  for i, rule in ipairs(config.mode == "rules" and config.rules or {}) do
    groups[i], report.ruleCounts[i] = {}, 0
    for b = rule.firstBox, rule.lastBox do reserved[b] = true end
  end
  for _, row in ipairs(layout.rows) do
    report.boxes[row.box].before = report.boxes[row.box].before + 1
    local chosen
    if config.mode == "rules" then
      for i, rule in ipairs(config.rules) do
        if ruleMatches(row.entry, rule) then chosen = i; break end
      end
    end
    if chosen then
      groups[chosen][#groups[chosen] + 1] = row
      report.ruleCounts[chosen] = report.ruleCounts[chosen] + 1
    elseif config.mode == "rules" and config.fallback == "keep"
        or config.mode == "sort" and config.box and row.box ~= config.box then
      boxes[row.box][row.slot] = row
    else rest[#rest + 1] = row end
  end
  local function place(rows, firstBox, lastBox, skipReserved)
    table.sort(rows, function(a, b) return compare(a, b, config) end)
    local index = 1
    for b = firstBox, lastBox do
      if not skipReserved or not reserved[b] then
        for slot = 1, layout.capacity do
          if not boxes[b][slot] and rows[index] then boxes[b][slot], index = rows[index], index + 1 end
        end
      end
    end
    return index > #rows
  end
  if config.mode == "rules" then
    for i, rule in ipairs(config.rules) do
      if not place(groups[i], rule.firstBox, rule.lastBox) then
        return nil, "Rule " .. i .. " needs more room in its destination. Widen its box range."
      end
    end
  end
  if not place(rest, config.box or 1, config.box or layout.count, config.mode == "rules") then
    return nil, "The remaining Pokémon need more room outside the rule boxes. Keep their boxes or free a destination."
  end
  for b = 1, layout.count do
    if layout.compact and (config.mode == "rules" or not config.box or config.box == b) then
      local dense = {}
      for slot = 1, layout.capacity do if boxes[b][slot] then dense[#dense + 1] = boxes[b][slot] end end
      boxes[b] = dense
    end
    for slot = 1, layout.capacity do
      local row = boxes[b][slot]
      if row then
        report.boxes[b].after = report.boxes[b].after + 1
        local moved = row.box ~= b or row.slot ~= slot
        if moved then report.moved, report.boxes[b].moved = report.moved + 1, report.boxes[b].moved + 1 end
        report.assignments[#report.assignments + 1] = { fromBox = row.box, fromSlot = row.slot,
          box = b, slot = slot, entry = row.entry, moved = moved }
      end
    end
  end
  return report, boxes
end

function Organizer.applyWarehouse(state, config)
  local report, boxes = Organizer.plan(Organizer.warehouse(state), config)
  if not report then return nil, boxes end
  local nextState = Store.copy(state)
  for b = 1, Store.BOXES do
    nextState.boxes[b].mons = {}
    for slot, row in pairs(boxes[b]) do nextState.boxes[b].mons[slot] = Store.copy(row.entry) end
  end
  nextState.revision = state.revision + 1
  return nextState, report
end
function Organizer.applyGame(save, version, config)
  local layout, why = Organizer.game(save, version)
  if not layout then return nil, why end
  local valid, err = Organizer.validate(config, layout.count)
  if not valid then return nil, err end
  if config.mode == "rules" then
    for _, rule in ipairs(config.rules) do
      for _, condition in ipairs(rule.conditions) do
        if not Organizer.available(condition.field, version) then
          return nil, GameVersion.info(version).label .. "'s Game PC doesn't record "
            .. Organizer.FIELD_LABELS[condition.field] .. ". Choose another condition."
        end
      end
    end
  end
  local report, boxes = Organizer.plan(layout, config)
  if not report then return nil, boxes end
  local nextSave, generation = Store.copy(save), GameVersion.generation(version)
  if generation == 3 then
    nextSave.storage = nextSave.storage or { currentBox = 1, boxes = {} }
    nextSave.storage.boxes = nextSave.storage.boxes or {}
    for b = 1, layout.count do
      if config.mode == "rules" or not config.box or config.box == b then
      local box = nextSave.storage.boxes[b] or { name = layout.names[b], wallpaper = 0 }
      box.mons = {}; nextSave.storage.boxes[b] = box
      for slot, row in pairs(boxes[b]) do box.mons[slot] = Store.copy(row.entry.mon) end
      end
    end
  else
    nextSave.boxes, nextSave.box = Records.boxes(nextSave, generation), nil
    for b = 1, layout.count do
      if config.mode == "rules" or not config.box or config.box == b then
      nextSave.boxes[b] = {}
      for slot, row in pairs(boxes[b]) do nextSave.boxes[b][slot] = Store.copy(row.entry.mon) end
      end
    end
  end
  return nextSave, report
end
return Organizer
