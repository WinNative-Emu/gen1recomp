local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/rs_easy_chat_screen"
local KIND = tonumber(os.getenv("RS_EASY_CHAT_TYPE") or "13")

local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function until_(n, fn)
  for _ = 1, n do
    if fn() then return true end
    U.wait(1)
  end
  return fn()
end

local function shot(game, name)
  U.wait(2)
  U.shot(game, DIR .. "/" .. name .. ".png")
  U.wait(2)
end

local function enterWorld(game)
  local Message = require("src.ui.game3.message")
  local Warp = require("src.core.game3.warp")
  local Runtime = require("src.core.game3.runtime")
  pcall(function() game:_handleBootAction({ action = "new_game", name = "BRENDAN", gender = 0 }) end)
  U.wait(60)
  until_(600, function()
    if Message.isOpen and Message.isOpen() then U.tap(game, "b") end
    return not (Warp.isBusy() or (Message.isOpen and Message.isOpen()))
  end)
  return Runtime.getSession()
end

return function(g)
  local session = enterWorld(g)
  check(session ~= nil, "new game has a session")
  local Contracts = require("src.core.game3.rs.easy_chat_contracts")
  local Editor = require("src.ui.game3.rs.easy_chat_editor")
  local token = Contracts.prepare(session, KIND, { slot = 0, person = 0, variant = 0 })
  local closed = false
  local ok, err = pcall(Editor.show, { type = KIND, token = token, words = token.words, session = session,
    variant = token.variant, onDone = function() closed = true end })
  check(ok, "editor opens " .. tostring(err))
  check(until_(120, function() return Editor._state == "input" end), "editor reaches input")
  shot(g, "01_phrase_type" .. KIND)
  U.tap(g, "a")
  check(until_(120, function() return Editor._view == "groups" and not Editor._transition end), "group picker open")
  U.wait(10)
  shot(g, "02_groups_type" .. KIND)
  local bg = Editor._man.palettes.bg
  check(bg[82] ~= 0 and bg[83] ~= 0 and bg[84] ~= 0 and bg[96] ~= 0, "word group frame palette 5 loaded")
  check(Editor._man.titlePalette == 1, "title prints with palette 1")
  check(Editor._indicator.tile == 32, "indicator shows GROUP MODE in group mode (tile=" .. tostring(Editor._indicator.tile) .. ")")
  U.tap(g, "right")
  U.wait(10)
  U.tap(g, "a")
  check(until_(120, function() return Editor._view == "words" and not Editor._transition end), "word list open")
  U.wait(10)
  shot(g, "03_words_type" .. KIND)
  U.tap(g, "b")
  check(until_(120, function() return Editor._view == "groups" and not Editor._transition end), "back to groups")
  U.tap(g, "select")
  check(until_(120, function() return Editor._view == "groups" and Editor._group.alpha and not Editor._transition end), "alphabet mode")
  U.wait(10)
  shot(g, "04_alpha_type" .. KIND)
  check(Editor._indicator.tile == 0, "indicator shows A-Z MODE in alphabet mode (tile=" .. tostring(Editor._indicator.tile) .. ")")
  U.tap(g, "b")
  check(until_(120, function() return Editor._view == "phrase" and not Editor._transition end), "back to phrase")
  U.tap(g, "b")
  U.wait(10)
  shot(g, "05_cancel_prompt_type" .. KIND)
  U.tap(g, "up")
  U.wait(4)
  U.tap(g, "a")
  check(until_(240, function() return closed end), "editor closes")

  local Trend = require("src.ui.game3.rs.trendy_phrase")
  local trendClosed = false
  ok, err = pcall(Trend.show, { session = session, words = { 0xFFFF, 0xFFFF }, onDone = function() trendClosed = true end })
  check(ok, "trendy phrase opens " .. tostring(err))
  check(until_(120, function() return Trend._state == "input" end), "trendy phrase reaches input")
  shot(g, "06_trendy_phrase")
  U.tap(g, "a")
  check(until_(120, function() return Trend._view == "groups" and not Trend._transition end), "trendy group picker open")
  U.wait(10)
  shot(g, "07_trendy_groups")
  U.tap(g, "b")
  check(until_(120, function() return Trend._view == "phrase" and not Trend._transition end), "trendy back to phrase")
  U.tap(g, "b")
  U.wait(4)
  U.tap(g, "up")
  U.wait(4)
  U.tap(g, "a")
  check(until_(240, function() return trendClosed end), "trendy phrase closes")

  local Mail = require("src.ui.game3.rs.mail_composer")
  local mailClosed = false
  local blank = {}
  for i = 1, 9 do blank[i] = 0xFFFF end
  ok, err = pcall(Mail.write, { words = blank }, { session = session, onClose = function() mailClosed = true end })
  check(ok, "mail composer opens " .. tostring(err))
  check(until_(120, function() return Mail._state == "input" end), "mail composer reaches input")
  shot(g, "08_mail")
  U.tap(g, "a")
  check(until_(120, function() return Mail._view == "groups" and not Mail._transition end), "mail group picker open")
  U.wait(10)
  shot(g, "09_mail_groups")
  U.tap(g, "b")
  check(until_(120, function() return Mail._view == "phrase" and not Mail._transition end), "mail back to phrase")
  U.tap(g, "b")
  U.wait(4)
  U.tap(g, "up")
  U.wait(4)
  U.tap(g, "a")
  check(until_(240, function() return mailClosed end), "mail composer closes")
  print((failures == 0 and "PASS" or "FAIL") .. " rs_easy_chat_screen failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
  U.wait(10)
end
