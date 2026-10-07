local U = require("tests.drivers.util")
local F = require("tests.drivers.em_fc_util").new("em_wailmer_pail_sudowoodo_2697")

local function realWait(sec)
  local t = love.timer.getTime()
  while love.timer.getTime() - t < sec do U.wait(1) end
end

return function(game)
  if not F.boot(game) then return F.finish() end
  F.givePartyAndRepel()
  local ok = F.try("pail", function()
    local Runtime = require("src.core.game3.runtime")
    local Objects = require("src.core.game3.objects")
    local Bag = require("src.core.game3.bag")
    local BagMenu = require("src.ui.game3.bag_menu")
    local Message = require("src.ui.game3.message")
    local Space = require("src.core.game3.scripting.space")
    local Battle = require("src.core.game3.battle")
    local BerryTrees = require("src.core.game3.rse.berry_trees")
    local Collision = require("src.core.game3.collision")
    local C = require("src.core.game3.constants").of("emerald")
    local s = Runtime.getSession()
    local pail = C:require("items", "ITEM_WAILMER_PAIL")
    Bag.add(s.bag, pail, 1)

    local function usePailFromBag()
      BagMenu.show(s, { session = s, pocket = "KEY_ITEMS" })
      for _ = 1, 120 do
        if BagMenu.isOpen() and BagMenu.mode == "list" then break end
        U.wait(1)
      end
      U.wait(20)
      for i, row in ipairs(BagMenu.list()) do
        if row.id == pail then BagMenu.cursor = i end
      end
      for _ = 1, 5 do
        if BagMenu.mode == "action" then break end
        U.tap(game, "a")
        U.wait(10)
      end
      U.wait(6)
      U.tap(game, "a")
      for _ = 1, 240 do
        if not BagMenu.isOpen() then break end
        U.wait(1)
      end
    end

    F.check(F.goTo(game, "EM_ROUTE104", 10, 10, "down"), "Route 104 loads")
    local tree
    for _, lid in ipairs(Objects._order) do
      local t = Objects._byId[lid]
      if t and t.berryTree and not tree and Collision.isWalkable(t.cellX, t.cellY + 1) then tree = t end
    end
    if F.check(tree ~= nil, "found a berry tree with a walkable cell below") then
      local id, lid = tree.berryTree.id, tree.localId
      BerryTrees.plant(id, 1, BerryTrees.STAGE_SPROUTED, false, s)
      F.goTo(game, "EM_ROUTE104", tree.cellX, tree.cellY + 1, "up")
      U.wait(4)
      usePailFromBag()
      local watered = false
      for _ = 1, 600 do
        if Message.isOpen and Message.isOpen() then
          realWait(1)
          F.shot(game, "2697_00_pail_berry_watered.png", true)
          watered = true
          break
        end
        U.wait(1)
      end
      F.check(watered, "pail on a sprouted tree runs the bag watering script")
      F.check(BerryTrees.peek(s, id).watered2 == true, "the tree is marked watered for its stage")
      F.settle(game)
      F.haltVm()
      F.goTo(game, "EM_ROUTE104", tree.cellX, tree.cellY + 1, "up")
      BerryTrees.plant(id, 1, BerryTrees.STAGE_BERRIES, false, s)
      U.wait(4)
      usePailFromBag()
      U.wait(30)
      F.check(not (Space.vm and Space.vm:isRunning()), "pail on a fruiting tree starts no script")
      F.settle(game)
      BagMenu.close()
      U.wait(10)
    end

    F.check(F.goTo(game, "EM_BATTLE_FRONTIER_OUTSIDE_EAST", 55, 62, "left"), "Battle Frontier east loads")
    local eo = Objects.at(54, 62)
    F.check(eo ~= nil and tonumber(eo.graphicsId or (eo.def and eo.def.graphicsId)) == 228,
      "the Sudowoodo stands left of the player")
    usePailFromBag()
    local sawText, battle = false, false
    local t0 = love.timer.getTime()
    while love.timer.getTime() - t0 < 12 do
      if Battle.isActive() then battle = true break end
      if Message.isOpen and Message.isOpen() then
        if not sawText then
          realWait(1)
          F.shot(game, "2697_01_pail_sudowoodo_attacked.png", true)
          sawText = true
        end
        U.tap(game, "a")
      end
      U.wait(2)
    end
    F.check(sawText, "watering the Sudowoodo runs WaterSudowoodo")
    F.check(battle, "the Sudowoodo battle starts")
    local foe = battle and Battle._st and Battle._st.enemy and Battle._st.enemy.mon
    F.check(foe and foe.species == C:require("species", "SPECIES_SUDOWOODO") and foe.level == 40,
      "wild Sudowoodo Lv40 (" .. tostring(foe and foe.species) .. " lv " .. tostring(foe and foe.level) .. ")")
    if battle then
      for _ = 1, 120 do
        if Battle._phase == "command" then break end
        U.wait(2)
      end
      F.shot(game, "2697_02_sudowoodo_battle.png", true)
    end
  end)
  F.check(ok, "Sudowoodo part ran without errors")
  F.finish()
end
