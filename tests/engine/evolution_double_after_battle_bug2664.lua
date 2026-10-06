-- engine/pokemon/evos_moves.asm:156

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

package.loaded["src.core.Sound"] = {
  play = function() end,
  playCry = function() end,
  playPress = function() end,
  stopLoop = function() end,
}

local Fixtures = require("tests.modkit.fixtures")
local Music = require("src.core.Music")
local Evolution = require("src.pokemon.Evolution")
local EvolutionState = require("src.ui.EvolutionState")
local Input = require("src.core.Input")
local Pokemon = require("src.pokemon.Pokemon")
local StateStack = require("src.core.StateStack")
local TextBox = require("src.render.TextBox")

local Data = Fixtures.fresh()
require("src.render.Font").load(Data)

local restores = 0
Music.restoreMap = function() restores = restores + 1 end

local A_KEY, B_KEY = "z", "x"

local function newGame(count)
  local game = { data = Data }
  local party = {}
  for i = 1, count do party[i] = Pokemon.new(Data, "FIXMON_A", 16) end
  game.save = {
    party = party,
    player = { name = "RED", id = 1 },
    options = { textSpeed = 5 },
    flags = {},
    pokedex = { seen = {}, owned = {} },
  }
  game.stack = setmetatable({}, { __index = StateStack })
  game.stack:init()
  game.input = Input
  Input:init()
  local under = { isOpaque = true, update = function() end, draw = function() end }
  game.stack:push(under)
  return game, party, under
end

local function step(game, key)
  if key then Input:keypressed(key) end
  game.input:step()
  game.stack:update(1 / 60)
  if key then Input:keyreleased(key) end
end

local function indexOf(game, state)
  for i, s in ipairs(game.stack.states) do
    if s == state then return i end
  end
end

local function leftovers(game)
  local n = 0
  for _, s in ipairs(game.stack.states) do
    if s.evoClear or s.evoIntro or getmetatable(s) == EvolutionState then
      n = n + 1
    end
  end
  return n
end

local function runBatch(cancelFirst)
  local game, party, battle = newGame(2)
  restores = 0
  local finished = false
  local leveled = { [party[1]] = true, [party[2]] = true }
  Evolution.checkParty(game, function() finished = true end, leveled)
  local intros, seen = 0, {}
  local secondIntro
  local restoresBeforeSecond
  for frame = 1, 6000 do
    if finished then break end
    local top = game.stack:top()
    if top and top.evoIntro and not seen[top] then
      seen[top] = true
      intros = intros + 1
      if intros == 2 then
        secondIntro = {
          below = game.stack.states[indexOf(game, top) - 1],
          base = game.stack:visibleBase(),
          battleAt = indexOf(game, battle),
        }
        restoresBeforeSecond = restores
      end
    end
    local key = A_KEY
    if cancelFirst and intros == 1 and getmetatable(top) == EvolutionState
       and top.t > 100 and not top.done then
      key = B_KEY
    elseif frame % 2 == 0 then
      key = nil
    end
    step(game, key)
  end
  return {
    game = game, party = party, battle = battle, finished = finished,
    intros = intros, second = secondIntro,
    restoresBeforeSecond = restoresBeforeSecond,
  }
end

for _, cancelFirst in ipairs({ false, true }) do
  local label = cancelFirst and "cancelled first mon" or "two evolutions"
  local r = runBatch(cancelFirst)
  eq(r.intros, 2, label .. ": both mons get an IsEvolvingText box")
  if check(r.second ~= nil, label .. ": the second intro box went up") then
    check(r.second.below and r.second.below.evoClear and r.second.below.isOpaque,
          label .. ": the second intro draws over an opaque blank screen")
    check(r.second.base > r.second.battleAt,
          label .. ": the battle screen is not drawn under the second intro")
    eq(r.restoresBeforeSecond, 0,
       label .. ": no map music between the two evolutions")
  end
  check(r.finished, label .. ": the batch finished")
  eq(r.game.stack:top(), r.battle, label .. ": the battle is top again")
  eq(leftovers(r.game), 0, label .. ": no evolution layers are left")
  eq(restores, 0, label .. ": the in-battle batch never restores map music")
  eq(r.party[2].species, "FIXMON_B", label .. ": the second mon evolved")
  eq(r.party[1].species, cancelFirst and "FIXMON_A" or "FIXMON_B",
     label .. ": the first mon's species")
end

for _, via in ipairs({ "ITEM", "TRADE" }) do
  local game, party, menu = newGame(1)
  restores = 0
  local finished, topAtDone = false, nil
  Evolution.evolve(game, party[1], "FIXMON_B", function()
    finished = true
    topAtDone = game.stack:top()
  end, via)
  local sawClear = false
  local realClear = Evolution.clearScreen
  Evolution.clearScreen = function(g, species)
    realClear(g, species)
    local top = g.stack:top()
    if top and top.evoClear and top.isOpaque then sawClear = true end
  end
  for frame = 1, 6000 do
    if finished then break end
    step(game, frame % 2 == 1 and A_KEY or nil)
  end
  check(finished, via .. ": the single evolution finished")
  eq(topAtDone, menu, via .. ": the caller's screen is top when onDone runs")
  eq(leftovers(game), 0, via .. ": no evolution layers are left")
  eq(restores, 1, via .. ": map music comes back once after the result box")
  Evolution.clearScreen = realClear
  check(sawClear, via .. ": the screen clears once the result box closes")
end

T.finish()
