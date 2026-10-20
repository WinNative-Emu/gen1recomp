package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Loader = require("src.mods.Loader")
local Version = require("src.core.GameVersion")
local Versions = require("src.import.gba.versions")
local Profile = require("src.core.game3.profile")
local ItemEffects = require("src.core.gen2.ItemEffects")

local function manifest(api)
  return '{"id":"misc","name":"misc","version":"1.0.0","api":' .. api
    .. ',"games":["all"],"entry":"main.lua"}'
end

local GEN2_BODY = [[
local mod = ...
mod.content.evolution_methods:register("MOD_METHOD", { check = function(a, b, c)
  mod.exports.shape = { a = a, b = b, c = c }
  return true
end })
]]

for _, case in ipairs({ { api = 2, gold = true }, { api = 3, gold = false } }) do
  local data = {}
  T.sdk.captureRuntime()
  local files = {
    ["mods/misc/manifest.json"] = manifest(case.api),
    ["mods/misc/main.lua"] = GEN2_BODY,
  }
  local loader = Loader.new({ fs = T.sdk.memfs(files), generation = 2, version = "gold", dev = true })
  T.check(loader:load(data), "api " .. case.api .. " loads an evolution method on Gold")
  local Evolution = require("src.core.gen2.Evolution")
  local entry = { method = "MOD_METHOD", into = "BAYLEEF", level = 5 }
  local mon = { species = "CHIKORITA", level = 9 }
  local ok = Evolution.rowMatches(entry, mon, { timeOfDay = "DAY" }, data)
  T.check(ok, "api " .. case.api .. " method fires")
  local shape = loader.exports.misc.shape
  if case.gold then
    T.eq(shape.a, entry, "api 2 check receives the EvosAttacks entry first")
    T.eq(shape.b, mon, "api 2 check receives the mon second")
    T.eq(type(shape.c), "table", "api 2 check receives the ctx third")
  else
    T.eq(shape.b, mon, "api 3 check receives the mon second")
    T.eq(shape.c, entry, "api 3 check receives the evolutions row third")
    T.eq(type(shape.a), "table", "api 3 check receives the game first")
    local seen
    local row = Evolution.gen1Trigger({ force = true, item = "FIRE_STONE" })
    T.eq(row.kind, "item", "a stone use is the item trigger")
    seen = Evolution.gen1Trigger({ link = true })
    T.eq(seen.kind, "trade", "a link evolution is the trade trigger")
    seen = Evolution.gen1Trigger({})
    T.eq(seen.kind, "levelup", "the after-battle sweep is the levelup trigger")
  end
  T.sdk.restoreRuntime()
end

local GEN2_ITEM_BODY = [[
local mod = ...
mod.content.items:register("MOD_TONIC", { id = "MOD_TONIC", name = "MOD TONIC", price = 100, effect = "TONIC_FX" })
mod.content.items:register("MOD_FLUTE", { id = "MOD_FLUTE", name = "MOD FLUTE", price = 100, effect = "FLUTE_FX" })
mod.content.items:register("MOD_SHUT", { id = "MOD_SHUT", name = "MOD SHUT", price = 100, effect = "SHUT_FX" })
mod.content.item_effects:register("TONIC_FX", { needsTarget = true, field = true, use = function(ctx)
  mod.exports.tonicCtx = ctx
  ctx.target.hp = ctx.target.maxHp
  return "consumed", { "Fully healed!" }
end })
mod.content.item_effects:register("FLUTE_FX", { needsTarget = false, field = true, use = function(ctx)
  mod.exports.fluteCtx = ctx
  return "kept", { "toot" }
end })
mod.content.item_effects:register("SHUT_FX", { battle = false, field = true, use = function()
  return "failed", { "No." }
end })
]]

for _, case in ipairs({ { api = 3, works = true }, { api = 2, works = false } }) do
  for _, version in ipairs({ "gold", "crystal" }) do
    local tag = "api " .. case.api .. " " .. version
    local data = {}
    T.sdk.captureRuntime()
    local files = {
      ["mods/misc/manifest.json"] = manifest(case.api),
      ["mods/misc/main.lua"] = GEN2_ITEM_BODY,
    }
    local loader = Loader.new({ fs = T.sdk.memfs(files), generation = 2, version = version, dev = true })
    loader:load(data)
    if case.works then
      T.same(loader.errors, {}, tag .. " item_effects loads without errors")
      T.eq(ItemEffects.partyAction("MOD_TONIC", data), "mod", tag .. " a Gen 1 shaped effect is a party action")
      T.check(ItemEffects.needsTarget("MOD_TONIC", data), tag .. " needsTarget keeps the party pick")
      T.check(not ItemEffects.needsTarget("MOD_FLUTE", data), tag .. " a targetless effect skips the pick")
      T.eq(ItemEffects.partyAction("MOD_SHUT", data, true), nil, tag .. " battle = false refuses in battle")
      T.eq(ItemEffects.partyAction("MOD_SHUT", data, false), "mod", tag .. " the field still runs it")
      local mon = { species = "CHIKORITA", hp = 1, maxHp = 30 }
      local result = ItemEffects.useOnMon("MOD_TONIC", mon, data, { game = { save = { name = "X" } } })
      T.eq(result.used, true, tag .. " consumed is a used result")
      T.check(not result.keep, tag .. " consumed spends the item")
      T.eq(result.text, "Fully healed!", tag .. " the effect message is the result text")
      T.eq(mon.hp, 30, tag .. " the effect acted on the party mon")
      T.eq(loader.exports.misc.tonicCtx.itemId, "MOD_TONIC", tag .. " ctx carries the mod item id")
      T.eq(loader.exports.misc.tonicCtx.target, mon, tag .. " ctx carries the target mon")
      local kept = ItemEffects.useWithoutTarget("MOD_FLUTE", data, { game = {} })
      T.check(kept.used and kept.keep, tag .. " kept is used without spending")
      T.eq(kept.text, "toot", tag .. " kept carries its message")
      local failed = ItemEffects.useOnMon("MOD_SHUT", mon, data)
      T.eq(failed.used, false, tag .. " failed is not a used result")
      T.eq(failed.text, "No.", tag .. " failed carries its message")
    else
      T.eq(ItemEffects.partyAction("MOD_TONIC", data), nil, tag .. " keeps the dev behavior: no action, no use")
      T.check(ItemEffects.needsTarget("MOD_TONIC", data), tag .. " needsTarget stays the party pick")
    end
    T.sdk.restoreRuntime()
  end
end

local GEN3_BODY = [[
local mod = ...
mod.content.items:register("MOD_TONIC", { id = "MOD_TONIC", index = 500, name = "MOD TONIC",
  price = 100, pocket = "ITEMS", effect = "TONIC_FX" })
mod.content.items:register("MOD_FLUTE", { id = "MOD_FLUTE", index = 501, name = "MOD FLUTE",
  price = 100, pocket = "ITEMS", effect = "FLUTE_FX" })
mod.content.item_effects:register("TONIC_FX", { needsTarget = true, use = function(ctx)
  ctx.target.hp = ctx.target.maxHp
  return "consumed", { "Fully healed!" }
end })
mod.content.item_effects:register("FLUTE_FX", { battle = false, use = function(ctx)
  mod.exports.fluteCtx = ctx
  return "kept", { "toot" }
end })
]]

local LANDMARK_BODY = [[
mod.content.landmarks:register("MAPSEC_MOD_COVE", { name = "MOD COVE", index = 230,
  theme = "wood", x = 4, y = 6, width = 2, height = 1 })
mod.content.landmarks:register("RENAME_START", { name = "HOME TOWN", index = 88, theme = "stone" })
]]

local DECOR_BODY = [[
mod.content.decorations:register("DECOR_MOD_DESK", { name = "MOD DESK", index = 130,
  permission = 0, shape = 0, category = 0, price = 500, description = "A mod desk.",
  tiles = { 640 } })
]]

local RSE = { ruby = true, sapphire = true, emerald = true }

for _, version in ipairs({ "firered", "leafgreen", "ruby", "sapphire", "emerald" }) do
  Version.set(version)
  Versions.select(version)
  Profile.reset()
  local data = T.sdk.gen3Data()
  T.sdk.captureRuntime()
  local files = {
    ["mods/misc/manifest.json"] = manifest(3),
    ["mods/misc/main.lua"] = GEN3_BODY .. LANDMARK_BODY .. (RSE[version] and DECOR_BODY or ""),
  }
  local loader = Loader.new({ fs = T.sdk.memfs(files), generation = 3, version = version, dev = true })
  T.check(loader:load(data), version .. " loads with item_effects")
  T.same(loader.errors, {}, version .. " item_effects is not reported unavailable")
  T.eq(type(data.item_effects.TONIC_FX.use), "function", version .. " item effect merged")

  local Compat = require("src.mods.Gen3Compat")
  local ItemsData = require("src.core.game3.items_data")
  local ItemUse = require("src.core.game3.item_use")
  local BattleItems = require("src.core.game3.battle.items")
  local Bag = require("src.core.game3.bag")
  local registered = data.gen3Landmarks
  local registeredDecor = data.gen3Decorations
  data.gen3Landmarks, data.gen3Decorations = nil, nil
  Compat.applyMerged({ data = data, options = {} })
  data.gen3Landmarks, data.gen3Decorations = registered, registeredDecor
  ItemsData.installPack({ items = data.gen3Items._byId })
  local savedBag = ItemsData._bagModel
  ItemsData._bagModel = ItemsData._bagModel or true

  local bag = Bag.new()
  Bag.add(bag, 500, 2)
  Bag.add(bag, 501, 1)
  local mon = { hp = 1, maxHp = 50 }
  local session = { party = { mon }, bag = bag }
  T.check(ItemUse.needsPartyTarget(500), version .. " a needsTarget effect asks for a party mon")
  T.check(not ItemUse.needsPartyTarget(501), version .. " a targetless effect does not")
  local ok, kind, text = ItemUse.useField(session, bag, 500, nil)
  T.check(not ok and kind == "need_slot", version .. " field use without a target asks for one")
  ok, kind, text = ItemUse.useField(session, bag, 500, 1)
  T.check(ok and kind == "mod", version .. " field use runs the mod effect")
  T.eq(text, "Fully healed!", version .. " the effect message is the result text")
  T.eq(mon.hp, 50, version .. " the effect acted on the party mon")
  T.eq(Bag.get(bag, 500), 1, version .. " consumed removes one")
  ok, kind, text = ItemUse.useField(session, bag, 501, nil)
  T.check(ok and kind == "mod" and text == "toot", version .. " a kept effect runs")
  T.eq(Bag.get(bag, 501), 1, version .. " kept leaves the item")
  T.eq(loader.exports.misc.fluteCtx.itemId, "MOD_FLUTE", version .. " ctx carries the mod item id")
  T.check(BattleItems.isBattleUsable(500), version .. " an effect without battle = false is usable in battle")
  T.check(not BattleItems.isBattleUsable(501), version .. " battle = false hides the item from the battle bag")
  T.check(BattleItems.needsPartySelect(500), version .. " battle asks for a target when the effect does")
  local st = { playerParty = { mon } }
  mon.hp = 3
  local result = BattleItems.use(st, nil, bag, session, 500, 1, nil, nil)
  T.eq(result, "heal", version .. " battle use runs the effect")
  T.eq(mon.hp, 50, version .. " battle use acted on the party mon")
  T.eq(Bag.get(bag, 500), 0, version .. " battle use consumed the item")

  ItemUse.installEffects({}, nil)
  T.check(ItemUse.modEffect(500) == nil, version .. " no registry means the item has no effect")
  ItemsData._bagModel = savedBag
  ItemsData._pack, ItemsData._byId, ItemsData._byName = nil, nil, nil

  T.eq(data.gen3Landmarks.MAPSEC_MOD_COVE.index, 230, version .. " landmarks merged")
  local ModLandmarks = require("src.core.game3.mod_landmarks")
  local rse = RSE[version]
  local cells = {}
  local sections = { [88] = { id = "MAPSEC_PALLET_TOWN", name = "PALLET TOWN", theme = "marble",
    x = 1, y = 1, width = 1, height = 1 } }
  local pack = { sections = sections, count = 100 }
  local Region, Sections, nativeName
  if rse then
    for y = 1, 10 do
      cells[y] = {}
      for x = 1, 10 do cells[y][x] = 0 end
    end
    package.loaded["src.ui.game3.rse.mapsec"] = { pack = function() return pack end }
    package.loaded["src.ui.game3.rse.region_map"] = { manifest = function() return { layout = cells } end }
  else
    Region = require("src.import.gba.region_map_extract")
    Sections = require("src.import.gba.map_sections_extract")
    Sections.installNames({})
    nativeName = Sections.SECTIONS[88].name
    Sections.SECTIONS[88].name = "PALLET TOWN"
    cells = { [0] = {}, [1] = {}, [2] = {}, [3] = {}, [4] = {}, [5] = {}, [6] = {} }
    for y = 0, 6 do for x = 0, 8 do cells[y][x] = 197 end end
    Region.LAYOUTS = { [0] = { map = cells } }
  end
  data.gen3Decorations = nil
  Compat.applyMerged({ data = data, options = {} })
  data.gen3Decorations = registeredDecor
  if rse then
    T.eq(pack.sections[230].name, "MOD COVE", version .. " a new section gets its name")
    T.eq(pack.sections[230].theme, "wood", version .. " a new section gets its theme")
    T.eq(pack.sections[88].name, "HOME TOWN", version .. " an existing index is renamed")
    T.eq(pack.sections[88].id, "MAPSEC_PALLET_TOWN", version .. " renaming keeps the native id")
    T.eq(cells[7][5], 230, version .. " the landmark claims its region map cells")
    T.eq(cells[7][6], 230, version .. " the landmark claims its width")
    T.eq(pack.count, 231, version .. " the section count grows")
  else
    T.eq(Sections.SECTIONS[230].name, "MOD COVE", version .. " a new section gets its name")
    T.eq(Sections.SECTIONS[88].name, "HOME TOWN", version .. " an existing index is renamed")
    T.eq(Sections.SECTIONS[88].id, "MAPSEC_PALLET_TOWN", version .. " renaming keeps the native id")
    T.eq(Region.SECTION_NAMES.MAPSEC_PALLET_TOWN, "HOME TOWN", version .. " the region map name box follows")
    T.eq(Region.SECTION_NAMES.MAPSEC_MOD_230, "MOD COVE", version .. " the new section is nameable")
    T.eq(cells[6][4], 230, version .. " the landmark claims its region map cells")
    local info = Sections.getInfo(230, nil, 0)
    T.eq(info.name, "MOD COVE", version .. " the popup resolves the new section")
  end
  ModLandmarks.reset()
  if rse then
    T.eq(pack.sections[230], nil, version .. " reset removes the new section")
    T.eq(pack.sections[88].name, "PALLET TOWN", version .. " reset restores the native name")
    T.eq(cells[7][5], 0, version .. " reset restores the cells")
  else
    T.eq(Sections.SECTIONS[230], nil, version .. " reset removes the new section")
    T.eq(Sections.SECTIONS[88].name, "PALLET TOWN", version .. " reset restores the native name")
    T.eq(cells[6][4], 197, version .. " reset restores the cells")
    Region.LAYOUTS = nil
    Sections.SECTIONS[88].name = nativeName
  end
  package.loaded["src.ui.game3.rse.mapsec"] = nil
  package.loaded["src.ui.game3.rse.region_map"] = nil

  if rse then
    T.eq(data.gen3Decorations.DECOR_MOD_DESK.index, 130, version .. " decorations merged")
    local DecorInv = require("src.core.game3.rse.decoration_inventory")
    local Decor = require("src.core.game3.rse.decoration")
    local ModDecorations = require("src.core.game3.mod_decorations")
    DecorInv.install({ decorations = { [1] = { id = 1, name = "SMALL DESK", permission = 0,
      shape = 0, category = 0, price = 3000, description = "d" } }, categoryNames = {} })
    Decor.install({ decorTiles = { [1] = { 1 } } })
    data.gen3Landmarks = nil
    Compat.applyMerged({ data = data, options = {} })
    T.eq(DecorInv.info(130).name, "MOD DESK", version .. " the decoration PC reads the mod row")
    T.eq(DecorInv.categoryOf(130), 0, version .. " the mod decoration files under its category")
    T.same(Decor.info(130).tiles, { 640 }, version .. " the mod decoration paints its metatiles")
    T.eq(Decor.NUM_DECORATIONS, 130, version .. " the secret base accepts the new id")
    T.eq(DecorInv.info(1).name, "SMALL DESK", version .. " native decorations are unchanged")
    ModDecorations.reset()
    T.eq(DecorInv.info(130), nil, version .. " reset removes the mod row")
    T.eq(Decor.NUM_DECORATIONS, 120, version .. " reset restores the id ceiling")
    DecorInv.reset()
    Decor.reset()
  else
    local frlgData = T.sdk.gen3Data()
    T.sdk.captureRuntime()
    local frlgLoader = Loader.new({ fs = T.sdk.memfs({
      ["mods/misc/manifest.json"] = manifest(3),
      ["mods/misc/main.lua"] = DECOR_BODY,
    }), generation = 3, version = version, dev = true })
    frlgLoader:load(frlgData)
    T.check(#frlgLoader.errors > 0, version .. " FRLG reports decorations as unavailable")
    T.eq(frlgData.gen3Decorations, nil, version .. " FRLG has no decorations table")
  end
  T.sdk.restoreRuntime()
end

for _, version in ipairs({ "gold", "silver", "crystal" }) do
  local data = {}
  T.sdk.captureRuntime()
  local files = {
    ["mods/misc/manifest.json"] = manifest(3),
    ["mods/misc/main.lua"] = [[
local mod = ...
mod.content.field:patch("boot", { startMap = "CHERRYGROVE_CITY", startX = 7, startY = 9,
  startFacing = "left", startMoney = 1234, rivalName = "ZED" })
]],
  }
  local loader = Loader.new({ fs = T.sdk.memfs(files), generation = 2, version = version, dev = true })
  T.check(loader:load(data), version .. " loads with the field registry")
  T.same(loader.errors, {}, version .. " field is not reported unavailable on Gen 2")
  T.eq(data.field.boot.startMoney, 1234, version .. " boot merged into data.field")
  local World = require("src.world.gen2.World")
  local maps = { PLAYERS_HOUSE_2F = {}, CHERRYGROVE_CITY = {} }
  local map, x, y, facing = World.bootSpawn(data, maps, "PLAYERS_HOUSE_2F", 3, 3, "down")
  T.same({ map, x, y, facing }, { "CHERRYGROVE_CITY", 7, 9, "left" }, version .. " New Game starts at the boot spawn")
  map, x, y, facing = World.bootSpawn(data, { PLAYERS_HOUSE_2F = {} }, "PLAYERS_HOUSE_2F", 3, 3, "down")
  T.same({ map, x, y, facing }, { "PLAYERS_HOUSE_2F", 3, 3, "down" }, version .. " an unknown boot map keeps SPAWN_HOME")
  map, x, y, facing = World.bootSpawn({}, maps, "PLAYERS_HOUSE_2F", 3, 3, "down")
  T.same({ map, x, y, facing }, { "PLAYERS_HOUSE_2F", 3, 3, "down" }, version .. " no boot config keeps SPAWN_HOME")
  local Save = require("src.core.gen2.Save")
  local save = Save.newGame({ startMoney = 1234, rivalName = "ZED" })
  T.eq(save.player.money, 1234, version .. " the New Game skeleton starts with the boot money")
  T.eq(save.rival.name, "ZED", version .. " the rival starts with the boot name")
  T.eq(Save.newGame().player.money, 3000, version .. " the cart money is the default")
  T.sdk.restoreRuntime()

  data = {}
  T.sdk.captureRuntime()
  files["mods/misc/main.lua"] = [[
local mod = ...
mod.content.field:patch("flyOrder", { "NEW_BARK_TOWN" })
]]
  loader = Loader.new({ fs = T.sdk.memfs(files), generation = 2, version = version, dev = true })
  loader:load(data)
  T.check(#loader.errors > 0, version .. " a Gen 1 only field key is reported on Gen 2")
  T.sdk.restoreRuntime()
end

T.finish("unified registries misc")
