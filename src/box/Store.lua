local GameVersion = require("src.core.GameVersion")
local Serializer = require("src.core.SaveSerializer")

local Store = { PATH = "box/storage.lua", FORMAT = 1, BOXES = 25, SLOTS = 60 }
Store.THEMES = { "Launcher", "Forest", "Sky", "Brick", "Sunset", "Ocean", "Showcase" }

function Store.copy(value, seen)
  if type(value) ~= "table" then return value end
  seen = seen or {}
  if seen[value] then return seen[value] end
  local out = {}; seen[value] = out
  for k, v in pairs(value) do out[Store.copy(k, seen)] = Store.copy(v, seen) end
  return out
end

local function integer(n, lo, hi)
  return type(n) == "number" and n == math.floor(n) and n >= lo and n <= hi
end

local function archivesValid(entry)
  if entry.archives == nil then return true end
  if type(entry.archives) ~= "table" then return false end
  for index, original in pairs(entry.archives) do
    if not integer(index, 1, #entry.archives) or type(original) ~= "table"
        or original.id ~= entry.id or not GameVersion.VERSIONS[original.version]
        or original.generation ~= GameVersion.generation(original.version)
        or type(original.mon) ~= "table" or type(original.display) ~= "table"
        or original.archives ~= nil then return false end
  end
  return true
end

function Store.new()
  local state = { format = Store.FORMAT, revision = 0, nextId = 1, boxes = {} }
  for b = 1, Store.BOXES do state.boxes[b] = { name = "BOX " .. b, mons = {} } end
  return state
end

function Store.validate(state)
  if type(state) ~= "table" or state.format ~= Store.FORMAT
      or not integer(state.revision, 0, 2^53 - 1)
      or not integer(state.nextId, 1, 2^53 - 1) or type(state.boxes) ~= "table" then
    return nil, "The Box storage format is invalid."
  end
  local ids = {}
  for b, box in pairs(state.boxes) do
    if not integer(b, 1, Store.BOXES) or type(box) ~= "table"
        or type(box.name) ~= "string" or #box.name > 128 or type(box.mons) ~= "table" then
      return nil, "A Box header is invalid."
    end
    if box.theme ~= nil then
      local found = false
      for _, theme in ipairs(Store.THEMES) do if box.theme == theme then found = true end end
      if not found then return nil, "A Box theme is invalid." end
    end
    if box.wallpaper ~= nil and (type(box.wallpaper) ~= "string"
        or not box.wallpaper:match("^box/showcase/%d+%.png$")) then
      return nil, "A Box wallpaper is invalid."
    end
    if box.showcaseMusic ~= nil then
      local found = false
      for _, track in ipairs(require("src.box.Showcase").MUSIC) do if track == box.showcaseMusic then found = true end end
      if not found or box.theme ~= "Showcase" then return nil, "A Box music track is invalid." end
    end
    for slot, entry in pairs(box.mons) do
      if not integer(slot, 1, Store.SLOTS) or type(entry) ~= "table"
          or not integer(entry.id, 1, state.nextId - 1) or ids[entry.id]
          or not GameVersion.VERSIONS[entry.version] or type(entry.mon) ~= "table"
          or entry.generation ~= GameVersion.generation(entry.version)
          or type(entry.display) ~= "table" or not archivesValid(entry) then
        return nil, "A stored Pokémon record is invalid."
      end
      ids[entry.id] = true
      if entry.markings ~= nil and not integer(entry.markings, 0, 15)
          or entry.depositorId ~= nil and not integer(entry.depositorId, 0, 4294967295)
          or entry.tags ~= nil and (type(entry.tags) ~= "string" or #entry.tags > 128) then
        return nil, "A Pokémon's local labels are invalid."
      end
    end
  end
  for b = 1, Store.BOXES do
    if not state.boxes[b] then return nil, "A Box is missing." end
  end
  if state.progress ~= nil and type(state.progress) ~= "table" then return nil, "Gift progress is invalid." end
  for key, value in pairs(state.progress or {}) do
    if type(key) ~= "string" or #key > 1024 or not integer(value, 0, Store.BOXES * Store.SLOTS) then
      return nil, "Gift progress is invalid."
    end
  end
  if state.presets ~= nil and type(state.presets) ~= "table" then return nil, "Team presets are invalid." end
  if state.organizerProfiles ~= nil then
    if type(state.organizerProfiles) ~= "table" or #state.organizerProfiles > 20 then return nil, "Auto Box presets are invalid." end
    for index, profile in pairs(state.organizerProfiles) do
      if not integer(index, 1, #state.organizerProfiles) or type(profile) ~= "table"
          or type(profile.name) ~= "string" or #profile.name == 0 or #profile.name > 64 or profile.name:find("%c")
          or (profile.target ~= "box" and profile.target ~= "pc")
          or not require("src.box.Organizer").validate(profile.config) then return nil, "An Auto Box preset is invalid." end
    end
  end
  if state.stages ~= nil and type(state.stages) ~= "table" then return nil, "Showcase stages are invalid." end
  if state.departures ~= nil and type(state.departures) ~= "table" then return nil, "Departed entries are invalid." end
  if state.syncMembers ~= nil and type(state.syncMembers) ~= "table" then return nil, "Box sync links are invalid." end
  for key, member in pairs(state.syncMembers or {}) do
    if type(key) ~= "string" or type(member) ~= "table" or not GameVersion.VERSIONS[member.version]
        or type(member.playthroughId) ~= "string" or not member.playthroughId:match("^[%w%._:%-]+$")
        or #member.playthroughId > 64 or key ~= member.version .. "/" .. member.playthroughId
        or type(member.path) ~= "string" or not member.path:match("^saves/[%w%._%-]+/slot%d+%.lua$") then
      return nil, "A Box sync link is invalid."
    end
    local scope, slot = member.path:match("^saves/([%w%._%-]+)/(slot%d+)%.lua$")
    if member.cartId ~= nil and (type(member.cartId) ~= "string" or #member.cartId > 64
        or not member.cartId:match("^[%w%._%-]+$"))
        or scope ~= (member.cartId and "cart_" .. member.cartId or member.version)
        or member.slotId ~= nil and member.slotId ~= slot
        or member.deleted ~= nil and type(member.deleted) ~= "boolean" then
      return nil, "A Box sync link points to a different save."
    end
  end
  for id, departure in pairs(state.departures or {}) do
    local entry = type(departure) == "table" and departure.entry
    if not integer(id, 1, state.nextId - 1) or ids[id] or type(entry) ~= "table" or entry.id ~= id
        or not GameVersion.VERSIONS[entry.version] or entry.generation ~= GameVersion.generation(entry.version)
        or type(entry.mon) ~= "table" or type(entry.display) ~= "table"
        or type(departure.path) ~= "string" or not archivesValid(entry)
        or departure.identity ~= nil and type(departure.identity) ~= "string" then return nil, "A departed Pokémon reference is invalid." end
  end
  for index, stage in pairs(state.stages or {}) do
    if not integer(index, 1, 5) then return nil, "A showcase stage slot is invalid." end
    local valid, why = require("src.box.Showcase").validate(stage, state.nextId)
    if not valid then return nil, why end
  end
  for key, preset in pairs(state.presets or {}) do
    if not integer(key, 1, 1000000) or type(preset) ~= "table"
        or type(preset.name) ~= "string" or #preset.name > 64
        or type(preset.ids) ~= "table" or #preset.ids < 1 or #preset.ids > 6 then
      return nil, "A team preset is invalid."
    end
    local used = {}
    for _, id in ipairs(preset.ids) do
      if not integer(id, 1, state.nextId - 1) or used[id] then return nil, "A team reference is invalid." end
      used[id] = true
    end
  end
  return state
end

function Store.load(fs)
  local body = fs.read(Store.PATH)
  if not body then
    if fs.getInfo(Store.PATH) then return nil, "Box storage could not be read." end
    local backup = fs.read(Store.PATH .. ".bak")
    if backup then
      local state = Serializer.decode(backup)
      if not Store.validate(state) then return nil, "Box storage is missing and its backup could not be read." end
      local ok = fs.write(Store.PATH, backup)
      if not ok or fs.read(Store.PATH) ~= backup then return nil, "Box storage could not be restored from its backup." end
      return state, nil, backup
    end
    if fs.getInfo(Store.PATH .. ".bak") or fs.getInfo(Store.PATH .. ".box-bak") then
      return nil, "Box storage is missing. Its backup was kept in the box folder."
    end
    return Store.new(), nil, nil
  end
  local state, err = Serializer.decode(body)
  if not state then return nil, "Box storage could not be decoded: " .. tostring(err) end
  local valid, why = Store.validate(state)
  if not valid then return nil, why end
  return valid, nil, body
end

function Store.at(state, box, slot)
  if not integer(box, 1, Store.BOXES) or not integer(slot, 1, Store.SLOTS) then return nil end
  return state.boxes[box].mons[slot]
end

function Store.free(state, box)
  if not integer(box, 1, Store.BOXES) then return nil end
  for slot = 1, Store.SLOTS do if not state.boxes[box].mons[slot] then return slot end end
end

function Store.count(state)
  local n = 0
  for b = 1, Store.BOXES do for _ in pairs(state.boxes[b].mons) do n = n + 1 end end
  return n
end

function Store.move(state, fromBox, fromSlot, toBox, toSlot)
  local entry = Store.at(state, fromBox, fromSlot)
  if not entry or not integer(toBox, 1, Store.BOXES)
      or not integer(toSlot, 1, Store.SLOTS) then return nil, "Choose valid Box slots." end
  local nextState = Store.copy(state)
  nextState.boxes[fromBox].mons[fromSlot], nextState.boxes[toBox].mons[toSlot] =
    nextState.boxes[toBox].mons[toSlot], nextState.boxes[fromBox].mons[fromSlot]
  nextState.revision = state.revision + 1
  return nextState
end

function Store.rename(state, box, name)
  if not integer(box, 1, Store.BOXES) or type(name) ~= "string"
      or #name == 0 or #name > 128 or name:find("%c") then
    return nil, "Enter a Box name of 1 to 128 bytes."
  end
  local nextState = Store.copy(state)
  nextState.boxes[box].name = name
  nextState.revision = state.revision + 1
  return nextState
end

function Store.find(state, id)
  for b = 1, Store.BOXES do
    for slot, entry in pairs(state.boxes[b].mons) do
      if entry.id == id then return { box = b, slot = slot, entry = entry } end
    end
  end
end

function Store.moveGroup(state, refs, box, slot)
  if type(refs) ~= "table" or #refs == 0 or not integer(box, 1, Store.BOXES)
      or not integer(slot, 1, Store.SLOTS) or slot + #refs - 1 > Store.SLOTS then
    return nil, "Choose a destination with room for the entire group."
  end
  local nextState, group, origins, vacated, displaced = Store.copy(state), {}, {}, {}, {}
  for _, ref in ipairs(refs) do
    local entry = Store.at(state, ref.box, ref.slot)
    local key = tostring(ref.box) .. ":" .. tostring(ref.slot)
    if not entry or origins[key] then return nil, "A selected Box Pokémon is missing or repeated." end
    origins[key], group[#group + 1] = true, Store.copy(entry)
    nextState.boxes[ref.box].mons[ref.slot] = nil
  end
  local targets = {}
  for i = 1, #refs do
    local target = slot + i - 1
    targets[box .. ":" .. target] = true
    local entry = nextState.boxes[box].mons[target]
    if entry then displaced[#displaced + 1] = entry end
    nextState.boxes[box].mons[target] = group[i]
  end
  for _, ref in ipairs(refs) do
    if not targets[ref.box .. ":" .. ref.slot] then vacated[#vacated + 1] = ref end
  end
  for i, entry in ipairs(displaced) do
    local ref = vacated[i]
    nextState.boxes[ref.box].mons[ref.slot] = entry
  end
  nextState.revision = state.revision + 1
  return nextState
end

function Store.arrange(state, box, sort)
  if not integer(box, 1, Store.BOXES) then return nil, "Choose a Box." end
  local nextState, rows = Store.copy(state), Store.search(state, "", sort)
  nextState.boxes[box].mons = {}
  local index = 0
  for _, row in ipairs(rows) do
    if row.box == box then index = index + 1; nextState.boxes[box].mons[index] = Store.copy(row.entry) end
  end
  nextState.revision = state.revision + 1
  return nextState
end

function Store.theme(state, box, theme, wallpaper, music)
  if not integer(box, 1, Store.BOXES) then return nil, "Choose a Box." end
  local nextState = Store.copy(state)
  nextState.boxes[box].theme, nextState.boxes[box].wallpaper = theme, wallpaper
  nextState.boxes[box].showcaseMusic = theme == "Showcase" and music or nil
  nextState.revision = state.revision + 1
  return Store.validate(nextState)
end

function Store.mark(state, refs, markings, tags)
  if not integer(markings, 0, 15) or type(refs) ~= "table" or #refs == 0 then
    return nil, "Choose Pokémon and valid markings."
  end
  if tags ~= nil and (type(tags) ~= "string" or #tags > 128 or tags:find("%c")) then
    return nil, "Enter tags of at most 128 bytes."
  end
  local nextState, seen = Store.copy(state), {}
  for _, ref in ipairs(refs) do
    local entry = Store.at(nextState, ref.box, ref.slot)
    if not entry or seen[entry.id] then return nil, "A selected Pokémon is missing or repeated." end
    seen[entry.id] = true
    if entry.generation == 3 then
      entry.mon.markings, entry.display.markings = markings, markings
    else entry.markings = markings end
    if tags ~= nil then entry.tags = tags end
  end
  nextState.revision = state.revision + 1
  return nextState
end

function Store.preset(state, name, refs)
  if type(name) ~= "string" or #name == 0 or #name > 64 or name:find("%c")
      or type(refs) ~= "table" or #refs == 0 or #refs > 6 then
    return nil, "Name a team of one to six Pokémon."
  end
  local nextState, ids, seen = Store.copy(state), {}, {}
  for _, ref in ipairs(refs) do
    local entry = Store.at(state, ref.box, ref.slot)
    if not entry or seen[entry.id] then return nil, "A team member is missing or repeated." end
    seen[entry.id], ids[#ids + 1] = true, entry.id
  end
  nextState.presets = nextState.presets or {}
  if #nextState.presets >= 100 then return nil, "All 100 team preset slots are full." end
  nextState.presets[#nextState.presets + 1] = { name = name, ids = ids }
  nextState.revision = state.revision + 1
  return nextState
end

function Store.search(state, query, sort)
  local out = {}
  local matches = require("src.box.Search").compile(query)
  for b = 1, Store.BOXES do
    for slot, entry in pairs(state.boxes[b].mons) do
      if matches(entry, state.boxes[b].name) then
        out[#out + 1] = { box = b, slot = slot, entry = entry }
      end
    end
  end
  table.sort(out, function(a, b)
    local x, y = a.entry.display, b.entry.display
    local av, bv
    if sort == "level" then av, bv = tonumber(x.level) or 0, tonumber(y.level) or 0
    elseif sort == "species" then av, bv = tonumber(x.national) or 0, tonumber(y.national) or 0
    elseif sort == "name" or sort == "nature" or sort == "ability" or sort == "trainer" or sort == "gender" then
      av, bv = tostring(x[sort] or ""):lower(), tostring(y[sort] or ""):lower()
    elseif sort ~= "slot" then av, bv = tonumber(x[sort]) or -1, tonumber(y[sort]) or -1 end
    if av and av ~= bv then return av < bv end
    return a.box < b.box or (a.box == b.box and a.slot < b.slot)
  end)
  return out
end

return Store
