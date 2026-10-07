local CacheFs = require("src.import.CacheFs")
local GameVersion = require("src.core.GameVersion")
local Store = require("src.box.Store")

local Catalog = {}
local cached = {}
local artCache = {}

local function read(version, path)
  local body = CacheFs.readAt(GameVersion.cachePrefix(version) .. path)
  if not body then return nil end
  local chunk = (loadstring or load)(body, "@" .. version .. "/" .. path)
  if not chunk then return nil end
  if setfenv then setfenv(chunk, {}) end
  local ok, value = pcall(chunk)
  return ok and type(value) == "table" and value or nil
end

function Catalog.reset()
  local cry = package.loaded["src.box.Cry"]
  if cry then cry.reset() end
  local animation = package.loaded["src.box.Animation"]
  if animation then animation.reset() end
  local themes = package.loaded["src.box.Themes"]
  if type(themes) == "table" and themes.reset then themes.reset() end
  cached, artCache = {}, {}
  require("src.online.OnlineSprites").reset()
end

function Catalog.get(version)
  if cached[version] then return cached[version] end
  local generation = GameVersion.generation(version)
  local data = { generation = generation }
  if generation == 3 then
    local root = "data/generated/gba/pokemon/"
    data.names = read(version, root .. "names.lua")
    data.national = read(version, root .. "national.lua") or {}
    data.moves = read(version, root .. "move_names.lua") or {}
    data.items = (read(version, "data/generated/gba/items/pack.lua") or {}).items or {}
    data.types = read(version, root .. "types.lua") or {}
    data.typeNames = read(version, root .. "type_names.lua") or {}
    data.stats = read(version, root .. "stats.lua") or {}
    data.meta = read(version, root .. "meta.lua") or {}
    data.abilities = read(version, root .. "abilities.lua") or {}
    data.abilityNames = read(version, root .. "ability_names.lua") or {}
    data.battleMoves = (read(version, root .. "battle_moves.lua") or {}).moves or {}
    local sections = read(version, "data/generated/gba/region_map/map_sections.lua") or {}
    data.locations = sections.sections or sections
    data.ready = data.names ~= nil
  else
    data.pokemon = read(version, "data/generated/pokemon.lua")
    data.moves = read(version, "data/generated/moves.lua") or {}
    data.items = read(version, "data/generated/items.lua") or {}
    data.byNational = {}
    for key, def in pairs(data.pokemon or {}) do
      if type(def) == "table" and type(def.dex) == "number" then
        data.byNational[def.dex] = key
      end
    end
    data.ready = data.pokemon ~= nil
  end
  cached[version] = data
  return data
end

local function label(records, key)
  local value = records[key]
  if type(value) == "table" then return value.name or value.id or tostring(key) end
  return value or tostring(key or "")
end

function Catalog.describe(version, mon)
  local data = Catalog.get(version)
  local def = data.pokemon and data.pokemon[mon.species]
  local species = data.names and data.names[tonumber(mon.species)]
    or (def and def.name) or tostring(mon.species or "Unknown")
  local national = def and def.dex or (data.national and data.national.toNational or {})[tonumber(mon.species)]
  local moves = {}
  for _, move in ipairs(mon.moves or {}) do
    local key = type(move) == "table" and (move.moveId or move.id or move.move or move.name) or move
    if key and key ~= 0 then moves[#moves + 1] = tostring(label(data.moves, key)) end
  end
  local item = mon.heldItem or mon.item
  local shiny = mon.isShiny == true or mon.shiny == true
  if data.generation == 3 then shiny = require("src.core.game3.pokemon").isShiny(mon) end
  if data.generation == 2 and mon.dvs then
    shiny = require("src.battle.gen2.Mon").vanillaShiny(mon.dvs)
  end
  local types = def and def.types or data.types and data.types[tonumber(mon.species)] or mon.types or {}
  if data.generation == 3 and type(types) == "table" then
    local names = {}
    for _, id in ipairs(types) do names[#names + 1] = tostring(data.typeNames[id] or id) end
    types = names
  end
  if type(types) == "table" then
    local unique, seen = {}, {}
    for _, value in ipairs(types) do
      if not seen[value] then unique[#unique + 1], seen[value] = value, true end
    end
    types = unique
  end
  local display = { name = mon.nickname or species, species = species, national = national,
    level = mon.level or 0, types = type(types) == "table" and table.concat(types, " / ") or tostring(types),
    moves = table.concat(moves, ", "), item = item and item ~= 0 and tostring(label(data.items, item)) or "",
    shiny = shiny, egg = mon.isEgg == true }
  require("src.box.Metadata").describe(data, mon, display, def)
  return display
end

local function moveKey(move)
  return type(move) == "table" and (move.moveId or move.id or move.move or move.name) or move
end

local function whole(value, lo, hi)
  return type(value) == "number" and value == math.floor(value) and value >= lo and value <= hi
end

local function clamp(value, lo, hi)
  if type(value) ~= "number" or value ~= value then return lo end
  return math.max(lo, math.min(hi, math.floor(value)))
end

local function clampAll(values, lo, hi)
  for key, value in pairs(values) do values[key] = clamp(value, lo, hi) end
end

local function placeholder(name)
  return type(name) ~= "string" or name == "" or name:match("^%?+$") ~= nil or name == "TERU-SAMA"
end

function Catalog.knownItem(data, item)
  local row = data.items and data.items[item]
  if type(row) == "table" then return not placeholder(row.name) end
  return data.generation == 3 and type(row) == "string" and not placeholder(row)
end

function Catalog.check(version, mon)
  local data = Catalog.get(version)
  if type(mon) ~= "table" then return "This Pokémon's data is missing.", {} end
  local known
  if data.generation == 3 then
    local name = data.names and data.names[tonumber(mon.species)]
    local national = (data.national.toNational or {})[tonumber(mon.species)]
    known = not placeholder(name) and whole(national, 1, 386)
  else
    local def = data.pokemon and data.pokemon[mon.species]
    known = type(def) == "table" and whole(def.dex, 1, data.generation == 1 and 151 or 251)
  end
  if not known then
    return "This Pokémon is not in the original games' Pokédex.", {}
  end
  local fixes = {}
  local function add(label, apply) fixes[#fixes + 1] = { label = label, apply = apply } end
  local moves = mon.moves
  if moves ~= nil and type(moves) ~= "table" then return "This Pokémon's moves are unreadable.", {} end
  local legalMoves = 0
  for _, move in ipairs(moves or {}) do
    local key = moveKey(move)
    if key and key ~= 0 and data.moves[key] then legalMoves = legalMoves + 1 end
  end
  local badMoves = 0
  for _, move in ipairs(moves or {}) do
    local key = moveKey(move)
    if key and key ~= 0 and not data.moves[key] then badMoves = badMoves + 1 end
  end
  if badMoves > 0 or legalMoves > 4 then
    if legalMoves == 0 then return "None of this Pokémon's moves exist in the original games.", {} end
    add(badMoves > 0 and ("remove %d unknown move%s"):format(badMoves, badMoves == 1 and "" or "s")
      or "keep only 4 moves", function(m)
      local keptMoves, keptPP, pp = {}, {}, type(m.pp) == "table" and #m.pp == #m.moves and m.pp or nil
      for i, move in ipairs(m.moves) do
        local key = moveKey(move)
        if key and key ~= 0 and data.moves[key] and #keptMoves < 4 then
          keptMoves[#keptMoves + 1] = move
          if pp then keptPP[#keptPP + 1] = pp[i] end
        end
      end
      m.moves = keptMoves
      if pp then m.pp = keptPP end
      if type(m.cartExtra) == "table" then m.cartExtra.moveSlots = nil end
    end)
  end
  local item = mon.heldItem or mon.item
  if item and item ~= 0 and not Catalog.knownItem(data, item) then
    add("remove unknown held item", function(m)
      if type(m.heldItem) == "number" then m.heldItem = 0 else m.heldItem = nil end
      m.item = nil
    end)
  end
  if mon.level ~= nil and not whole(mon.level, 1, 100) then
    add("set level within 1-100", function(m) m.level = clamp(m.level, 1, 100) end)
  end
  local function group(values, lo, hi)
    if values == nil then return true, 0 end
    if type(values) ~= "table" then return false, 0 end
    local ok, total = true, 0
    for _, value in pairs(values) do
      if whole(value, lo, hi) then total = total + value else ok = false end
    end
    return ok, total
  end
  if data.generation == 3 then
    if not group(mon.ivs, 0, 31) then
      add("cap IVs at 31", function(m) if type(m.ivs) == "table" then clampAll(m.ivs, 0, 31) else m.ivs = nil end end)
    end
    local evsOk, evTotal = group(mon.evs, 0, 255)
    if not evsOk or evTotal > 510 then
      add("cap EVs at 255 each, 510 total", function(m)
        if type(m.evs) ~= "table" then m.evs = nil return end
        clampAll(m.evs, 0, 255)
        local keys, total = {}, 0
        for key, value in pairs(m.evs) do keys[#keys + 1], total = key, total + value end
        table.sort(keys, function(a, b) return m.evs[a] > m.evs[b] end)
        local i = 1
        while total > 510 do
          local key = keys[(i - 1) % #keys + 1]
          local cut = math.min(m.evs[key], total - 510)
          m.evs[key], total, i = m.evs[key] - cut, total - cut, i + 1
        end
      end)
    end
    if mon.abilityNum ~= nil and not whole(mon.abilityNum, 0, 1) then
      add("reset ability slot", function(m) m.abilityNum = 0 end)
    end
    if mon.friendship ~= nil and not whole(mon.friendship, 0, 255) then
      add("cap friendship at 255", function(m)
        m.friendship = clamp(m.friendship, 0, 255)
        if m.happiness ~= nil then m.happiness = m.friendship end
      end)
    end
    if mon.pokeball ~= nil and not whole(mon.pokeball, 0, 12) then
      add("change ball to Poké Ball", function(m) m.pokeball = 4 end)
    end
    if mon.metLevel ~= nil and not whole(mon.metLevel, 0, 100) then
      add("set met level within 0-100", function(m) m.metLevel = clamp(m.metLevel, 0, 100) end)
    end
  else
    if not group(mon.dvs, 0, 15) then
      add("cap DVs at 15", function(m) if type(m.dvs) == "table" then clampAll(m.dvs, 0, 15) else m.dvs = nil end end)
    end
    if not group(mon.statExp, 0, 65535) then
      add("cap stat experience", function(m)
        if type(m.statExp) == "table" then clampAll(m.statExp, 0, 65535) else m.statExp = nil end
      end)
    end
  end
  return nil, fixes
end

function Catalog.repair(version, mon)
  local fatal, fixes = Catalog.check(version, mon)
  if fatal then return nil, fatal end
  local fixed = Store.copy(mon)
  for _, fix in ipairs(fixes) do fix.apply(fixed) end
  return fixed, fixes
end

function Catalog.compatible(entry, version)
  if entry.generation ~= GameVersion.generation(version) then
    return nil, "This Pokémon must return to a game in its original generation."
  end
  local data = Catalog.get(version)
  if not data.ready then return nil, "Import that game's ROM before withdrawing." end
  local fatal, fixes = Catalog.check(version, entry.mon)
  if fatal then return nil, fatal end
  if #fixes > 0 then return nil, "This Pokémon is illegal: " .. fixes[1].label .. ".", fixes end
  return true
end

function Catalog.art(entry)
  local display, mon = entry.display, entry.mon
  local letter = display.national == 201 and entry.generation == 2
    and (mon.unownLetter or require("src.core.gen2.Unown").letterFromDVs(mon.dvs)) or ""
  local key = table.concat({ entry.version, tostring(mon.species), tostring(display.national),
    tostring(mon.personality), tostring(letter), tostring(display.shiny), tostring(display.egg) }, "|")
  local hit = artCache[key]
  if hit then return hit.art or nil, hit.version, hit.mon end
  local order = {}
  for i, version in ipairs(GameVersion.ORDER) do
    order[#order + 1] = { version = version, generation = GameVersion.generation(version), index = i }
  end
  table.sort(order, function(a, b)
    if (a.version == "emerald") ~= (b.version == "emerald") then return a.version == "emerald" end
    return a.generation > b.generation or (a.generation == b.generation and a.index > b.index)
  end)
  local sprites = require("src.online.OnlineSprites")
  for _, row in ipairs(order) do
    local data = Catalog.get(row.version)
    local species
    if data.generation == 3 then
      species = (data.national.toSpecies or {})[display.national]
    else species = data.byNational and data.byNational[display.national] end
    if row.version == entry.version and species == nil then species = mon.species end
    if data.ready and species and (not display.egg or data.generation >= 2) then
      local artMon = Store.copy(mon)
      artMon.species, artMon.isShiny, artMon.shiny = species, display.shiny, display.shiny
      if data.generation == 3 and entry.generation == 2 and display.national == 201 then
        local Unown = require("src.core.gen2.Unown")
        local letter = Unown.index(mon.unownLetter or Unown.letterFromDVs(mon.dvs)) or 1
        local value = letter - 1
        artMon.personality = value % 4 + (math.floor(value / 4) % 4) * 256
          + (math.floor(value / 16) % 4) * 65536
      end
      if display.egg and data.generation == 2 then artMon.species = "BOX_EGG" end
      local art = sprites.ensure(row.version, artMon)
      if art and (art.front or art.icon) then
        artCache[key] = { art = art, version = row.version, mon = artMon }
        return art, row.version, artMon
      end
    end
  end
  artCache[key] = {}
end

return Catalog
