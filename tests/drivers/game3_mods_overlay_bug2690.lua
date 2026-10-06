local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_mods_overlay_bug2690"

local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  print((failures == 0 and "PASS" or "FAIL") .. " game3_mods_overlay_bug2690 failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
  U.wait(10)
end

local function try(label, fn)
  local ok, err = xpcall(fn, debug.traceback)
  if not ok then
    print("[driver] " .. label .. " error: " .. tostring(err))
    failures = failures + 1
  end
  return ok
end

local Chrome = require("src.ui.game3.chrome")
local FrlgFont = require("src.ui.game3.frlg_font")

local function recordFrame(game, shot)
  local log = {}
  local real = { std = Chrome.stdFrame, fixed = Chrome.fixedStdFrame,
    dlg = Chrome.dialogueFrame, draw = FrlgFont.draw }
  Chrome.fixedStdFrame = function(...)
    for i = #log, 1, -1 do log[i] = nil end
    return real.fixed(...)
  end
  Chrome.stdFrame = function(l, t, w, h, ...)
    log[#log + 1] = { frame = true, l = l, t = t, w = w, h = h }
    return real.std(l, t, w, h, ...)
  end
  Chrome.dialogueFrame = function(...)
    local l, t, w, h = Chrome.dialogueWindow()
    log[#log + 1] = { frame = true, l = l, t = t, w = w, h = h }
    return real.dlg(...)
  end
  FrlgFont.draw = function(s, x, y, ...)
    log[#log + 1] = { s = tostring(s), x = x, y = y }
    return real.draw(s, x, y, ...)
  end
  check(U.still(game, shot), "shot " .. shot:match("[^/]+$"))
  Chrome.stdFrame, Chrome.fixedStdFrame = real.std, real.fixed
  Chrome.dialogueFrame, FrlgFont.draw = real.dlg, real.draw
  return log
end

local function inside(e, f)
  return f and e and e.x >= f.l * 8 and e.x < (f.l + f.w) * 8
    and e.y >= f.t * 8 and e.y + FrlgFont.GLYPH_HEIGHT <= (f.t + f.h) * 8
end

local function verify(game, label, lines, confirm, shot)
  local log = recordFrame(game, DIR .. "/" .. shot)
  local msgFrame, ynFrame
  for _, e in ipairs(log) do
    if e.frame and e.l == 21 then ynFrame = e
    elseif e.frame and e.l <= 2 then msgFrame = e end
  end
  check(msgFrame ~= nil, label .. ": message frame drawn")
  local prevY
  for _, s in ipairs(lines) do
    local hit
    for _, e in ipairs(log) do
      if e.s == s then hit = e end
    end
    check(inside(hit, msgFrame), label .. ": '" .. s .. "' inside the message frame")
    if hit and prevY then check(hit.y - prevY >= 14, label .. ": rows 14px+ apart") end
    prevY = hit and hit.y
  end
  if confirm then
    local yes, no
    for _, e in ipairs(log) do
      if e.s == "YES" then yes = e elseif e.s == "NO" then no = e end
    end
    check(inside(yes, ynFrame) and inside(no, ynFrame), label .. ": YES/NO inside a left-21 std frame")
    check(ynFrame and msgFrame and (ynFrame.t + ynFrame.h < msgFrame.t - 1
      or msgFrame.l + msgFrame.w < ynFrame.l - 1),
      label .. ": YES/NO frame clears the message frame")
    check(ynFrame and ynFrame.t - 1 > 5, label .. ": YES/NO frame clears the title frame")
  end
  check(msgFrame and msgFrame.t - 1 > 5, label .. ": message frame clears the title frame")
  for _, e in ipairs(log) do
    if e.s and e.y and e.y + FrlgFont.GLYPH_HEIGHT > 160 then
      check(false, label .. ": '" .. e.s .. "' drawn off screen at y=" .. e.y)
    end
  end
end

local function overlays(game)
  local ModManager = require("src.ui.game3.mod_manager")
  ModManager.show({ game = game, session = game.session })
  U.wait(20)
  if not check(ModManager.isOpen(), "START > MODS manager open") then return end
  local m = ModManager._mgr
  check(U.still(game, DIR .. "/manager_list.png"), "shot manager_list.png")

  m:openConfirm({ "RESTART NOW?" }, function() end)
  local drew, err = pcall(ModManager.draw)
  check(drew, "manager draw does not raise " .. tostring(err or ""))
  U.wait(4)
  verify(game, "restart", { "RESTART NOW?" }, true, "confirm_restart_now.png")
  U.tap(game, "down")
  U.wait(4)
  check(m.overlay and m.overlay.index == 2, "restart: DOWN moves the cursor to NO")
  U.tap(game, "b")
  U.wait(4)
  check(m.overlay == nil, "restart: B closes the confirm")

  local nmf = { "NOT MADE FOR", "THIS GAME.", "TRY IT ANYWAY?" }
  m:openConfirm(nmf, function() end)
  U.wait(4)
  verify(game, "not made for", nmf, true, "confirm_not_made_for_this_game.png")
  U.tap(game, "b")
  U.wait(4)

  local exp = { "EXPERIMENTAL MOD", "THIS MOD IS MARKED", "EXPERIMENTAL.", "ENABLE ANYWAY?" }
  m:openConfirm(exp, function() end)
  U.wait(4)
  verify(game, "experimental", exp, true, "confirm_experimental_mod.png")
  U.tap(game, "b")
  U.wait(4)

  m:openBlocked({ missing = { "basemod" }, conflicts = {}, badVersion = {} })
  U.wait(4)
  verify(game, "blocked", { "NEEDS basemod", "NOT INSTALLED" }, false, "notice_needs_basemod.png")
  U.tap(game, "a")
  U.wait(4)
  check(m.overlay == nil, "blocked: A closes the notice")

  local QuantityBox = require("src.ui.QuantityBox")
  local got
  m.game.stack:push(QuantityBox.new(m.game, { max = 9, start = 3, onDone = function(q) got = q end }))
  U.wait(4)
  verify(game, "qty", { "HOW MANY?" }, false, "qty_prompt_how_many.png")
  U.tap(game, "a")
  U.wait(4)
  check(got == 3, "qty: A confirms the value")
  ModManager.close()
  U.wait(4)
end

local function controls(game)
  local Controls = require("src.ui.game3.controls_menu")
  Controls.show({ game = game })
  U.wait(10)
  if not check(Controls.open, "CONTROLS screen open") then return end
  local texts = {}
  local realDraw = FrlgFont.draw
  FrlgFont.draw = function(s, ...)
    texts[#texts + 1] = tostring(s)
    return realDraw(s, ...)
  end
  local drew, err = pcall(Controls.draw)
  FrlgFont.draw = realDraw
  check(drew, "controls draw does not raise " .. tostring(err or ""))
  local sawLabel = false
  for _, s in ipairs(texts) do
    if s:find("SET", 1, true) then sawLabel = true end
  end
  check(sawLabel, "controls help bar drawn")
  check(U.still(game, DIR .. "/controls_screen.png"), "shot controls_screen.png")
  Controls.close()
  U.wait(4)
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  check(game.boot ~= nil, "boot reached")
  try("new_game", function() game:_handleBootAction({ action = "new_game", name = "RED" }) end)
  for _ = 1, 600 do
    if game.phase == "field" then break end
    U.wait(1)
  end
  check(game.phase == "field", "reached the overworld")
  U.wait(60)
  try("overlays", function() overlays(game) end)
  try("controls", function() controls(game) end)
  return finish()
end
