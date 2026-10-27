package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Fixture = require("tests.modkit.dataset_view_fixture")
local GameVersion = require("src.core.GameVersion")
local CacheFs = require("src.import.CacheFs")
local Logger = require("src.core.Logger")
local Loader = require("src.mods.Loader")
local DatasetHydration = require("src.core.DatasetHydration")
local DatasetViews = require("src.mods.DatasetViews")
local Game2 = require("src.core.Game2")

local GEN2 = { "gold", "silver", "crystal" }
local originalVersion, originalPrefix = GameVersion.get(), CacheFs.prefix
GameVersion.set("red")

local files = {}
for _, version in ipairs(GEN2) do Fixture.cache(files, version) end
local probe = Fixture.addMod(files, "emote_probe", [[
local mod = ...
local out = {}
for _, version in ipairs({ "gold", "silver", "crystal" }) do
  local view, reason = mod.datasets:open(version)
  local row = { reason = reason, walked = {} }
  if view then
    local emotes = view.content.field:get("emotes") or {}
    row.fishing = emotes.fishing
    row.fishingFemale = emotes.fishingFemale
    row.order = emotes.order
    row.fishingInfo = emotes.fishing and view.assets:info(emotes.fishing)
    row.femaleInfo = emotes.fishingFemale and view.assets:info(emotes.fishingFemale)
    row.battleHud = view.content.field:has("battleHud")
    row.pack = view.content.field:has("pack")
    row.fieldIds = {}
    for id in view.content.field:each() do row.fieldIds[#row.fieldIds + 1] = id end
    for name, registry in pairs(view.content) do
      local count = 0
      for _ in registry:each() do count = count + 1 end
      row.walked[name] = count
    end
    row.species = view.content.pokemon:get("FIXMON") ~= nil
  end
  local again, againReason = mod.datasets:open(version)
  row.reopened, row.reopenReason = again ~= nil, againReason
  out[version] = row
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
T.eq(#run.errors, 0, "emote probe loads clean")
local rejected = {}
for _, line in ipairs(warnings) do
  if line:find("rejected", 1, true) then rejected[#rejected + 1] = line end
end
T.same(rejected, {}, "no Gen 2 dataset is rejected after the field walk")

local out = run.loader.exports.emote_probe.result or {}
for _, version in ipairs(GEN2) do
  local row = out[version] or {}
  T.eq(row.reason, nil, version .. " opens")
  T.eq(row.fishing, "assets/generated/emotes/fishing.png",
    version .. " field emotes exposes the fishing sheet")
  T.same(row.fishingInfo, { type = "file" }, version .. " fishing sheet resolves as a file")
  T.same(row.order, { "shock" }, version .. " emotes keep their order list")
  if version == "crystal" then
    T.eq(row.fishingFemale, "assets/generated/emotes/fishing_female.png",
      version .. " exposes Kris' fishing sheet")
    T.same(row.femaleInfo, { type = "file" }, version .. " fishingFemale resolves as a file")
  else
    T.eq(row.fishingFemale, nil, version .. " has no fishingFemale")
  end
  T.eq(row.battleHud, false, version .. " other menu_gfx keys stay out of field")
  T.eq(row.pack, false, version .. " pack art stays out of field")
  T.same(row.fieldIds, { "emotes" }, version .. " field lists only emotes")
  T.eq(row.walked.field, 1, version .. " field walk yields emotes")
  T.eq(row.species, true, version .. " pokemon still reads after the walk")
  T.eq(row.reopened, true, version .. " stays valid after every registry is walked")
  T.eq(row.reopenReason, nil, version .. " reopens without a reason")
end
run.release()

for _, version in ipairs(GEN2) do
  local service = DatasetViews.new(T.sdk.memfs(files))
  local view = service:open(version)
  local internal = service.datasets[version]
  T.check(view ~= nil, version .. " lazy probe opens")
  if view then
    T.check(view.content.items:get("LEFTOVERS") ~= nil, version .. " items read")
    T.eq(internal.moduleCache.menu_gfx, nil,
      version .. " reading items leaves menu_gfx undecoded")
    T.check(type(view.content.field:get("emotes")) == "table", version .. " field emotes read")
    T.check(internal.moduleCache.menu_gfx ~= nil,
      version .. " reading field decodes menu_gfx")
  end
end

local function manifest(api)
  return '{"id":"emotes","name":"emotes","version":"1.0.0","api":' .. api
    .. ',"games":["all"],"entry":"main.lua"}'
end

for _, version in ipairs(GEN2) do
  for _, api in ipairs({ 2, 3 }) do
    local label = version .. " api " .. api
    local vanilla = {
      shock = "assets/generated/emotes/shock.png",
      fishing = "assets/generated/emotes/fishing.png",
      order = { "shock" },
    }
    local data = { gen2MenuGfx = { emotes = vanilla, battleHud = {} } }
    DatasetHydration.seedGen2Field(data)
    T.eq(data.field.emotes, vanilla, label .. " seeds field.emotes from menu_gfx")
    T.eq(data.field.battleHud, nil, label .. " seeds no other menu_gfx key")
    T.sdk.captureRuntime()
    local loader = Loader.new({ fs = T.sdk.memfs({
      ["mods/emotes/manifest.json"] = manifest(api),
      ["mods/emotes/main.lua"] = [[
local mod = ...
mod.exports.before = (mod.content.field:get("emotes") or {}).fishing
mod.exports.ok, mod.exports.reason = mod.content.field:patch("emotes",
  { fishing = "mods/emotes/fishing_red.png" })
]],
    }), generation = 2, version = version, dev = true })
    loader:load(data)
    T.same(loader.errors, {}, label .. " an emotes patch loads clean")
    local exports = loader.exports.emotes or {}
    T.eq(exports.before, "assets/generated/emotes/fishing.png",
      label .. " mod reads the cart fishing sheet")
    T.eq(data.field.emotes.fishing, "mods/emotes/fishing_red.png",
      label .. " the patch merges into field.emotes")
    Game2.applyFieldEmotes(data)
    T.eq(data.gen2MenuGfx.emotes.fishing, "mods/emotes/fishing_red.png",
      label .. " the patched sheet reaches gen2MenuGfx.emotes")
    T.eq(data.gen2MenuGfx.emotes.shock, "assets/generated/emotes/shock.png",
      label .. " unpatched emotes are kept")
    T.sdk.restoreRuntime()
  end
end

local plain = { gen2MenuGfx = { emotes = { fishing = "a.png" } } }
DatasetHydration.seedGen2Field(plain)
local same = plain.gen2MenuGfx.emotes
Game2.applyFieldEmotes(plain)
T.eq(plain.gen2MenuGfx.emotes, same, "no mod keeps the cart emote table")

GameVersion.set(originalVersion)
CacheFs.prefix = originalPrefix
T.finish("dataset_views_gen2_emotes")
