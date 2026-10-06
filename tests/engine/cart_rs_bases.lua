
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

love.graphics.setLineJoin = love.graphics.setLineJoin or function() end
love.graphics.newShader = love.graphics.newShader or function() return {} end
love.graphics.polygon = love.graphics.polygon or function() end
love.graphics.getDimensions = function() return 1280, 720 end
love.graphics.getPixelDimensions = function() return 1280, 720 end

local GameVersion = require("src.core.GameVersion")
local SaveData = require("src.core.SaveData")
local SaveSerializer = require("src.core.SaveSerializer")
local CartManifest = require("src.carts.CartManifest")
local CartStore = require("src.carts.CartStore")
local Loader = require("src.mods.Loader")
local LauncherMods = require("src.mods.LauncherMods")
local RomImporter = require("src.import.RomImporter")
local LauncherView = require("src.import.LauncherView")
local SaveIO = require("src.import.SaveFileIO")

local SHA = ("c0ffee00"):rep(8)

local function cartTable(over)
  local tbl = {
    id = "hoenn_run", title = "Hoenn Run", version = "1.0.0",
    author = "May", shell = "#b92e32", base = "ruby", seal = "sealed",
    mods = { { id = "rare_soda", source = "github", repo = "ren/rare-soda",
               version = "0.4.1", sha256 = SHA } },
  }
  for key, value in pairs(over or {}) do tbl[key] = value end
  return tbl
end

local realPrint = love.graphics.print
local function drawAndCapture(imp)
  local seen = {}
  love.graphics.print = function(str, ...)
    seen[#seen + 1] = tostring(str)
    return realPrint(str, ...)
  end
  local ok, err = pcall(LauncherView.draw, imp)
  love.graphics.print = realPrint
  check(ok, "the frame draws: " .. tostring(err))
  return table.concat(seen, "\n")
end

local hashes = {}
for _, base in ipairs({ "ruby", "sapphire" }) do
  local id = base .. "_run"
  local cart, err = CartManifest.parse(cartTable({ id = id, base = base,
    title = GameVersion.info(base).label .. " Run" }))
  check(cart ~= nil, base .. " is a cart base the manifest accepts: " .. tostring(err))
  eq(cart and cart.base, base, "the parsed cart keeps the " .. base .. " base")
  local ok, why = CartStore.install(CartManifest.encode(cart))
  check(ok ~= nil, base .. " cart installs: " .. tostring(why))
  hashes[base] = CartManifest.hash(cart)
end
check(hashes.ruby ~= hashes.sapphire, "the two bases hash to different builds")

local imp = RomImporter.new(function() end, { launcher = true })
for _, base in ipairs({ "ruby", "sapphire" }) do
  local rows = imp:_ensureCarts(base)
  eq(#rows, 1, base .. " lists exactly its own cart")
  eq(rows[1] and rows[1].id, base .. "_run", "and it is the " .. base .. " one")
end
eq(#imp:_ensureCarts("emerald"), 0, "Emerald lists neither Hoenn cart")

imp.tab = "ruby"
imp.ready.ruby = true
imp._cartPopup = "ruby"
local picker = drawAndCapture(imp)
check(picker:find("Pokemon Ruby", 1, true) ~= nil,
  "the Ruby picker offers the base game first")
check(picker:find("Ruby Run", 1, true) ~= nil, "and lists the Ruby cart")
check(picker:find("Sapphire Run", 1, true) == nil, "and not the Sapphire one")

imp:_selectCart("ruby", "ruby_run")
eq(imp.activeCart.ruby, "ruby_run", "picking the Ruby cart activates it")
eq(imp.tab, "ruby", "a cart id never reaches imp.tab")
check(drawAndCapture(imp):find("Ruby Run", 1, true) ~= nil,
  "the Ruby page takes the cart's title")

local scope = imp:slotScope("ruby")
eq(scope, "cart_ruby_run", "the Ruby cart scopes its own save slots")
imp:_newSlot(scope)
eq(#SaveData.listCartSlots("ruby_run"), 1, "the slot lands in the cart")
eq(#SaveData.listSlots("ruby"), 0, "and not in vanilla Ruby")

local handed = {}
local player = RomImporter.new(function(version, cartId)
  handed.version, handed.cart = version, cartId
end, { launcher = true })
player.ready.sapphire = true
player:_selectCart("sapphire", "sapphire_run")
player:play("sapphire")
eq(handed.version, "sapphire", "Play boots Sapphire")
eq(handed.cart, "sapphire_run", "and names the Sapphire cart")

local plan = Loader.planCart(CartStore.get("ruby_run"),
  { { id = "rare_soda", version = "0.4.1" } })
eq(plan.refused, false, "a fully installed Ruby cart plans to load")
local missing = Loader.planCart(CartStore.get("ruby_run"), {})
eq(missing.refused, true, "a Ruby cart missing its pin refuses before boot")

SaveData.setCart("ruby_run", hashes.ruby)
local slot = SaveData.activeCartSlot("ruby_run")
check(slot ~= nil, "the Ruby cart has an active slot to save into")
local save = { version = "ruby", engine = "game3", map = "LITTLEROOT_TOWN",
  player = { name = "MAY" }, playTime = 0 }
check(SaveData.save(save), "a Ruby cart playthrough saves")
check(SaveData.readCartSlotSource("ruby_run", slot) ~= nil,
  "into the cart's own slot")
eq(SaveData.slotCartHash("ruby_run", slot), hashes.ruby,
  "stamped with the cart build it was made under")
eq(SaveData.readSlotSource("ruby", slot), nil, "never into vanilla Ruby")
SaveData.setCart(nil)

local ok, path = SaveIO.exportLuaSlot("ruby", slot, "ruby_run")
check(ok, "the Ruby cart save exports: " .. tostring(path))
check(tostring(path):find("gen1recomp-ruby-ruby_run-", 1, true) ~= nil,
  "under a name that carries the game and the cart")

local realList = LauncherMods.list
LauncherMods.list = function()
  return { { id = "rare_soda", name = "Rare Soda", version = "0.4.1",
    github = "ren/rare-soda", sha256 = SHA, enabled = true, status = "ok",
    statusDetail = "", targetsHere = true, requiredImports = {}, imports = {},
    missingRequiredImports = 0, missingOptionalImports = 0,
    enabledByVersion = { sapphire = true },
    manifest = { id = "rare_soda", name = "Rare Soda", version = "0.4.1" } } }
end
local maker = RomImporter.new(function() end, { launcher = true })
maker.tab = "sapphire"
maker.ready.sapphire = true
maker:_setModScope("sapphire")
maker:_beginCartSave("sapphire")
check(maker._cartSave ~= nil, "Save as cart opens on Sapphire")
eq(maker._cartSave and maker._cartSave.version, "sapphire", "scoped to Sapphire")
maker._cartSave.text = "Deep Blue"
maker:_commitCartSave()
eq(maker._cartSave, nil, "the Sapphire capture saves")
local made = CartStore.get("deep_blue")
eq(made and made.base, "sapphire", "the captured cart plays as Sapphire")
eq(made and made.shell, "#355ec4", "wearing Sapphire's rail colour")
LauncherMods.list = realList

T.finish("cart rs bases")
