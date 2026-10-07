local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/drv2699"

local function until_(n, fn)
  for _ = 1, n do
    if fn() then return true end
    U.wait(1)
  end
  return fn()
end

return function(game)
  local pass = true
  local function check(cond, label)
    print((cond and "PASS " or "FAIL ") .. label)
    if not cond then pass = false end
    return cond
  end
  until_(900, function() return game.phase == "boot" and game.boot end)
  local ok, err = xpcall(function()
    local Runtime = require("src.core.game3.runtime")
    local Warp = require("src.core.game3.warp")
    local Message = require("src.ui.game3.message")
    pcall(function() game:_handleBootAction({ action = "new_game", name = "TAI", gender = 0 }) end)
    U.wait(60)
    until_(600, function()
      if Message.isOpen and Message.isOpen() then U.tap(game, "b") end
      return not (Warp.isBusy() or (Message.isOpen and Message.isOpen()))
    end)
    local s = Runtime.getSession()
    local C = require("src.core.game3.constants").active(s)
    local Bag = require("src.core.game3.bag")
    local Party = require("src.core.game3.party")
    local Pokemon = require("src.core.game3.pokemon")
    local ItemsData = require("src.core.game3.items_data")
    local PartyMenu = require("src.ui.game3.party_menu")
    local zig = C:require("species", "SPECIES_ZIGZAGOON")
    s.party = {}
    Party.giveMonToPlayer(s, zig, 18)
    Party.giveMonToPlayer(s, zig, 3)
    local full, small = s.party[1], s.party[2]
    check(full and Pokemon.moveSlotCount(full) == 4, "slot 1 Zigzagoon knows four moves")
    check(small and Pokemon.moveSlotCount(small) < 4, "slot 2 Zigzagoon has a free move slot")

    local tm, bad
    for id = C:require("items", "ITEM_TM01_FOCUS_PUNCH"), C:require("items", "ITEM_TM50_OVERHEAT") do
      local m = Pokemon.moveFromTmItem(id)
      if m and Pokemon.canLearnTmItem(zig, id) and not Pokemon.knowsMove(full, m) and not Pokemon.knowsMove(small, m) then
        tm = tm or id
      elseif m and not Pokemon.canLearnTmItem(zig, id) then
        bad = bad or id
      end
    end
    if not check(tm ~= nil and bad ~= nil, "found a compatible and an incompatible TM") then return end
    Bag.add(s.bag, tm, 2)
    Bag.add(s.bag, bad, 1)

    local function open(item)
      PartyMenu.show(s.party, nil, { session = s, bag = s.bag, item = item, mode = "use" })
      U.wait(30)
      PartyMenu.mode = "use"
    end
    local function text() return tostring(PartyMenu._messageText or PartyMenu._yesNoPrompt or "") end
    local function waitMode(mode, n)
      return until_(n or 120, function() return PartyMenu.mode == mode end)
    end

    open(tm)
    PartyMenu.cursor = 1
    U.tap(game, "a")
    waitMode("message")
    check(text():find("wants to learn", 1, true) ~= nil, "four-move TM shows gOtherText_WantsToLearn")
    U.still(game, DIR .. "/2699_01_wants_to_learn.png")
    for _ = 1, 4 do
      if PartyMenu.mode == "yesno" then break end
      U.tap(game, "a")
      U.wait(10)
    end
    check(PartyMenu.mode == "yesno" and text():find("replaced with", 1, true) ~= nil,
      "delete-a-move yes/no prompt is up")
    U.still(game, DIR .. "/2699_02_replace_prompt.png")
    U.tap(game, "b")
    U.wait(10)
    check(PartyMenu.mode == "yesno" and text():find("Stop trying to teach", 1, true) ~= nil,
      "NO asks gOtherText_StopTryingTo")
    U.still(game, DIR .. "/2699_03_stop_trying.png")
    U.tap(game, "a")
    waitMode("message")
    check(text():find("did not learn", 1, true) ~= nil, "YES on stop shows gOtherText_DidNotLearnMove2")
    U.still(game, DIR .. "/2699_04_did_not_learn.png")
    check(Bag.get(s.bag, tm) == 2, "TM kept after not learning")
    PartyMenu.close()
    U.wait(20)

    open(bad)
    PartyMenu.cursor = 2
    U.tap(game, "a")
    waitMode("message")
    check(text():find("not compatible", 1, true) ~= nil, "incompatible TM shows gOtherText_NotCompatible")
    U.still(game, DIR .. "/2699_05_not_compatible.png")
    PartyMenu.close()
    U.wait(20)

    open(tm)
    PartyMenu.cursor = 2
    U.tap(game, "a")
    waitMode("message")
    check(text():find("learned", 1, true) ~= nil, "free-slot TM shows gOtherText_LearnedMove")
    U.still(game, DIR .. "/2699_06_learned.png")
    check(Pokemon.knowsMove(small, Pokemon.moveFromTmItem(tm)), "slot 2 knows the TM move")
    check(Bag.get(s.bag, tm) == 1, "TM count drops by one")
    PartyMenu.close()
  end, debug.traceback)
  if not ok then print("FAIL driver error: " .. tostring(err)); pass = false end
  love.event.quit(pass and 0 or 1)
  U.wait(10)
end
