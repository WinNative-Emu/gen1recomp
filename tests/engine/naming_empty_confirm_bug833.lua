-- Empty confirm on the naming screen (#833).  DisplayNamingScreen seeds
-- wStringBuffer with '@' (engine/menus/naming_screen.asm), so a name the
-- player never typed reads back as the terminator, and every caller checks
-- that first byte: AskName falls through to .declinedNickname and copies the
-- species name over the nick slot (vanilla's "un-nicknamed", which this port
-- models as mon.nickname == nil, src/save_convert/GenSave.lua), while
-- DisplayNameRaterScreen takes .playerCancelled and keeps the old nickname.
-- Nothing in the original invents a letter, so NamingScreen:confirm must hand
-- the caller "" rather than the literal "A" when nothing was typed -- both via
-- START and via the ED cell.  Player/rival naming (oak_speech2.asm
-- ChoosePlayerName never accepts an empty name) re-opens the grid, and
-- opts.default still covers the Name Rater cancel.
--   luajit tests/engine/naming_empty_confirm_bug833.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

-- NamingScreen reaches for Sound at the top of the module; seeding
-- package.loaded before it loads keeps the suite ROM-free and silent.
package.loaded["src.core.Sound"] = { play = function() end }

local NamingScreen = require("src.ui.NamingScreen")

-- The three things the screen touches: a stack it pops itself off, an input
-- queue that is exactly one fixed step of edges, and a non-nil `data` for the
-- click cue.
local function newGame()
  local game = { data = {} }
  game.stack = {
    states = {},
    push = function(self, s) table.insert(self.states, s) end,
    pop = function(self) return table.remove(self.states) end,
    top = function(self) return self.states[#self.states] end,
  }
  game.input = {
    queue = {},
    wasPressed = function(self, btn) return self.queue[btn] or false end,
    isDown = function() return false end,
  }
  return game
end

-- builds a pushed screen plus a `result` table the onDone writes into
local function newScreen(opts)
  local game = newGame()
  local result = { fired = false, name = nil }
  opts = opts or {}
  opts.onDone = function(n)
    result.fired = true
    result.name = n
  end
  local ns = NamingScreen.new(game, opts)
  game.stack:push(ns)
  return ns, game, result
end

-- one fixed step with `btn` on its edge
local function press(ns, game, btn)
  game.input.queue = { [btn] = true }
  ns:update(1 / 60)
  game.input.queue = {}
end

-- the ED cell's coordinates on whatever grid the screen is showing
local function edCell(ns)
  for r, row in ipairs(ns:grid()) do
    for c, cell in ipairs(row) do
      if cell == "ED" then return r, c end
    end
  end
  return nil, nil
end

-- ---------------------------------------------------------------- START, nothing typed
-- The nickname callers (BattleState caught-mon, Commands gift/starter) push
-- the screen with only title/maxLen/onDone: no presets, no default.
local ns, game, res = newScreen({ title = "NICK?", maxLen = 10 })
press(ns, game, "start")
check(res.fired, "START confirms an untyped name")
eq(res.name, "", "START with nothing typed delivers the empty name")
check(res.name ~= "A", "an untyped confirm does not invent the letter A (#833)")
eq(#game.stack.states, 0, "confirm pops the naming screen")

-- the caller-shaped guard both nickname sites use
local mon = {}
if res.name and #res.name > 0 then mon.nickname = res.name end
check(mon.nickname == nil,
      "an empty name leaves the mon un-nicknamed, so evolution can rename it")

-- ---------------------------------------------------------------- ED cell, nothing typed
ns, game, res = newScreen({ title = "NICK?", maxLen = 10 })
local edRow, edCol = edCell(ns)
eq(edRow, 5, "ED sits on row 5 of the vanilla grid (data/text/alphabets.asm)")
eq(edCol, 9, "ED is the last cell of that row")
ns.row, ns.col = edRow, edCol
press(ns, game, "a")
check(res.fired, "A on the ED cell confirms")
eq(res.name, "", "ED with nothing typed delivers the empty name too")

-- ---------------------------------------------------------------- typed names are untouched
ns, game, res = newScreen({ title = "NICK?", maxLen = 10 })
ns.row, ns.col = 1, 1 -- "A"
press(ns, game, "a")
press(ns, game, "start")
eq(res.name, "A", "a genuinely typed A still comes back as A")

-- ---------------------------------------------------------------- player / rival re-prompt
-- engine/movie/oak_speech/oak_speech2.asm:20
ns, game, res = newScreen({ title = "YOUR NAME?", maxLen = 7, presets = { "RED", "ASH" } })
ns.row, ns.col, ns.lower = 3, 4, true
press(ns, game, "start")
check(not res.fired, "an empty player/rival name does not confirm")
eq(#game.stack.states, 1, "the naming screen stays up on an empty START")
eq(ns.row, 1, "re-entry puts the cursor back on row 1")
eq(ns.col, 1, "re-entry puts the cursor back on column 1")
eq(ns.lower, true, "wAlphabetCase carries over the re-entry")
check((ns.whiteout or 0) > 0, "the re-entry whites the screen out")
ns.lower = false
press(ns, game, "a")
eq(#ns.glyphs, 0, "input is ignored while the screen is white")
for _ = 1, 60 do ns:update(1 / 60) end
eq(ns.whiteout, 0, "the whiteout ends")
local edR, edC = edCell(ns)
ns.row, ns.col = edR, edC
press(ns, game, "a")
check(not res.fired, "ED with nothing typed re-prompts too")
eq(#game.stack.states, 1, "the naming screen is still up after an empty ED")
for _ = 1, 60 do ns:update(1 / 60) end
ns.row, ns.col = 1, 1
press(ns, game, "a")
press(ns, game, "start")
check(res.fired, "a typed player name confirms")
eq(res.name, "A", "the typed name comes back, never presets[1]")
eq(#game.stack.states, 0, "a typed confirm pops the naming screen")

-- ---------------------------------------------------------------- default fallback (Name Rater)
-- DisplayNameRaterScreen jumps to .playerCancelled on '@' and keeps the
-- existing nickname; data/scripts/story4.lua passes it as opts.default.
ns, game, res = newScreen({ title = "RATTATA's name?", maxLen = 10, default = "SPLASH" })
press(ns, game, "start")
eq(res.name, "SPLASH", "an empty confirm with a default keeps the old nickname")

T.finish("naming_empty_confirm_bug833")
