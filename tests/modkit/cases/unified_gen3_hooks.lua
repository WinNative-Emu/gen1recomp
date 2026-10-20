package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.harness").suite("unified gen3 hooks")
local ModRuntime = require("src.mods.Runtime")
local Hooks = require("src.mods.Hooks")
local Events = require("src.mods.Events")
local Version = require("src.core.GameVersion")
local Runtime = require("src.core.game3.runtime")
local Pokemon = require("src.core.game3.pokemon")
local Space = require("src.core.game3.scripting.space")
local Trainers = require("src.core.game3.scripting.trainers")
local Vm = require("src.core.game3.scripting.vm")
local ScriptAdapters = require("src.core.game3.scripting.adapters")
local TrainerSight = require("src.core.game3.trainer_sight")
local FieldEffects = require("src.core.game3.field_effects")
local Field = require("src.core.game3.field")
local Objects = require("src.core.game3.objects")
local Map = require("src.core.game3.map")
local State = require("src.core.game3.battle.state")
local Adapter = require("src.core.game3.battle.adapter")
local Residuals = require("src.core.game3.battle.residuals")
local Engine = require("src.core.game3.battle.engine")
local Battle = require("src.core.game3.battle")
local Bridge = require("src.core.game3.battle_bridge")
local Healthbox = require("src.core.game3.battle.healthbox")
local Anim = require("src.core.game3.battle.anim")
local Ui = require("src.core.game3.battle.ui")
local Input = require("src.core.Input")
local Dex = require("src.core.game3.dex")
local Font = require("src.ui.game3.frlg_font")
local PalText = require("src.ui.game3.rse.pal_text")
local Kit = require("src.ui.game3.rse.scene_kit")
local PartyMenu = require("src.ui.game3.party_menu")
local PartyChrome = require("src.ui.game3.party_chrome")
local SummaryMenu = require("src.ui.game3.summary_menu")
local SummaryChrome = require("src.ui.game3.summary_chrome")
local RsSummary = require("src.ui.game3.rs.summary_menu")
local EmSummary = require("src.ui.game3.rse.summary_menu")
local RsParty = require("src.ui.game3.rs.party_chrome")
local BattleChrome = require("src.ui.game3.battle_chrome")

local savedRuntime = { ModRuntime.events, ModRuntime.hooks, ModRuntime.errors }
local restore = {}
local printed, glyphs, rectangles, draws = {}, {}, {}, {}
local function fixture(owner, key, value)
  local old = owner[key]
  restore[#restore + 1] = function() owner[key] = old end
  owner[key] = value
end

fixture(Font, "draw", function(text, x, y)
  printed[#printed + 1] = { text = tostring(text), x = x, y = y }
end)
fixture(Font, "drawGlyph", function(code, x, y)
  glyphs[#glyphs + 1] = { code = code, x = x, y = y }
end)
fixture(Font, "measure", function(text) return #tostring(text) * 6 end)
fixture(Font, "advance", function() return 6 end)
fixture(PalText, "draw", function(text, x, y)
  printed[#printed + 1] = { text = tostring(text), x = x, y = y }
end)
local image = love.graphics.newImage("unified-gen3-hooks.png")
fixture(Kit, "image", function() return image end)
local loadLua = Kit.loadLua
fixture(Kit, "loadLua", function(path, ...)
  if path:match("/pokemon/hoenn%.lua$") then
    return { toHoenn = { [1] = 1, [129] = 52 } }
  end
  return loadLua(path, ...)
end)
fixture(love.graphics, "intersectScissor", function(x, y, w, h)
  love.graphics.setScissor(x, y, w, h)
end)
fixture(love.graphics, "rectangle", function(mode, x, y, w, h)
  rectangles[#rectangles + 1] = { mode = mode, x = x, y = y, w = w, h = h }
end)
fixture(love.graphics, "draw", function(img, quad, x, y)
  draws[#draws + 1] = { image = img, quad = quad, x = x, y = y }
end)
local originalRead = love.filesystem.read
fixture(love.filesystem, "read", function(path, ...)
  if path == "unified-gen3-order.4bpp" then return string.rep("\17", 4096) end
  return originalRead(path, ...)
end)

local palette = {}
for i = 1, 512 do palette[i] = 0 end
local partyPalette = {}
for i = 0, 255 do partyPalette[i] = { 0, 0, 0 } end
fixture(PartyChrome, "_manifest", { palBuffer = partyPalette })
fixture(SummaryChrome, "_manifest", { coords = {} })
fixture(BattleChrome, "_manifest", { healthboxPal = palette })
fixture(FieldEffects, "_anims", {})
fixture(Trainers, "_pack", { classNames = { [0] = "TRAINER", [1] = "SCOUT" }, trainers = {
  [0] = { class = 0, name = "TRAINER", pic = 0, party = { { species = 129, level = 42, moves = { 150 } } } },
  [1] = { class = 1, name = "SCOUT", pic = 0, party = { { species = 129, level = 42, moves = { 150 } } } },
} })

local cache = require("src.core.game3.dataset").cache()
local movePack = [[return { moves = {
  [150] = { effect = 85, power = 0, type = 0, accuracy = 100, pp = 40,
    secondaryEffectChance = 0, target = 16, priority = 0, flags = 0 }
} }]]
local cacheRead = cache.read
fixture(cache, "read", function(self, path, ...)
  if path:match("/battle_moves%.lua$") then return movePack end
  return cacheRead(self, path, ...)
end)

local function native(owner, wanted)
  local visited = {}
  local function search(fn)
    if type(fn) ~= "function" or visited[fn] then return nil end
    visited[fn] = true
    local children = {}
    for i = 1, 100 do
      local name, value = debug.getupvalue(fn, i)
      if not name then break end
      if name == wanted then return value end
      if type(value) == "function" then children[#children + 1] = value end
    end
    for _, child in ipairs(children) do
      local found = search(child)
      if found then return found end
    end
  end
  for _, fn in pairs(owner) do
    local found = search(fn)
    if found then return found end
  end
  error("native draw routine missing: " .. wanted)
end

local function capture(fn)
  printed, glyphs, rectangles, draws = {}, {}, {}, {}
  fn()
  return printed, glyphs, rectangles, draws
end

local function has(rows, text)
  for _, row in ipairs(rows) do
    if row.text:find(text, 1, true) then return true end
  end
  return false
end

local function mon(species)
  return { species = species or 1, nickname = "SCOUT", name = "SCOUT", level = 42,
    hp = 160, maxHp = 160, attack = 60, defense = 60, spAtk = 60, spDef = 60,
    speed = 60, moves = { 150 }, pp = { 40 }, maxPp = { 40 }, ability = 0,
    personality = 1, gender = "U", friendship = 70, growthRate = 0,
    exp = 74088, item = 0, otId = 1, otSecretId = 2 }
end

local function setup(version, double)
  Battle.reset()
  Bridge.reset()
  Version.set(version)
  require("src.import.gba.versions").select(version)
  ModRuntime.install(Events.new(), Hooks.new(), {})
  Pokemon._names = { [1] = "SCOUT", [129] = "FOE" }
  Pokemon._types = { [1] = { 0, 0 }, [129] = { 11, 11 } }
  Pokemon._stats = {}
  Pokemon._abilities = { [1] = { 0, 0 }, [129] = { 0, 0 } }
  Pokemon._speciesMeta = { [1] = { genderRatio = 255, growthRate = 0 },
    [129] = { genderRatio = 255, growthRate = 0 } }
  Pokemon._national = { toNational = { [1] = 1, [129] = 129 } }
  Pokemon._moveNames, Pokemon._romMoveNames = { [150] = "SPLASH" }, { [150] = "SPLASH" }
  Pokemon._battleMoves = { [150] = { pp = 40, type = 0, power = 0, effect = 85 } }
  Pokemon._learnsets, Pokemon._evolutions = {}, {}
  Pokemon._front, Pokemon._back = {}, {}
  Pokemon._icons = { [1] = { image = image, w = 32, h = 32, quads = { [0] = {} } } }
  local labels = { gText_Lv = "Lv", gOtherText_Lv = "Lv", gText_LevelSymbol = "Lv" }
  Space.bundle = { text = setmetatable({}, { __index = function(t, key)
    local value = labels[key] or key
    local ir = { { t = "text", s = value, v = value, text = value } }
    rawset(t, key, ir)
    return ir
  end }), events = {}, maps = {} }
  Space.store, Space.vm = { flags = {}, vars = {} }, nil
  local input = setmetatable({}, { __index = Input })
  input:init()
  local session = { version = version, party = { mon() }, name = "RED",
    trainerId = 1, secretId = 2, flags = Space.store.flags, vars = Space.store.vars,
    dex = Dex.new(), map = nil, money = 1000, options = {} }
  if double then session.party[2] = mon() end
  local game = { session = session, save = {}, input = input, data = {} }
  session.game = game
  Runtime.active, Runtime.session, Runtime._game = true, session, game
  Map.current = nil
  Field._session, Field._game, Field.running, Field._locks = session, game, false, {}
  local foes = { mon(129) }
  if double then foes[2] = mon(129) end
  local st = State.new({ playerParty = session.party, foeParty = foes,
    wild = not double, double = double, rng = function(lo) return lo or 0 end })
  st.session, st.turn = session, 1
  local ad = Adapter.new(st)
  Ui.reset({ headless = true })
  Ui.bindState(st, session)
  Anim.reset({ headless = true, double = double })
  return game, session, st, ad
end

local function exercise(version, label, fn)
  local ok, err = pcall(fn)
  T.check(ok, version .. " " .. label .. " completes: " .. tostring(err))
  Battle.reset()
  Bridge.reset()
  Runtime.drainDeferred()
  PartyMenu.open, SummaryMenu.open, RsSummary.open = false, false, false
  Field.running = false
end

local function decision(version)
  local game, session, st, ad = setup(version)
  Battle._active, Battle._st, Battle._adapter = true, st, ad
  Battle._phase, Battle._auto, Battle._headless = "command", false, false
  Battle._fade = false
  Ui._headless = false
  Ui.openMenu()
  for id = 0, 1 do
    local b, p = State.battler(st, id), Anim.present(id)
    Anim.setShown(id, b)
    p.displayHp, p.displayMaxHp = b.mon.hp, b.mon.maxHp
    p.displayStatus = b.status or b.mon.status or b.mon.status1
  end
  return game, session, st, ad
end

local function trainer(version)
  local game, session = setup(version)
  Field.running = true
  local foe = mon(129)
  foe.trainerId, foe.trainerClass = 1, 1
  foe.party = { mon(129) }
  local done = 0
  local opts = { headless = true, autoFight = false, fade = false, cache = cache,
    song = 1, mapBehavior = 0, noWhiteout = true,
    done = function() done = done + 1 end }
  return game, session, foe, opts, function() return done end
end

local function assertLevelCycle(version, game, monData, where, draw, marker, tiledLabel)
  local stock, _, _, stockDraws = capture(draw)
  T.check(has(stock, marker), version .. " " .. where .. " native label and digits print")
  local calls = 0
  local unsubscribe = ModRuntime.hooks:wrap("pokemon.level_visible", function(_, m, ctx)
    calls = calls + 1
    T.eq(m, monData, version .. " " .. where .. " receives actual mon")
    T.eq(ctx.where, where, version .. " level surface")
    T.eq(ctx.game, game, version .. " level receives current game")
    return false
  end)
  local hidden, _, _, hiddenDraws = capture(draw)
  T.check(calls > 0, version .. " " .. where .. " actual draw invokes wrapper")
  T.check(not has(hidden, marker) and not has(hidden, "Lv") and not has(hidden, "{LV}"),
    version .. " " .. where .. " hides label and digits together")
  if tiledLabel then
    T.eq(#hiddenDraws, #stockDraws - 1, version .. " party hides the native tiled level label")
  end
  unsubscribe()
  local restored, _, _, restoredDraws = capture(draw)
  T.same(restored, stock, version .. " " .. where .. " unsubscribe restores native text")
  if tiledLabel then
    T.same(restoredDraws, stockDraws, version .. " party unsubscribe restores the native tiled label")
  end
end

for _, version in ipairs({ "firered", "leafgreen", "ruby", "sapphire", "emerald" }) do
  exercise(version, "trainer defer and once", function()
    local game, session, foe, opts, done = trainer(version)
    local continuation, calls, started = nil, 0, 0
    ModRuntime.events:on("battle.started", function() started = started + 1 end)
    local unsubscribe = ModRuntime.hooks:wrap("trainer.before_battle", function(_, g, ctx, resume)
      calls, continuation = calls + 1, resume
      T.eq(g, game, version .. " trainer receives game")
      T.eq(ctx.trainerClass, 1, version .. " trainer class identity")
      T.eq(ctx.partyIndex, 1, version .. " inherited trainer party identity")
      return true
    end)
    T.eq(Bridge.start(nil, game, foe, opts), true, version .. " deferred start owns request")
    T.eq(Battle.isActive(), false, version .. " defer constructs no battle")
    T.eq(done(), 0, version .. " defer cannot advance caller")
    T.eq(started, 0, version .. " defer emits no start")
    T.eq(Field.isLocked(), true, version .. " deferred engagement owns field lock")
    Bridge.start(nil, game, foe, opts)
    T.eq(calls, 1, version .. " same engagement is intercepted once")
    T.eq(continuation(), true, version .. " continuation starts actual battle")
    T.eq(Battle.isActive(), true, version .. " native battle is active")
    T.eq(Battle.getState().session, session, version .. " native battle keeps session")
    T.eq(continuation(), false, version .. " continuation cannot start twice")
    T.eq(started, 1, version .. " native start event exactly once")
    Bridge.finishPending("run")
    Bridge.finishPending("run")
    T.eq(done(), 1, version .. " caller completion exactly once")
    unsubscribe()
    Battle.reset()
    T.eq(Bridge.start(nil, game, foe, opts), true, version .. " unsubscribe starts immediately")
    T.eq(Battle.isActive(), true, version .. " no-hook native entry remains immediate")
  end)

  for _, mode in ipairs({ "false", "error" }) do
    exercise(version, "trainer " .. mode .. " fallthrough", function()
      local game, _, foe, opts, done = trainer(version)
      local calls = 0
      ModRuntime.hooks:wrap("trainer.before_battle", function()
        calls = calls + 1
        if mode == "error" then error("trainer callback probe") end
        return false
      end)
      T.eq(Bridge.start(nil, game, foe, opts), true, version .. " observational wrapper falls through")
      T.eq(Battle.isActive(), true, version .. " fallback starts native battle")
      T.eq(calls, 1, version .. " fallback calls wrapper once")
      Bridge.finishPending("run")
      T.eq(done(), 1, version .. " fallback completes caller once")
    end)
  end

  exercise(version, "trainer cancel", function()
    local game, session, foe, opts, done = trainer(version)
    local continuation, cancelled = nil, 0
    opts.cancel = function(reason)
      cancelled = cancelled + 1
      T.eq(reason, "declined", version .. " private cancellation preserves reason")
    end
    ModRuntime.hooks:wrap("trainer.before_battle", function(_, _, _, resume)
      continuation = resume
      return true
    end)
    Bridge.start(nil, game, foe, opts)
    T.eq(continuation({ cancel = true, reason = "declined" }), true, version .. " explicit cancel is accepted")
    T.eq(Field.isLocked(), false, version .. " cancel releases engagement lock")
    T.eq(Battle.isActive(), false, version .. " cancel starts no battle")
    T.eq(Bridge._trainerPending, nil, version .. " cancel clears pending request")
    T.eq(done(), 0, version .. " cancel reports no VM battle success")
    T.eq(session.battleOutcome, nil, version .. " cancel invents no outcome")
    T.same(session.flags, {}, version .. " cancel awards no trainer flags")
    T.eq(continuation(), false, version .. " cancelled continuation stays spent")
    Bridge.finishPending("win")
    Runtime.drainDeferred()
    T.eq(cancelled, 1, version .. " private cancellation runs once")
    T.eq(done(), 0, version .. " late finish cannot fabricate cancellation success")
  end)

  exercise(version, "trainer retained continuation after individual unsubscribe", function()
    local game, _, foe, opts, done = trainer(version)
    local continuation
    local unsubscribe = ModRuntime.hooks:wrap("trainer.before_battle", function(_, _, _, resume)
      continuation = resume
      return true
    end, 0, "trainer-probe")
    Bridge.start(nil, game, foe, opts)
    unsubscribe()
    Runtime.drainDeferred()
    Field.update(0)
    T.check(Bridge._trainerPending ~= nil, version .. " individual unsubscribe retains pending request")
    T.eq(Field.isLocked(), true, version .. " retained continuation keeps engagement locked")
    T.eq(continuation(), true, version .. " unsubscribed callback may still resume")
    T.eq(Battle.isActive(), true, version .. " retained continuation starts native battle")
    ModRuntime.hooks:removeOwner("trainer-probe")
    Runtime.drainDeferred()
    T.eq(Battle.isActive(), true, version .. " owner removal cannot cancel a started battle")
    Bridge.finishPending("run")
    Bridge.finishPending("run")
    T.eq(done(), 1, version .. " retained continuation completes once")
  end)

  exercise(version, "trainer cancellation without private handler", function()
    local game, session, foe, opts, done = trainer(version)
    local continuation
    ModRuntime.hooks:wrap("trainer.before_battle", function(_, _, _, resume)
      continuation = resume
      return true
    end)
    Field.lock("other-mod")
    Bridge.start(nil, game, foe, opts)
    T.eq(continuation({ cancel = true }), true, version .. " handlerless cancellation is accepted")
    Runtime.drainDeferred()
    T.same(Field._locks, { ["other-mod"] = true }, version .. " cancellation releases only its own lock")
    T.eq(done(), 0, version .. " handlerless cancellation never invokes normal completion")
    T.eq(session.battleOutcome, nil, version .. " handlerless cancellation invents no result")
    T.eq(Battle.isActive(), false, version .. " handlerless cancellation starts no battle")
  end)

  exercise(version, "native trainer adapter preflight failure", function()
    local game, session, foe = trainer(version)
    local failures, completions = 0, 0
    session.party[1] = nil
    local started, reason = ScriptAdapters.host(nil, game).startTrainerBattle(foe,
      function() completions = completions + 1 end, {
        failed = function(failure)
          failures = failures + 1
          T.eq(failure, "empty party", version .. " adapter forwards preflight reason")
        end,
      })
    T.eq(started, nil, version .. " adapter returns native preflight rejection")
    T.eq(reason, "empty party", version .. " adapter returns native preflight reason")
    T.eq(failures, 1, version .. " adapter reports preflight failure once")
    T.eq(completions, 0, version .. " preflight failure cannot become normal completion")
    T.eq(session.battleOutcome, nil, version .. " preflight failure invents no result")
    T.same(session.flags, {}, version .. " preflight failure awards no flags")
  end)

  exercise(version, "trainer failed native start", function()
    local game, session, foe, opts, done = trainer(version)
    local continuation, failures, cancellations = nil, 0, 0
    opts.failed = function(reason)
      failures = failures + 1
      T.eq(reason, "empty party", version .. " failed start preserves native reason")
    end
    opts.cancel = function() cancellations = cancellations + 1 end
    ModRuntime.hooks:wrap("trainer.before_battle", function(_, _, _, resume)
      continuation = resume
      return true
    end)
    Bridge.start(nil, game, foe, opts)
    session.party[1] = nil
    T.eq(continuation(), false, version .. " actual native start rejects empty party")
    T.eq(continuation(), false, version .. " failed continuation stays spent")
    Runtime.drainDeferred()
    T.eq(failures, 1, version .. " failed native start reports once")
    T.eq(cancellations, 0, version .. " failure uses its separate callback")
    T.eq(done(), 0, version .. " failed start never completes a battle")
    T.eq(Battle.isActive(), false, version .. " failed start creates no battle")
    T.eq(Bridge._trainerPending, nil, version .. " failed start clears pending ownership")
    T.eq(Field.isLocked(), false, version .. " failed start releases engagement")
    T.eq(session.battleOutcome, nil, version .. " failed start invents no outcome")
    T.same(session.flags, {}, version .. " failed start awards no trainer flags")
  end)

  for _, mode in ipairs({ "cancel", "failed", "rollback" }) do
    exercise(version, "native trainer VM " .. mode, function()
      local game, session = trainer(version)
      local continuation, ended = nil, {}
      local scripts = { probe = {
        { op = "trainerbattle", trainer = 1, type = 1, eventScript = "reward" },
        { op = "setflag", flag = 42 }, { op = "end" },
      }, reward = { { op = "setflag", flag = 43 }, { op = "end" } } }
      local vm = Vm.new({ store = Space.store, scripts = scripts,
        adapters = ScriptAdapters.host(nil, game) })
      Space.vm = vm
      ModRuntime.events:on("script.ended", function(ev) ended[#ended + 1] = ev.completed end)
      ModRuntime.hooks:wrap("trainer.before_battle", function(_, _, _, resume)
        continuation = resume
        return true
      end, 0, "trainer-probe")
      Field.lock()
      Field.lock("other-mod")
      vm:start("probe")
      T.eq(vm.ctx.status, "waiting", version .. " native trainer opcode waits for hook")
      if mode == "cancel" then
        T.eq(continuation({ cancel = true }), true, version .. " VM cancellation accepted")
      elseif mode == "failed" then
        session.party[1] = nil
        T.eq(continuation(), false, version .. " VM native start fails")
      else
        ModRuntime.hooks:removeOwner("trainer-probe")
      end
      Runtime.drainDeferred()
      Field.update(0)
      T.eq(vm:isRunning(), false, version .. " unplayed battle halts actual native VM")
      T.same(ended, { false }, version .. " native script aborts exactly once")
      T.same(session.flags, {}, version .. " aborted VM runs no trainer or reward flag rows")
      T.eq(session.money, 1000, version .. " aborted VM awards no money")
      T.eq(session.battleOutcome, nil, version .. " aborted VM fabricates no result")
      T.same(Field._locks, { ["other-mod"] = true }, version .. " VM cleanup preserves unrelated field lock")
      T.eq(Bridge._trainerPending, nil, version .. " VM cleanup retires pending engagement")
      T.eq(continuation(), false, version .. " aborted VM continuation stays spent")
    end)
  end

  for _, mode in ipairs({ "cancel", "failed", "preflight" }) do
    exercise(version, "native trainer sight pair " .. mode, function()
      local game, session = trainer(version)
      if mode ~= "preflight" then session.party[2] = mon() end
      local continuation, ended = nil, {}
      local vm = Vm.new({ store = Space.store, adapters = ScriptAdapters.host(nil, game) })
      Space.vm = vm
      vm.ctx.mode, vm.ctx.status, vm.ctx.selectedLocalId = "native", "waiting", 1
      vm._scriptKey = "sight-probe"
      ModRuntime.events:on("script.ended", function(ev) ended[#ended + 1] = ev.completed end)
      ModRuntime.hooks:wrap("trainer.before_battle", function(_, _, _, resume)
        continuation = resume
        return true
      end)
      local a = { eo = { localId = 1, trainerId = 0, facing = "down" }, dist = 1 }
      local b = { eo = { localId = 2, trainerId = 1, facing = "down" }, dist = 1 }
      local retScriptCount, checkTrainerB, trainerBRet =
        TrainerSight.retScriptCount, TrainerSight.checkTrainerB, TrainerSight.trainerBRet
      Field.lock("other-mod")
      TrainerSight.engagePair(game, a, b)
      local effect = FieldEffects._anims[#FieldEffects._anims]
      local startBattle = native({ effect.onDone }, "startBattle")
      FieldEffects._anims = {}
      startBattle()
      if mode == "cancel" then
        T.eq(continuation({ cancel = true }), true, version .. " pair cancellation is accepted")
      elseif mode == "failed" then
        session.party[1], session.party[2] = nil, nil
        T.eq(continuation(), false, version .. " pair native start fails")
      else
        T.eq(continuation, nil, version .. " pair preflight rejects before hook dispatch")
      end
      Runtime.drainDeferred()
      T.eq(TrainerSight._pair, nil, version .. " unplayed pair retires ownership")
      T.eq(a.eo.frozen, false, version .. " unplayed pair unfreezes first trainer")
      T.eq(b.eo.frozen, false, version .. " unplayed pair unfreezes second trainer")
      T.eq(a.eo.scriptBusy, false, version .. " unplayed pair releases first trainer script")
      T.eq(b.eo.scriptBusy, false, version .. " unplayed pair releases second trainer script")
      T.eq(vm:isRunning(), false, version .. " unplayed pair halts its waiting VM")
      T.same(ended, { false }, version .. " unplayed pair aborts its script once")
      T.same(Field._locks, { ["other-mod"] = true }, version .. " pair cleanup preserves unrelated lock")
      T.same(session.flags, {}, version .. " unplayed pair awards no trainer flags")
      T.eq(session.money, 1000, version .. " unplayed pair awards no money")
      T.eq(session.battleOutcome, nil, version .. " unplayed pair invents no outcome")
      T.eq(TrainerSight.retScriptCount, retScriptCount, version .. " pair cancellation adds no return scripts")
      T.eq(TrainerSight.checkTrainerB, checkTrainerB, version .. " pair cancellation preserves return-script check")
      T.eq(TrainerSight.trainerBRet, trainerBRet, version .. " pair cancellation adds no second return script")
      T.eq(Battle.isActive(), false, version .. " unplayed pair starts no battle")
    end)
  end

  local stale = {
    session = function(_, session) Runtime.session = { version = session.version } end,
    game = function() Runtime._game = {} end,
    world = function(game) game.world = {} end,
    overworld = function(game) game.overworld = {} end,
    map = function() Map.current = "OTHER_ROUTE" end,
    party = function(_, session) session.party = {} end,
    foe = function(_, _, foe) foe.party = {} end,
    provider = function() ModRuntime.hooks = Hooks.new() end,
    bus = function() ModRuntime.events = Events.new() end,
    rollback = function() ModRuntime.hooks:removeOwner("trainer-probe") end,
  }
  for name, change in pairs(stale) do
    exercise(version, "trainer stale " .. name, function()
      local game, session, foe, opts, done = trainer(version)
      local continuation, remainingCalls = nil, 0
      ModRuntime.hooks:wrap("trainer.before_battle", function(next, ...)
        remainingCalls = remainingCalls + 1
        return next(...)
      end, 10, "other-owner")
      ModRuntime.hooks:wrap("trainer.before_battle", function(_, _, _, resume)
        continuation = resume
        return true
      end, 0, "trainer-probe")
      Bridge.start(nil, game, foe, opts)
      change(game, session, foe)
      Runtime.drainDeferred()
      Field.update(0)
      T.eq(Field.isLocked(), false, version .. " stale " .. name .. " update releases lock without resume")
      T.eq(Bridge._trainerPending, nil, version .. " stale " .. name .. " update clears ownership")
      T.eq(continuation(), false, version .. " stale " .. name .. " continuation refused")
      T.eq(Battle.isActive(), false, version .. " stale context starts no battle")
      T.eq(done(), 0, version .. " stale context cannot complete VM")
      if name == "rollback" then
        T.eq(#ModRuntime.hooks.chains["trainer.before_battle"], 1,
          version .. " owner rollback leaves other owner's same-chain callback")
        T.eq(remainingCalls, 1, version .. " remaining owner participated in captured chain")
      end
    end)
  end

  exercise(version, "native residual HP, order, detachment and unsubscribe", function()
    local _, _, st, ad = setup(version)
    st.player.status, st.player.mon.status = "PSN", "PSN"
    st.field = { tokens = { { id = "wind", state = { strength = 2 },
      onExpire = function() error("live callback leaked") end } } }
    local calls, seen, order = 0, nil, {}
    local unsubscribe = ModRuntime.hooks:wrap("battle.field_residual", function(_, view)
      calls, seen = calls + 1, view
      order[#order + 1] = "residual"
      T.eq(view.battlers.player.hp, 140, version .. " poison applies before custom residual")
      T.eq(view.battlers.player.types[1], "NORMAL", version .. " inherited normal type is a string ID")
      T.eq(view.battlers.enemy.types[1], "WATER", version .. " inherited water type is a string ID")
      T.eq(view.battle, nil, version .. " residual view has no battle alias")
      T.eq(view.field.tokens[1].onExpire, nil, version .. " residual strips callbacks")
      view.field.tokens[1].state.strength = 99
      view.battlers.player.hp = 1
      view.battlers.enemy.types[1] = "FIRE"
      return { { side = "player", amount = 7, message = "FIELD CHIP" },
        { side = "enemy", amount = 3 } }
    end)
    Battle._st, Battle._adapter, Battle._active = st, ad, true
    Battle._phase, Battle._headless, Battle._auto = "actions", true, false
    st._modTurnOpen = true
    ModRuntime.events:on("battle.turn_ended", function()
      order[#order + 1] = "end"
      T.eq(st.enemy.mon.hp, 157, version .. " turn end sees custom HP")
    end)
    Battle._actions, Battle._actionI = {}, 1
    Battle.update(0, Runtime._game)
    local rows = Battle._residualEvents
    T.eq(st.player.mon.hp, 133, version .. " actual player HP includes poison and chip")
    T.eq(st.enemy.mon.hp, 157, version .. " actual enemy HP includes chip")
    T.eq(st.field.tokens[1].state.strength, 2, version .. " token data is detached")
    T.eq(st.enemy.type1, 11, version .. " public type edits cannot change native type")
    T.eq(seen.turn, 1, version .. " residual identifies actual round")
    T.eq(rows[#rows].phase, "field_residual", version .. " custom rows follow native residual phases")
    T.check(has({ { text = table.concat(rows[#rows].msgs, " ") } }, "FIELD CHIP"),
      version .. " custom message enters native residual queue")
    local hpEvent
    for _, ev in ipairs(rows[#rows].events) do
      if ev.kind == "hp" and ev.side == "player" then hpEvent = ev end
    end
    T.check(hpEvent and hpEvent.from == 140 and hpEvent.to == 133,
      version .. " actual adapter emits native HP drain event")
    Residuals.collectEvents(ad)
    T.eq(calls, 1, version .. " custom residual runs once per round")
    T.same(order, { "residual", "end" }, version .. " actual turn closes after custom residual")
    unsubscribe()
    st.turn, st.player.status, st.player.mon.status = 2, nil, nil
    local hp = st.player.mon.hp
    Residuals.collectEvents(ad)
    T.eq(st.player.mon.hp, hp, version .. " unsubscribe restores no custom chip")
    T.eq(calls, 1, version .. " unsubscribe stops callback")
  end)

  exercise(version, "invalid descriptors and no-subscriber identity", function()
    local _, _, st, ad = setup(version)
    T.same(Residuals.collectEvents(ad), {}, version .. " native healthy round has no residual rows")
    ModRuntime.hooks:wrap("battle.field_residual", function()
      return { false, "bad", {}, { side = "other", amount = 4 },
        { side = "player", amount = -1 }, { side = "player", amount = 0 },
        { side = "player", amount = 1.5 }, { side = "player", amount = "7" },
        { side = "player", amount = math.huge }, { side = "player", amount = 0 / 0 },
        { side = "enemy", amount = 5, message = {} },
        { side = "player", amount = 5, battlerId = 1 },
        setmetatable({ side = "enemy", amount = 5 }, {}) }
    end)
    T.same(Residuals.collectEvents(ad), {}, version .. " invalid descriptors emit no native events")
    T.eq(st.player.mon.hp, 160, version .. " invalid rows preserve player HP")
    T.eq(st.enemy.mon.hp, 160, version .. " invalid rows preserve enemy HP")
  end)

  for _, double in ipairs({ false, true }) do
    exercise(version, "native residual faint batch double=" .. tostring(double), function()
      local _, _, st, ad = setup(version, double)
      local calls, fainted = 0, {}
      ModRuntime.events:on("battle.fainted", function(ev)
        fainted[#fainted + 1] = (ev.battler and ev.battler.side) or ev.sideName
        T.eq(st.player.mon.hp, 0, version .. " faint callback sees whole batch applied")
        T.eq(st.enemy.mon.hp, 0, version .. " enemy faint callback sees whole batch applied")
      end)
      ModRuntime.hooks:wrap("battle.field_residual", function()
        calls = calls + 1
        local rows = { { side = "enemy", amount = 999999 },
          { side = "player", amount = 999999 } }
        if double then
          rows[#rows + 1] = { side = "enemy", battlerId = 3, amount = 999999 }
          rows[#rows + 1] = { side = "player", battlerId = 2, amount = 999999 }
        end
        return rows
      end)
      local rows = Residuals.collectEvents(ad)
      T.eq(Engine.checkEnd(st, ad), "lose", version .. " terminal player faint owns outcome")
      for _, id in ipairs(State.presentIds(st)) do
        local b = State.battler(st, id)
        T.eq(b.mon.hp, 0, version .. " descriptor clamps native battler " .. id)
        T.eq(State.isFainted(b), true, version .. " native faint state " .. id)
      end
      T.check(#fainted > 0 and fainted[1] == "player", version .. " player faint is emitted before enemy awards")
      local changes = rows[#rows].hpChanges
      T.eq(#changes, double and 4 or 2, version .. " native queue drains all targeted battlers")
      for _, change in ipairs(changes) do
        T.eq(change.from, 160, version .. " native drain starts at real HP")
        T.eq(change.to, 0, version .. " native drain ends at clamped HP")
      end
      Residuals.collectEvents(ad)
      T.eq(calls, 1, version .. " decided battle receives no additional custom residual")
    end)
  end

  exercise(version, "doubles residual targeting", function()
    local _, _, st, ad = setup(version, true)
    ModRuntime.hooks:wrap("battle.field_residual", function(_, view)
      T.eq(view.battlers[2].battlerId, 2, version .. " doubles exposes additive battler identity")
      return { { side = "player", battlerId = 2, amount = 9 },
        { side = "enemy", battlerId = 3, amount = 4 } }
    end)
    Residuals.collectEvents(ad)
    T.eq(st.player.mon.hp, 160, version .. " partner descriptor preserves primary player")
    T.eq(st.enemy.mon.hp, 160, version .. " partner descriptor preserves primary enemy")
    T.eq(State.battler(st, 2).mon.hp, 151, version .. " player partner takes actual damage")
    T.eq(State.battler(st, 3).mon.hp, 156, version .. " enemy partner takes actual damage")
  end)

  exercise(version, "actual Healthbox caught eligibility and live subscription", function()
    local _, session, st = setup(version)
    Battle._st = st
    T.eq(Healthbox.shouldShowCaughtMarker(st, st.enemy), false, version .. " no Dex ownership hides caught icon")
    Dex.setCaught(session.dex, 129)
    T.eq(Healthbox.shouldShowCaughtMarker(st, st.enemy), true, version .. " caught wild species is eligible")
    local answer, calls = false, 0
    local unsubscribe = ModRuntime.hooks:wrap("battle.caught_marker_visible", function()
      calls = calls + 1
      return answer
    end)
    capture(function() Healthbox.draw("enemy", st.enemy) end)
    local before = calls
    T.check(before > 0, version .. " actual healthbox draw evaluates caught wrapper")
    T.eq(Healthbox.shouldShowCaughtMarker(st, st.enemy), false, version .. " false suppresses eligible icon")
    answer = true
    capture(function() Healthbox.draw("enemy", st.enemy) end)
    T.check(calls > before, version .. " next draw reevaluates live answer")
    T.eq(Healthbox.shouldShowCaughtMarker(st, st.enemy), true, version .. " true restores eligible icon")
    session.dex = Dex.new()
    T.eq(Healthbox.shouldShowCaughtMarker(st, st.enemy), false, version .. " true cannot invent Dex ownership")
    Dex.setCaught(session.dex, 129)
    st.trainer = true
    T.eq(Healthbox.shouldShowCaughtMarker(st, st.enemy), false, version .. " trainer marker remains ineligible")
    st.trainer = nil
    unsubscribe()
    T.eq(Healthbox.shouldShowCaughtMarker(st, st.enemy), true, version .. " unsubscribe restores native eligibility")
  end)

  for _, double in ipairs({ false, true }) do
    exercise(version, "actual Healthbox whole level double=" .. tostring(double), function()
      local game, _, st = setup(version, double)
      Battle._st = st
      for _, side in ipairs({ "player", "enemy" }) do
        local b = st[side]
        local key = double and b.id or side
        local draw = function() Healthbox.draw(key, b) end
        local stock, stockGlyphs = capture(draw)
        T.check(has(stock, "42"), version .. " healthbox native level digits print")
        local unsubscribe = ModRuntime.hooks:wrap("pokemon.level_visible", function(_, m, ctx)
          T.eq(m, b.mon, version .. " healthbox passes actual mon")
          T.eq(ctx.where, "battle." .. side, version .. " healthbox surface")
          T.eq(ctx.game, game, version .. " healthbox live game")
          return false
        end)
        local hidden, hiddenGlyphs, cleared = capture(draw)
        T.check(not has(hidden, "42"), version .. " healthbox hides digits")
        local levelGlyph = false
        for _, glyph in ipairs(hiddenGlyphs) do
          if glyph.code == Font.CHAR_LV_2 then levelGlyph = true end
        end
        T.eq(levelGlyph, false, version .. " healthbox hides level glyph")
        if version == "ruby" or version == "sapphire" then
          local erased = false
          for _, rect in ipairs(cleared) do
            if rect.mode == "fill" and rect.w >= 24 and rect.h >= 8 then erased = true end
          end
          T.check(erased, version .. " healthbox erases baked level label as well as digits")
        else
          T.check(#stockGlyphs > #hiddenGlyphs, version .. " native level glyph is suppressed")
        end
        T.check(has(hidden, "SCOUT"), version .. " level suppression preserves nickname")
        unsubscribe()
        T.same(capture(draw), stock, version .. " healthbox unsubscribe restores text")
      end
    end)
  end

  exercise(version, "actual party level row", function()
    local game, session = setup(version)
    PartyMenu._party, PartyMenu._session, PartyMenu.mode = session.party, session, "list"
    PartyMenu._layout = "single"
    if version == "ruby" or version == "sapphire" then
      local panel = { variants = setmetatable({}, { __index = function() return "panel.png" end }) }
      local data = { x = 0, y = 0, oam = {} }
      for i = 1, 6 do data.oam[i] = { 0, 0 } end
      RsParty._man = { coordinates = { panels = { { { 0, 0 } } }, text = { { { 2, 2 } } },
          hpBars = { { { 2, 3 } } }, monIcons = { { { 16, 16 } } } },
        panels = { large = panel }, textSettings = { { data } },
        windows = { monText = { fontNum = 1, foregroundColor = 1, shadowColor = 2, backgroundColor = 0 } },
        palettes = { bg = palette }, orderGfx = "unified-gen3-order.4bpp",
        hpTiles = { png = "hp.png", w = 8, h = 8,
          variants = { green = "hp.png", caps = "hp.png" } } }
      local drawSlot = native(RsParty, "drawSlot")
      local draw = function() drawSlot(PartyMenu, 1, session.party[1]) end
      assertLevelCycle(version, game, session.party[1], "party", draw, "42", true)
    else
      local drawSlot = native(PartyMenu, "draw_filled_slot")
      assertLevelCycle(version, game, session.party[1], "party",
        function() drawSlot(1, session.party[1], false) end, "Lv42")
    end
  end)

  exercise(version, "actual summary level row", function()
    local game, session = setup(version)
    local m = session.party[1]
    local draw
    if version == "ruby" or version == "sapphire" then
      RsSummary._party, RsSummary._cursor, RsSummary._playerState = session.party, 1, session
      RsSummary._loaded, RsSummary._state, RsSummary._pane = nil, "normal", nil
      local colors = setmetatable({}, { __index = function()
        return { color = 1, background = 0, shadow = 2 }
      end })
      RsSummary._man = { noFlip = {}, nativeWindow = { fontNum = 1, paletteNum = 0 },
        textColors = colors, palettes = { bg = palette },
        text = { png = "text.png", w = 8, h = 8 },
        build = "fixture-rs-summary", nativeTextTiles = {}, nativeTextPal = palette }
      session.dex.national = true
      local portrait = native(RsSummary, "portrait")
      draw = function() portrait() end
    elseif version == "emerald" then
      local windows = {}
      for i = 1, 20 do windows[i] = { left = 0, top = 0, paletteNum = 0 } end
      local manifest = { windows = windows, palette = palette, textColors = palette }
      local portrait = native(EmSummary, "drawPortrait")
      draw = function() portrait(manifest, { _playerState = session }, m, false, false, 0) end
    else
      SummaryMenu._playerState = session
      local header = native(SummaryMenu, "draw_header")
      draw = function() header(m, true, 0) end
    end
    assertLevelCycle(version, game, m, "summary", draw,
      (version == "ruby" or version == "sapphire") and "{LV}42" or "Lv42")
  end)

  exercise(version, "actual Battle.update START claim, fallback and unsubscribe", function()
    local game = decision(version)
    game.input.pressed = { start = true, right = true }
    Battle.update(0, game)
    T.eq(Ui._menuIndex, 2, version .. " no-hook START preserves native right input")
    Ui._menuIndex = 1
    local answer, calls = true, 0
    local unsubscribe = ModRuntime.hooks:wrap("battle.menu_auxiliary", function(_, g, ctx)
      calls = calls + 1
      T.eq(g, game, version .. " START receives game")
      T.same(ctx, { kind = "wild" }, version .. " START inherited context")
      return answer
    end)
    Battle.update(0, game)
    T.eq(calls, 1, version .. " safe START invokes wrapper once")
    T.eq(Ui._menuIndex, 1, version .. " claimed START consumes native input")
    answer = false
    Battle.update(0, game)
    T.eq(calls, 2, version .. " unclaimed START invokes wrapper once")
    T.eq(Ui._menuIndex, 2, version .. " false falls through native input exactly once")
    unsubscribe()
    Ui._menuIndex = 1
    Battle.update(0, game)
    T.eq(Ui._menuIndex, 2, version .. " unsubscribe restores native input")
    T.eq(calls, 2, version .. " unsubscribe stops auxiliary hook")
  end)

  local unsafe = {
    covered = function(game) game.stack = { top = function() return {} end } end,
    automatic = function() Battle._auto = true end,
    link = function(_, st) st.link = true end,
    queued = function() Ui.push("queued message") end,
    animating = function() Battle._phase = "animating" end,
    target = function() Ui._target = {} end,
    switch = function() Battle._phase = "faint_switch" end,
    safari = function(_, st) st.safari = true end,
    tutorial = function(_, st) st.oldManTutorial = true end,
    fainted = function(_, st) st.player.mon.hp = 0 end,
    hpDrain = function() Anim.present(0).displayHp = 1 end,
    forced = function(_, st) st.player.expMustRecharge = true end,
  }
  for name, change in pairs(unsafe) do
    exercise(version, "unsafe START " .. name, function()
      local game, _, st = decision(version)
      local calls = 0
      ModRuntime.hooks:wrap("battle.menu_auxiliary", function() calls = calls + 1; return true end)
      change(game, st)
      game.input.pressed = { start = true }
      local ok, err = pcall(Battle.update, 0, game)
      T.eq(calls, 0, version .. " " .. name .. " cannot reach auxiliary hook")
      T.check(ok, version .. " " .. name .. " native update remains valid: " .. tostring(err))
    end)
  end
end

Battle.reset()
Bridge.reset()
for i = #restore, 1, -1 do restore[i]() end
ModRuntime.events, ModRuntime.hooks, ModRuntime.errors = (table.unpack or unpack)(savedRuntime)
T.finish("unified gen3 hooks")
