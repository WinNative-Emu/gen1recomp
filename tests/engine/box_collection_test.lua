package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")
local T = require("tests.harness")
local Store = require("src.box.Store")
local Catalog = require("src.box.Catalog")
local Search = require("src.box.Search")
local Collection = require("src.box.Collection")
local Serializer = require("src.core.SaveSerializer")
local GameVersion = require("src.core.GameVersion")
local CacheFs = require("src.import.CacheFs")
local Service = require("src.box.Service")
local originalRead = CacheFs.readAt
local tables = {}
local function put(version, path, value) tables[GameVersion.cachePrefix(version)..path] = Serializer.encode(value) end
local root = "data/generated/gba/pokemon/"
put("emerald", root.."names.lua", { [25] = "PIKACHU" })
put("emerald", root.."national.lua", { toNational = { [25] = 25 } })
put("emerald", root.."meta.lua", { [25] = { genderRatio = 127, growthRate = 0 } })
put("emerald", root.."stats.lua", { [25] = { hp = 35, atk = 55, def = 40, spe = 90, spa = 50, spd = 50 } })
put("emerald", root.."abilities.lua", { [25] = { 9, 31 } })
put("emerald", root.."ability_names.lua", { [9] = "STATIC", [31] = "LIGHTNING ROD" })
put("emerald", root.."move_names.lua", { [84] = "THUNDERSHOCK" })
put("emerald", root.."battle_moves.lua", { moves = { [84] = { pp = 30 } } })
put("emerald", root.."types.lua", { [25] = { 13 } })
put("emerald", root.."type_names.lua", { [13] = "ELECTRIC" })
put("emerald", "data/generated/gba/items/pack.lua", { items = { [4] = { name = "POKé BALL" } } })
put("emerald", "data/generated/gba/region_map/map_sections.lua", { sections = { [7] = { name = "Route 1" } } })
put("gold", "data/generated/pokemon.lua", { PIKACHU = { name = "PIKACHU", dex = 25,
  genderRatio = 127, types = { "ELECTRIC" }, baseStats = { hp = 35, attack = 55, defense = 30,
  speed = 90, specialAttack = 50, specialDefense = 40 } } })
put("gold", "data/generated/moves.lua", { THUNDERSHOCK = { name = "THUNDERSHOCK", pp = 30 } })
CacheFs.readAt = function(path) return tables[path] end
Catalog.reset()
local mon = { species = 25, personality = 13, exp = 125000, otId = 42, otSecretId = 3,
  otName = "Alice", abilityNum = 0, metLocation = 7, metLevel = 5, pokeball = 4,
  moves = { 84 }, pp = { 15 }, ppBonusesPacked = 3, friendship = 110, markings = 5,
  ivs = { hp = 31, atk = 31, def = 31, spe = 31, spa = 31, spd = 31 }, evs = { spe = 252 } }
local original = Store.copy(mon)
local d = Catalog.describe("emerald", mon)
T.eq(d.level, 50, "boxed Gen3 level derives from native experience")
T.eq(d.nature, "Jolly", "nature derives from personality")
T.eq(d.gender, "Female", "gender uses species ratio and personality")
T.eq(d.ability, "STATIC", "stored ability bit wins over personality parity")
T.eq(d.hp, 110, "boxed HP is calculated from native base stats and IVs")
T.eq(d.speed, 156, "Speed includes EVs and Jolly nature")
T.eq(d.spAtk, 63, "Jolly reduces Special Attack")
T.eq(d.spDef, 70, "Special Defense has the correct nature key")
T.eq(d.location, "Route 1", "location reads selected game's cache")
T.eq(d.moveDetails[1].maxPP, 48, "PP Ups extend ROM move PP")
T.eq(d.moveDetails[1].pp, 15, "current native PP is retained")
T.same(mon, original, "summary computation leaves native Pokémon untouched")
local gapMon=Store.copy(mon)
gapMon.cartExtra={moveSlots={moves={0,84,0,0},pp={0,15,0,0}}}
gapMon.ppBonusesPacked=12
T.eq(Catalog.describe("emerald",gapMon).moveDetails[1].ppUps,3,"native empty move slots retain the correct PP Up bit position")
local state = Store.new()
for i = 1, 60 do
  local m = Store.copy(mon); m.nickname = "Pika " .. i
  state.boxes[1].mons[i] = { id = i, version = "emerald", generation = 3, mon = m, display = Catalog.describe("emerald", m) }
end
state.nextId = 61
local e = state.boxes[1].mons[1]
T.check(Search.compile('trainer:alice nature:jolly gender:female speed>=156 mark:triangle')(e), "metadata and native markings filter together")
T.check(not Search.compile('gender:male')(e), "Male filter does not include Female")
e.display.ability = "LIGHTNING ROD"
T.check(Search.compile('ability:"lightning rod" -egg')(e), "quoted fields support multiword names")
T.check(not Search.compile('mark:heart')(e), "missing native marking is excluded")

local refs = { { box = 1, slot = 1 }, { box = 1, slot = 2 } }
local overlap = assert(Store.moveGroup(state, refs, 1, 2))
T.eq(overlap.boxes[1].mons[1].id, 3, "overlapping group swaps displaced entry into vacated origin")
T.eq(overlap.boxes[1].mons[2].id, 1, "first selected entry lands at first destination")
T.eq(overlap.boxes[1].mons[3].id, 2, "group order remains intact")
T.eq(Store.count(overlap), 60, "overlap preserves every Pokémon exactly once")
local across = assert(Store.moveGroup(state, refs, 25, 59))
T.eq(across.boxes[25].mons[59].id, 1, "group reaches Box 25 slot 59")
T.eq(across.boxes[25].mons[60].id, 2, "group reaches final warehouse slot")
T.eq(Store.count(across), 60, "cross-box group preserves count")
T.check(not Store.moveGroup(state, refs, 25, 60), "group cannot overrun final slot")
T.check(not Store.moveGroup(state, { refs[1], refs[1] }, 2, 1), "duplicate group references rejected")
T.eq(state.boxes[1].mons[1].id, 1, "move planning never changes original state")
local marked = assert(Store.mark(across, { { box = 25, slot = 59 } }, 10, "battle team"))
T.eq(marked.boxes[25].mons[59].mon.markings, 10, "Gen3 changes native marking bits")
T.eq(marked.boxes[25].mons[59].tags, "battle team", "local tags persist separately")
local codec = require("src.save_convert.Gen3Save").forVersion("emerald")
local native = codec.fromPortMon(marked.boxes[25].mons[59].mon, {}, false)
local roundTrip = codec.toPortMon(assert(codec.decodeBoxMon(codec.encodeBoxMon(native))), false)
T.eq(roundTrip.markings, 10, "markings survive encrypted native PK3 round trip")
T.eq(roundTrip.personality, mon.personality, "marking edit preserves native personality")
local older = Store.copy(marked)
older.boxes[25].mons[59] = { id = 1, version = "gold", generation = 2,
  mon = { species = "PIKACHU", level = 50, moves = { { id = "THUNDERSHOCK", pp = 15, maxPp = 30 } },
    dvs = { attack = 15, defense = 10, speed = 10, special = 10 } }, display = {} }
older.boxes[25].mons[59].display = Catalog.describe("gold", older.boxes[25].mons[59].mon)
local localMark = assert(Store.mark(older, { { box = 25, slot = 59 } }, 8))
T.eq(localMark.boxes[25].mons[59].markings, 8, "Gen2 uses a local marking")
T.eq(localMark.boxes[25].mons[59].mon.markings, nil, "Gen2 native mon gains no fictitious marking field")
T.check(Search.compile('mark:heart')(localMark.boxes[25].mons[59]), "local marks participate in filters")
T.eq(localMark.boxes[25].mons[59].display.nature, nil, "Gen2 summary has no fictitious nature")

local preset = assert(Store.preset(across, "Pair", { { box = 25, slot = 59 }, { box = 25, slot = 60 } }))
preset = assert(Store.moveGroup(preset, { { box = 25, slot = 59 }, { box = 25, slot = 60 } }, 8, 10))
T.eq(Store.find(preset, preset.presets[1].ids[1]).box, 8, "team references survive rearrangement")
local themed = assert(Store.theme(preset, 8, "Forest"))
local encoded = Serializer.encode(themed)
T.eq(assert(Store.validate(assert(Serializer.decode(encoded)))).boxes[8].theme, "Forest", "Box theme persists through serialization")
T.eq(assert(Serializer.decode(encoded)).presets[1].name, "Pair", "preset name persists")
T.check(not Store.theme(preset, 8, "Unknown"), "invalid theme fails before persistence")
local report = Collection.dashboard(state, { dex = { caught = { [25] = true, [1] = true }, owned = { [25] = true } },
  modData = { cartImport = { dexOwned = { 4 } } } })
T.eq(report.total, 60, "dashboard counts all holdings")
T.eq(report.species, 1, "dashboard deduplicates species")
T.eq(report.caught, 3, "dashboard combines native caught history without duplicate counting")
T.eq(report.duplicates[1].count, 60, "dashboard reports duplicate holdings")
T.eq(#report.missing, 385, "missing holdings differ from caught history")
Catalog.get("emerald").national.toNational[288]=263
T.eq(Collection.dashboard(state,{version="emerald",dex={caught={[288]=true}},
  modData={cartImport={dexOwned={263}}}}).caught,1,"dashboard merges internal Gen3 IDs with native national history without double counting")

local files = { [Store.PATH] = Serializer.encode(preset), ["saves/emerald/slot1.lua"] = Serializer.encode({
  version = "emerald", generation = 3, party = { Store.copy(mon) }, storage = { boxes = {} } }) }
local fs = { read = function(path) return files[path] end,
  getInfo = function(path) return files[path] and { type = "file" } end,
  createDirectory = function() return true end,
  write = function(path, body) files[path] = body; return true end,
  remove = function(path) files[path] = nil; return true end }
local source = { version = "emerald", path = "saves/emerald/slot1.lua", slotId = "slot1" }
local service = assert(Service.open(fs))
T.check(service:deployPreset(source, 1), "team deploy moves actual records into party")
T.eq(#assert(Serializer.decode(files[source.path])).party, 3, "party gets exactly two team members")
T.check(assert(Serializer.decode(files[source.path])).dex.caught[25] or assert(Serializer.decode(files[source.path])).dex.caught["25"],
  "receiving a non-egg Pokémon registers caught history")
T.eq(Store.count(service.state), 58, "deployed members leave warehouse")
local beforeBox, beforeGame = files[Store.PATH], files[source.path]
T.check(not service:deployPreset(source, 1), "repeated deployment refuses missing members")
T.eq(files[Store.PATH], beforeBox, "refusal leaves warehouse unchanged")
T.eq(files[source.path], beforeGame, "refusal leaves game unchanged")

CacheFs.readAt = originalRead; Catalog.reset()
T.finish("Box collection")
