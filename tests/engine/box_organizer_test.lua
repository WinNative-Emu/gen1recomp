package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")
local T = require("tests.harness")
local Store = require("src.box.Store")
local Organizer = require("src.box.Organizer")
local Service = require("src.box.Service")
local Records = require("src.box.Records")
local Transaction = require("src.box.Transaction")
local Serializer = require("src.core.SaveSerializer")
local Catalog = require("src.box.Catalog")
local CacheFs = require("src.import.CacheFs")
local GameVersion = require("src.core.GameVersion")
local originalRead = CacheFs.readAt
local data = {}
local defs = { BULBASAUR = { dex = 1, name = "BULBASAUR", types = { "GRASS" } },
  CHARMANDER = { dex = 4, name = "CHARMANDER", types = { "FIRE" } },
  PIKACHU = { dex = 25, name = "PIKACHU", types = { "ELECTRIC" } },
  MEWTWO = { dex = 150, name = "MEWTWO", types = { "PSYCHIC" } },
  MEW = { dex = 151, name = "MEW", types = { "PSYCHIC" } } }
for _, version in ipairs(GameVersion.ORDER) do
  local prefix = GameVersion.cachePrefix(version)
  if GameVersion.generation(version) == 3 then
    local names, national = {}, { toNational = {}, toSpecies = {} }
    for _, def in pairs(defs) do names[def.dex], national.toNational[def.dex], national.toSpecies[def.dex] = def.name, def.dex, def.dex end
    data[prefix .. "data/generated/gba/pokemon/names.lua"] = Serializer.encode(names)
    data[prefix .. "data/generated/gba/pokemon/national.lua"] = Serializer.encode(national)
  else data[prefix .. "data/generated/pokemon.lua"] = Serializer.encode(defs) end
end
CacheFs.readAt = function(path) return data[path] end
Catalog.reset()
local function config(mode)
  return { mode = mode or "sort", sort = "species", descending = false, fallback = "keep",
    rules = { { firstBox = 1, lastBox = 1, match = "all", conditions = { { field = "shiny", value = true } } } } }
end
local function entry(id, species, level, shiny, egg)
  local def = defs[species]
  return { id = id, version = "emerald", generation = 3,
    mon = { species = def.dex, personality = id * 1001, moves = { 1, 2 }, pp = { 12, 4 },
      opaque = { raw = "\000\255", duplicate = id } },
    display = { name = species, species = species, national = def.dex, level = level,
      types = table.concat(def.types, " / "), shiny = shiny or false, egg = egg or false } }
end
local function state()
  local s = Store.new()
  s.nextId = 7
  s.boxes[1].mons[8] = entry(1, "MEWTWO", 80)
  s.boxes[3].mons[6] = entry(2, "MEW", 20, true)
  s.boxes[1].mons[11] = entry(3, "PIKACHU", 5, false, true)
  s.boxes[2].mons[9] = entry(4, "MEW", 50)
  s.boxes[1].mons[4] = entry(5, "BULBASAUR", 15)
  s.boxes[2].mons[1] = entry(6, "CHARMANDER", 17)
  s.presets = { { name = "Team", ids = { 1, 5 } } }
  s.stages = { [1] = { name = "Demo", background = "Forest", pattern = "Plain", music = "Silent",
    pieces = { { entryId = 1, x = .5, y = .5, scale = 1, rotation = 0, flip = false } } } }
  return s
end
local function inventory(s)
  local out = {}
  for _, row in ipairs(Store.search(s, "", "slot")) do out[row.entry.id] = row.entry end
  return out
end
local original, cfg = state(), config()
local sorted, report = assert(Organizer.applyWarehouse(original, cfg))
T.eq(report.moved, 6, "all moved slots are reported")
T.eq(sorted.boxes[1].mons[1].id, 5, "lowest dex sorts first")
T.eq(sorted.boxes[1].mons[6].id, 4, "same species uses level to break equal nickname ties")
T.same(inventory(sorted), inventory(original), "whole native records and duplicate species survive")
T.same(sorted.presets, original.presets, "team references stay intact")
T.same(sorted.stages, original.stages, "showcase references stay intact")
T.eq(Organizer.applyWarehouse(sorted, cfg).revision, sorted.revision + 1, "pure planner creates an independent candidate")
local _, repeated = Organizer.applyWarehouse(sorted, cfg)
T.eq(repeated.moved, 0, "sort is idempotent")
cfg.box = 2
local one = assert(Organizer.applyWarehouse(original, cfg))
T.same(one.boxes[1], original.boxes[1], "single-box sorting leaves other boxes alone")
T.eq(one.boxes[2].mons[1].id, 6, "single-box sort keeps its own contents")
cfg.box, cfg.sort, cfg.descending = nil, "level", true
local descending = assert(Organizer.applyWarehouse(original, cfg))
T.eq(descending.boxes[1].mons[1].id, 1, "descending level is honored")
do
  local missing, order = state(), config()
  missing.boxes[1].mons[4].display.national = 0
  order.descending = true
  local result = assert(Organizer.applyWarehouse(missing, order))
  T.eq(result.boxes[1].mons[6].id, 5, "unknown dex stays last even in descending order")
  missing.boxes[1].mons[4].display.types = ""
  order.sort, order.descending = "type", false
  result = assert(Organizer.applyWarehouse(missing, order))
  T.eq(result.boxes[1].mons[6].id, 5, "missing type is unknown instead of an empty-string first entry")
end
cfg = config("rules")
cfg.rules[2] = { firstBox = 2, lastBox = 2, match = "all", conditions = { { field = "species", value = "mew" } } }
cfg.fallback = "sort"
local routed, routing = assert(Organizer.applyWarehouse(original, cfg))
T.eq(routed.boxes[1].mons[1].id, 2, "earlier shiny rule wins over species")
T.eq(routed.boxes[2].mons[1].id, 4, "species match is exact and case insensitive")
T.eq(Store.find(routed, 1).box, 3, "Mewtwo does not match Mew")
T.eq(routing.ruleCounts[1], 1, "priority counts do not double count")
T.same(inventory(routed), inventory(original), "rules preserve every complete entry")
local _, routedAgain = Organizer.applyWarehouse(routed, cfg)
T.eq(routedAgain.moved, 0, "rules are idempotent")
cfg = config("rules")
cfg.rules[1] = { firstBox = 5, lastBox = 5, match = "all",
  conditions = { { field = "egg", value = true }, { field = "type", value = "electric" } } }
local eggs = assert(Organizer.applyWarehouse(original, cfg))
T.eq(Store.find(eggs, 3).box, 5, "all conditions combine")
T.same(Store.find(eggs, 1), Store.find(original, 1), "unmatched warehouse entries keep exact slots")
cfg.rules[1].match = "any"
cfg.rules[1].conditions = { { field = "species", value = "MEW" }, { field = "type", value = "fire" } }
local any = assert(Organizer.applyWarehouse(original, cfg))
T.eq(Store.find(any, 6).box, 5, "any condition matches fire")
T.eq(Store.find(any, 4).box, 5, "any condition matches species")
local crowded = Store.new()
crowded.nextId = 62
for i = 1, 60 do crowded.boxes[1].mons[i] = entry(i, "BULBASAUR", i) end
crowded.boxes[2].mons[1] = entry(61, "BULBASAUR", 5)
cfg.rules[1].conditions = { { field = "species", value = "BULBASAUR" } }
cfg.rules[1].firstBox, cfg.rules[1].lastBox = 1, 1
local before = Serializer.encode(crowded)
local failed, reason = Organizer.applyWarehouse(crowded, cfg)
T.eq(failed, nil, "full rule destination blocks")
T.check(reason:find("more room", 1, true), "overflow error tells how to fix it")
T.eq(Serializer.encode(crowded), before, "overflow changes nothing")
cfg.rules[1].lastBox = 2
local spill = assert(Organizer.applyWarehouse(crowded, cfg))
T.eq(Store.count(spill), 61, "box ranges spill without dropping entries")
T.eq(spill.boxes[2].mons[1].display.level, 60, "each box fills before next")
cfg.rules[1].conditions[1] = { field = "bogus", value = "x" }
T.eq(Organizer.validate(cfg), nil, "unknown conditions are blocked")
T.eq(Organizer.validate({ mode = "sort", sort = "bogus", descending = false }), nil, "unknown sort is blocked")
do
  local s, rules = state(), config("rules")
  s.boxes[1].mons[8].display.moves = "TACKLE, THUNDERBOLT"
  s.boxes[1].mons[8].display.item = "LEFTOVERS"
  rules.rules[1] = { firstBox = 5, lastBox = 5, match = "all", conditions = {
    { field = "move", value = "thunderbolt" }, { field = "item", value = "leftovers" } } }
  T.eq(Store.find(assert(Organizer.applyWarehouse(s, rules)), 1).box, 5, "move and held item combine")
  rules.rules[1].conditions[1].value = "THUNDER"
  T.eq(Store.find(assert(Organizer.applyWarehouse(s, rules)), 1).box, 1, "move names match exactly")
  rules.rules[1].conditions = { { field = "shiny", value = false } }
  T.eq(Store.find(assert(Organizer.applyWarehouse(s, rules)), 2).box, 3, "No boolean value excludes shiny")
end

local function filesystem()
  local files, mode, writes = {}, {}, 0
  return {
    read = function(path) return files[path] end,
    getInfo = function(path) return files[path] and { type = "file" } or nil end,
    createDirectory = function() return true end,
    remove = function(path) files[path] = nil; return true end,
    write = function(path, body)
      writes = writes + 1
      if mode.at == writes then
        if mode.partial then files[path] = body:sub(1, math.floor(#body / 2)) end
        return nil, "write fault"
      end
      files[path] = body; return true
    end,
  }, files, mode, function() return writes end
end
do
  local full = Store.new()
  full.nextId = Store.BOXES * Store.SLOTS + 1
  for b = 1, Store.BOXES do
    for slot = 1, Store.SLOTS do
      local id = (b - 1) * Store.SLOTS + slot
      full.boxes[b].mons[slot] = entry(id, "BULBASAUR", (full.nextId - id) % 100)
    end
  end
  local rules = config("rules")
  rules.sort = "level"
  rules.rules[1] = { firstBox = 1, lastBox = Store.BOXES, match = "all",
    conditions = { { field = "species", value = "BULBASAUR" } } }
  local arranged, fullReport = assert(Organizer.applyWarehouse(full, rules))
  T.eq(fullReport.total, 1500, "full warehouse preview includes every slot")
  T.eq(Store.count(arranged), 1500, "full warehouse applies without dropping entries")
  T.same(inventory(arranged), inventory(full), "full warehouse preserves every complete entry")
  T.check(Store.validate(arranged), "full warehouse remains valid")
  local _, settled = Organizer.applyWarehouse(arranged, rules)
  T.eq(settled.moved, 0, "full warehouse rules settle")
end
local Trade = require("src.online.Trade")
local originalPending = Trade.pendingSentAt
local pending = false
Trade.pendingSentAt = function() return pending and { {} } or {} end
local function fixture(version)
  local generation = GameVersion.generation(version)
  local mons = {}
  for i, species in ipairs({ "MEWTWO", "BULBASAUR", "PIKACHU", "MEW", "BULBASAUR" }) do
    mons[i] = { species = generation == 3 and defs[species].dex or species, nickname = "Mon " .. i,
      level = 12 + i, hp = 31, moves = { generation == 3 and 1 or "TACKLE" }, pp = { 17 },
      personality = i * 1001, otId = 42, otSecretId = 97, otName = "Demo",
      dvs = { attack = 7, defense = 3, speed = 9, special = 4 }, opaque = { raw = "\000\255", id = i } }
  end
  local save = { version = version, generation = generation, party = { Store.copy(mons[1]) },
    money = 123, rawImport = "original-template", modData = { cartImage = "opaque-cart-image" },
    boxNames = { "First", "Second" }, currentBox = 2, unknown = { keep = true } }
  if generation == 3 then
    save.storage = { currentBox = 2, opaque = "keep", boxes = {
      { name = "First", wallpaper = 3, mons = { [2] = mons[1], [6] = mons[2], [9] = mons[3] } },
      { name = "Second", wallpaper = 4, mons = { [5] = mons[4], [8] = mons[5] } } } }
  else save.boxes = { { mons[1], mons[2], mons[3] }, { mons[4], mons[5] } } end
  return save
end
local function nativeInventory(save, generation)
  local out = {}
  for _, row in ipairs(Records.candidates(save, generation)) do
    if row.where == "box" then out[#out + 1] = Serializer.encode(row.mon) end
  end
  table.sort(out); return out
end
for _, version in ipairs(GameVersion.ORDER) do
  local fs, files, _, writes = filesystem()
  local source = { version = version, slotId = "slot1", path = "saves/" .. version .. "/slot1.lua" }
  local save, generation = fixture(version), GameVersion.generation(version)
  local body = Serializer.encode(save)
  files[source.path] = body
  local service = assert(Service.open(fs))
  local preview = assert(service:previewOrganize("pc", source, config()))
  T.eq(writes(), 0, version .. " preview writes nothing")
  T.check(service:applyOrganize(preview), version .. " applies to linked game")
  local after = Serializer.decode(files[source.path])
  T.same(nativeInventory(after, generation), nativeInventory(save, generation), version .. " preserves every native record")
  T.same(after.party, save.party, version .. " leaves party alone")
  T.same(after.unknown, save.unknown, version .. " keeps unrelated fields")
  T.same(after.modData, save.modData, version .. " keeps cartridge image")
  T.eq(after.rawImport, save.rawImport, version .. " keeps raw template")
  T.eq(after.currentBox, save.currentBox, version .. " keeps selected box")
  T.eq(files[source.path .. ".box-bak"], body, version .. " stores exact pre-sort backup")
  T.eq(Records.list(after, generation, 1)[1].opaque.id, 2, version .. " writes actual PC arrangement")
  if generation == 3 then
    T.eq(after.storage.boxes[1].wallpaper, 3, version .. " keeps wallpaper")
    T.eq(after.storage.boxes[1].name, "First", version .. " keeps box name")
  else T.same(after.boxNames, save.boxNames, version .. " keeps box names") end
  T.check(next(service.state.syncMembers) ~= nil, version .. " links organized game to Box sync")
  T.eq(Store.count(service.state), 0, version .. " does not copy game Pokémon into warehouse")
  local done = assert(service:previewOrganize("pc", source, config()))
  T.eq(done.report.moved, 0, version .. " native sort is idempotent")
  local rules = config("rules")
  local destination = generation == 1 and 12 or 14
  rules.rules[1] = { firstBox = destination, lastBox = destination, match = "all",
    conditions = { { field = "species", value = "PIKACHU" } } }
  local arranged, ruleReport = assert(Organizer.applyGame(save, version, rules))
  T.eq(Records.list(arranged, generation, destination)[1].opaque.id, 3, version .. " routes game Pokémon to last box")
  T.same(nativeInventory(arranged, generation), nativeInventory(save, generation), version .. " game rules preserve complete records")
  T.same(arranged.party, save.party, version .. " game rules leave party alone")
  T.check(ruleReport.ruleCounts[1] == 1, version .. " game rules report exact match")
  rules.rules[1].lastBox = destination + 1
  T.eq(Organizer.applyGame(save, version, rules), nil, version .. " unavailable destination blocks")
  rules.rules[1].lastBox = destination
  rules.rules[1].conditions = { { field = "tag", value = "private-label" } }
  T.eq(Organizer.applyGame(save, version, rules), nil, version .. " rejects warehouse-only tags in Game PC")
end
do
  local fs, files, _, writes = filesystem()
  local service = assert(Service.open(fs))
  T.check(service:saveOrganizer("My rules", "box", config("rules")), "rules save")
  local reopened = assert(Service.open(fs))
  T.same(reopened.state.organizerProfiles[1].config, config("rules"), "saved rules reload exactly")
  local SyncBox = require("src.sync.SyncBox")
  local snapshot = assert(SyncBox.new(fs):snapshot({}, {}))
  local cloud = assert(SyncBox.validate(snapshot.payload))
  T.same(cloud.state.organizerProfiles, reopened.state.organizerProfiles, "saved rules survive cloud snapshot validation")
  local source = { version = "emerald", slotId = "slot1", path = "saves/emerald/slot1.lua" }
  files[source.path] = Serializer.encode(fixture("emerald"))
  local preview = assert(service:previewOrganize("pc", source, config()))
  files[source.path] = Serializer.encode(fixture("red"))
  local n = writes()
  T.eq(service:applyOrganize(preview), nil, "changed game refuses stale preview")
  T.eq(writes(), n, "stale game writes nothing")
  files[source.path] = preview.gameBefore
  preview = assert(service:previewOrganize("pc", source, config()))
  pending = true
  T.eq(service:applyOrganize(preview), nil, "new pending trade blocks apply")
  pending = false
  files[Store.PATH] = Serializer.encode(state())
  n = writes()
  T.eq(service:applyOrganize(preview), nil, "changed warehouse refuses stale preview")
  T.eq(writes(), n, "stale warehouse writes nothing")
  files[Store.PATH] = service.body
  T.check(service:deleteOrganizer(1), "preset deletes")
  T.eq(#service.state.organizerProfiles, 0, "preset removed")
end
for _, partial in ipairs({ false, true }) do
  for at = 1, 6 do
    local fs, files, fault = filesystem()
    local source = { version = "emerald", slotId = "slot1", path = "saves/emerald/slot1.lua" }
    local save = fixture("emerald")
    files[source.path] = Serializer.encode(save)
    local service = assert(Service.open(fs))
    local preview = assert(service:previewOrganize("pc", source, config()))
    fault.at, fault.partial = at, partial
    service:applyOrganize(preview)
    fault.at = nil
    local recovered = assert(Service.open(fs))
    T.same(nativeInventory(Serializer.decode(files[source.path]), 3), nativeInventory(save, 3), "interrupted sort preserves records")
    T.eq(files[Transaction.PATH], nil, "interrupted sort journal clears")
    T.check(Store.validate(recovered.state), "interrupted sort warehouse validates")
  end
end
Trade.pendingSentAt, CacheFs.readAt = originalPending, originalRead
Catalog.reset()
T.finish("box_organizer")
