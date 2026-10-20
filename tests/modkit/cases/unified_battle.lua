package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.harness").suite("unified battle")
local UnifiedBattle = require("src.mods.UnifiedBattle")
local Runtime = require("src.mods.Runtime")
local Hooks = require("src.mods.Hooks")
local Events = require("src.mods.Events")
local Sdk = require("tests.modkit.sdk")
local Catching1 = require("src.battle.Catching")
local Catching2 = require("src.battle.gen2.Catching")
local nativeModules = {
  "src.battle.BattleAPI", "src.battle.gen2.BattleAPI", "src.battle.game3.BattleAPI",
}
local versions = { "red", "gold", "firered" }
local savedRuntime = { Runtime.events, Runtime.hooks, Runtime.errors }
local errors, hooks, events = {}, Hooks.new(), Events.new()
Runtime.install(events, hooks, errors)
local savedModules = {}
local function install(name, value)
  if not savedModules[name] then savedModules[name] = { package.loaded[name] } end
  package.loaded[name] = value
end

require("src.battle.TypeChart").load({ type_chart = {
  types = { NORMAL = { name = "NORMAL", category = "physical" } }, matchups = {},
} })

local gen3Data = Sdk.gen3Data()
gen3Data.gen3Items._byId[1] = { name = "MASTER BALL", pocket = "POKE_BALLS" }
local Pokemon = gen3Data.gen3Pokemon
function Pokemon.name(id) return Pokemon._names[id] end
function Pokemon.speciesOf(mon) return mon.species end
function Pokemon.speciesMeta(id) return Pokemon._speciesMeta[id] end
function Pokemon.moveName(id) return Pokemon._moveNames[id] end
function Pokemon.romMoveName(id) return Pokemon._moveNames[id] end

local Moves, savedMoves
local function rejected(value, reason, expected, label)
  T.eq(value, nil, label .. " returns nil")
  T.eq(reason, expected, label .. " explains refusal")
end

local function mon(generation, species, nickname)
  local out = { species = species, nickname = nickname, level = 20, hp = 30,
    moves = { { id = "POUND", pp = 30, maxPp = 35 } },
    stats = { hp = 40, attack = 21, defense = 22, speed = 23 },
    status = generation == 1 and "PSN" or "poison",
    provenance = { route = 1 } }
  if generation == 1 then out.stats.special = 24
  elseif generation == 2 then
    out.maxHp, out.item = 40, "POTION"
    out.stats.specialAttack, out.stats.specialDefense = 24, 25
  else
    out.species = ({ MEW = 151, CHARMANDER = 4, PIDGEY = 16 })[species]
    out.maxHp, out.attack, out.defense, out.speed = 40, 21, 22, 23
    out.spAtk, out.spDef, out.stats, out.status, out.item = 24, 25, nil, 8, 13
    out.moves, out.pp, out.maxPp = { 1 }, { 30 }, { 35 }
  end
  return out
end

local function fixture(generation)
  local f = { generation = generation, inputs = 0, active = true }
  f.player, f.enemy = mon(generation, "MEW", "Scout"), mon(generation, "CHARMANDER")
  f.reserve = mon(generation, "CHARMANDER", "Reserve")
  f.enemy.hp, f.enemy.status = 12, nil
  if generation == 1 then f.enemy.stats.hp = 20 else f.enemy.maxHp = 20 end
  local data = generation == 3 and gen3Data or {
    pokemon = { MEW = { name = "MEW", catchRate = 45 },
      CHARMANDER = { name = "CHARMANDER", catchRate = 45 } },
    moves = { POUND = { name = "POUND", type = "NORMAL", power = 40,
      accuracy = 100, pp = 35 } },
    items = { POKE_BALL = { name = "POKE BALL", pocket = "BALL" },
      MASTER_BALL = { name = "MASTER BALL", pocket = "BALL" },
      POTION = { name = "POTION", pocket = "ITEM" } },
  }
  f.game = { data = data, save = { version = versions[generation],
    party = { f.player, f.reserve }, inventory = { POKE_BALL = 2, MASTER_BALL = 1 } },
    stack = { states = {} } }
  function f:setPrompt(prompt)
    if generation == 3 then
      self.ui._mode = prompt
      self.battleModule._phase = prompt == "locked" and "resolving" or "command"
    else
      self.screen.phase = prompt == "moves" and (generation == 1 and "moveSelect" or "moves")
        or prompt == "locked" and (generation == 1 and "messages" or "resolving") or prompt
    end
  end
  if generation == 1 then
    f.state = { isBattleState = true, queue = {}, turnCount = 2,
      ruleset = { oneIn256Miss = true },
      player = { mon = f.player, curTypes = { "NORMAL" }, stages = {}, curMoves = f.player.moves },
      enemy = { mon = f.enemy, curTypes = { "NORMAL" }, stages = {} } }
    f.screen = f.state
    function f.state:battleKind() return self.kind or "wild" end
    function f.state:effectRecord() return { accuracyChecked = true } end
    function f.state:visibleText() return { "Wild CHARMANDER appeared!" } end
    function f.state:catchChance(ball)
      return Catching1.chance(ball, self.enemy.mon, data.pokemon.CHARMANDER)
    end
  elseif generation == 2 then
    f.state = { wild = true, turn = 2, player = f.player, enemy = f.enemy,
      party = f.game.save.party }
    function f.state:moveDisabled() return false end
    f.screen = { screenId = "Gen2BattleState", battle = f.state, menuIndex = 1,
      moveIndex = 1, message = "Wild CHARMANDER appeared!" }
    function f.screen:catchChance(ball)
      return Catching2.chance({ ball = ball, hp = f.enemy.hp,
        maxHp = f.enemy.maxHp, catchRate = 45, status = f.enemy.status })
    end
  else
    f.game.session = { version = "firered", party = f.game.save.party,
      bag = { balls = { { id = 4, name = "POKE BALL", qty = 2 },
        { id = 1, name = "MASTER BALL", qty = 1 } } } }
    f.state = { kind = "wild", wild = true, turn = 2,
      playerParty = f.game.save.party, player = { mon = f.player, partyIndex = 1 },
      enemy = { mon = f.enemy }, absent = {} }
    f.ui = { _mode = "menu", _menuIndex = 1, _moveIndex = 1, _active = 0 }
    f.battleModule = { _phase = "command", isActive = function() return f.active end,
      getState = function() return f.state end }
    function f.ui.handleInput(input)
      f.inputs = f.inputs + 1
      if input:wasPressed("b") then
        f:setPrompt(f.ui._mode == "target" and "moves" or "menu")
      elseif input:wasPressed("a") then
        if f.ui._mode == "menu" then
          f.chosenMenu = f.ui._menuIndex
          f:setPrompt("moves")
        elseif f.ui._mode == "moves" then
          f.chosenMove = f.ui._moveIndex
          if f.state.double then
            f.ui._target = { battler = f.ui._active, slot = f.ui._moveIndex, cursor = 1 }
            f:setPrompt("target")
          else f:setPrompt("locked") end
        elseif f.ui._mode == "target" then
          f.chosenTarget = f.ui._target.cursor
          f:setPrompt("locked")
        end
      end
    end
  end
  if generation ~= 3 then
    function f.screen:chooseMenu(choice)
      f.inputs, f.chosenMenu = f.inputs + 1, choice
      f:setPrompt("moves")
      return true
    end
    function f.screen:chooseMove(slot)
      f.inputs, f.chosenMove = f.inputs + 1, slot
      f:setPrompt("locked")
      return true
    end
    function f.screen:cancelMove()
      f.inputs = f.inputs + 1
      f:setPrompt("menu")
      return true
    end
  end
  function f:activate()
    if generation == 3 then
      install("src.core.game3.pokemon", Pokemon)
      install("src.core.game3.runtime", { getSession = function() return self.game.session end })
      install("src.core.game3.battle.init", self.battleModule)
      install("src.core.game3.battle.ui", self.ui)
      install("src.ui.game3.message", { isOpen = function() return false end })
      install("src.core.game3.bag", { listPocket = function(bag, pocket)
        assert(pocket == "POKE_BALLS")
        return bag.balls
      end })
      if not Moves then
        Moves = require("src.core.game3.battle.moves")
        savedMoves = { Moves._rom, Moves._romLoaded, Moves._numByName, Moves.BY_NUM, Moves._linkRows }
        Moves._rom, Moves._romLoaded, Moves._linkRows = gen3Data.gen3Moves._rom, true, nil
        Moves._numByName, Moves.BY_NUM = {}, {}
        for id, name in pairs(Pokemon._moveNames) do
          Moves._numByName[name], Moves.BY_NUM[id] = id, name
        end
      end
    end
    self:setActive(true)
  end
  function f:setActive(active)
    self.active = active
    if generation ~= 3 then self.game.stack.states = active and { self.screen } or {} end
  end
  f:setPrompt("menu")
  f:activate()
  f.native = require(nativeModules[generation]).new(f.game)
  return f
end

local function item(snapshot, id)
  for _, row in ipairs(snapshot.items) do if row.id == id then return row end end
  error("missing battle item " .. id)
end

local core
for generation = 1, 3 do
  local f, live = fixture(generation)
  local function provider() return live end
  local api = UnifiedBattle.new(provider, generation, versions[generation])
  local value, reason = api:snapshot()
  rejected(value, reason, "no battle", "pre-ready snapshot")
  value, reason = api:submit({ id = 1, revision = 1, kind = "menu", choice = "fight" })
  rejected(value, reason, "no battle", "pre-ready intent")
  live = f.game
  f:setActive(false)
  value, reason = api:snapshot()
  rejected(value, reason, "no battle", "snapshot outside battle")
  T.eq(f.native:snapshot(), nil, "native adapter also reports no battle")
  value, reason = api:submit({ id = 1, revision = 1, kind = "menu", choice = "fight" })
  rejected(value, reason, "no battle", "intent outside battle")
  f:setActive(true)

  local raw = f.native:snapshot()
  T.eq(raw.moves[1].id, generation == 3 and 1 or "POUND", "native move IDs retain their schema")
  T.eq(f.native:submit({ id = 1, revision = raw.revision, kind = "menu", choice = "fight" }),
    true, "native public submit reaches the battle screen")
  T.eq(f.chosenMenu, generation == 3 and 1 or "fight", "native semantic FIGHT dispatch")
  raw = f.native:snapshot()
  T.eq(f.native:submit({ id = 2, revision = raw.revision, kind = "back" }), true,
    "native public back returns to the menu")

  local snapshot = api:snapshot()
  T.check(snapshot.revision >= 1, "revision is positive")
  T.eq(api:snapshot().revision, snapshot.revision, "unchanged snapshots retain the revision")
  local shape = { kind = snapshot.kind, prompt = snapshot.prompt, turn = snapshot.turn,
    double = snapshot.double, active = snapshot.active, catchable = snapshot.catchable,
    targets = snapshot.targets, player = snapshot.player.species, enemy = snapshot.enemy.species,
    moves = snapshot.player.moves, party = #snapshot.party, battlers = #snapshot.battlers }
  local expected = { kind = "wild", prompt = "menu", turn = 2, double = false,
    active = 0, catchable = true, targets = {}, player = "MEW", enemy = "CHARMANDER",
    moves = { { id = "POUND", pp = 30, maxPp = 35 } }, party = 2, battlers = 2 }
  T.same(shape, expected, "native singles have the canonical core shape")
  if core then T.same(shape, core, "the same core snapshot works across generations") else core = expected end
  T.eq(snapshot.player.name, "Scout", "nickname is portable")
  T.eq(snapshot.player.nickname, "Scout", "raw nickname follows Gen 1")
  T.eq(snapshot.player.status, "PSN", "native status representation follows Gen 1")
  T.same(snapshot.player.stats, { hp = 40, attack = 21, defense = 22, speed = 23,
    special = 24, specialAttack = 24, specialDefense = generation == 1 and 24 or 25 },
    "Gen 1 Special is common while split Special remains available")
  T.eq(snapshot.player.item, generation ~= 1 and "POTION" or nil, "held item IDs are canonical")
  T.eq(snapshot.player.hp, 30, "current HP is preserved")
  T.eq(snapshot.player.maxHp, 40, "maximum HP is preserved")
  T.eq(snapshot.moves[1].id, "POUND", "move IDs are canonical")
  T.eq(snapshot.moves[1].type, "NORMAL", "move types are canonical")
  T.eq(snapshot.moves[1].pp, 30, "move rows preserve PP")
  T.eq(snapshot.moves[1].maxPp, 35, "move rows preserve maximum PP")
  T.eq(snapshot.moves[1].disabled, false, "disabled is always boolean")
  T.eq(snapshot.battlers[1].id, 0, "first battler retains numeric ID zero")
  T.eq(snapshot.battlers[1].side, "player", "even battler IDs are player side")
  T.eq(snapshot.battlers[2].id, 1, "enemy battler ID is one")
  T.eq(snapshot.battlers[2].side, "enemy", "odd battler IDs are enemy side")
  T.eq(snapshot.battlers[1].absent, false, "present battlers are explicit")
  T.eq(snapshot.party[1].slot, 1, "party slots are one based")
  T.eq(snapshot.party[2].species, "CHARMANDER", "reserve party species is canonical")
  T.eq(snapshot.party[2].active, false, "reserve party member is inactive")
  T.eq(item(snapshot, "MASTER_BALL").catchChance, 100, "guaranteed capture is 100 percent")
  local ball = item(snapshot, "POKE_BALL")
  T.eq(ball.count, 2, "ball count survives normalization")
  T.eq(ball.ball, true, "ball classification is portable")
  T.eq(ball.needsTarget, false, "balls have no party target")
  T.eq(ball.catchable, true, "wild ball rows are catchable")
  T.check(ball.catchChance > 0 and ball.catchChance < 100, "catch preview is a percentage")
  if generation ~= 3 then
    T.eq(ball.catchChance, item(f.native:snapshot(), "POKE_BALL").catchChance,
      "native percentage is preserved")
  end

  snapshot.player.hp, snapshot.player.stats.attack = 0, 999
  snapshot.player.moves[1].pp, snapshot.player.native.provenance.route = 0, 99
  snapshot.party[1].native.hp, snapshot.party[1].moves[1].id = 0, "MISSING"
  snapshot.battlers[1].stats.speed, snapshot.battlers[2].native.hp = 999, 0
  snapshot.moves[1].pp, ball.count = 0, 99
  snapshot.targets[1], snapshot.party[3] = 3, {}
  local detached = api:snapshot()
  T.eq(detached.player.hp, 30, "player records are detached")
  T.eq(detached.player.stats.attack, 21, "nested stats are detached")
  T.eq(detached.player.native.provenance.route, 1, "nested native extension is detached")
  T.eq(detached.party[1].moves[1].id, "POUND", "party move records are detached")
  T.eq(detached.battlers[1].stats.speed, 23, "battler stats are detached")
  T.eq(detached.enemy.hp, 12, "enemy native extension is detached")
  T.eq(detached.moves[1].pp, 30, "move preview records are detached")
  T.eq(item(detached, "POKE_BALL").count, 2, "inventory records are detached")
  T.eq(#detached.targets, 0, "target lists are detached")
  T.eq(#detached.party, 2, "party lists are detached")
  T.eq(f.player.hp, 30, "snapshot edits never reach native HP")
  T.eq(f.player.provenance.route, 1, "snapshot edits never reach native metadata")
  T.eq(api:snapshot().revision, detached.revision, "snapshot edits do not advance native revision")

  local revision = detached.revision
  local malformed = {
    { value = false, reason = "intent must be a plain table" },
    { value = setmetatable({}, {}), reason = "intent must be a plain table" },
  }
  for _, id in ipairs({ 0, -1, 1.5, 0 / 0, math.huge, 9007199254740992 }) do
    malformed[#malformed + 1] = { value = { id = id, revision = revision, kind = "back" },
      reason = "intent id must be a positive integer" }
  end
  for _, rev in ipairs({ 0, -1, 1.5, 0 / 0, math.huge, 9007199254740992 }) do
    malformed[#malformed + 1] = { value = { id = 1, revision = rev, kind = "back" },
      reason = "invalid battle revision" }
  end
  for _, row in ipairs({
    { "menu", "choice", "missing", "unknown battle menu choice" },
    { "move", "slot", 0, "invalid move slot" },
    { "move", "slot", 5, "invalid move slot" },
    { "move", "slot", 1.5, "invalid move slot" },
    { "target", "target", 4, "target must be a battler id 0-3" },
    { "mimic", "index", 0, "invalid mimic index" },
    { "safari", "action", false, "invalid safari action" },
    { "unknown", "slot", 1, "unknown battle intent" },
    { "back", "extra", true, "unknown battle intent field" },
  }) do
    malformed[#malformed + 1] = { value = { id = 1, revision = revision,
      kind = row[1], [row[2]] = row[3] }, reason = row[4] }
  end
  local inputs = f.inputs
  for _, bad in ipairs(malformed) do
    value, reason = api:submit(bad.value)
    rejected(value, reason, bad.reason, "malformed intent")
  end
  T.eq(f.inputs, inputs, "malformed intents never dispatch input")
  T.eq(api:snapshot().revision, revision, "malformed intents never change the battle")

  f.enemy.hp = f.enemy.hp - 1
  local current = api:snapshot()
  T.check(current.revision > revision, "native HP changes invalidate prior snapshots")
  value, reason = api:submit({ id = 1, revision = revision, kind = "menu", choice = "fight" })
  rejected(value, reason, "stale battle context", "stale intent")
  T.eq(api:submit({ id = 1, revision = current.revision, kind = "menu", choice = "fight" }),
    true, "validation failures leave intent ID one usable")
  T.eq(f.inputs, inputs + 1, "accepted intent dispatches exactly once")
  value, reason = api:submit({ id = 1, revision = current.revision, kind = "menu", choice = "fight" })
  rejected(value, reason, "replayed intent", "replayed intent")
  current = api:snapshot()
  T.eq(current.prompt, "moves", "semantic FIGHT opens the move menu")
  T.eq(api:submit({ id = 2, revision = current.revision, kind = "back" }), true, "back is portable")
  current = api:snapshot()
  value, reason = api:submit({ id = 3, revision = current.revision, kind = "move", slot = 1 })
  rejected(value, reason, "move menu is not active", "move at the command menu")
  T.eq(api:submit({ id = 3, revision = current.revision, kind = "menu", choice = "fight" }), true,
    "native phase refusal does not consume the intent ID")
  if generation == 3 then f.player.pp[1] = 0 else f.player.moves[1].pp = 0 end
  current = api:snapshot()
  value, reason = api:submit({ id = 4, revision = current.revision, kind = "move", slot = 1 })
  rejected(value, reason, "move has no PP", "exhausted move")
  if generation == 3 then f.player.pp[1] = 30 else f.player.moves[1].pp = 30 end
  current = api:snapshot()
  T.eq(api:submit({ id = 4, revision = current.revision, kind = "move", slot = 1 }), true,
    "portable move intent reaches the native adapter")
  T.eq(f.chosenMove, 1, "native move slot is preserved")
  f:setPrompt("menu")

  local other = UnifiedBattle.new(provider, generation, versions[generation])
  current = other:snapshot()
  T.eq(other:submit({ id = 1, revision = current.revision, kind = "menu", choice = "fight" }),
    true, "another mod starts its own intent sequence at one")
  current = api:snapshot()
  T.eq(api:submit({ id = 5, revision = current.revision, kind = "back" }), true,
    "the first mod keeps its sequence after another mod acts")
  current = other:snapshot()
  T.eq(other:submit({ id = 2, revision = current.revision, kind = "menu", choice = "fight" }), true,
    "the second mod continues independently")
  current = api:snapshot()
  T.eq(api:submit({ id = 6, revision = current.revision, kind = "back" }), true,
    "independent mod intents interleave")

  local beforeReset = api:snapshot()
  local replacement = fixture(generation)
  live = replacement.game
  value, reason = api:submit({ id = 7, revision = beforeReset.revision, kind = "menu", choice = "fight" })
  rejected(value, reason, "stale battle context", "provider replacement invalidates old revision")
  current = api:snapshot()
  T.check(current.revision > beforeReset.revision, "replacement revision increases monotonically")
  value, reason = api:submit({ id = 6, revision = current.revision, kind = "menu", choice = "fight" })
  rejected(value, reason, "replayed intent", "provider replacement retains the mod replay ledger")
  T.eq(api:submit({ id = 7, revision = current.revision, kind = "menu", choice = "fight" }), true,
    "held facade resolves the replacement native adapter")
  T.eq(replacement.chosenMenu, generation == 3 and 1 or "fight", "replacement receives input")
  current = api:snapshot()
  T.eq(api:submit({ id = 8, revision = current.revision, kind = "back" }), true, "replacement back succeeds")
  local replacementSnapshot = api:snapshot()
  live = f.game
  f:activate()
  current = api:snapshot()
  T.check(current.revision > replacementSnapshot.revision, "returning to an old provider advances revision")
  value, reason = api:submit({ id = 8, revision = current.revision, kind = "menu", choice = "fight" })
  rejected(value, reason, "replayed intent", "returning provider retains latest replay ledger")
  value, reason = api:submit({ id = 9, revision = replacementSnapshot.revision, kind = "menu", choice = "fight" })
  rejected(value, reason, "stale battle context", "replacement snapshot cannot control restored provider")
  T.eq(api:submit({ id = 9, revision = current.revision, kind = "menu", choice = "fight" }), true,
    "restored provider accepts a fresh intent")
  local fresh = UnifiedBattle.new(provider, generation, versions[generation])
  current = fresh:snapshot()
  T.eq(fresh:submit({ id = 1, revision = current.revision, kind = "back" }), true,
    "a new mod has an independent sequence after provider resets")
  f:setActive(false)
  value, reason = api:snapshot()
  rejected(value, reason, "no battle", "ended battle snapshot")
  live = nil
  value, reason = api:snapshot()
  rejected(value, reason, "no battle", "removed provider snapshot")
end

local f = fixture(3)
local api = UnifiedBattle.new(function() return f.game end, 3, "firered")
local Catching3 = require("src.core.game3.battle.catching")
local rngCalls, hookCalls, eventCalls = 0, 0, 0
local oldRandom, oldLoveRandom = math.random, love.math.random
local function countedRandom() rngCalls = rngCalls + 1; return 0 end
math.random, love.math.random, f.state.rng = countedRandom, countedRandom, countedRandom
local stopHook = hooks:wrap("catch.rate", function()
  hookCalls = hookCalls + 1
  return false, 0
end)
local stopThrown = events:on("battle.ball_thrown", function() eventCalls = eventCalls + 1 end)
local stopCaught = events:on("pokemon.caught", function() eventCalls = eventCalls + 1 end)
local function chanceFor(odds)
  if odds >= 255 then return 100 end
  local threshold = math.floor(1048560 / math.sqrt(math.sqrt(16711680 / odds)))
  return (math.min(65536, threshold) / 65536) ^ 4 * 100
end
T.eq(Catching3.catchOdds(4, f.state.enemy, f.state, f.game.session), 27, "native healthy foe odds")
local snapshot = api:snapshot()
T.eq(item(snapshot, "POKE_BALL").catchChance, chanceFor(27), "preview uses four native shake checks")
T.eq(item(snapshot, "MASTER_BALL").catchChance, 100, "Master Ball stays certain with catch hook installed")
f.enemy.status = "SLP"
T.eq(Catching3.catchOdds(4, f.state.enemy, f.state, f.game.session), 54, "native sleep bonus doubles odds")
T.eq(item(api:snapshot(), "POKE_BALL").catchChance, chanceFor(54), "preview includes native sleep bonus")
f.state.noCatch = true
snapshot = api:snapshot()
T.eq(snapshot.catchable, false, "native no-catch state is respected")
T.eq(item(snapshot, "POKE_BALL").catchChance, nil, "no-catch state exposes no percentage")
f.state.noCatch, f.state.wild, f.state.kind = nil, false, "trainer"
snapshot = api:snapshot()
T.eq(item(snapshot, "MASTER_BALL").catchable, false, "trainer battle balls are not catchable")
T.eq(item(snapshot, "MASTER_BALL").catchChance, nil, "trainer battle has no catch preview")
f.state.wild, f.state.kind = true, "wild"

f.state.double, f.state.activeBattler, f.ui._active = true, 2, 2
f.reserve.moves, f.reserve.pp, f.reserve.maxPp = { 57 }, { 15 }, { 15 }
local foe = mon(3, "PIDGEY")
foe.hp, foe.status = 8, "SLP"
f.state.battlers = { [2] = { mon = f.reserve, partyIndex = 2 }, [3] = { mon = foe } }
f.state.absent[1] = true
f:setPrompt("moves")
snapshot = api:snapshot()
T.eq(snapshot.double, true, "optional doubles uses the common snapshot")
T.eq(snapshot.active, 2, "active partner retains battler ID two")
T.eq(snapshot.player.name, "Reserve", "player view follows the active partner")
T.eq(snapshot.moves[1].id, "SURF", "active partner's numeric move becomes canonical")
T.eq(#snapshot.battlers, 4, "doubles exposes all four battler slots")
T.eq(snapshot.battlers[2].absent, true, "absent enemy slot is explicit")
T.eq(snapshot.battlers[3].side, "player", "partner has the player side")
T.eq(snapshot.battlers[3].partyIndex, 2, "native party index is retained")
T.eq(snapshot.party[2].active, true, "partner is active in the party list")
local odds = Catching3.catchOdds(4, f.state.battlers[3], f.state, f.game.session)
T.eq(item(snapshot, "POKE_BALL").catchChance, chanceFor(odds), "double preview uses active partner's foe")
T.eq(api:submit({ id = 1, revision = snapshot.revision, kind = "move", slot = 1 }), true,
  "double move dispatch opens native target cursor")
snapshot = api:snapshot()
T.eq(snapshot.prompt, "target", "target prompt is optional")
T.same(snapshot.targets, { 0, 2, 3 }, "target list uses battler IDs and excludes absent slots")
snapshot.targets[1], snapshot.battlers[4].native.hp = 99, 0
local current = api:snapshot()
T.same(current.targets, { 0, 2, 3 }, "double target list is detached")
T.eq(current.battlers[4].hp, 8, "double battler native extension is detached")
local inputs = f.inputs
local value, reason = api:submit({ id = 2, revision = current.revision, kind = "target", target = 1 })
rejected(value, reason, "no battler in that slot", "absent target")
value, reason = api:submit({ id = 2, revision = current.revision, kind = "target", target = 2 })
rejected(value, reason, "that move cannot target its user", "invalid self target")
T.eq(f.inputs, inputs, "rejected targets do not confirm native UI")
T.eq(api:submit({ id = 2, revision = current.revision, kind = "target", target = 3 }), true,
  "valid enemy target confirms native UI")
T.eq(f.chosenTarget, 3, "native cursor receives the requested battler ID")
T.eq(f.inputs, inputs + 1, "valid target confirms exactly once")
f:setPrompt("target")
current = api:snapshot()
T.eq(api:submit({ id = 3, revision = current.revision, kind = "back" }), true,
  "back cancels the optional target cursor")
T.same(api:snapshot().targets, {}, "outside target mode the common target list is empty")
T.eq(rngCalls, 0, "snapshot previews never consume RNG")
T.eq(hookCalls, 0, "snapshot previews never invoke catch.rate")
T.eq(eventCalls, 0, "snapshot previews never emit catch events")
T.eq(f.state.battleResults, nil, "previews never record a catch attempt")
T.eq(f.game.session.bag.balls[1].qty, 2, "previews never spend a ball")
math.random, love.math.random = oldRandom, oldLoveRandom
stopHook()
stopThrown()
stopCaught()
T.eq(#errors, 0, "battle regressions have no swallowed runtime failures")
if Moves then
  Moves._rom, Moves._romLoaded, Moves._numByName, Moves.BY_NUM, Moves._linkRows =
    savedMoves[1], savedMoves[2], savedMoves[3], savedMoves[4], savedMoves[5]
end
for name, saved in pairs(savedModules) do package.loaded[name] = saved[1] end
Runtime.install(savedRuntime[1], savedRuntime[2], savedRuntime[3])
T.finish()
