#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local function eq(a, b, msg)
  check(a == b, string.format("%s (%s == %s)", msg, tostring(a), tostring(b)))
end

do
  local ItemsData = require("src.core.game3.items_data")
  if not pcall(ItemsData.ensureLoaded) then
    ItemsData.installPack({ count = 4, items = {
      [275] = { name = "EON TICKET", pocket = "KEY_ITEMS", fieldUse = "key" },
      [370] = { name = "MYSTIC TICKET", pocket = "KEY_ITEMS", fieldUse = "key" },
      [371] = { name = "AURORA TICKET", pocket = "KEY_ITEMS", fieldUse = "key" },
      [376] = { name = "OLD SEA MAP", pocket = "KEY_ITEMS", fieldUse = "key" },
    } })
  end
end

local GameVersion = require("src.core.GameVersion")
GameVersion.set("emerald")
local Bag = require("src.core.game3.bag")
local Flags = require("src.core.game3.scripting.flags")
local C = require("src.core.game3.constants").of("emerald")

local store = { flags = {}, vars = {} }
local session = { version = "emerald", store = store, bag = Bag.new(), party = {}, modData = {} }
package.loaded["src.core.game3.scripting.space"] = { store = store }
package.loaded["src.core.game3.runtime"] = { getSession = function() return session end }

local Rse = require("src.core.game3.rse.init")
Rse.session = function() return session end
local Natives = require("src.core.game3.scripting.natives")
Natives.bind("emerald")
local NativesFrontier = require("src.core.game3.scripting.natives_frontier")
local FieldRse = require("src.core.game3.scripting.natives_field_rse")
local ListMenu = require("src.core.game3.scripting.natives_listmenu")

local VAR_0x8004 = 0x8004
local VAR_RESULT = 0x800D

local function newCtx() return { specialVars = {} } end

local function giveAll()
  for _, name in ipairs({ "ITEM_EON_TICKET", "ITEM_AURORA_TICKET", "ITEM_MYSTIC_TICKET", "ITEM_OLD_SEA_MAP" }) do
    Bag.add(session.bag, C:require("items", name), 1)
  end
  for _, name in ipairs({ "FLAG_MET_SCOTT_ON_SS_TIDAL", "FLAG_ENABLE_SHIP_SOUTHERN_ISLAND",
    "FLAG_ENABLE_SHIP_BIRTH_ISLAND", "FLAG_ENABLE_SHIP_NAVEL_ROCK", "FLAG_ENABLE_SHIP_FARAWAY_ISLAND" }) do
    Rse.setFlag(name, true, session)
  end
end

print("[test] 1. Seven destinations open the scrollable multichoice (pokeemerald/src/script_menu.c:503)")
giveAll()
local scrollCalls = {}
local realScroll = Natives.BY_NAME.ShowScrollableMultichoice
Natives.BY_NAME.ShowScrollableMultichoice = function(ctx)
  scrollCalls[#scrollCalls + 1] = Rse.specialVar(ctx, VAR_0x8004)
  return false
end
local Choice = require("src.ui.game3.choice")
local multiCalls = 0
local realMulti = Choice.multi
Choice.multi = function() multiCalls = multiCalls + 1 end
local ctx = newCtx()
pcall(NativesFrontier.ssTidalMultichoice, ctx, {})
eq(#NativesFrontier._ssTidal, 7, "all seven SS Tidal selections are built")
eq(#scrollCalls, 1, "ShowScrollableMultichoice runs once")
eq(scrollCalls[1], 11, "VAR_0x8004 is SCROLL_MULTI_SS_TIDAL_DESTINATION")
eq(multiCalls, 0, "the fixed six-row multichoice window is not opened")
Choice.multi = realMulti
Natives.BY_NAME.ShowScrollableMultichoice = realScroll

print("[test] 2. GetLilycoveSSTidalSelection maps the scroll row straight through")
for row = 0, 6 do
  local c = newCtx()
  Rse.setSpecialVar(c, VAR_RESULT, row)
  NativesFrontier.ssTidalSelection(c)
  eq(Rse.specialVar(c, VAR_RESULT), row, "row " .. row .. " keeps selection " .. row)
end

print("[test] 3. The scrollable window width comes from its text (pokeemerald/src/field_specials.c:2570)")
local realLabels, realPresent = FieldRse.scrollMultichoiceLabels, ListMenu.presentItems
FieldRse.scrollMultichoiceLabels = function()
  return { "SLATEPORT CITY", "BATTLE FRONTIER", "SOUTHERN ISLAND", "NAVEL ROCK", "BIRTH ISLAND", "FARAWAY ISLAND", "EXIT" }
end
local seen
ListMenu.presentItems = function(_, _, labels, layout) seen = { labels = labels, layout = layout } return false end
local c3 = newCtx()
Rse.setSpecialVar(c3, VAR_0x8004, 11)
realScroll(c3, {})
check(seen ~= nil, "the scroll list is presented")
eq(seen and seen.layout.width, nil, "no fixed template width is forced on the window")
eq(seen and seen.layout.left, 19, "template left column 19")
eq(seen and seen.layout.maxShowed, 6, "six rows on screen")
FieldRse.scrollMultichoiceLabels, ListMenu.presentItems = realLabels, realPresent

print("[test] 4. Fewer than seven destinations keep the plain multichoice")
session.bag = Bag.new()
Bag.add(session.bag, C:require("items", "ITEM_EON_TICKET"), 1)
Bag.add(session.bag, C:require("items", "ITEM_AURORA_TICKET"), 1)
Rse.setFlag("FLAG_ENABLE_SHIP_BIRTH_ISLAND", false, session)
scrollCalls = {}
Natives.BY_NAME.ShowScrollableMultichoice = function(c) scrollCalls[#scrollCalls + 1] = true return false end
pcall(NativesFrontier.ssTidalMultichoice, newCtx(), {})
local sel = NativesFrontier._ssTidal
eq(#sel, 4, "AURORA TICKET without FLAG_ENABLE_SHIP_BIRTH_ISLAND opens no route")
eq(sel[3], 2, "SOUTHERN ISLAND listed")
eq(#scrollCalls, 0, "four rows do not use the scrollable multichoice")
Natives.BY_NAME.ShowScrollableMultichoice = realScroll

if failed > 0 then
  print(string.format("FAILED %d check(s)", failed))
  os.exit(1)
end
print("game3_rse_ss_tidal_destinations_test: all passed")
