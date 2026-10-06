package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.harness")
local Font = require("src.render.Font")
Font.load({ font = require("tests.fixture_data.font") })
local Theme = require("src.ui.Theme")
local TextBox = require("src.render.TextBox")
local Version = require("src.core.GameVersion")
local Timing = require("src.core.Timing")
package.loaded["src.core.Sound"] = { play = function() end, playPress = function() end }

local ARROW = Theme.moreArrow or 0xEE
local SPACE = 0x7F
local LINE = "ENTIRELY COMPLETEZ"
local HEAD = "YOUR DEX IS"

local function make(text, save)
  local pressed = false
  local game = {
    data = {}, save = save or { options = { textSpeed = 1 } },
    input = { wasPressed = function(_, key) return pressed == key end,
      isDown = function() return false end },
    stack = { pop = function() end },
  }
  local box = TextBox.new(game, text, function() end)
  return box, function(key)
    pressed = key or false
    box:update(1 / 60)
    pressed = false
  end
end

local function prompt(box, tick)
  for _ = 1, 400 do
    if box.waiting or box.done then return true end
    tick()
  end
  return false
end

local function drawn(box, blink)
  local drawCode, drawBox = Font.drawCode, Font.drawBox
  local out = {}
  Font.drawCode = function(code, x, y)
    out[#out + 1] = { code = code, x = x, y = y }
  end
  Font.drawBox = function() end
  local saved = box.blink
  box.blink = blink
  box:draw()
  box.blink = saved
  Font.drawCode, Font.drawBox = drawCode, drawBox
  return out
end

local function at(list, x, y)
  local codes = {}
  for _, g in ipairs(list) do
    if g.x == x and g.y == y then codes[#codes + 1] = g.code end
  end
  return codes
end

local bang = Font.encode("Z")[1]

local function has(codes, code)
  for _, c in ipairs(codes) do
    if c == code then return true end
  end
  return false
end

-- home/text.asm:262
for _, edition in ipairs({ "red", "blue", "yellow" }) do
  Version.set(edition)
  local box, tick = make(HEAD .. "\n" .. LINE .. "\vCONGRATULATIONS")
  T.check(prompt(box, tick) and box.contAdvance, edition .. " reaches the cont wait")
  local ax, ay = box:arrowPos()
  T.eq(#box.shown[2], 18, edition .. " bottom line is 18 tiles")
  local lit = at(drawn(box, 0), ax, ay)
  T.same(lit, { ARROW }, edition .. " arrow replaces the 18th glyph while lit")
  local dark = at(drawn(box, 30), ax, ay)
  T.same(dark, {}, edition .. " the cell is blank while the arrow blinks off")
  for _ = 1, Timing.TEXT_PRE_ADVANCE do tick() end
  tick("a")
  T.eq(box.shown[1][18], SPACE, edition .. " cont leaves a space in the scrolled line")
  T.eq(box.shown[1][17], Font.encode(LINE)[17], edition .. " the 17th glyph survives")
  for _ = 1, Timing.TEXT_SCROLL_PAIR do tick() end
  T.check(prompt(box, tick) and box.done, edition .. " completes")
  local after = drawn(box, 30)
  T.check(not has(at(after, ax, box.line1Y), bang),
    edition .. " scrolled line keeps no 18th glyph")
end

Version.set("red")
local plain, plainTick = make("SHORT LINE\nHERE")
T.check(prompt(plain, plainTick) and plain.done, "short page completes")
local ax, ay = plain:arrowPos()
local list = drawn(plain, 0)
T.same(at(list, ax, ay), { ARROW }, "short line still draws the arrow")
T.eq(#plain.shown[2], 4, "short line untouched")

Version.set("gold")
local gold, goldTick = make(HEAD .. "\n" .. LINE .. "\vNEXT",
  { generation = 2, options = { textSpeed = 1 } })
T.check(prompt(gold, goldTick) and gold.contAdvance, "gold reaches cont")
local gx = gold:arrowPos()
local gglyphs = at(drawn(gold, 0), gx, gold.line2Y)
T.same(gglyphs, { bang }, "gold keeps the glyph above its border-row arrow")
for _ = 1, Timing.TEXT_PRE_ADVANCE do goldTick() end
goldTick("a")
T.eq(gold.shown[#gold.shown - 1][18], bang, "gold cont keeps the glyph")
Version.set("red")

T.finish("textbox_arrow_cell_bug2674")
