local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/drv2729"

return function(game)
  local fails = 0
  local function result(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then fails = fails + 1 end
  end
  local function finish() love.event.quit(fails == 0 and 0 or 1) end

  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "TAI", gender = 0 })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local BattleBridge = require("src.core.game3.battle_bridge")
  local Battle = require("src.core.game3.battle")
  local Ui = require("src.core.game3.battle.ui")
  local version = os.getenv("POKEPORT_VERSION") or "sapphire"
  local C = require("src.core.game3.constants").of(version)
  local session = Runtime.getSession()
  result(session ~= nil, "field session exists")
  if not session then finish() return end
  local function sp(name) return C.species.byName["SPECIES_" .. name] end
  local function mv(name) return C.moves.byName["MOVE_" .. name] end

  session.party = {}
  Party.giveMon(session, sp("TREECKO"), 11, "TREECKO")
  local m = session.party[1]
  m.moves = { mv("POUND"), mv("LEER"), mv("ABSORB"), mv("QUICK_ATTACK") }
  m.pp = { 35, 30, 20, 30 }
  m.maxPp = { 35, 30, 20, 30 }

  local ok, err = BattleBridge.startWild(Runtime._mod, game, { species = sp("WURMPLE"), level = 3 }, {})
  result(ok == true, "battle started " .. tostring(err or ""))
  if not ok then finish() return end
  local lastTap, f = 0, 0
  local function at_command()
    return Battle.isActive() and Battle._phase == "command" and Ui._mode == "menu"
  end
  for _ = 1, 6000 do
    if at_command() then break end
    f = f + 1
    if Ui.dialogPending and Ui.dialogPending() and f - lastTap >= 14 then
      lastTap = f
      U.tap(game, "a")
    else
      U.wait(1)
    end
  end
  result(at_command(), "reached command menu")
  if not at_command() then finish() return end
  U.wait(30)
  local BattleChromeA = require("src.ui.game3.battle_chrome")
  local menu = BattleChromeA.menuFrameRects("menu", "rs")
  result(menu and menu[1][1] - 1 == 17, "action menu frame left border at tile 17")
  U.still(game, DIR .. "/2729_00_action_menu.png")
  U.tap(game, "a")
  U.wait(30)
  result(Ui._mode == "moves", "move menu open")
  U.tap(game, "down")
  U.wait(6)
  U.tap(game, "right")
  U.wait(10)
  result(Ui._moveIndex == 4, "cursor on QUICK ATTACK")

  local BattleChrome = require("src.ui.game3.battle_chrome")
  local Moves = require("src.core.game3.battle.moves")
  local P = require("src.core.game3.profile").forSession(session)
  local F = require(P.font.module)
  local drawn
  local orig = BattleChrome.drawMenuFrames
  result(BattleChrome.layout() == "rs", "battle chrome layout is rs")
  BattleChrome.drawMenuFrames = function(mode)
    drawn = BattleChrome.menuFrameRects(mode, BattleChrome.layout())
    return orig(mode)
  end
  for _ = 1, 2000 do
    if drawn then break end
    U.wait(1)
  end
  BattleChrome.drawMenuFrames = orig
  local left = drawn and drawn[1]
  result(left ~= nil, "move menu frame drawn")
  if left then
    local limit = (left[1] + left[3]) * 8
    result(limit == 168, "left move frame content ends at x=168 (got " .. limit .. ")")
    for i = 1, 4 do
      local label = Moves.displayName(m.moves[i])
      local x = 8 + 80 * ((i - 1) % 2)
      local right = x + F.measure(label)
      result(right <= limit, string.format("move %d %s right edge %d within %d", i, label, right, limit))
    end
  end
  U.still(game, DIR .. "/2729_01_quick_attack_move_menu.png")
  Battle.abort("run")
  U.wait(30)
  finish()
end
