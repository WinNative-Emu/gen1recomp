-- Custom Carts "Import .g1rcart" follows the same platform split as ROM, mod,
-- and save import. Self-contained: luajit tests/engine/cart_import_picker.lua
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local S = require("tests.harness").suite("cart import picker")
local eq, check = S.eq, S.check

local Platform = require("src.core.Platform")
local RomImporter = require("src.import.RomImporter")

love.system = love.system or {}
local saved = {
  getOS = love.system.getOS,
  pickFile = love.system.pickFile,
  pickFileKinds = love.system.pickFileKinds,
  getPickedFile = love.system.getPickedFile,
}

local picks = {}
local function androidImporter()
  picks = {}
  love.system.getOS = function() return "Android" end
  love.system.pickFile = function(kind)
    picks[#picks + 1] = kind
    return true
  end
  love.system.pickFileKinds = function()
    return "rom,mod,sav,cart,required_import"
  end
  Platform._resetForTests()
  local imp = RomImporter.new(function() end, { launcher = true })
  imp._installCartFile = function(self, source)
    self.installed = source
    self._cartNotice = "Imported Picked One. It is in this list now."
    return true
  end
  return imp
end

local imp = androidImporter()
imp._cartPopup = "red"
eq(imp:importCartFile("red"), true, "Android Import .g1rcart opens the picker")
eq(picks[1], "cart", "and asks for the cart kind, not a ROM")
eq(imp.pickerPendingKind, "cart", "focus knows the staged file is a cart")

love.filesystem.write("picked_cart.g1rcart", "cart-bytes")
imp:focus(true)
eq(imp.installed, "picked_cart.g1rcart", "focus installs the staged cart")
check(love.filesystem.getInfo("picked_cart.g1rcart") == nil,
  "and retires the staged file")

local function legacyCartPick(kinds, label)
  love.system.pickFileKinds = kinds
  Platform._resetForTests()
  local legacy = RomImporter.new(function() end, { launcher = true })
  legacy._installCartFile = imp._installCartFile
  local modInstalls = 0
  legacy._installMod = function() modInstalls = modInstalls + 1 end
  picks = {}
  eq(legacy:importCartFile("red"), true, label .. ": Import .g1rcart opens the picker")
  eq(picks[1], "mod", label .. ": through the mod kind the old bridge has")
  eq(#picks, 1, label .. ": with one pick and never a ROM pick")
  eq(legacy.pickerPendingKind, "cart", label .. ": focus knows the pick is a cart")
  love.filesystem.write("picked_mod.zip", "cart-bytes")
  legacy:focus(true)
  eq(legacy.installed, "picked_mod.zip", label .. ": focus installs the pick as a cart")
  eq(modInstalls, 0, label .. ": and never as a mod")
  check(love.filesystem.getInfo("picked_mod.zip") == nil,
    label .. ": and retires the staged file")
  eq(legacy.pickerPendingKind, nil, label .. ": and clears the pending kind")
  eq(legacy.cartLegacyModPick, nil, label .. ": and the legacy flag")

  picks = {}
  eq(legacy:importCartFile("red"), true, label .. ": a second import reopens the picker")
  love.filesystem.write("pick_error.flag", "cancelled:picked_mod.zip")
  legacy:focus(true)
  check(type(legacy._cartNotice) == "string"
      and legacy._cartNotice:find("did not return a file", 1, true),
    label .. ": a cancelled pick lands on the cart notice")
  check(legacy.modNotice == nil or legacy.modNotice.text == nil,
    label .. ": and not on the mod notice")

  picks = {}
  legacy.installed = nil
  eq(legacy:importCartFile("red"), true, label .. ": a third import reopens the picker")
  legacy:focus(true)
  eq(legacy.pickerPendingKind, "cart",
    label .. ": a silent cancel (old APK, no flag) leaves the cart pick armed")
  legacy:chooseMod()
  eq(picks[#picks], "mod", label .. ": the Mods tab import opens the mod picker")
  eq(legacy.pickerPendingKind, "mod", label .. ": and claims the pending kind")
  eq(legacy.cartLegacyModPick, nil, label .. ": and disarms the legacy cart flag")
  love.filesystem.write("picked_mod.zip", "real-mod-bytes")
  legacy:focus(true)
  eq(modInstalls, 1, label .. ": a real mod picked after the silent cancel installs as a mod")
  eq(legacy.installed, nil, label .. ": and never reaches the cart installer")
  eq(legacy.pickerPendingKind, nil, label .. ": and clears the pending kind after install")

  picks = {}
  eq(legacy:importCartFile("red"), true, label .. ": a fourth import reopens the picker")
  legacy:focus(true)
  legacy:chooseMod()
  love.filesystem.write("pick_error.flag", "cancelled:picked_mod.zip")
  legacy._cartNotice = nil
  legacy:focus(true)
  check(legacy.modNotice and legacy.modNotice.ok == false,
    label .. ": a cancelled Mods-tab pick after a silent cart cancel lands on the mod notice")
  eq(legacy._cartNotice, nil, label .. ": and not on the cart notice")
  eq(legacy.pickerPendingKind, nil, label .. ": and leaves nothing armed")
end

legacyCartPick(function() return "rom,mod,sav" end, "pre-cart bridge")
legacyCartPick(nil, "pre-kinds bridge")

love.system.pickFileKinds = nil
love.system.pickFile = nil
Platform._resetForTests()
local bare = RomImporter.new(function() end, { launcher = true })
eq(bare:importCartFile("red"), false, "an APK with no picker bridge cannot open one")
check(type(bare._cartNotice) == "string"
    and bare._cartNotice:find("Update the app", 1, true) ~= nil,
  "and the notice tells the player to update the app")
eq(bare.pickerPendingKind, nil, "and leaves no pending cart pick")
love.system.pickFile = function(kind)
  picks[#picks + 1] = kind
  return true
end

love.system.getOS = function() return "NX" end
love.system.pickFile = nil
Platform._resetForTests()
local nx = RomImporter.new(function() end, { launcher = true })
nx._installCartFile = function(self, source)
  self.installed = source
  self._cartNotice = "Imported inbox."
  return true
end
love.filesystem.write("imports/carts/inbox.g1rcart", "cart-bytes")
eq(nx:importCartFile("red"), true, "NX Import scans imports/carts/")
eq(nx.installed, "imports/carts/inbox.g1rcart", "and installs the inbox file")
love.filesystem.remove("imports/carts/inbox.g1rcart")

nx.installed = nil
eq(nx:importCartFile("red"), false, "an empty NX inbox does not invent a cart")
check(nx._cartNotice:find("imports/carts/", 1, true) ~= nil,
  "and the notice names the MTP folder")

love.system.getOS = saved.getOS
love.system.pickFile = saved.pickFile
love.system.pickFileKinds = saved.pickFileKinds
love.system.getPickedFile = saved.getPickedFile
Platform._resetForTests()

S.finish()
