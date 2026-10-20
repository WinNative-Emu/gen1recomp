package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Loader = require("src.mods.Loader")
local ModRuntime = require("src.mods.Runtime")
local Records = require("src.mods.UnifiedRecords")
local Version = require("src.core.GameVersion")
local Versions = require("src.import.gba.versions")
local Runtime = require("src.core.game3.runtime")
local Profile = require("src.core.game3.profile")
local Dataset = require("src.core.game3.dataset")
local CacheBlob = require("src.import.CacheBlob")
local NativeMenus = require("tests.fixture_data.game3_native_menus")
local Pokemon = require("src.core.game3.pokemon")
local ItemsData = require("src.core.game3.items_data")
local Rng = require("src.core.game3.rng")
local Space = require("src.core.game3.scripting.space")
local State = require("src.core.game3.battle.state")
local Adapter = require("src.core.game3.battle.adapter")
local Battle = require("src.core.game3.battle")
local Ui = require("src.core.game3.battle.ui")
local Healthbox = require("src.core.game3.battle.healthbox")
local Experience = require("src.core.game3.battle.experience")
local ExpSeq = require("src.core.game3.battle.exp_seq")
local Engine = require("src.core.game3.battle.engine")
local HeldItems = require("src.core.game3.battle.held_items")
local Ai = require("src.core.game3.battle.ai")
local AiItems = require("src.core.game3.battle.ai_items")
local Anim = require("src.core.game3.battle.anim")
local PicCoords = require("src.core.game3.battle.pic_coords")
local Link = require("src.core.game3.link")
local LinkBattle = require("src.core.game3.link.battle")
local Font = require("src.ui.game3.frlg_font")
local BattleChrome = require("src.ui.game3.battle_chrome")
local Kit = require("src.ui.game3.rse.scene_kit")
local Choice = require("src.ui.game3.choice")

local originalVersion, originalNativeVersion = Version.get(), Versions.active()
local originalRng = Rng.getState()
local savedRuntime = { ModRuntime.events, ModRuntime.hooks, ModRuntime.errors }
local restore, activeVersion, printed, draws, order = {}, nil, {}, {}, {}
local function fixture(owner, key, value)
  local old = owner[key]
  restore[#restore + 1] = function() owner[key] = old end
  owner[key] = value
end

local function copy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for key, item in pairs(value) do out[key] = copy(item) end
  return out
end

local function provideCache()
  local cache = Dataset.cache()
  local cacheRead, cacheExists = cache.read, cache.exists
  fixture(cache, "read", function(self, path, ...)
    return NativeMenus.bytes(activeVersion, path) or cacheRead(self, path, ...)
  end)
  fixture(cache, "exists", function(self, path, ...)
    return NativeMenus.bytes(activeVersion, path) ~= nil or cacheExists(self, path, ...)
  end)
  local read, loadFile, info = love.filesystem.read, love.filesystem.load, love.filesystem.getInfo
  fixture(love.filesystem, "read", function(path, ...)
    local bytes = NativeMenus.bytes(activeVersion, path)
    return bytes and CacheBlob.encode(path, bytes) or read(path, ...)
  end)
  fixture(love.filesystem, "load", function(path, ...)
    local bytes = NativeMenus.bytes(activeVersion, path)
    if bytes then return (loadstring or load)(bytes, "@" .. path) end
    return loadFile(path, ...)
  end)
  fixture(love.filesystem, "getInfo", function(path, ...)
    local bytes = NativeMenus.bytes(activeVersion, path)
    if bytes then return { type = "file", size = #bytes } end
    return info(path, ...)
  end)
end
provideCache()
local drawFont = Font.draw
fixture(Font, "draw", function(text, x, y, ...)
  printed[#printed + 1] = { text = tostring(text), x = x, y = y }
  order[#order + 1] = "text"
  return drawFont(text, x, y, ...)
end)
fixture(love.graphics, "draw", function(image, ...)
  draws[#draws + 1] = { image = image, args = { ... } }
  order[#order + 1] = "draw"
end)
fixture(love.graphics, "intersectScissor", function(x, y, w, h)
  love.graphics.setScissor(x, y, w, h)
end)

local images = {}
for _, key in ipairs({ "player", "enemy", "panel", "elements", "doublePlayer", "doubleEnemy", "sprite" }) do
  images[key] = love.graphics.newImage("battle-hook-" .. key .. ".png")
end
local function capture(fn)
  printed, draws, order = {}, {}, {}
  fn()
  return { text = copy(printed), draws = draws, order = copy(order) }
end
local function imageCount(frame, image)
  local count = 0
  for _, row in ipairs(frame.draws) do if row.image == image then count = count + 1 end end
  return count
end
local function contains(frame, text)
  for _, row in ipairs(frame.text) do
    if row.text:find(text, 1, true) then return true end
  end
  return false
end
local function input(key)
  return { wasPressed = function(_, edge) return key == edge end,
    isDown = function(_, edge) return key == edge end }
end

local BODY = [[
local mod = ...
local out = mod.exports
out.calls, out.events = {}, {}
out.install = function(name)
  return mod.hooks:wrap(name, function(next, value)
    out.calls[name] = (out.calls[name] or 0) + 1
    out.context = value
    if out.mode == "observe" then return next(value) end
    if name == "battle.exp_award" then
      out.participants, out.alive = value.participants, value.alive
      if out.mode == "bench" then
        value.applyShare(out.bench, out.split, out.announce)
      elseif out.mode == "omitted" then
        value.applyShare(value.alive[1], out.split)
      else
        value.alive[1].hp = out.hp or value.alive[1].hp
        value.applyShare(value.alive[1], out.split, out.announce)
      end
      return
    elseif name == "held_item.trigger" then
      out.effect, out.parameter, out.trigger = value.effect, value.parameter, value.trigger
      if out.mode == "suppress" then return nil end
      return out.effectOverride or value.effect, out.parameterOverride
    elseif name == "battle.enemy_switch_or_item" then
      if out.mode == "claim" then next(value); return true end
      return out.decision
    elseif name == "battle.overlay" then
      out.overlay(value)
      return
    end
    return out.answer
  end)
end
out.listen = function(name)
  return mod.events:on(name, function(event)
    out.events[#out.events + 1] = event
    if out.onEvent then out.onEvent(event) end
  end)
end
]]

local function mon(species)
  return { species = species or 4, nickname = species == 16 and "FOE" or "SCOUT",
    level = 20, growthRate = 0, exp = 8000, hp = 60, maxHp = 60,
    attack = 30, defense = 30, speed = 30, spAtk = 30, spDef = 30,
    moves = { 1, 10, 33, 52 }, pp = { 35, 35, 35, 25 }, maxPp = { 35, 35, 35, 25 },
    item = 0, ability = 0, friendship = 70, personality = 1, otId = 1, otSecretId = 2,
    ivs = { hp = 0, atk = 0, def = 0, spe = 0, spa = 0, spd = 0 },
    evs = { hp = 0, atk = 0, def = 0, spe = 0, spa = 0, spd = 0 } }
end

local function setup(version, double, trainer)
  Battle.reset()
  Choice.reset()
  LinkBattle.reset()
  Link.reset()
  activeVersion = version
  Version.set(version)
  Versions.select(version)
  Profile.reset()
  Kit.resetCaches()
  Font.invalidate()
  local data = T.sdk.gen3Data()
  for key, value in pairs(data.gen3Pokemon) do fixture(Pokemon, key, value) end
  fixture(Pokemon, "_cache", Dataset.cache())
  fixture(Pokemon, "_national", { toNational = { [4] = 4, [16] = 16 } })
  fixture(Pokemon, "_romMoveNames", data.gen3Pokemon._moveNames)
  fixture(Pokemon, "_battleMoves", data.gen3Moves._rom)
  local sprite = { image = images.sprite, w = 64, h = 64 }
  fixture(Pokemon, "_front", { [4] = sprite, [16] = sprite })
  fixture(Pokemon, "_back", { [4] = sprite, [16] = sprite })
  local Moves = require("src.core.game3.battle.moves")
  fixture(Moves, "_rom", data.gen3Moves._rom)
  fixture(Moves, "_romLoaded", true)
  fixture(Moves, "_numByName", { POUND = 1, SCRATCH = 10, TACKLE = 33, EMBER = 52 })
  fixture(Moves, "BY_NUM", { [1] = "POUND", [10] = "SCRATCH", [33] = "TACKLE", [52] = "EMBER" })
  data.gen3Pokemon._speciesMeta[16].evYield = { hp = 1 }
  local itemRows = data.gen3Items._byId
  itemRows[13].effect = { 0, 0, 0, 0, 4, 0, 20 }
  for id, name in pairs({ [179] = "BRIGHTPOWDER", [182] = "EXP SHARE", [183] = "QUICK CLAW",
    [187] = "KINGS ROCK", [196] = "FOCUS BAND", [197] = "LUCKY EGG", [200] = "LEFTOVERS" }) do
    itemRows[id] = { name = name, pocket = "ITEMS", price = 100 }
  end
  fixture(ItemsData, "_byId", itemRows)
  fixture(ItemsData, "_byName", nil)
  local session = { version = version, name = "RED", trainerId = 1, secretId = 2,
    party = { mon(), mon() }, flags = {}, vars = {}, options = {}, gameStats = {} }
  local game = { data = data, session = session, options = session.options }
  session.game = game
  fixture(Runtime, "active", true)
  fixture(Runtime, "session", session)
  fixture(Runtime, "_game", game)
  fixture(Space, "bundle", { text = setmetatable({}, { __index = function(t, key)
    local text = key == "gText_BattleYesNoChoice" and "YES\nNO" or tostring(key)
    local value = { { t = "text", s = text }, { t = "eos" } }
    rawset(t, key, value)
    return value
  end }), events = {}, maps = {}, textTables = {} })
  local files = {
    ["mods/battle_probe/manifest.json"] = [[{"id":"battle_probe","name":"Battle Probe",
      "version":"1.0.0","api":3,"games":["all"],"entry":"main.lua"}]],
    ["mods/battle_probe/main.lua"] = BODY,
  }
  local loader = Loader.new({ fs = T.sdk.memfs(files), generation = 3, version = version, dev = true })
  loader.game = game
  T.eq(loader:load(data), true, version .. " actual Loader accepts API 3")
  T.eq(#loader.errors, 0, version .. " actual Loader loads callback body")
  local st = State.new({ playerParty = session.party, foeParty = { mon(16), mon(16) },
    wild = not trainer, double = double, rng = Rng.compat })
  st.session, st.turn, st.aiFlags = session, 1, 0
  st.enemy.participants = { [1] = true }
  local ad = Adapter.new(st)
  Battle._active, Battle._st, Battle._adapter = true, st, ad
  Battle._phase, Battle._headless, Battle._fade = "command", true, false
  Ui.reset({ headless = true })
  Ui.bindState(st, session)
  Anim.reset({ headless = true, double = double })
  for id = 0, double and 3 or 1 do
    local b = State.battler(st, id)
    Anim.setShown(id, b)
    local p = Anim.present(id)
    p.displayHp, p.displayMaxHp = b.mon.hp, b.mon.maxHp
  end
  local windows, palette = {}, {}
  for i = 1, 15 do windows[i] = { left = 1, top = 14, w = 28, h = 4 } end
  for i = 1, 512 do palette[i] = 0 end
  fixture(BattleChrome, "_manifest", { layout = (version == "ruby" or version == "sapphire")
      and "rs" or version == "emerald" and "rse" or "frlg",
    healthboxPal = palette, windows = { normal = windows }, textboxW = 256, textboxH = 512 })
  for key, image in pairs({ _playerBox = images.player, _enemyBox = images.enemy,
    _textbox = images.panel, _elements = images.elements, _elementsExp = images.elements,
    _doublesPlayerBox = images.doublePlayer, _doublesOpponentBox = images.doubleEnemy }) do
    fixture(BattleChrome, key, image)
  end
  fixture(BattleChrome, "_quads", {})
  fixture(BattleChrome, "_terrains", setmetatable({}, { __index = function() return nil end }))
  rawset(BattleChrome._terrains, require("src.core.game3.battle.bg").sheetKey(),
    { image = images.sprite, postDexImage = images.sprite, w = 256, h = 256 })
  fixture(PicCoords, "active", function() return { front = {}, back = {}, elev = {} } end)
  fixture(BattleChrome, "_doublesTried", true)
  fixture(BattleChrome, "_hpBoldTried", true)
  fixture(BattleChrome, "_hpBold", nil)
  return loader.exports.battle_probe, game, st, ad, loader
end

local function exercise(version, label, fn)
  local ok, err = xpcall(fn, debug.traceback)
  T.check(ok, version .. " " .. label .. ": " .. tostring(err))
  Battle.reset()
  Choice.reset()
  LinkBattle.reset()
  Link.reset()
end

for _, version in ipairs({ "firered", "leafgreen", "ruby", "sapphire", "emerald" }) do
  for _, double in ipairs({ false, true }) do
    exercise(version, "actual HUD and bottom draw " .. tostring(double), function()
      local out, game, st = setup(version, double)
      Ui._headless = false
      Ui.openMenu()
      local native = capture(function() Battle.draw(game) end)
      local playerBox = double and images.doublePlayer or images.player
      T.check(imageCount(native, playerBox) > 0, version .. " real Healthbox draws native player box")
      T.check(imageCount(native, images.panel) > 0, version .. " native bottom panel draws")
      T.check(imageCount(native, images.sprite) > 0, version .. " native battler sprites draw")
      out.answer = false
      local remove = out.install("battle.status_hud_visible")
      local hidden = capture(function() Battle.draw(game) end)
      T.eq(out.context, st, version .. " HUD receives live battle handle")
      T.eq(imageCount(hidden, playerBox), 0, version .. " hidden HUD omits entire healthbox")
      T.eq(imageCount(hidden, images.elements), 0, version .. " hidden HUD omits HP/status/EXP tiles")
      local upperText = 0
      for _, row in ipairs(hidden.text) do if row.y < 112 then upperText = upperText + 1 end end
      T.eq(upperText, 0, version .. " hidden HUD omits nickname, level and HP text")
      T.eq(imageCount(hidden, images.sprite), imageCount(native, images.sprite), version .. " HUD leaves native sprites")
      T.eq(imageCount(hidden, images.panel), imageCount(native, images.panel), version .. " HUD leaves bottom panel")
      remove()
      local restored = capture(function() Battle.draw(game) end)
      T.same(restored.text, native.text, version .. " unsubscribe restores native HUD text")
      T.eq(imageCount(restored, playerBox), imageCount(native, playerBox), version .. " unsubscribe restores boxes")
      remove = out.install("battle.bottom_ui_visible")
      hidden = capture(function() Battle.draw(game) end)
      T.eq(imageCount(hidden, images.panel), 0, version .. " bottom hook suppresses actual panel")
      T.eq(imageCount(hidden, playerBox), imageCount(native, playerBox), version .. " bottom hook preserves healthbox")
      local selected
      Ui.askYesNo(function(answer) selected = answer end)
      Ui.handleInput(input("a"))
      T.eq(selected, true, version .. " hidden bottom retains native modal confirmation")
      remove()
      Ui._mode = "none"
      local direct = capture(function() Healthbox.draw(double and 0 or "player", st.player) end)
      T.check(imageCount(direct, playerBox) > 0, version .. " real Healthbox owner draws independently")
      if not double then
        Ui.markVoiceover("VOICE", { litHealthbox = true })
        Ui._oak, Ui._oakShown = { y = 16 }, "VOICE"
        out.answer = false
        remove = out.install("battle.status_hud_visible")
        local relit = capture(function() Battle.draw(game) end)
        T.eq(imageCount(relit, playerBox), 0, version .. " Oak relighting respects hidden healthbox")
        remove()
      end
    end)
  end

  exercise(version, "native grid and linear move input", function()
    local out, _, st = setup(version)
    Ui._headless, Ui._mode, Ui._moveIndex = false, "moves", 1
    Ui.handleInput(input("down"))
    T.eq(Ui._moveIndex, 3, version .. " no-hook native move grid")
    out.answer = false
    local remove = out.install("battle.move_grid_navigation")
    Ui._moveIndex = 1
    Ui.handleInput(input("down"))
    T.eq(out.context, st, version .. " navigation receives live battle")
    T.eq(Ui._moveIndex, 2, version .. " false selects actual linear picker")
    Ui.handleInput(input("right"))
    T.eq(Ui._moveIndex, 2, version .. " linear picker ignores horizontal input")
    out.answer = true
    Ui._moveIndex = 1
    Ui.handleInput(input("down"))
    T.eq(Ui._moveIndex, 3, version .. " live true selects grid")
    remove()
    Ui._moveIndex = 1
    Ui.handleInput(input("down"))
    T.eq(Ui._moveIndex, 3, version .. " unsubscribe restores grid")
  end)

  exercise(version, "overlay order, caught branch and graphics state", function()
    local out, game, st = setup(version)
    out.overlay = function(battle)
      T.eq(battle, st, version .. " overlay receives live native battle")
      order[#order + 1] = "overlay"
      love.graphics.setColor(0.1, 0.2, 0.3, 0.4)
      love.graphics.setBlendMode("add")
      love.graphics.setShader({ marker = true })
    end
    local remove = out.install("battle.overlay")
    local function checkFrame()
      love.graphics.setBlendMode("alpha")
      love.graphics.setShader()
      local frame = capture(function() Battle.draw(game) end)
      local count = 0
      for _, step in ipairs(frame.order) do if step == "overlay" then count = count + 1 end end
      T.eq(count, 1, version .. " overlay runs once per real battle frame")
      T.eq(frame.order[#frame.order], "overlay", version .. " overlay follows native frame layers")
      T.eq(love.graphics.getBlendMode(), "alpha", version .. " overlay restores blend mode")
      T.eq(love.graphics.getShader(), nil, version .. " overlay restores shader")
      T.same({ love.graphics.getColor() }, { 1, 1, 1, 1 }, version .. " overlay restores color")
    end
    checkFrame()
    Ui._headless = false
    Choice.multi({ "MODAL" }, 0, function() end)
    checkFrame()
    Choice.reset()
    Ui.beginCaughtDexScene({ family = "frlg", sprite = { img = images.sprite, x = 120, y = 64 } })
    checkFrame()
    Ui.clearCaughtDexScene()
    remove()
    local frame = capture(function() Battle.draw(game) end)
    T.eq(frame.order[#frame.order] == "overlay", false, version .. " unsubscribe removes overlay")
  end)

  exercise(version, "whole native EXP distribution and observer parity", function()
    local out, _, st = setup(version)
    st.playerParty[2].item = 182
    local before, seed = copy(st.playerParty), Rng.getState()
    local function award()
      return Experience.awardFoe(st, st.enemy, { getOpts = function(_, pi)
        return { traded = true, luckyEgg = pi == 1 }
      end })
    end
    local stock = award()
    local native, afterRng = copy(st.playerParty), Rng.getState()
    T.eq(#stock, 2, version .. " native distribution pays participant and share holder")
    T.eq(stock[1].result.gained, 175, version .. " participant preserves separate half-pool and boost floors")
    T.eq(stock[2].result.gained, 117, version .. " holder preserves separate half-pool and trade floor")
    for i, raw in ipairs(before) do
      for key in pairs(st.playerParty[i]) do st.playerParty[i][key] = nil end
      for key, value in pairs(copy(raw)) do st.playerParty[i][key] = value end
    end
    Rng.setState(seed)
    out.mode = "observe"
    local remove = out.install("battle.exp_award")
    out.listen("battle.exp_gained")
    local observed = award()
    T.eq(out.calls["battle.exp_award"], 1, version .. " whole award wrapper runs once")
    T.same(st.playerParty, native, version .. " next preserves actual EXP/EV/stats writes")
    T.same(Rng.getState(), afterRng, version .. " observer preserves native RNG")
    T.eq(#observed, #stock, version .. " observer preserves actual payment entries")
    T.eq(#out.events, 2, version .. " event occurs once per actual payment")
    remove()
    for i, raw in ipairs(before) do
      for key in pairs(st.playerParty[i]) do st.playerParty[i][key] = nil end
      for key, value in pairs(copy(raw)) do st.playerParty[i][key] = value end
    end
    Rng.setState(seed)
    award()
    T.same(st.playerParty, native, version .. " unsubscribe restores native award distribution")
  end)

  for _, mode in ipairs({ "bench", "silent", "nil", "omitted" }) do
    exercise(version, "custom EXP helper " .. mode, function()
      local out, game, st = setup(version)
      local raw = mode == "bench" and st.playerParty[2] or st.playerParty[1]
      Pokemon.applyStats(raw)
      raw.hp = raw.maxHp
      raw.exp = Experience.expForLevel(raw.growthRate, 21) - 1
      out.mode, out.split, out.announce, out.hp = mode, 2, false, 40
      if mode == "nil" then out.announce = nil end
      out.bench = Records.mon(raw, 3, game.data, version)
      local beforeExp, beforeFriendship, beforeHp = raw.exp, raw.friendship, raw.hp
      out.install("battle.exp_award")
      out.listen("battle.exp_gained")
      local expCalls = 0
      local remove = ModRuntime.hooks:wrap("exp.gain", function(next, ctx)
        expCalls = expCalls + 1
        return next(ctx)
      end)
      local awards = Experience.awardFoe(st, st.enemy)
      T.eq(out.participants, 1, version .. " Gen1 participants is a count")
      T.eq(#out.alive, 1, version .. " alive contains actual living participants only")
      T.eq(out.alive[1].species, "CHARMANDER", version .. " helper gets canonical participant")
      T.eq(#awards, 1, version .. " replacement performs exactly one custom payment")
      T.eq(awards[1].mon, raw, version .. " Record helper resolves native party identity")
      T.eq(raw.exp, beforeExp + 78, version .. " split is a divisor, including for bench")
      T.eq(raw.level, 21, version .. " helper commits actual level-up")
      T.same(raw.evs, Pokemon.evYield(16), version .. " helper awards actual species EV yield")
      T.check(raw.friendship > beforeFriendship, version .. " helper applies native level friendship")
      T.check(raw.hp > ((mode == "silent" or mode == "nil") and 40 or beforeHp), version .. " native level HP survives boundary restore")
      T.eq(expCalls, 1, version .. " exp.gain runs once per custom payment")
      T.eq(#out.events, 1, version .. " battle.exp_gained runs once per custom payment")
      if mode ~= "omitted" then T.eq(awards[1].announce, false, version .. " explicit false suppresses gained line") end
      local messages = {}
      ExpSeq.begin(awards, function(text) messages[#messages + 1] = text end, nil, { headless = true })
      for _ = 1, 1000 do if not ExpSeq.busy() then break end; ExpSeq.update() end
      T.eq(ExpSeq.busy(), false, version .. " actual EXP sequence completes")
      local gainedLine = false
      for _, text in ipairs(messages) do
        if text:find("STRINGID_PKMNGAINEDEXP", 1, true) then gainedLine = true end
      end
      T.eq(gainedLine, mode == "omitted", version .. " announcement controls only individual gained line")
      T.eq(raw.level, 21, version .. " presentation creates no extra level-up")
      remove()
    end)
  end

  for _, visible in ipairs({ false, true }) do
    exercise(version, "actual catch handler EXP once " .. tostring(visible), function()
      local out, _, st = setup(version)
      local before = st.playerParty[1].exp
      local catchResult = { success = true, mon = st.enemy.mon, location = "party" }
      out.answer = true
      out.install("battle.catch_exp")
      out.listen("battle.exp_gained")
      local fainted, ended = 0, 0
      ModRuntime.events:on("battle.pokemon_fainted", function() fainted = fainted + 1 end)
      ModRuntime.events:on("battle.ended", function() ended = ended + 1 end)
      Battle._headless, Ui._headless = not visible, not visible
      Battle.startPostCatchFlow(catchResult)
      Battle.startPostCatchFlow(catchResult)
      T.eq(st.playerParty[1].exp, before + 157, version .. " successful catch uses native foe award")
      T.eq(out.calls["battle.catch_exp"], 1, version .. " reentry cannot repeat catch permission")
      T.eq(#out.events, 1, version .. " actual catch payment occurs exactly once")
      T.eq(fainted, 0, version .. " catch does not invent faint notification")
      T.eq(ended, 0, version .. " award completes before battle completion")
      if visible then
        T.eq(Battle._phase, "awarding", version .. " visible catch enters native EXP sequence")
        T.eq(ExpSeq.busy(), true, version .. " visible catch owns actual EXP presentation")
      else
        T.eq(Battle._phase, "ending", version .. " headless catch reaches native ending")
      end
    end)
  end

  exercise(version, "catch defaults, failure and native guards", function()
    for _, guard in ipairs({ "none", "declined", "failure", "link", "oldManTutorial", "pokedude", "noExp" }) do
      local out, _, st = setup(version)
      local before = st.playerParty[1].exp
      if guard ~= "none" then
        out.answer = guard ~= "declined"
        out.install("battle.catch_exp")
      end
      if guard == "noExp" then
        for name in pairs(require("src.core.game3.battle.profile").of(st).rules.noExp) do
          st[name] = true
          break
        end
      elseif guard ~= "none" and guard ~= "failure" and guard ~= "declined" then st[guard] = true end
      Battle.startPostCatchFlow({ success = guard ~= "failure", mon = st.enemy.mon, location = "party" })
      T.eq(st.playerParty[1].exp, before, version .. " catch " .. guard .. " preserves native EXP")
      T.eq(out.calls["battle.catch_exp"], guard == "declined" and 1 or nil,
        version .. " catch " .. guard .. " respects native permission boundary")
    end
  end)

  exercise(version, "held effect substitution, suppression, units and RNG", function()
    local out, _, st, ad = setup(version)
    local b = st.player
    for _, row in ipairs({ { 183, "HELD_QUICK_CLAW", 51, "priority" },
      { 179, "HELD_BRIGHTPOWDER", 25, "accuracy" },
      { 196, "HELD_FOCUS_BAND", 25, "endure" }, { 187, "HELD_FLINCH", 25, "flinch" } }) do
      b.item, b.mon.item = row[1], row[1]
      local seed = Rng.getState()
      local stock = { HeldItems.of(b, row[4], st) }
      out.mode = "observe"
      local remove = out.install("held_item.trigger")
      T.same({ HeldItems.of(b, row[4], st) }, stock, version .. " held observer keeps exact native units")
      T.eq(out.context.effect, row[2], version .. " first Gen2 HELD name")
      T.eq(out.context.parameter, row[3], version .. " first Gen2 chance byte units")
      T.eq(out.context.trigger, row[4], version .. " actual query trigger")
      T.eq(out.context.battle, st, version .. " actual battle context")
      T.eq(out.context.mon.species, "CHARMANDER", version .. " canonical held mon")
      T.eq(out.context.def.heldParameter, row[3], version .. " held definition shares byte units")
      T.same(Rng.getState(), seed, version .. " held query/observer consumes no RNG")
      remove()
      T.same({ HeldItems.of(b, row[4], st) }, stock, version .. " held unsubscribe restores exact tuple")
    end
    b.item, b.mon.item, st.randomTurnNumber = 183, 183, 0
    local nativeSpeed = Engine.speedOf(b, st, ad)
    T.eq(nativeSpeed, 0xFFFFFFFF, version .. " actual Quick Claw affects native speed ordering")
    out.mode = "suppress"
    local remove = out.install("held_item.trigger")
    T.check(Engine.speedOf(b, st, ad) < nativeSpeed, version .. " suppression changes native priority")
    T.eq(out.trigger, "priority", version .. " engine supplies actual priority trigger")
    remove()
    out.mode, out.effectOverride, out.parameterOverride = "replace", "HELD_LEFTOVERS", 0
    b.mon.hp = 20
    remove = out.install("held_item.trigger")
    T.eq(HeldItems.normal(ad, b, false), true, version .. " substituted Leftovers executes native effect")
    T.eq(b.mon.hp, 23, version .. " substituted Leftovers heals actual HP")
    T.eq(b.item, 183, version .. " substitution preserves held item metadata")
    T.eq(out.trigger, "residual", version .. " native residual supplies trigger")
    remove()
    b.item, b.mon.item = 196, 196
    local seed = Rng.getState()
    local nativeBand = HeldItems.rollFocusBand(ad, b)
    local nativeRng = Rng.getState()
    b.expFocusBanded = nil
    Rng.setState(seed)
    out.mode = "observe"
    remove = out.install("held_item.trigger")
    T.eq(HeldItems.rollFocusBand(ad, b), nativeBand, version .. " observer preserves actual Focus Band roll")
    T.same(Rng.getState(), nativeRng, version .. " observer preserves native chance RNG sequence")
    remove()
    out.mode, out.effectOverride, out.parameterOverride = "replace", "HELD_FOCUS_BAND", 256
    remove = out.install("held_item.trigger")
    T.eq(HeldItems.rollFocusBand(ad, b), true, version .. " byte 256 guarantees actual native survival roll")
    out.parameterOverride = 0
    T.eq(HeldItems.rollFocusBand(ad, b), false, version .. " byte zero disables actual survival roll")
    out.parameterOverride = "invalid"
    T.eq(select(2, HeldItems.of(b, "endure", st)), 10, version .. " invalid parameter retains native percentage")
    out.effectOverride = 7
    T.eq(HeldItems.of(b, "endure", st), 0, version .. " non-string effect disables actual query")
    remove()
  end)

  exercise(version, "actual enemy item and switch decisions", function()
    local out, _, st, ad = setup(version, false, true)
    st.trainerItems, st.foeParty[2].hp = { 13 }, 0
    st.enemy.mon.hp = 1
    local seed = Rng.getState()
    local stock = Ai.chooseAction(st, 1, { adapter = ad, aiFlags = 0 })
    local nativeRng, nativeHistory = Rng.getState(), copy(AiItems.history(st))
    T.eq(stock.kind, "item", version .. " native trainer selects real stocked Potion")
    st._aiHistory = nil
    Rng.setState(seed)
    out.mode = "claim"
    local remove = out.install("battle.enemy_switch_or_item")
    local chosen = Ai.chooseAction(st, 1, { adapter = ad, aiFlags = 0 })
    T.eq(out.calls["battle.enemy_switch_or_item"], 1, version .. " native decision invokes inherited hook")
    T.same(chosen, stock, version .. " next plus true retains the native item action")
    T.same(AiItems.history(st), nativeHistory, version .. " next consumes stock exactly once")
    T.same(Rng.getState(), nativeRng, version .. " next retains native decision RNG")
    T.eq(Engine.performEnemyItem(st, ad, chosen), true, version .. " selected action executes native item handler")
    T.eq(st.enemy.mon.hp, 21, version .. " selected Potion changes actual enemy HP")
    remove()
    st._aiHistory, st.enemy.mon.hp = nil, 1
    Rng.setState(seed)
    T.same(Ai.chooseAction(st, 1, { adapter = ad, aiFlags = 0 }), stock,
      version .. " unsubscribe restores native trainer decision")
    st._aiHistory, st.enemy.mon.hp = nil, 1
    out.mode, out.decision = "override", { kind = "item", item = "POTION" }
    remove = out.install("battle.enemy_switch_or_item")
    chosen = Ai.chooseAction(st, 1, { adapter = ad, aiFlags = 0 })
    T.eq(chosen.kind, "item", version .. " public item ID selects executable native action")
    T.eq(chosen.item, 13, version .. " public Potion converts to native ID")
    T.eq(AiItems.history(st).items[1], 0, version .. " explicit choice consumes actual stock")
    remove()
    st.trainerItems, st._aiHistory, st.foeParty[2].hp = {}, nil, 60
    st.enemy.mon.hp = 60
    out.decision = { kind = "switch", index = 2 }
    remove = out.install("battle.enemy_switch_or_item")
    chosen = Ai.chooseAction(st, 1, { adapter = ad, aiFlags = 0 })
    T.eq(chosen.kind, "switch", version .. " one-based party request selects actual switch")
    T.eq(chosen.slot, 2, version .. " native switch slot is requested party member")
    Engine.performSwitch(st, ad, 1, chosen.slot)
    T.eq(State.battler(st, 1).partyIndex, 2, version .. " selected switch changes actual battler")
    remove()
    for _, invalid in ipairs({ { kind = "switch", index = 2 }, { kind = "switch", index = 9 },
      { kind = "item", item = "POTION" }, { kind = "item", item = "NO_SUCH_ITEM" }, false }) do
      out.decision = invalid
      remove = out.install("battle.enemy_switch_or_item")
      chosen = Ai.chooseAction(st, 1, { adapter = ad, aiFlags = 0 })
      T.eq(chosen.kind, "move", version .. " invalid/unstocked request falls back to actual move")
      remove()
    end
  end)

  exercise(version, "native init failure releases battle state", function()
    local _, game = setup(version)
    local BattleBridge = require("src.core.game3.battle_bridge")
    Battle.reset()
    local failure
    fixture(Battle, "start", function()
      Battle._active, Battle._st = true, {}
      error("native init exploded")
    end)
    local called, reason = pcall(BattleBridge.startWild, nil, game, { species = 16, level = 5, item = 0 },
      { headless = true, failed = function(why) failure = why end })
    T.eq(called, false, version .. " failed native start propagates with no mod")
    T.check(tostring(reason):find("native init exploded", 1, true) ~= nil, version .. " failure reason preserved")
    T.eq(Battle._active, false, version .. " failed start clears active battle")
    T.eq(Battle._st, nil, version .. " failed start clears battle state")
    T.eq(failure, nil, version .. " no failure callback without a mod hook")
    T.eq(BattleBridge._finish, nil, version .. " failed start clears pending finish")
  end)

  exercise(version, "link completion copies and once guard", function()
    local out, _, st, ad = setup(version)
    st.link = true
    ad:applyHpLoss(st.player, 7)
    ad:applyHpLoss(st.enemy, 60)
    LinkBattle._started, LinkBattle._offField, LinkBattle.state = true, true, "battle"
    LinkBattle.peer, LinkBattle.seat = { name = "BLUE", trainerId = 9 }, 0
    local seed, originalParty = Rng.getState(), copy(st.session.party)
    out.listen("link.battle_ended")
    out.onEvent = function() LinkBattle.finish("win") end
    T.eq(LinkBattle.finish("win"), true, version .. " native link finish completes")
    T.eq(LinkBattle.finish("win"), false, version .. " duplicate finish is refused")
    T.eq(#out.events, 1, version .. " reentrant and duplicate finish notify once")
    local event = out.events[1]
    T.eq(event.result, "win", version .. " Gen1 link result")
    T.eq(event.role, "host", version .. " Gen1 link host role")
    T.eq(event.peerName, "BLUE", version .. " Gen1 peer name")
    T.eq(event.myParty[1].species, "CHARMANDER", version .. " own result record canonical")
    T.eq(event.myParty[1].hp, 53, version .. " payload captures actual battle HP changes")
    T.eq(event.theirParty[1].species, "PIDGEY", version .. " peer result record canonical")
    T.eq(event.theirParty[1].hp, 0, version .. " payload captures actual peer faint")
    event.myParty[1].hp, event.theirParty[1].native.hp = 1, 50
    T.eq(st.player.mon.hp, 53, version .. " notification cannot mutate live player")
    T.eq(st.enemy.mon.hp, 0, version .. " native extension cannot mutate live peer")
    T.same(st.session.party, originalParty, version .. " off-field finish preserves session party")
    T.same(Rng.getState(), seed, version .. " link notification consumes no RNG")
    T.eq(LinkBattle.state, "done", version .. " native finish reaches completed state")
    LinkBattle.freshBattle()
    LinkBattle._started, LinkBattle._offField = true, true
    LinkBattle.finish("lose")
    T.eq(#out.events, 2, version .. " future genuine battle may notify again")
  end)

  exercise(version, "actual divergent hash desync payload", function()
    local out, _, st, ad = setup(version)
    st.link = true
    LinkBattle.state, LinkBattle._started = "battle", true
    LinkBattle._offField = true
    local localParts = LinkBattle.hashParts(st)
    ad:applyHpLoss(st.player, 1)
    local remoteParts = LinkBattle.hashParts(st)
    local component
    for _, key in ipairs(LinkBattle.HASH_PARTS) do
      if localParts[key] ~= remoteParts[key] then component = key; break end
    end
    T.check(component ~= nil, version .. " actual HP change alters native hash component")
    LinkBattle._myParts[1] = localParts
    LinkBattle._myHashes[1] = LinkBattle.hashValue(localParts)
    LinkBattle._peerHashes[1] = { [1] = { parts = remoteParts, value = LinkBattle.hashValue(remoteParts) } }
    out.listen("link.desync")
    LinkBattle.checkHashes()
    T.eq(#out.events, 1, version .. " native hash comparison emits actual divergence")
    local event = out.events[1]
    T.eq(event.turn, 1, version .. " Gen1 divergence turn")
    T.eq(event.component, component, version .. " Gen1 divergent component")
    T.eq(event.localHash, localParts[component], version .. " actual local component hash")
    T.eq(event.remoteHash, remoteParts[component], version .. " actual remote component hash")
    T.eq(event.fatal, true, version .. " Gen1 fatal flag")
    T.eq(st.result, "draw", version .. " actual divergence settles native battle as draw")
    LinkBattle.checkHashes()
    T.eq(#out.events, 1, version .. " repeated divergence does not notify twice")
  end)
end

exercise("firered", "no-mod start failure keeps the native completion flow", function()
  local BattleBridge = require("src.core.game3.battle_bridge")
  local _, game = setup("firered")
  local results = {}
  local real = Battle.start
  Battle.start = function() return false, "refused" end
  local started, why = BattleBridge.start(nil, game, { species = 16, level = 5 },
    { headless = true, wild = true, done = function(r) results[#results + 1] = r end })
  T.eq(started, nil, "failed start returns nil")
  T.eq(why, "refused", "failed start returns the reason")
  T.same(results, { "win" }, "failed start completes the caller with win")
  Battle.start = function() error("boom") end
  local ok = pcall(BattleBridge.start, nil, game, { species = 16, level = 5 },
    { headless = true, wild = true, done = function(r) results[#results + 1] = r end })
  Battle.start = real
  T.eq(ok, false, "an error inside Battle.start propagates with no mod")
  T.eq(#results, 1, "a propagated error does not complete the caller")
end)

exercise("firered", "caught marker is decided once per healthbox", function()
  local _, game, st = setup("firered")
  Ui._headless = false
  Ui.openMenu()
  local calls = 0
  local real = Healthbox.shouldShowCaughtMarker
  Healthbox.shouldShowCaughtMarker = function() calls = calls + 1; return calls > 1 end
  for _ = 1, 3 do capture(function() Battle.draw(game) end) end
  Healthbox.shouldShowCaughtMarker = real
  T.eq(calls, 1, "marker evaluated once across frames")
  T.check(st.enemy._caughtIcon ~= nil, "latch stored on the battler")
end)

Battle.reset()
Choice.reset()
LinkBattle.reset()
Link.reset()
for i = #restore, 1, -1 do restore[i]() end
Kit.resetCaches()
Font.invalidate()
Version.set(originalVersion)
Versions.select(originalNativeVersion)
Profile.reset()
Rng.setState(originalRng)
ModRuntime.install(savedRuntime[1], savedRuntime[2], savedRuntime[3])
T.finish("unified_gen3_battle_hooks")
