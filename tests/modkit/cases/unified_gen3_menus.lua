package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Loader = require("src.mods.Loader")
local ModRuntime = require("src.mods.Runtime")
local Version = require("src.core.GameVersion")
local Versions = require("src.import.gba.versions")
local Runtime = require("src.core.game3.runtime")
local Profile = require("src.core.game3.profile")
local Pokemon = require("src.core.game3.pokemon")
local Dataset = require("src.core.game3.dataset")
local CacheBlob = require("src.import.CacheBlob")
local Extract = require("src.import.gba.extract_island1")
local Cache = require("tests.game3_cache")
local NativeMenus = require("tests.fixture_data.game3_native_menus")
local Font = require("src.ui.game3.frlg_font")
local Space = require("src.core.game3.scripting.space")
local Kit = require("src.ui.game3.rse.scene_kit")
local Stack = require("src.ui.game3.stack")
local List = require("src.ui.game3.list_menu")
local Naming = require("src.ui.game3.naming")
local Party = require("src.ui.game3.party_menu")
local Options = require("src.core.game3.options")

local originalVersion = Version.get()
local originalNativeVersion = Versions.active()
local restore, printed = {}, {}
local function fixture(owner, key, value)
  local old = owner[key]
  restore[#restore + 1] = function() owner[key] = old end
  owner[key] = value
end

fixture(love.graphics, "intersectScissor", function(x, y, width, height)
  local sx, sy, sw, sh = love.graphics.getScissor()
  if sx then
    local right, bottom = math.min(x + width, sx + sw), math.min(y + height, sy + sh)
    x, y = math.max(x, sx), math.max(y, sy)
    width, height = math.max(0, right - x), math.max(0, bottom - y)
  end
  love.graphics.setScissor(x, y, width, height)
end)

local originalDraw = Font.draw
fixture(Font, "draw", function(text, x, y, ...)
  printed[#printed + 1] = { text = tostring(text), x = x, y = y }
  return originalDraw(text, x, y, ...)
end)

local function input(edge, held)
  return {
    wasPressed = function(_, key) return key == edge end,
    isDown = function(_, key) return key == (held or edge) end,
  }
end

local function capture(draw)
  printed = {}
  draw()
  return printed
end

local function has(rows, text)
  for _, row in ipairs(rows) do if row.text == text then return true end end
  return false
end

local BODY = [[
local mod = ...
local out = mod.exports
out.mode, out.calls, out.actions, out.steps, out.values = "change", {}, 0, 0, 0
out.install = function()
  local removers = {}
  local function wrap(name, fn)
    removers[#removers + 1] = mod.hooks:wrap(name, function(next, ...)
      out.calls[name] = (out.calls[name] or 0) + 1
      return fn(next, ...)
    end)
  end
  wrap("ui.list_menu", function(next, opts, ctx)
    out.listContext = ctx
    opts = next(opts, ctx)
    if out.mode == "invalid" then opts.wrap = true; return false end
    if out.mode == "pass" then return opts end
    opts.wrap, opts.pageJump, opts.keyRepeat = true, true, not out.noRepeat
    opts.repeatDelay, opts.repeatRate = 2, 2
    return opts
  end)
  wrap("ui.options.rows", function(next, game, rows)
    out.optionsGame = game
    rows = next(game, rows)
    if out.mode == "invalid" then rows[1].label = "CORRUPTED"; return false end
    if out.mode == "pass" then return rows end
    local native
    for _, row in ipairs(rows) do if row.id == "textSpeed" then native = row end end
    out.nativeValue = native and native.value(game)
    return {
      { id = "menu.action", label = "MENU ACTION", activate = function(g)
        out.actionGame = g
        out.actions = out.actions + 1
        g.options.menuAction = out.actions
      end },
      { id = "menu.step", label = "MENU STEP", value = function(g)
        out.valueGame = g
        out.values = out.values + 1
        return tostring(g.options.menuStep or 0)
      end, step = function(g, dir)
        out.stepGame, out.direction = g, dir
        out.steps = out.steps + 1
        g.options.menuStep = (g.options.menuStep or 0) + dir
        return true
      end },
      native,
    }
  end)
  wrap("ui.naming.grid", function(next, grid, ctx)
    out.namingContext = ctx
    grid = next(grid, ctx)
    if out.mode == "invalid" then grid[1][1] = "CORRUPTED"; return false end
    if out.mode == "pass" then return grid end
    grid[1][1] = ctx.lower and "z" or "Z"
    if out.mode == "controls" then
      grid[1][2], grid[1][3], grid[1][4] = " ", "lower case", "ED"
    end
    return grid
  end)
  wrap("ui.party.submenu", function(next, game, items, mon, ctx)
    out.partyContext, out.partyGame, out.monSpecies = ctx, game, mon.species
    out.mon, out.monHp = mon, mon.hp
    items = next(game, items, mon, ctx)
    if out.mode == "invalid" then items[1].label = "CORRUPTED"; return false end
    if out.mode == "pass" then return items end
    mon.hp = 1
    return { items[#items], { label = "MENU PARTY", onSelect = function(...)
      local selectedMon, selectedGame = ...
      out.selectedArgs = select("#", ...)
      out.selectedMon, out.selectedGame = selectedMon, selectedGame
      out.selectedSpecies, out.selectedHp = selectedMon.species, selectedMon.hp
      selectedMon.hp = 2
      out.actions = out.actions + 1
    end } }
  end)
  wrap("ui.party.grid_navigation", function(next, menu)
    out.partyMenu = menu
    if out.mode == "pass" then return next(menu) end
    if out.mode == "invalid" then return "true" end
    return true
  end)
  return function() for _, remove in ipairs(removers) do remove() end end
end
]]

local function addMod(files, id, api, body)
  files["mods/" .. id .. "/manifest.json"] = ('{"id":"%s","name":"%s",'
    .. '"version":"1.0.0","api":%d,"games":["all"],"entry":"main.lua"}')
    :format(id, id, api)
  files["mods/" .. id .. "/main.lua"] = body
end

local function setup(version, api, rollback)
  Version.set(version)
  Versions.select(version)
  Profile.reset()
  local files = {}
  addMod(files, "menus", api or 3, BODY)
  if rollback then
    addMod(files, "z_failure", 3, BODY .. [[
      local mod = ...
      mod.exports.install()
      error("menu owner rollback")
    ]])
  end
  local data = T.sdk.gen3Data()
  for key, value in pairs(data.gen3Pokemon) do fixture(Pokemon, key, value) end
  fixture(Pokemon, "_cache", Dataset.cache())
  fixture(Pokemon, "_icons", {})
  fixture(Pokemon, "_national", { toNational = { [16] = 16 } })
  local mon = { species = 16, nickname = "BIRD", level = 5, hp = 20, maxHp = 30,
    moves = { 1 }, pp = { 10 }, maxPp = { 35 }, item = 0,
    attack = 12, defense = 13, speed = 14, spAtk = 15, spDef = 16 }
  local session = { version = version, party = { mon, mon, mon, mon, mon, mon },
    options = {}, flags = {}, vars = {}, name = "RED" }
  local game = { data = data, session = session, options = session.options, phase = "field" }
  session.game = game
  T.sdk.captureRuntime()
  local loader = Loader.new({ fs = T.sdk.memfs(files), generation = 3, version = version, dev = true })
  loader.game = game
  local ok = loader:load(data)
  T.eq(ok, not rollback, version .. " Loader result")
  if rollback then
    T.eq(#loader.errors, 1, version .. " only intentional owner failure")
    T.check(tostring(loader.errors[1]):find("menu owner rollback", 1, true) ~= nil,
      version .. " rollback reaches intended entry failure")
    T.eq(loader.exports.z_failure, nil, version .. " failed owner exports removed")
  else
    T.eq(#loader.errors, 0, version .. " Loader API " .. tostring(api or 3) .. " loads cleanly")
  end
  fixture(Runtime, "active", true)
  fixture(Runtime, "session", session)
  fixture(Runtime, "_game", game)
  return loader.exports.menus, game, loader
end

local items = {}
for i = 1, 8 do items[i] = { label = "ROW " .. i, id = i } end

local function listTrace(game, extra)
  local opts = { game = game, title = "MENUS", kind = "bag", items = items,
    maxShowed = 3, sound = false, arrows = false, frame = "none" }
  for key, value in pairs(extra or {}) do opts[key] = value end
  local menu = List.new(opts)
  local trace = {}
  for _, key in ipairs({ "up", "right", "down", "left" }) do
    menu:handleInput(input(key))
    local _, index = menu:selected()
    trace[#trace + 1] = index
  end
  return trace, menu, opts
end

local function optionMenu(version)
  if version == "ruby" or version == "sapphire" then return require("src.ui.game3.rs.option_menu") end
  if version == "emerald" then return require("src.ui.game3.rse.option_menu") end
  return require("src.ui.game3.option_menu")
end

local function openOptions(version, game)
  local menu = optionMenu(version)
  menu.show({ game = game, session = game.session })
  if version == "ruby" or version == "sapphire" then
    menu.handleInput(input("down"))
    T.eq(menu.cursor, 1, version .. " native options reject input during fade-in")
  end
  for _ = 1, 40 do menu.update() end
  return menu, menu._pages or menu._st.pages
end

local function rowLabels(rows)
  local labels = {}
  for _, row in ipairs(rows) do labels[#labels + 1] = { id = row.id, label = row.label } end
  return labels
end

local function exercise(version, label, fn)
  local ok, err = xpcall(fn, debug.traceback)
  T.check(ok, version .. " " .. label .. ": " .. tostring(err))
  Naming.dismiss()
  if Party.isOpen() then Party.close() end
  local menu = optionMenu(version)
  if menu.isOpen() then menu.close() end
  Stack.clear()
  T.sdk.restoreRuntime()
end

local baseRoot = Cache.root("meta.json", { native = true })
local originalRead, originalLoad, originalInfo = love.filesystem.read, love.filesystem.load, love.filesystem.getInfo
local assetRoot, assetVersion
local stableRoot = "data/generated/gba"
local function assetBytes(path)
  if type(path) ~= "string" then return nil end
  local neutral = NativeMenus.bytes(assetVersion, path)
  if neutral ~= nil then return neutral end
  local marker = path:find(stableRoot .. "/", 1, true)
  if not marker or not assetRoot then return nil end
  local target = assetRoot .. "/" .. path:sub(marker + #stableRoot + 1)
  local f = io.open(target, "rb")
  if not f then return nil end
  local bytes = CacheBlob.decode(target, f:read("*a"))
  f:close()
  return bytes
end
fixture(love.filesystem, "read", function(path, ...)
  local bytes = assetBytes(path)
  return bytes and CacheBlob.encode(path, bytes) or originalRead(path, ...)
end)
fixture(love.filesystem, "getInfo", function(path, ...)
  local bytes = assetBytes(path)
  if bytes then return { type = "file", size = #bytes } end
  return originalInfo(path, ...)
end)
fixture(love.filesystem, "load", function(path, ...)
  local bytes = assetBytes(path)
  if bytes then return (loadstring or load)(bytes, "@" .. path) end
  return originalLoad(path, ...)
end)

local nativeCache = Dataset.cache()
local nativeCacheRead, nativeCacheExists = nativeCache.read, nativeCache.exists
fixture(nativeCache, "read", function(self, path, ...)
  return assetBytes(path) or nativeCacheRead(self, path, ...)
end)
fixture(nativeCache, "exists", function(self, path, ...)
  return assetBytes(path) ~= nil or nativeCacheExists(self, path, ...)
end)
fixture(Extract, "CACHE_ROOT", stableRoot)
for _, version in ipairs({ "firered", "leafgreen", "ruby", "sapphire", "emerald" }) do
  assetVersion = version
  assetRoot = baseRoot and (version == "firered" and baseRoot
    or baseRoot:gsub("/firered/", "/" .. version .. "/")) or version .. "/" .. stableRoot
  if version ~= "firered" and assetRoot == baseRoot then assetRoot = version .. "/" .. stableRoot end
  fixture(Dataset, "cacheRootOverride", assetRoot)
  fixture(Space, "bundle", {
    text = setmetatable({}, { __index = function(data, key)
      local ir = { { t = "text", s = tostring(key) }, { t = "eos" } }
      rawset(data, key, ir)
      return ir
    end }),
    textTables = setmetatable({}, { __index = function() return 3 end }),
    events = {}, maps = {}, scripts = {},
  })
  Kit.resetCaches()
  Font.invalidate()
  require("src.ui.game3.naming_chrome").install()

  exercise(version, "list navigation and lifecycle", function()
    local out, game = setup(version)
    local stock = listTrace(game)
    T.same(stock, { 1, 1, 2, 2 }, version .. " no-hook edge and page defaults")
    local remove = out.install()
    local trace, menu, opts = listTrace(game)
    T.same(trace, { 8, 3, 4, 1 }, version .. " wrap and horizontal page jumps affect selection")
    T.eq(opts.wrap, nil, version .. " caller constructor options stay untouched")
    T.eq(out.listContext.game, game, version .. " list context game")
    T.eq(out.listContext.kind, "bag", version .. " list context kind")
    T.eq(out.listContext.title, "MENUS", version .. " list context title")
    T.eq(out.listContext.itemCount, 8, version .. " list context item count")
    menu:setSelected(1)
    menu:handleInput(input("down"))
    for frame = 1, 4 do
      menu:update(frame % 2 == 0 and 1 / 30 or 1 / 120)
      menu:handleInput(input(nil, "down"))
      local _, index = menu:selected()
      T.eq(index, frame < 2 and 2 or frame < 4 and 3 or 4, version .. " repeat fixed tick " .. frame)
    end
    out.noRepeat = true
    local _, disabled = listTrace(game)
    disabled:setSelected(1)
    disabled:handleInput(input("down"))
    for _ = 1, 8 do disabled:handleInput(input(nil, "down")) end
    local _, selected = disabled:selected()
    T.eq(selected, 2, version .. " keyRepeat false suppresses held movement")
    out.mode = "invalid"
    T.same(listTrace(game), stock, version .. " invalid mutation keeps pristine list defaults")
    remove()
    T.same(listTrace(game), stock, version .. " unsubscribe restores native navigation")
    for _, legacy in ipairs({ "dpad", "lr" }) do
      local _, native = listTrace(game, { scrollMultiple = legacy })
      native:setSelected(1)
      native:handleInput(input(legacy == "lr" and "r" or "right"))
      local _, index = native:selected()
      T.eq(index, 4, version .. " legacy scrollMultiple " .. legacy .. " remains active")
    end
  end)

  exercise(version, "options descriptors through native input", function()
    local out, game = setup(version)
    local menu, pages = openOptions(version, game)
    local stock = rowLabels(pages[1].rows)
    menu.close()
    local remove = out.install()
    menu, pages = openOptions(version, game)
    T.eq(out.calls["ui.options.rows"], 1, version .. " root hook fires exactly once")
    T.eq(out.optionsGame, game, version .. " options receives the game")
    T.eq(pages[1].rows[#pages[1].rows - 1].label, "MENU ACTION", version .. " custom action survives grouping")
    local function focus(id)
      for i, row in ipairs(pages[#pages].rows) do
        if row.id == id then pages[#pages].index = i; return end
      end
      error("native option row missing: " .. id)
    end
    focus("menu.action")
    menu.handleInput(input("a"))
    T.eq(out.actions, 1, version .. " A runs custom activate once")
    T.eq(out.actionGame, game, version .. " activate receives game, not native context")
    T.eq(game.options.menuAction, 1, version .. " activate writes the running options")
    focus("menu.step")
    menu.handleInput(input("left"))
    menu.handleInput(input("right"))
    T.eq(out.steps, 2, version .. " left and right run custom step")
    T.eq(out.direction, 1, version .. " step receives direction")
    T.eq(out.stepGame, game, version .. " step receives game")
    T.eq(game.options.menuStep, 0, version .. " step changes live values in both directions")
    capture(menu.draw)
    T.check(out.values > 0, version .. " native draw evaluates custom value")
    T.eq(out.valueGame, game, version .. " value receives game")
    focus("group.speed")
    menu.handleInput(input("a"))
    T.eq(#pages, 2, version .. " grouped native row opens its page")
    T.eq(out.calls["ui.options.rows"], 1, version .. " nested page does not hook again")
    local before = Options.block(game.options).textSpeed or 0
    menu.handleInput(input("right"))
    local pending = menu._pending and menu._pending.textSpeed or Options.block(game.options).textSpeed
    T.eq(pending, (before + 1) % 3, version .. " inherited native step remains functional")
    menu.close()
    out.mode = "invalid"
    menu, pages = openOptions(version, game)
    T.same(rowLabels(pages[1].rows), stock, version .. " invalid row mutation keeps pristine native rows")
    menu.close()
    remove()
    menu, pages = openOptions(version, game)
    T.same(rowLabels(pages[1].rows), stock, version .. " options unsubscribe restores native grouping")
  end)

  exercise(version, "naming and party native asset fixtures", function()
    local out, game = setup(version)
    local required = { "/naming/manifest.lua", "/pokemon/party/manifest.lua", "/chrome/user_frame_0.rgba" }
    if version == "ruby" or version == "sapphire" then
      required[#required + 1] = "/rse/menus/manifest.lua"
      required[#required + 1] = "/rse/party/manifest.lua"
    end
    for _, suffix in ipairs(required) do
      assert(assetBytes(Extract.CACHE_ROOT .. suffix) ~= nil,
        version .. " native fixture required: " .. suffix)
    end
    local function naming()
      Naming.open({ game = game, session = game.session, title = "MENUS", template = "PLAYER", maxLen = 7 })
      return Naming._state
    end
    local st = naming()
    T.eq(st.rs, version == "ruby" or version == "sapphire", version .. " naming uses native family layout")
    local originalChar = st.pages and st.pages[st.page].rows[1][1] or "A"
    local stock = capture(Naming.draw)
    Naming.handleInput(input("a"))
    T.eq(st.name, originalChar, version .. " no-hook naming chooses displayed native character")
    Naming.dismiss()
    local remove = out.install()
    st = naming()
    local changed = capture(Naming.draw)
    T.check(has(changed, "Z"), version .. " hook character reaches actual keyboard drawing")
    Naming.handleInput(input("a"))
    T.eq(st.name, "Z", version .. " A chooses hooked displayed character")
    T.eq(out.namingContext.game, game, version .. " naming context game")
    T.eq(out.namingContext.maxLen, 7, version .. " naming context length")
    Naming.dismiss()
    out.mode = "controls"
    st = naming()
    Naming.handleInput(input("a"))
    Naming.handleInput(input("right"))
    Naming.handleInput(input("a"))
    T.eq(st.name, "Z ", version .. " canonical space inserts one space")
    Naming.handleInput(input("right"))
    Naming.handleInput(input("a"))
    T.eq(st.name, "Z ", version .. " case control inserts no text")
    for _ = 1, 160 do Naming.update(1 / 60) end
    T.eq(st.pages[st.page].id, "LOWER", version .. " canonical case control switches native page")
    st.row, st.col = 1, 4
    Naming.handleInput(input("a"))
    T.eq(Naming.isOpen(), false, version .. " canonical ED confirms without insertion")
    out.mode = "invalid"
    naming()
    T.same(capture(Naming.draw), stock, version .. " invalid grid mutation preserves native drawing")
    Naming.dismiss()
    remove()
    naming()
    T.same(capture(Naming.draw), stock, version .. " naming unsubscribe restores native drawing")
    Naming.dismiss()

    local function party(mode)
      Party.show(game.session.party, nil, { session = game.session, mode = mode or "list" })
      if version == "ruby" or version == "sapphire" then
        Party.handleInput(input("down"))
        T.eq(Party.cursor, 1, version .. " native party rejects input during fade-in")
      end
      for _ = 1, 40 do Party.update(1 / 60) end
    end
    party()
    Party.handleInput(input("a"))
    local nativeActions = capture(Party.draw)
    Party.close()
    out.mode = "change"
    remove = out.install()
    party()
    Party.handleInput(input("a"))
    local actions = capture(Party.draw)
    T.check(has(actions, "MENU PARTY"), version .. " custom party descriptor is drawn")
    T.check(not has(actions, "SUMMARY"), version .. " removed party row is absent from drawing")
    T.eq(Party.actionCursor, 1, version .. " reordered cancel is selected first")
    T.eq(out.partyGame, game, version .. " party callback game")
    T.eq(out.monSpecies, "PIDGEY", version .. " API3 party mon uses canonical species")
    T.neq(out.mon, game.session.party[1], version .. " party mon record is detached")
    T.eq(game.session.party[1].hp, 1, version .. " hook record mutation writes back to native mon")
    Party.handleInput(input("down"))
    Party.handleInput(input("a"))
    T.eq(out.actions, 1, version .. " actual party A executes custom onSelect exactly once")
    T.eq(out.selectedArgs, 2, version .. " party onSelect receives exactly mon and game")
    T.eq(out.selectedGame, game, version .. " party onSelect receives the running game")
    T.eq(out.selectedSpecies, "PIDGEY", version .. " party onSelect receives canonical species")
    T.eq(out.selectedHp, 1, version .. " party onSelect receives the committed hook mutation")
    T.neq(out.selectedMon, game.session.party[1], version .. " party onSelect mon record is detached")
    T.neq(out.selectedMon, out.mon, version .. " party onSelect receives a fresh record")
    T.eq(game.session.party[1].hp, 2, version .. " party onSelect record mutation writes back to native mon")
    game.session.party[1].hp = 20
    Party.close()
    local gridBefore = out.calls["ui.party.grid_navigation"] or 0
    party()
    Party.handleInput(input("right"))
    T.eq(out.calls["ui.party.grid_navigation"] or 0, gridBefore, version .. " field menu never queries battle grid hook")
    Party.close()
    party("battle_switch")
    Party.handleInput(input("right"))
    T.eq(Party.cursor, 3,
      version .. " opted-in battle navigation reaches nearest native right-column slot")
    Party.handleInput(input("down"))
    T.eq(Party.cursor, 4, version .. " opted-in battle navigation follows native two-column geometry")
    T.check((out.calls["ui.party.grid_navigation"] or 0) > gridBefore, version .. " battle input consults grid hook")
    Party.close()
    out.mode = "invalid"
    party("battle_switch")
    T.eq(Party.gridNavigation(), false, version .. " non-boolean grid hook keeps native navigation")
    Party.close()
    party()
    Party.handleInput(input("a"))
    T.same(capture(Party.draw), nativeActions, version .. " invalid submenu mutation preserves native drawing")
    Party.close()
    remove()
    party()
    Party.handleInput(input("a"))
    T.same(capture(Party.draw), nativeActions, version .. " party unsubscribe restores native action menu")
  end)

  exercise(version, "owner rollback and legacy API", function()
    local _, game, loader = setup(version, 3, true)
    T.same(listTrace(game), { 1, 1, 2, 2 }, version .. " failed owner cannot change native input")
    for _, chain in pairs(loader.hooks.chains) do
      for _, entry in ipairs(chain) do T.neq(entry.owner, "z_failure", version .. " rollback removes menu owner") end
    end
    T.sdk.restoreRuntime()
    local out
    out, game = setup(version, 2)
    local stock = listTrace(game)
    local remove = out.install()
    T.same(listTrace(game), { 8, 3, 4, 1 }, version .. " legacy API source changes actual native navigation")
    remove()
    T.same(listTrace(game), stock, version .. " legacy API unsubscribe restores native navigation")
  end)
end

for i = #restore, 1, -1 do restore[i]() end
Version.set(originalVersion)
Versions.select(originalNativeVersion)
Profile.reset()
Kit.resetCaches()
T.finish("unified gen3 menus")
