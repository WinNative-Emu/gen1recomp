-- engine/gfx/hp_bar.asm:81-135, engine/items/item_effects.asm:1208
--   tools/run_driver.sh red <identity> tests/drivers/hp_bar_speed_2723.lua <shotdir>
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR")
    or "/tmp/shots"
  local Pokemon = require("src.pokemon.Pokemon")
  local Bag = require("src.inventory.Bag")
  local PartyMenu = require("src.ui.PartyMenu")
  local BattleState = require("src.battle.BattleState")
  local Timing = require("src.core.Timing")
  local TextBox = require("src.render.TextBox")

  local pass, fail = 0, 0
  local function check(label, ok)
    if ok then pass = pass + 1 else fail = fail + 1 end
    print((ok and "PASS " or "FAIL ") .. label)
    return ok
  end
  local function top() return game.stack:top() end
  local function isPicker(s)
    return s ~= nil and (s.screenId == "PartyMenu" or getmetatable(s) == PartyMenu)
  end
  local function cursorTo(menu, want)
    for _ = 1, 40 do
      if not menu or menu.index == want then return menu and menu.index == want end
      U.tap(game, menu.index < want and "down" or "up")
      U.wait(3)
    end
    return menu.index == want
  end

  local lead = Pokemon.new(game.data, "MEWTWO", 100)
  lead.stats.hp = 415
  lead.hp = 1
  game.save.party = { lead }
  Bag.add(game.save, "MAX_POTION", 3)
  local maxHP = lead.stats.hp
  U.log(("lead MEWTWO 1/%d HP"):format(maxHP))
  check("lead is pinned to the reporter's 415 max HP", maxHP == 415)

  U.teleport(game, "PALLET_TOWN", 5, 6, "down")
  U.wait(10)

  local function openPickerFor(id)
    U.tap(game, "start")
    U.wait(10)
    local menu = top()
    if not (menu and menu.screenId == "StartMenu") then return nil end
    local itemRow
    for i, it in ipairs(menu.items or {}) do
      if it.label == "ITEM" then itemRow = i break end
    end
    if not itemRow or not cursorTo(menu, itemRow) then return nil end
    U.tap(game, "a")
    U.wait(10)
    local bag = top()
    if not (bag and bag.screenId == "BagMenu") then return nil end
    local bagRow
    for i, r in ipairs(bag.items or {}) do
      if r.value == id then bagRow = i break end
    end
    if not bagRow or not cursorTo(bag, bagRow) then return nil end
    U.tap(game, "a")
    U.wait(10)
    local ut = top()
    if ut and ut.items and ut.items[1] and ut.items[1].label == "USE" then
      cursorTo(ut, 1)
      U.tap(game, "a")
      U.wait(10)
    end
    local picker = top()
    if not isPicker(picker) then return nil end
    return picker
  end

  local picker = openPickerFor("MAX_POTION")
  check("party picker opened for MAX POTION", picker ~= nil)
  if picker then
    cursorTo(picker, 1)
    U.tap(game, "a")
    check("the fill started from 1 HP",
          picker.heal ~= nil and picker.heal.shown == 1)
    local expect = Timing.hpDrainFrames(1, maxHP, maxHP, true)
    local frames, jumps, last = 0, 0, 1
    local shot1, shot2 = false, false
    while picker.heal and frames < 2000 do
      local shown = picker.heal.shown
      if not shot1 and shown >= math.floor(maxHP / 3) then
        shot1 = true
        U.still(game, DIR .. "/2723_01_party_fill_third.png")
      elseif not shot2 and shown >= math.floor(maxHP * 2 / 3) then
        shot2 = true
        U.still(game, DIR .. "/2723_02_party_fill_two_thirds.png")
      end
      U.wait(1)
      frames = frames + 1
      if picker.heal then
        if picker.heal.shown - last > 1 then jumps = jumps + 1 end
        last = picker.heal.shown
      end
    end
    U.log(("party fill: %d frames, UpdateHPBar2 budget %d"):format(frames, expect))
    check(("party heal 1 -> %d runs the D + 2P + 6 budget (%d ~ %d)")
            :format(maxHP, frames, expect), math.abs(frames - expect) <= 2)
    check(("party heal 1 -> 415 is exactly 514 frames (got %d)"):format(frames),
          frames == 514 and expect == 514)
    check("party heal takes several seconds, not ~1.6", frames > 400)
    check("party heal shown HP climbs one point per step", jumps == 0)
    check("mon is at full HP after the fill", lead.hp == maxHP)
    for _ = 1, 60 do
      if not isPicker(top()) then break end
      U.wait(1)
    end
    local box
    for _ = 1, 400 do
      box = top()
      if getmetatable(box) == TextBox and box.done then break end
      U.wait(1)
    end
    check("heal message finished printing before the shot",
          getmetatable(box) == TextBox and box.done == true)
    U.still(game, DIR .. "/2723_03_party_heal_message.png")
  end

  for _ = 1, 30 do
    if top() == game.overworld then break end
    U.tap(game, "a")
    U.wait(8)
    if top() ~= game.overworld then U.tap(game, "b") U.wait(6) end
  end

  lead.moves = { { id = "SEISMIC_TOSS", pp = 20 } }
  U.teleport(game, "ROUTE_1", 5, 5, "down")
  local battle = BattleState.newWild(game, "CHANSEY", 60)
  battle.onFinish = function() end
  game.overworld:pushBattle(battle)
  for _ = 1, 200 do
    if battle.phase == "menu" then break end
    U.tap(game, "a")
    U.wait(4)
  end
  check("battle reached the move menu", battle.phase == "menu")
  local enemy = battle.enemy
  local eMax = enemy.mon.stats.hp
  U.log(("enemy CHANSEY L60 %d/%d HP"):format(enemy.mon.hp, eMax))
  check("enemy has more than 4 HP per bar pixel", eMax > 4 * 48)

  local startHP = enemy.mon.hp
  U.tap(game, "a")
  U.wait(10)
  U.tap(game, "a")
  local frames, started, shot = 0, false, false
  for _ = 1, 4000 do
    U.wait(1)
    if not started and (enemy.shownHP or startHP) < startHP then started = true end
    if started then
      frames = frames + 1
      if not shot and enemy.shownHP <= startHP - (startHP - enemy.mon.hp) / 2 then
        shot = true
        U.still(game, DIR .. "/2723_04_enemy_drain_mid.png")
      end
      if enemy.shownHP == enemy.mon.hp and enemy.drainHold == nil then break end
    end
  end
  local endHP = enemy.mon.hp
  local expect = Timing.hpDrainFrames(startHP, endHP, eMax, false)
  local lagless = 2 * math.abs(Timing.hpBarPixels(startHP, eMax)
                               - Timing.hpBarPixels(endHP, eMax)) + 5
  U.log(("enemy drain %d -> %d: %d frames, budget %d, lag-free 2P+5 %d")
          :format(startHP, endHP, frames, expect, lagless))
  check("enemy drain happened", started and endHP < startHP)
  check("SEISMIC TOSS took the level in HP", startHP - endHP == lead.level)
  check(("enemy drain matches the per-step CPU budget (%d ~ %d)")
          :format(frames, expect), math.abs(frames - expect) <= 2)
  check("enemy drain is slower than the lag-free 2P + 5",
        endHP == startHP or frames > lagless)
  U.wait(4)
  U.still(game, DIR .. "/2723_05_enemy_drain_done.png")

  print(("hp_bar_speed_2723: %d passed, %d failed"):format(pass, fail))
  love.event.quit(fail == 0 and 0 or 1)
end
