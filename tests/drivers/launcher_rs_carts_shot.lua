--   tools/run_driver.sh ruby <identity> tests/drivers/launcher_rs_carts_shot.lua <shotdir>
--   POKEPORT_CART=hoenn_run tools/run_driver.sh ruby <identity> tests/drivers/launcher_rs_carts_shot.lua <shotdir>
local U = require("tests.drivers.util")

local DIR = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR")
  or "/tmp/launcher_rs_carts"
local CART = "hoenn_run"

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish(tag)
  require("src.core.SaveData").setCart(nil)
  if failures == 0 then
    print("PASS launcher_rs_carts " .. tag)
    love.event.quit(0)
  else
    print("FAIL launcher_rs_carts " .. tag .. " failures=" .. failures)
    love.event.quit(1)
  end
  while true do coroutine.yield() end
end

local function launcherPhase(game)
  if game then game.update = function() end end
  local RomImporter = require("src.import.RomImporter")
  local CartStore = require("src.carts.CartStore")
  local GameVersion = require("src.core.GameVersion")
  os.execute('mkdir -p "' .. DIR .. '" 2>/dev/null')
  love.window.setMode(1280, 720, { resizable = true })
  U.wait(2)

  for _, id in ipairs({ CART, "deep_blue" }) do
    if CartStore.get(id) then CartStore.uninstall(id) end
  end

  require("src.ui.kit.Transition").reduceMotion = true
  local imp = RomImporter.new(function() end, { launcher = true })
  love.draw = function() imp:draw() end
  local function settle(n)
    local untilAt = love.timer.getTime() + (n or 30) / 60
    repeat imp:update(1 / 60); coroutine.yield() until love.timer.getTime() >= untilAt
  end
  local function shot(name)
    settle(20)
    local g = love.graphics
    local w, h = g.getDimensions()
    local c = g.newCanvas(w, h)
    g.push("all")
    g.setCanvas(c)
    g.clear(0, 0, 0, 1)
    local seen, realPrint, realPrintf = {}, g.print, g.printf
    g.print = function(str, ...) seen[#seen + 1] = tostring(str) return realPrint(str, ...) end
    g.printf = function(str, ...) seen[#seen + 1] = tostring(str) return realPrintf(str, ...) end
    imp:draw()
    g.print, g.printf = realPrint, realPrintf
    g.setCanvas()
    g.pop()
    local f = io.open(DIR .. "/" .. name, "wb")
    if f then f:write(c:newImageData():encode("png"):getString()) f:close() end
    result(f ~= nil, "shot " .. name)
    return "\n" .. table.concat(seen, "\n") .. "\n"
  end

  settle(30)
  result(imp.ready.ruby == true, "Ruby is imported and ready")
  result(imp.ready.sapphire == true, "Sapphire is imported and ready")

  imp._gamePopup = true
  shot("01_game_picker.png")
  imp._gamePopup = nil

  imp:_switchTab("ruby")
  settle(30)
  result(imp.tab == "ruby", "the Ruby tab opens")
  shot("02_ruby_page.png")
  imp:_switchTab("sapphire")
  settle(30)
  result(imp.tab == "sapphire", "the Sapphire tab opens")
  shot("03_sapphire_page.png")

  imp:_switchTab("mods")
  settle(30)
  imp._modScopePopup = true
  local scopeText = shot("04_mods_show_for.png")
  print("show-for text has Ruby=" .. tostring(scopeText:find("Ruby", 1, true) ~= nil))
  imp._modScopePopup = nil

  imp:_switchTab("find")
  settle(30)
  imp._filterPopup = true
  local filterText = shot("05_find_filter_mods.png")
  print("find filter text has Ruby=" .. tostring(filterText:find("Ruby", 1, true) ~= nil))
  imp._filterPopup = nil
  imp:_setFindKind("carts")
  settle(10)
  if imp.findIndex then
    local bases = imp.findIndex.baseGames or {}
    local seen = {}
    for _, b in ipairs(bases) do seen[b] = true end
    if not seen.ruby then bases[#bases + 1] = "ruby" end
    if not seen.sapphire then bases[#bases + 1] = "sapphire" end
    imp.findIndex.baseGames = bases
  end
  imp._filterPopup = true
  local cartFilter = shot("06_find_filter_carts.png")
  print("cart base filter text has Ruby=" .. tostring(cartFilter:find("Ruby", 1, true) ~= nil))
  imp._filterPopup = nil
  imp:_setFindKind("mods")

  for _, spec in ipairs({ { "ruby", "Hoenn Run", CART }, { "sapphire", "Deep Blue", "deep_blue" } }) do
    local version, title, id = spec[1], spec[2], spec[3]
    imp:_switchTab(version)
    settle(20)
    imp:_setModScope(version)
    imp:_beginCartSave(version)
    result(imp._cartSave ~= nil, "Save as cart opens on " .. version)
    if imp._cartSave then
      imp._cartSave.text = title
      shot("07_save_as_cart_" .. version .. ".png")
      imp:_commitCartSave()
    end
    local made = CartStore.get(id)
    result(made ~= nil and made.base == version, title .. " is a " .. version .. " cart")
    result(made ~= nil and made.shell == GameVersion.info(version).cartShell,
      title .. " wears " .. version .. "'s shell")
    result(imp._cartPopup == version, "the cart picker opens on " .. version)
    shot("08_cart_picker_" .. version .. ".png")
    imp:_selectCart(version, id)
    imp._cartPopup = nil
    settle(20)
    result(imp.activeCart[version] == id, title .. " is the active cart")
    result(imp:slotScope(version) == "cart_" .. id, title .. " scopes its own slots")
    shot("09_cart_page_" .. version .. ".png")
  end

  local plan = imp.modCartPlan and imp:modCartPlan() or nil
  print("cart plan refused=" .. tostring(plan and plan.refused) .. " message=" .. tostring(plan and plan.message))
  result(plan == nil or plan.refused ~= true, "the active cart plans to load")
  finish("launcher")
end

local function playPhase(game)
  local SaveData = require("src.core.SaveData")
  local SaveIO = require("src.import.SaveFileIO")
  local GameVersion = require("src.core.GameVersion")
  result(GameVersion.get() == "ruby", "the cart boots Ruby")
  result(SaveData.getCart() == CART, "with the cart active")
  if not SaveData.activeCartSlot(CART) then
    local id = SaveData.createCartSlot(CART)
    SaveData.setActiveCartSlot(CART, id)
  end
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  U.shot(game, DIR .. "/10_cart_boot.png")
  game:_handleBootAction({ action = "new_game", name = "MAY" })
  U.wait(600)
  local Runtime = require("src.core.game3.runtime")
  result(Runtime.getSession() ~= nil, "a new game starts under the cart")
  U.shot(game, DIR .. "/11_cart_ingame.png")
  game:saveGame()
  U.wait(10)
  local slot = SaveData.activeCartSlot(CART)
  result(slot ~= nil, "the cart has an active save slot")
  result(slot ~= nil and SaveData.readCartSlotSource(CART, slot) ~= nil,
    "the save landed in the cart's own slot")
  result(slot ~= nil and SaveData.slotCartHash(CART, slot) ~= nil,
    "stamped with the cart build")
  result(#SaveData.listSlots("ruby") == 0, "and vanilla Ruby has no slots")
  local ok, path = SaveIO.exportLuaSlot("ruby", slot, CART)
  result(ok, "the cart save exports: " .. tostring(path))
  print("export " .. tostring(path))
  finish("play")
end

return function(game)
  local SaveData = require("src.core.SaveData")
  local ok, err = pcall(function()
    if SaveData.getCart() == CART then playPhase(game) else launcherPhase(game) end
  end)
  if not ok then
    result(false, "driver error: " .. tostring(err))
    finish("error")
  end
end
