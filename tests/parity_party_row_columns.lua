-- engine/menus/party_menu.asm:14
-- engine/menus/party_menu.asm:71
-- engine/menus/party_menu.asm:93
-- engine/menus/party_menu.asm:160
-- engine/pokemon/status_screen.asm:46
-- data/sgb/sgb_packets.asm:152
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local S = require("tests.harness").suite("parity party row columns")
local check, eq = S.check, S.eq

local Data = require("src.core.Data")
if not Data.maps then Data:load() end
local Font = require("src.render.Font")
Font.load(Data)

local PaletteFX = require("src.render.PaletteFX")
local HudTiles = require("src.render.HudTiles")
local Strings = require("src.core.Strings")
local PartyMenu = require("src.ui.PartyMenu")
local Pokemon = require("src.pokemon.Pokemon")

local NAME_COL = 3
local BAR_COL = NAME_COL + 1
local FRACTION_COL = BAR_COL + 9
local LEARN_COL = NAME_COL + 9

local function makeGame(species)
  local party = {}
  for i, sp in ipairs(species) do
    local mon = Pokemon.new(Data, sp, 20)
    mon.stats.hp = 266
    mon.hp = 266
    party[i] = mon
  end
  return {
    data = Data,
    save = { party = party, options = {} },
    stack = { push = function() end, pop = function() end,
              top = function() end },
  }, party
end

local function capture(menu)
  local bars, texts = {}, {}
  local realBar, realDraw, realGfx = HudTiles.drawHPBar, Font.draw, love.graphics.draw
  HudTiles.drawHPBar = function(data, tx, ty, mon, barType, grayFill, segments)
    bars[#bars + 1] = { tx = tx, ty = ty, segments = segments }
  end
  Font.draw = function(text, x, y, ...)
    texts[#texts + 1] = { text = text, x = x, y = y }
  end
  love.graphics.draw = function() end
  local ok, err = pcall(function() menu:draw() end)
  HudTiles.drawHPBar, Font.draw, love.graphics.draw = realBar, realDraw, realGfx
  check(ok, "PartyMenu:draw runs headless" .. (ok and "" or (": " .. tostring(err))))
  return bars, texts
end

local prevMode = PaletteFX.mode

do
  local game, party = makeGame({ "NIDOKING", "BULBASAUR", "PIDGEY" })
  local bars, texts = capture(PartyMenu.new(game, {}))
  eq(#bars, #party, "one HP bar per party row")
  for i, bar in ipairs(bars) do
    eq(bar.tx, BAR_COL, ("row %d HP: tile sits one column right of the name"):format(i))
    eq(bar.ty, i * 2 - 1, ("row %d bar sits on its HP row"):format(i))
    local capCol = bar.tx + 2 + (bar.segments or 6)
    check(capCol < FRACTION_COL,
          ("row %d bar cap (col %d) ends before the fraction (col %d)")
            :format(i, capCol, FRACTION_COL))
  end
  local fractions = 0
  for _, t in ipairs(texts) do
    if type(t.text) == "string" and t.text:match("^%s*%d+/%s*%d+$") then
      fractions = fractions + 1
      eq(t.x, FRACTION_COL * 8, "HP fraction prints nine columns right of the bar")
    elseif t.text == party[1].nickname or t.text == Data.pokemon.NIDOKING.name then
      eq(t.x, NAME_COL * 8, "nickname prints at column 3")
    end
  end
  eq(fractions, #party, "one HP fraction per party row")

  for _, mode in ipairs({ "gbc", "redpp" }) do
    PaletteFX.setMode(mode)
    local zones = PartyMenu.new(game, {}):sgbPalettes(game) or {}
    local tag = " [" .. PaletteFX.modeLabel(mode) .. "]"
    for i = 1, #party do
      local z = zones[2 + i] or {}
      eq(z.x, 5 * 8, ("row %d bar block starts at the packet's tile 5%s"):format(i, tag))
      eq(z.w, (11 - 5 + 1) * 8, ("row %d bar block ends at the packet's tile 11%s"):format(i, tag))
      eq(z.x, (BAR_COL + 1) * 8, ("row %d bar block starts on the bar's ':' tile%s"):format(i, tag))
    end
  end
end

local function learnRows(opts, species)
  local game = makeGame(species)
  local _, texts = capture(PartyMenu.new(game, opts))
  local able, notAble = Strings("ABLE"), Strings("NOT ABLE")
  local seen = { [able] = 0, [notAble] = 0 }
  for _, t in ipairs(texts) do
    if t.text == able or t.text == notAble then
      seen[t.text] = seen[t.text] + 1
      eq(t.x, LEARN_COL * 8, ("%q prints at column 12"):format(t.text))
    end
  end
  return seen[able], seen[notAble]
end

do
  local a, n = learnRows({ tmhm = { move = "SWORDS_DANCE", kind = "TM" } },
                         { "BULBASAUR", "MAGIKARP" })
  eq(a, 1, "TM list shows one ABLE row")
  eq(n, 1, "TM list shows one NOT ABLE row")
end

do
  local a, n = learnRows({ evoStone = "THUNDER_STONE" }, { "PIKACHU", "RATTATA" })
  eq(a, 1, "stone list shows one ABLE row")
  eq(n, 1, "stone list shows one NOT ABLE row")
end

PaletteFX.setMode(prevMode)
S.finish()
