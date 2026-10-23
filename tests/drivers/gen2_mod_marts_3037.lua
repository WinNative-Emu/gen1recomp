local U = require("tests.drivers.util")
local Loader = require("src.mods.Loader")
local Sdk = require("tests.modkit.sdk")

return function(game)
  U.wait(45)
  local failures = 0
  local function check(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then failures = failures + 1 end
    return ok
  end
  local files = {
    ["mods/probe/manifest.json"] = '{"id":"probe","name":"probe","version":"1.0.0",'
      .. '"api":3,"games":["all"],"entry":"main.lua"}',
    ["mods/probe/main.lua"] = [[local mod = ...
mod.content.marts:patch("0", {"ULTRA_BALL"})
mod.content.marts:patch("1", {"ULTRA_BALL"})
mod.content.marts:remove("33")
mod.content.marts:patch("bargain", {{item="NUGGET",price=500}})]],
  }
  local loader = Loader.new({ fs = Sdk.memfs(files), generation = 2,
    version = game.save.version, dev = true })
  loader.game = game
  local data = {}
  for key, value in pairs(game.data) do data[key] = value end
  for key in pairs(require("src.mods.Builtins").namespaceRoots(2)) do data[key] = nil end
  loader:load(data)
  if not check(not loader.mods.probe.failed, "3037_fixture_registered") then
    love.event.quit(1)
    return
  end
  game.world:warpToMapId("CHERRYGROVE_MART", 2, 4, "up")
  U.wait(15)
  local dir = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/gen2_mod_marts_3037"
  game.save.player.money = 10000
  local before = game.save.inventory.ULTRA_BALL or 0
  game.world:openMart(0, 0)
  local menu = game.stack:top()
  if check(menu and menu.entries and #menu.entries == 1 and menu.entries[1].id == "ULTRA_BALL",
      "3037_standard_stock") then
    menu:enterBuy()
    check(U.still(game, dir .. "/3037_cherrygrove_mod_stock.png"), "3037_standard_shot")
    menu.qtyItem, menu.qty = menu.entries[1], 1
    local price = menu.entries[1].price
    menu:completePurchase(price)
    check(game.save.inventory.ULTRA_BALL == before + 1 and game.save.player.money == 10000 - price,
      "3037_standard_purchase")
  end
  game.stack:pop()
  game.save.bargainShop = {}
  game.world:openMart(2, 0)
  menu = game.stack:top()
  if check(menu and menu.entries and #menu.entries == 1 and menu.entries[1].price == 500,
      "3037_bargain_price") then
    menu:enterBuy()
    check(U.still(game, dir .. "/3037_bargain_mod_price.png"), "3037_bargain_shot")
    menu.qtyItem, menu.qty = menu.entries[1], 1
    menu:completePurchase(500)
    check(game.save.bargainShop.NUGGET == true, "3037_bargain_sold")
  end
  local Mart = require("src.ui.gen2.MartMenu")
  check(#Mart.inventory(game.data.gen2Marts, 33) == 0, "3037_removed_shelf_empty")
  love.event.quit(failures == 0 and 0 or 1)
end
