package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Fixture = require("tests.modkit.dataset_view_fixture")
local GameVersion = require("src.core.GameVersion")
local CacheFs = require("src.import.CacheFs")
local Logger = require("src.core.Logger")
local Schemas = require("src.mods.Schemas")
local Loader = require("src.mods.Loader")
local Records = require("src.mods.UnifiedRecords")

local VERSIONS = { "red", "blue", "yellow", "gold", "silver", "crystal" }
local originalVersion, originalPrefix = GameVersion.get(), CacheFs.prefix
GameVersion.set("red")

local files = {}
for _, version in ipairs(VERSIONS) do Fixture.cache(files, version) end
local probe = Fixture.addMod(files, "metadata_probe", [[
local mod = ...
local out = {}
for _, version in ipairs({ "red", "blue", "yellow", "gold", "silver", "crystal" }) do
  local view = assert(mod.datasets:open(version))
  local counts, ids = {}, {}
  for name, registry in pairs(view.content) do
    counts[name], ids[name] = 0, {}
    for id in registry:each() do
      counts[name] = counts[name] + 1
      ids[name][id] = true
    end
  end
  local again, reason = mod.datasets:open(version)
  out[version] = {
    counts = counts, ids = ids, reopened = again ~= nil, reason = reason,
    tutorHidden = not view.content.pokemon:has("tutorMoves"),
    capsuleHidden = not view.content.items:has("timeCapsule"),
    special = view.content.landmarks:get("LANDMARK_SPECIAL"),
  }
end
mod.exports.result = out
]])

local warnings = {}
local originalWarn = Logger.warn
Logger.warn = function(fmt, ...)
  warnings[#warnings + 1] = select("#", ...) > 0 and fmt:format(...) or fmt
end
local run = T.sdk.loadMods({ probe }, {
  fs = T.sdk.memfs(files), data = { pokemon = {} }, generation = 1,
})
Logger.warn = originalWarn
T.eq(#run.errors, 0, "metadata probe loads clean")
local rejected = {}
for _, line in ipairs(warnings) do
  if line:find("rejected", 1, true) then rejected[#rejected + 1] = line end
end
T.same(rejected, {}, "no fixture dataset is rejected")

local out = run.loader.exports.metadata_probe.result
for _, version in ipairs(VERSIONS) do
  local row = out[version]
  T.eq(row.reopened, true, version .. " stays valid after every registry is walked")
  T.eq(row.reason, nil, version .. " reopens without a reason")
  T.eq(row.counts.pokemon,
    GameVersion.generation(version) == 2 and 1 + #Fixture.CONTINUATIONS or 1,
    version .. " pokemon each counts species only")
end
for _, version in ipairs({ "gold", "silver", "crystal" }) do
  local row = out[version]
  T.eq(row.counts.items, 2, version .. " items each lists LEFTOVERS and ITEM_C3")
  T.eq(row.ids.items.ITEM_C3, true, version .. " nameless unused item row walks")
  T.eq(row.ids.items.timeCapsule, nil, version .. " timeCapsule is not an item id")
  T.eq(row.capsuleHidden, true, version .. " has skips timeCapsule")
  T.eq(row.counts.cries, 1, version .. " cries each accepts word pitch and length")
  T.eq(row.ids.encounters.timeFishGroups, true,
    version .. " encounters each walks timeFishGroups")
  T.eq(row.counts.landmarks, 1, version .. " landmarks each walks LANDMARK_SPECIAL")
  T.eq(row.special and row.special.x, -8, version .. " LANDMARK_SPECIAL keeps x -8")
  T.eq(row.counts.text, 1, version .. " text each lists script text only")
  T.eq(row.ids.text.labels, nil, version .. " text labels table is not a text id")
  T.eq(row.counts.tilesets, 1, version .. " tilesets each lists tileset records only")
  T.eq(row.ids.tilesets.animFrames, nil, version .. " animFrames is not a tileset id")
  T.eq(row.ids.pokemon.tutorMoves, nil, version .. " tutorMoves is not a species id")
  T.eq(row.tutorHidden, true, version .. " has skips tutorMoves")
end
run.release()

local function gen2(name)
  return Schemas.shapeFor(name, Schemas.REGISTRIES[name], 2)
end
local function check(name, id, value, mode)
  local ok, valid, detail = pcall(Schemas.check, gen2(name), name, id, value, mode or "register")
  T.eq(ok, true, name .. "." .. tostring(id) .. " check returns instead of throwing")
  return valid, detail
end
T.eq(check("items", "MY_ITEM", { id = "MY_ITEM", price = 10 }), nil,
  "a mod item without a name is still rejected")
T.eq(check("items", "ITEM_C3", { id = "ITEM_C3", index = 0xC4, price = 10 }), nil,
  "a nameless item whose id does not match its index is rejected")
for _, row in ipairs({ { "ITEM_FB", 0xFB }, { "ITEM_100", 0x100 } }) do
  for _, mode in ipairs({ "register", "override" }) do
    T.eq(check("items", row[1], { id = row[1], index = row[2], price = 0 }, mode), nil,
      "a nameless mod item named after its own index is rejected on " .. mode)
  end
end
T.eq(check("items", "ITEM_C3", { id = "ITEM_C3", index = 0xC3, price = 0 }, "register"), nil,
  "a mod register of a nameless ITEM_C3 is rejected")
T.eq(check("items", "ITEM_C3", { id = "ITEM_C3", index = 0xC3, price = 0 }, "base"), true,
  "the cart's own nameless ITEM_C3 row is accepted as base data")
T.eq(check("items", "ITEM_FB", { id = "ITEM_FB", index = 0xFB, price = 0 }, "base"), nil,
  "a nameless base row outside the cart's three is rejected")
local loaded = T.fixtures.fresh()
loaded.items.generation, loaded.items.source, loaded.items.pockets = 2, "fixture", {}
local modFiles = {
  ["mods/n/manifest.json"] = '{"id":"n","name":"n","version":"1.0.0","api":2,'
    .. '"games":["all"],"entry":"main.lua"}',
  ["mods/n/main.lua"] = [[
local mod = ...
mod.exports.ok = pcall(mod.content.items.register, mod.content.items, "ITEM_FB",
  { id = "ITEM_FB", index = 251, price = 0 })
]],
}
T.sdk.captureRuntime()
local modLoader = Loader.new({ fs = T.sdk.memfs(modFiles), generation = 2,
  version = "gold", dev = true })
local loadOk = pcall(modLoader.load, modLoader, loaded)
T.sdk.restoreRuntime()
T.eq(loadOk, true, "a mod registering a nameless ITEM_FB still loads")
T.eq((modLoader.exports.n or {}).ok, false, "api 2 register of a nameless ITEM_FB is refused")
T.eq(loaded.items.ITEM_FB, nil, "the nameless ITEM_FB is not merged")
T.eq(check("items", "MY_ITEM", { id = "MY_ITEM", name = "MY ITEM", price = 10 }), true,
  "a named mod item is accepted")
T.eq(check("cries", "FIXMON", { header = {}, pitch = 65536, length = 1 }), nil,
  "a Gen 2 cry pitch past a word is rejected")
T.eq(check("landmarks", "LANDMARK_X", { name = "X", index = 1, x = -9, y = 0 }), nil,
  "a landmark left of the cart's -8 floor is rejected")
T.eq(check("encounters", "timeFishGroups", { [true] = {
  day = { species = "FIXMON", level = 1 }, nite = { species = "FIXMON", level = 1 } } }), nil,
  "a timeFishGroups key of the wrong type is rejected")
T.eq(check("encounters", "timeFishGroups", { [3] = {
  day = { species = "FIXMON", level = 1 }, nite = { species = "FIXMON", level = 1 } } }), true,
  "a numeric timeFishGroups key is accepted")
T.eq(check("tilesets", "TILESET_FIXTURE", "assets/generated/tilesets/x.png"), nil,
  "a non-table tileset record is rejected")
local thrown, detail = Schemas.check({ fields = { id = Schemas.f.str },
  extra = function() error("boom") end }, "probe", "X", { id = "X" }, "register")
T.eq(thrown, nil, "a throwing schema hook reports failure")
T.check(type(detail) == "string" and detail:find("boom", 1, true) ~= nil,
  "a throwing schema hook names its error")

local data = {
  pokemon = { MEW = { id = "MEW", index = 151 }, tutorMoves = { "FLAMETHROWER" } },
  items = { LEFTOVERS = { id = "LEFTOVERS", index = 146 },
    timeCapsule = { [0x19] = "LEFTOVERS" } },
}
for _, row in ipairs({ { "tutorMoves", "species" }, { "timeCapsule", "item" } }) do
  local id, reason = Records.nativeId(row[1], row[2], 2, data)
  T.eq(id, nil, row[1] .. " is not a Gen 2 " .. row[2] .. " id")
  T.check(type(reason) == "string" and reason:find("reserved", 1, true) ~= nil,
    row[1] .. " is reserved engine metadata")
end
local mon = { species = "MEW", level = 5, hp = 10, maxHp = 10, moves = {} }
local accepted = Records.applyMon(mon, { species = "tutorMoves" }, 2, data, "crystal")
T.eq(accepted, nil, "applyMon refuses tutorMoves as a species")
T.eq(mon.species, "MEW", "refused metadata leaves the mon intact")

GameVersion.set(originalVersion)
CacheFs.prefix = originalPrefix
T.finish("dataset_views_gen2_metadata")
