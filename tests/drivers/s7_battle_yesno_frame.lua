local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or ".bazinga/BSA/10-07-26-01-sidebugs/shots/s7_battle_yesno_frame"

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
  local BattleText = require("src.core.game3.battle.battle_text")
  local Choice = require("src.ui.game3.choice")
  local BattleChrome = require("src.ui.game3.battle_chrome")
  local version = os.getenv("POKEPORT_VERSION") or "emerald"
  local C = require("src.core.game3.constants").of(version)
  local session = Runtime.getSession()
  result(session ~= nil, "field session exists")
  if not session then finish() return end
  local function sp(name) return C.species.byName["SPECIES_" .. name] end

  session.party = {}
  Party.giveMon(session, sp("TREECKO"), 11, "TREECKO")
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

  local layout = BattleChrome.layout()
  local expect = ({ frlg = "frlg", emerald = "emerald", rs = "rs" })[layout]
  print("layout " .. tostring(layout))
  result((version == "firered" or version == "leafgreen") == (layout == "frlg"), "battle chrome layout matches version (" .. tostring(layout) .. ")")

  Ui._mode = "none"
  Ui.askYesNo(BattleText.get("STRINGID_GIVENICKNAMECAPTURED", { opponentMon1 = "WURMPLE" }), function() end)
  for _ = 1, 600 do
    if Choice.isOpen() and Choice.style == "battle" then break end
    Ui.pump()
    U.wait(1)
  end
  result(Choice.isOpen() and Choice.style == "battle", "battle yes/no open")
  U.wait(20)
  U.tap(game, "down")
  U.wait(10)
  result(Choice.cursor == 2, "cursor on No")

  local withBox = DIR .. "/s7_01_" .. version .. "_yesno_cursor_on_no.png"
  local noBox = DIR .. "/s7_00_" .. version .. "_same_frame_without_yesno.png"
  U.still(game, withBox)
  local wasActive = Choice.active
  Choice.active = false
  U.still(game, noBox)
  Choice.active = wasActive

  local a = love.image.newImageData(love.filesystem.newFileData(assert(io.open(withBox, "rb")):read("*a"), "a.png"))
  local b = love.image.newImageData(love.filesystem.newFileData(assert(io.open(noBox, "rb")):read("*a"), "b.png"))
  local sx = math.floor(math.min(a:getWidth() / 240, a:getHeight() / 160))
  local ox, oy = (a:getWidth() - 240 * sx) / 2, (a:getHeight() - 160 * sx) / 2
  local minX, maxX, minY, maxY = 999, -1, 999, -1
  for y = 56, 119 do
    for x = 0, 239 do
      local px, py = ox + math.floor((x + 0.5) * sx), oy + math.floor((y + 0.5) * sx)
      local r1, g1, b1 = a:getPixel(px, py)
      local r2, g2, b2 = b:getPixel(px, py)
      if math.abs(r1 - r2) + math.abs(g1 - g2) + math.abs(b1 - b2) > 0.02 then
        if x < minX then minX = x end
        if x > maxX then maxX = x end
        if y < minY then minY = y end
        if y > maxY then maxY = y end
      end
    end
  end
  local wantLeft = (expect == "frlg") and 184 or 192
  result(math.floor(minX / 8) == wantLeft / 8, string.format("frame left edge in tile %d (x=%d) got x=%d", wantLeft / 8, wantLeft, minX))
  result(math.floor(maxX / 8) == 29, "frame right edge in tile 29 got x=" .. maxX)
  result(math.floor(minY / 8) == 8 and math.floor(maxY / 8) == 13, string.format("frame rows 8..13 got y %d..%d", minY, maxY))
  if expect == "rs" then
    local r, g, bb = a:getPixel(ox + math.floor(204 * sx), oy + math.floor(88 * sx))
    local r0, g0, b0 = a:getPixel(ox + math.floor(204 * sx), oy + math.floor(72 * sx))
    print(string.format("rs cursor sample no-row %.2f,%.2f,%.2f yes-row %.2f,%.2f,%.2f", r, g, bb, r0, g0, b0))
  end

  Choice.reset()
  Battle.abort("run")
  U.wait(30)
  finish()
end
