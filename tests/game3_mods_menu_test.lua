#!/usr/bin/env luajit
-- Gen 3 MODS entry + FRLG mod-manager shell (docs/compose/spec/game3-mods-menu.md).
-- ROM-free: pure option rows, start-menu gating, ManagerState row models, and
-- the game3.stack push/close path. No GBA cache required.

package.path = "./?.lua;./?/init.lua;" .. package.path
local function romTextKey(n, i, j) return j and (n .. "[" .. i .. "][" .. j .. "]") or (n .. "[" .. i .. "]") end
local function romTextPlain(key) return key end
package.loaded["src.core.game3.rom_text"] = {
  plain = romTextPlain, box = romTextPlain, ascii = romTextPlain, has = function() return true end,
  key = romTextKey, at = function(n, i, j) return romTextKey(n, i, j) end,
  count = function() return 0 end, list = function() return {} end,
  lazy = function(map) return setmetatable({}, { __index = function(_, k) return map[k] end }) end,
}

local love = _G.love or require("tests.love_stub")
_G.love = love

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

print("[test] 1. OPTION row is always present with installed count")
local Rows = require("src.ui.game3.option_rows")
local function optionRow(ctx)
  for _, row in ipairs(Rows.build(ctx)) do
    if row.id == "mods" then return row end
  end
  return nil
end

local vanillaCtx = {
  options = { musicVol = 7, sfxVol = 7, musicFilter = 0, buttonMode = 0 },
  game = { modStatus = { available = {} } },
}
local modsRow = optionRow(vanillaCtx)
check(modsRow ~= nil, "mods row present on vanilla install")
check(modsRow and modsRow.activate ~= nil and modsRow.step == nil,
  "mods row is activate-only")
check(modsRow and tostring(modsRow.value(vanillaCtx)):find("0"), 
  "vanilla value reports 0 INSTALLED (got " ..
    tostring(modsRow and modsRow.value(vanillaCtx)) .. ")")

local withModsCtx = {
  options = vanillaCtx.options,
  game = {
    modStatus = {
      available = {
        { id = "a", name = "A", category = "TWEAK", enabled = true, state = "loaded" },
        { id = "b", name = "B", category = "TWEAK", enabled = true, state = "loaded" },
      },
    },
  },
}
local modsRow2 = optionRow(withModsCtx)
check(modsRow2 and tostring(modsRow2.value(withModsCtx)):find("2"),
  "value reports 2 INSTALLED")

local orderHasMods = false
for _, id in ipairs(Rows.ORDER) do
  if id == "mods" then orderHasMods = true end
end
check(orderHasMods, "mods listed in Rows.ORDER")

print("[test] 2. START menu MODS gate (normal field only)")
local StartMenu = require("src.ui.game3.start_menu")
local function entryIds()
  local out = {}
  for _, e in ipairs(StartMenu.ENTRIES or {}) do out[#out + 1] = e.id end
  return out
end
local function hasId(list, id)
  for _, v in ipairs(list) do
    if v == id then return true end
  end
  return false
end

StartMenu._game = { modStatus = { available = {} } }
StartMenu.show({ session = { bag = {}, party = {} }, game = StartMenu._game })
local ids = entryIds()
check(not hasId(ids, "mods"), "vanilla START has no MODS row")
check(hasId(ids, "option") and hasId(ids, "exit"), "vanilla START keeps OPTION/EXIT")
StartMenu.close(true)

StartMenu._game = {
  modStatus = {
    available = {
      { id = "a", name = "A", category = "TWEAK", enabled = true, state = "loaded" },
    },
  },
}
StartMenu.show({ session = { bag = {}, party = {} }, game = StartMenu._game })
ids = entryIds()
check(hasId(ids, "mods"), "START shows MODS when mods are discovered")
local oi, mi, ei
for i, id in ipairs(ids) do
  if id == "option" then oi = i end
  if id == "mods" then mi = i end
  if id == "exit" then ei = i end
end
check(oi and mi and ei and oi < mi and mi < ei, "MODS sits after OPTION, before EXIT")
StartMenu.close(true)

print("[test] 3. Manager list rows come from ManagerState.modRows")
local ManagerState = require("src.mods.ManagerState")
local statusStub = withModsCtx.game.modStatus
local modsStub = {
  status = function() return statusStub end,
}
local mgrGame = {
  modStatus = statusStub,
  mods = modsStub,
  save = { options = {} },
  stack = { pop = function() end },
  input = { wasPressed = function() return false end },
}
local mgr = ManagerState.new(mgrGame)
mgr:refresh()
local listRows = mgr:modRows()
local sawHeader, sawA = false, false
for _, row in ipairs(listRows) do
  if row.header then sawHeader = true end
  if row.mod and row.mod.id == "a" then sawA = true end
end
check(sawHeader and sawA, "modRows groups by category and lists mods")
check(mgr:rowsForScreen() ~= nil, "rowsForScreen exposes the model to Gen 3 chrome")

print("[test] 4. Toggle path still uses ManagerState.resolveToggle")
local r = ManagerState.resolveToggle({
  a = { id = "a", dependencySpecs = {}, conflictSpecs = {} },
}, "a", true, {})
check(r.apply.a == true, "resolveToggle enable lands on the target")
check(#r.alsoEnable == 0, "no phantom cascade for a leaf mod")

print("[test] 5. ModManager pushes/pops game3.stack")
local Stack = require("src.ui.game3.stack")
local ModManager = require("src.ui.game3.mod_manager")
local function stubGame(available)
  local status = { available = available or statusStub.available }
  return {
    modStatus = status,
    mods = { status = function() return status end },
    save = { options = {} },
    options = {},
    input = { wasPressed = function() return false end },
    writeOptions = function() end,
    returnToTitle = function() end,
  }
end
Stack.clear()
check(not ModManager.isOpen(), "closed before show")
local openerDepthAfterShow
do
  -- opener stays under the manager so B-close can return to it
  Stack.push("start", StartMenu, { hideBelow = false })
  ModManager.show({ game = stubGame() })
  openerDepthAfterShow = Stack.depth()
end
check(ModManager.isOpen(), "open after show")
check(Stack.has("mod_manager"), "mod_manager layer on the game3 stack")
check(openerDepthAfterShow == 2, "opener still on the stack under the manager")
ModManager.draw()
check(true, "draw with FRLG chrome did not raise")
ModManager.handleInput({ wasPressed = function() return false end })
check(ModManager.isOpen(), "inert input keeps the manager open")
-- B at the manager root is ManagerState:goBack → proxy stack:pop → close
ModManager.handleInput({
  wasPressed = function(_, btn) return btn == "b" end,
})
check(not ModManager.isOpen(), "B at root closes the manager")
check(not Stack.has("mod_manager"), "close pops the manager layer")
check(Stack.has("start") and Stack.depth() == 1,
  "stack depth returns to the opener")
Stack.clear()

print("[test] 6. START confirm and OPTION activate open the manager")
StartMenu._game = stubGame()
StartMenu.show({ session = { bag = {}, party = {} }, game = StartMenu._game })
local modsIndex
for i, e in ipairs(StartMenu.ENTRIES) do
  if e.id == "mods" then modsIndex = i end
end
check(modsIndex ~= nil, "MODS entry present before confirm")
StartMenu.cursor = modsIndex
StartMenu.confirm()
check(ModManager.isOpen() and Stack.has("mod_manager"),
  "START confirm on MODS opens the manager")
ModManager.close()
StartMenu.close(true)

local activateRow = optionRow(withModsCtx)
local activated = false
local actGame = stubGame()
activateRow.activate({ game = actGame, session = {}, options = vanillaCtx.options })
check(ModManager.isOpen(), "OPTION activate opens the manager")
ModManager.close()
check(not ModManager.isOpen(), "manager closed after OPTION path")

print("[test] 7. Link / Union / Safari start lists stay retail")
package.loaded["src.core.game3.link"] = { link = {}, inLinkRoom = function() return true end }
StartMenu.show({ session = { bag = {}, party = {} }, game = stubGame() })
check(not hasId(entryIds(), "mods"), "link start menu has no MODS")
StartMenu.close(true)
package.loaded["src.core.game3.link"] = nil

package.loaded["src.core.game3.map"] = { current = "FR_UNION_ROOM" }
StartMenu.show({ session = { bag = {}, party = {}, map = "FR_UNION_ROOM" }, game = stubGame() })
check(not hasId(entryIds(), "mods"), "union room start menu has no MODS")
StartMenu.close(true)
package.loaded["src.core.game3.map"] = nil

package.loaded["src.core.game3.safari"] = { isActive = function() return true end }
StartMenu.show({ session = { bag = {}, party = {} }, game = stubGame() })
check(not hasId(entryIds(), "mods"), "safari start menu has no MODS")
StartMenu.close(true)
package.loaded["src.core.game3.safari"] = nil

print("[test] 8. Nested NamingScreen / QuantityBox are bridged, not dropped")
local NamingScreen = require("src.ui.NamingScreen")
local QuantityBox = require("src.ui.QuantityBox")
local named, qtyDone = nil, nil
local g = stubGame()
ModManager.show({ game = g })
local mproxy = ModManager._mgr.game
mproxy.stack:push(NamingScreen.new(mproxy, {
  title = "NAME?", maxLen = 10,
  onDone = function(name) named = name end,
}))
check(named == nil and require("src.ui.game3.naming").isOpen(),
  "NamingScreen routes to Gen 3 naming modal")
require("src.ui.game3.naming").close("ALPHA")
check(named == "ALPHA", "naming onDone delivers the typed name")

mproxy.stack:push(QuantityBox.new(mproxy, {
  max = 9, start = 3,
  onDone = function(q) qtyDone = q end,
}))
check(ModManager._prompt and ModManager._prompt.kind == "qty",
  "QuantityBox becomes an FRLG qty prompt")
ModManager.handleInput({ wasPressed = function(_, b) return b == "a" end })
check(qtyDone == 3, "qty prompt confirms the current value")
ModManager.close()

print("[test] 9. APPLY & RESTART restarts the process like Gen 1/2 (#2691)")
local restarts = 0
local realHostShell = package.loaded["src.core.HostShell"]
package.loaded["src.core.HostShell"] = { restart = function() restarts = restarts + 1 end }
local returned = false
local g2 = stubGame()
g2.returnToTitle = function() returned = true end
ModManager.show({ game = g2 })
ModManager._mgr:restartGame()
check(restarts == 1, "restartGame reaches HostShell.restart")
check(not returned, "restartGame does not soft-return to the Gen 3 title")
check(not ModManager.isOpen(), "restart closes the manager (open flag not stuck)")

local Game3 = require("src.core.Game3")
check(type(Game3.restartWithMods) == "function", "Game3 defines restartWithMods")
local g3r = stubGame()
g3r.restartWithMods = Game3.restartWithMods
local titled = false
g3r.returnToTitle = function() titled = true end
restarts = 0
ModManager.show({ game = g3r })
ModManager._mgr:restartGame()
check(restarts == 1 and not titled, "Game3:restartWithMods goes through HostShell.restart")
check(not ModManager.isOpen(), "Game3 restart path closes the manager")
package.loaded["src.core.HostShell"] = realHostShell

ModManager.show({ game = stubGame() })
check(ModManager.isOpen(), "manager can re-open after APPLY & RESTART")
ModManager.close()

print("[test] 9b. Title-screen manager (no save yet) writes the live Game3.options (#2691)")
do
  local SaveData = require("src.core.SaveData")
  local status = { available = {
    { id = "a", name = "A", category = "TWEAK", enabled = true, state = "loaded" },
    { id = "b", name = "B", category = "TWEAK", enabled = true, state = "loaded" },
  } }
  local written
  local gt = {
    modStatus = status,
    mods = {
      status = function() return status end,
      setEnabled = function(_, id, en)
        for _, m in ipairs(status.available) do
          if m.id == id then m.enabled = en end
        end
        return true
      end,
    },
    save = nil,
    options = {},
    input = { wasPressed = function() return false end },
    writeOptions = function(self) written = self.options end,
  }
  ModManager.show({ game = gt })
  local m = ModManager._mgr
  m:commitToggle({ a = false })
  check(SaveData.modEnabled(gt.options, "a", m:enableScope()) == false,
    "toggle from the title mirrors into Game3.options")
  m:moveOrder(m.byId.b, -1)
  local order = SaveData.modOrder(gt.options) or {}
  check(order[1] == "b", "load-order move from the title lands in Game3.options")
  check(written == gt.options, "persistOptions writes the live Game3.options table")
  ModManager.close()
end

print("[test] 10. Options scroll uses ManagerState's 0-based window")
do
  local g3 = stubGame({
    { id = "o1", name = "O1", category = "TWEAK", enabled = true, state = "loaded" },
    { id = "o2", name = "O2", category = "TWEAK", enabled = true, state = "loaded" },
    { id = "o3", name = "O3", category = "TWEAK", enabled = true, state = "loaded" },
    { id = "o4", name = "O4", category = "TWEAK", enabled = true, state = "loaded" },
    { id = "o5", name = "O5", category = "TWEAK", enabled = true, state = "loaded" },
    { id = "o6", name = "O6", category = "TWEAK", enabled = true, state = "loaded" },
  })
  ModManager.show({ game = g3 })
  local m = ModManager._mgr
  m.screen = "options"
  m.optionRows = {
    { id = "a", label = "A", value = function() return "1" end },
    { id = "b", label = "B", value = function() return "2" end },
    { id = "c", label = "C", value = function() return "3" end },
    { id = "d", label = "D", value = function() return "4" end },
    { id = "e", label = "E", value = function() return "5" end },
    { id = "f", label = "F", value = function() return "6" end },
  }
  m.cursor = 5
  m.scroll = 1
  ModManager.draw()
  check(true, "options draw with 0-based scroll did not raise")
  check((m.scroll or 0) + 1 == 2, "options first row is scroll+1 (0-based scroll)")
  ModManager.close()
end

print("[test] 11. List view is a sticky 7-row window (not ManagerState's 11)")
do
  local many = {}
  for i = 1, 15 do
    many[i] = {
      id = "m" .. i, name = "M" .. i, category = "TWEAK",
      enabled = true, state = "loaded",
    }
  end
  ModManager.show({ game = stubGame(many) })
  local m = ModManager._mgr
  -- ManagerState clamps to LIST_ROWS=11; we must stay on a 7-row follow
  for step = 1, 8 do
    m:moveCursor(1)
  end
  ModManager.draw()
  local first = ModManager._viewFirst or 1
  check(m.cursor >= first and m.cursor <= first + 6,
    "cursor stays inside the 7-row view (cursor=" .. tostring(m.cursor) ..
      " first=" .. tostring(first) .. ")")
  check(first >= 1 and first <= m.cursor,
    "view scrolls one row at a time, cursor never parks off screen")
  ModManager.close()
end

print("[test] 11b. Overlays print inside their own frames (#2690)")
do
  local Chrome = require("src.ui.game3.chrome")
  local FrlgFont = require("src.ui.game3.frlg_font")
  local log = {}
  local real = {
    std = Chrome.stdFrame, fixed = Chrome.fixedStdFrame, user = Chrome.userFrame,
    dlg = Chrome.dialogueFrame, draw = FrlgFont.draw, glyph = FrlgFont.drawGlyph,
  }
  Chrome.stdFrame = function(l, t, w, h) log[#log + 1] = { frame = true, l = l, t = t, w = w, h = h } end
  Chrome.fixedStdFrame = function() end
  Chrome.userFrame = function() end
  Chrome.dialogueFrame = function()
    local l, t, w, h = Chrome.dialogueWindow()
    log[#log + 1] = { frame = true, dlg = true, l = l, t = t, w = w, h = h }
  end
  FrlgFont.draw = function(s, x, y) log[#log + 1] = { s = tostring(s), x = x, y = y } return 0 end
  FrlgFont.drawGlyph = function(id, x, y) log[#log + 1] = { glyph = id, x = x, y = y } return 0 end

  local function inside(e, f)
    return f and e.x >= f.l * 8 and e.x < (f.l + f.w) * 8
      and e.y >= f.t * 8 and e.y + FrlgFont.GLYPH_HEIGHT <= (f.t + f.h) * 8
  end
  local function find(s)
    for _, e in ipairs(log) do if e.s == s then return e end end
  end

  local function layout(label, setup, expect, confirm)
    for i = #log, 1, -1 do log[i] = nil end
    ModManager.show({ game = stubGame() })
    local m = ModManager._mgr
    setup(m)
    ModManager.draw()
    local msgFrame, ynFrame
    for _, e in ipairs(log) do
      if e.frame and e.l == 21 then ynFrame = e
      elseif e.frame and e.l == 2 then msgFrame = e end
    end
    check(msgFrame ~= nil, label .. ": message frame drawn")
    local prevY
    for _, s in ipairs(expect) do
      local e = find(s)
      check(e and inside(e, msgFrame), label .. ": '" .. s .. "' inside the message frame"
        .. (e and (" (y=" .. e.y .. ")") or " (missing)"))
      if e and prevY then
        check(e.y - prevY >= 14, label .. ": message rows at least 14px apart")
      end
      prevY = e and e.y
    end
    if confirm then
      check(ynFrame ~= nil and ynFrame.w == 6 and ynFrame.h == 4,
        label .. ": YES/NO std frame at left 21")
      local yes, no = find("YES"), find("NO")
      check(yes and no and inside(yes, ynFrame) and inside(no, ynFrame),
        label .. ": YES/NO printed inside the YES/NO frame")
      check(ynFrame and msgFrame and (ynFrame.t + ynFrame.h < msgFrame.t - 1
        or msgFrame.l + msgFrame.w < ynFrame.l - 1),
        label .. ": YES/NO frame clears the message frame border")
      check(ynFrame and ynFrame.t - 1 > 5, label .. ": YES/NO frame clears the title frame border"
        .. (ynFrame and (" (top=" .. ynFrame.t .. ")") or ""))
      local arrow
      for _, e in ipairs(log) do
        if e.glyph and ynFrame and e.x == ynFrame.l * 8 then arrow = e end
      end
      check(arrow and yes and arrow.y == yes.y, label .. ": cursor sits on YES")
    elseif confirm == false then
      check(ynFrame == nil, label .. ": no YES/NO frame for an OK notice")
    end
    check(msgFrame and msgFrame.t - 1 > 5, label .. ": message frame clears the title frame border"
      .. (msgFrame and (" (top=" .. msgFrame.t .. ")") or ""))
    for _, e in ipairs(log) do
      if e.s and e.y then
        check(e.y + FrlgFont.GLYPH_HEIGHT <= 160, label .. ": '" .. e.s .. "' on screen")
      end
    end
    ModManager._prompt = nil
    ModManager.close()
  end

  layout("restart", function(m)
    m:openConfirm({ "RESTART NOW?" }, function() end)
  end, { "RESTART NOW?" }, true)
  layout("not made for", function(m)
    m:openConfirm({ "NOT MADE FOR", "THIS GAME.", "TRY IT ANYWAY?" }, function() end)
  end, { "NOT MADE FOR", "THIS GAME.", "TRY IT ANYWAY?" }, true)
  layout("experimental", function(m)
    m:openConfirm({ "EXPERIMENTAL MOD", "THIS MOD IS MARKED", "EXPERIMENTAL.", "ENABLE ANYWAY?" },
      function() end)
  end, { "EXPERIMENTAL MOD", "THIS MOD IS MARKED", "EXPERIMENTAL.", "ENABLE ANYWAY?" }, true)
  layout("blocked", function(m)
    m:openBlocked({ missing = { "dep" }, conflicts = { "zz" }, badVersion = {} })
  end, { "NEEDS dep", "NOT INSTALLED", "CONFLICTS WITH", "zz", "DISABLE IT FIRST" }, false)
  layout("blocked long", function(m)
    m:openBlocked({ missing = { "d1", "d2", "d3", "d4" }, conflicts = {}, badVersion = {} })
  end, { "NEEDS d1", "NOT INSTALLED", "NEEDS d2" }, false)
  layout("qty", function(m)
    m.game.stack:push(QuantityBox.new(m.game, { max = 9, start = 4, onDone = function() end }))
  end, { "HOW MANY?" }, nil)
  local qtyValue = find("4")
  local qtyFrame
  for _, e in ipairs(log) do
    if e.frame and e.l == 21 then qtyFrame = e end
  end
  check(qtyFrame and qtyValue and inside(qtyValue, qtyFrame),
    "qty: value printed inside its own std frame")

  local wraps = 0
  local realWrap = FrlgFont.wrap
  FrlgFont.wrap = function(...) wraps = wraps + 1 return realWrap(...) end
  ModManager.show({ game = stubGame() })
  ModManager._mgr:openConfirm({ "EXPERIMENTAL MOD", "THIS MOD IS MARKED", "EXPERIMENTAL.", "ENABLE ANYWAY?" },
    function() end)
  ModManager.draw()
  check(wraps > 0, "overlay: first draw wraps the message lines")
  local afterFirst = wraps
  ModManager.draw()
  ModManager.draw()
  check(wraps == afterFirst, "overlay: later frames reuse the wrapped layout (wraps=" .. wraps .. ")")
  ModManager._mgr.game.stack:push(QuantityBox.new(ModManager._mgr.game, { max = 9, start = 4, onDone = function() end }))
  ModManager.draw()
  afterFirst = wraps
  ModManager.draw()
  check(wraps == afterFirst, "qty prompt: later frames reuse the wrapped layout")
  ModManager._prompt = nil
  ModManager.close()
  FrlgFont.wrap = realWrap

  Chrome.stdFrame, Chrome.fixedStdFrame, Chrome.userFrame = real.std, real.fixed, real.user
  Chrome.dialogueFrame, FrlgFont.draw, FrlgFont.drawGlyph = real.dlg, real.draw, real.glyph
end

print("[test] 11c. Keypad icons fall back to button words without a keypad sheet (Ruby/Sapphire)")
do
  local FrlgFont = require("src.ui.game3.frlg_font")
  local real = { sync = FrlgFont.sync, draw = FrlgFont.draw, measure = FrlgFont.measure, keypad = FrlgFont._keypad }
  local texts = {}
  FrlgFont.draw = function(s, x, y, opts) texts[#texts + 1] = { s = tostring(s), opts = opts } return 0 end
  FrlgFont.measure = function(s) return 6 * #tostring(s) end

  FrlgFont.sync = function() return { nativeLayout = "rs" } end
  check(FrlgFont.hasKeypadIcons() == false, "rs: no keypad icon sheet")
  local colors = { fg = { 1, 1, 1, 1 } }
  local ok, w = pcall(FrlgFont.drawKeypadIcon, 0x00, 10, 2, { colors = colors, small = true })
  check(ok, "rs: drawKeypadIcon does not raise " .. tostring(not ok and w or ""))
  check(texts[1] and texts[1].s == "A " and texts[1].opts.colors == colors and texts[1].opts.small == true,
    "rs: A_BUTTON draws the word 'A' in the caller's colors and face")
  check(w == 12, "rs: drawKeypadIcon returns the word width")
  check(FrlgFont.keypadIconWidth(0x0A) == 6 * #"UP/DN ", "rs: measure uses the word width")

  FrlgFont.sync = function() return nil end
  FrlgFont._keypad = nil
  check(FrlgFont.keypadIconWidth(0x04) == 6 * #"START " and FrlgFont._keypad == false,
    "missing sheet on a FRLG cache: measure-only caller gets the word width before any draw")
  FrlgFont._keypad = false
  texts = {}
  ok = pcall(FrlgFont.drawKeypadIcon, 0x04, 0, 0)
  check(ok and texts[1] and texts[1].s == "START ", "missing sheet on a FRLG cache: START word, no raise")
  FrlgFont._keypad = { getDimensions = function() return 128, 32 end }
  check(FrlgFont.hasKeypadIcons() == true, "frlg with a sheet keeps the icons")
  check(FrlgFont.keypadIconWidth(0x04) == FrlgFont.KEYPAD_ICONS[0x04].w, "frlg: icon width unchanged")

  FrlgFont.draw, FrlgFont.measure = real.draw, real.measure
  local font = { fg = FrlgFont._fg, widths = FrlgFont._widths, quads = FrlgFont._quads, icon = FrlgFont.drawKeypadIcon }
  FrlgFont._fg, FrlgFont._widths, FrlgFont._quads = font.fg or {}, font.widths or {}, font.quads or {}
  local seen = {}
  FrlgFont.drawKeypadIcon = function(id, _, _, opts)
    seen[#seen + 1] = { opts = opts, colors = opts and opts.colors, fg = opts and opts.colors and opts.colors.fg }
    return FrlgFont.KEYPAD_ICONS[id].w
  end
  local white = { fg = { 1, 1, 1, 1 } }
  FrlgFont.draw("{A_BUTTON}{B_BUTTON}", 0, 0, { colors = white })
  FrlgFont.draw("{START_BUTTON}", 0, 0, { colors = white })
  check(#seen == 3 and seen[1].opts == seen[2].opts and seen[2].opts == seen[3].opts
    and seen[1].colors == seen[3].colors and seen[1].opts ~= nil,
    "draw: icon opts/colors tables are reused across icons and calls (no per-icon allocation)")
  check(seen[1] and seen[1].fg == white.fg, "draw: icon colors carry the caller's fg")
  FrlgFont._fg, FrlgFont._widths, FrlgFont._quads, FrlgFont.drawKeypadIcon = font.fg, font.widths, font.quads, font.icon

  FrlgFont.sync, FrlgFont._keypad = real.sync, real.keypad

  local msrc = io.open("src/ui/game3/mod_manager.lua", "r"):read("*a")
  check(not msrc:find("KEY_WORDS", 1, true) and not msrc:find("_keypadOk", 1, true),
    "mod manager has no per-screen keypad fallback")
end

print("[test] 11d. Named colors map to the RS font palette slots on Ruby/Sapphire only")
do
  local FrlgFont = require("src.ui.game3.frlg_font")
  local P, C = FrlgFont.STDPAL, FrlgFont.COLOR
  FrlgFont.applyColorSlots(true)
  check(C.DARK_GRAY.fg == P[1] and C.DARK_GRAY.shadow == P[8], "rs: DARK_GRAY is DARK_GREY/LIGHT_GREY")
  check(C.RED.fg == P[2] and C.RED.shadow == P[8], "rs: RED is slot 2")
  check(C.BLUE.fg == P[4] and C.GREEN.fg == P[3], "rs: BLUE slot 4, GREEN slot 3")
  check(C.WHITE.fg == P[12] and C.WHITE.shadow == P[1], "rs: WHITE slot 12 over DARK_GREY")
  check(FrlgFont.COLOR_IDS.RED == 2 and FrlgFont.COLOR_IDS.BLUE == 4 and FrlgFont.COLOR_IDS.WHITE == 12,
    "rs: {COLOR} names use pokeruby charmap ids")
  FrlgFont.applyColorSlots(false)
  check(C.DARK_GRAY.fg == P[2] and C.DARK_GRAY.shadow == P[3], "frlg: DARK_GRAY back to 2/3")
  check(C.RED.fg == P[4] and C.RED.shadow == P[5] and C.BLUE.fg == P[8] and C.BLUE.shadow == P[3],
    "frlg: RED 4/5, BLUE 8/3")
  check(C.MALE.fg == P[9] and C.FEMALE.fg == P[5] and C.WHITE.fg == P[1] and C.WHITE.shadow == P[2],
    "frlg: gender and WHITE slots unchanged")
  check(FrlgFont.COLOR_IDS.RED == 4 and FrlgFont.COLOR_IDS.BLUE == 8 and FrlgFont.COLOR_IDS.WHITE == 1
    and FrlgFont.COLOR_IDS.DARK_GREY == nil, "frlg: COLOR_IDS restored")
end

print("[test] 12. New manager module does not draw with Gen 1 Font/Theme")
local src = io.open("src/ui/game3/mod_manager.lua", "r"):read("*a")
check(not src:find('require("src.render.Font")', 1, true),
  "no src.render.Font require")
check(not src:find('require("src.ui.Theme")', 1, true),
  "no src.ui.Theme require")
-- Match Gen 1 Font.draw, not FrlgFont.draw (shared substring).
check(not src:find("[^%w]Font%.draw"), "no Gen 1 Font.draw call")

if failed > 0 then
  print(string.format("[FAIL] %d check(s) failed", failed))
  os.exit(1)
end
print("ALL TESTS PASSED")
os.exit(0)
