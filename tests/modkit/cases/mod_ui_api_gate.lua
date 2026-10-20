package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Version = require("src.core.GameVersion")
local ModUI = require("src.ui.ModUI")

local savedCurrent = Version.current
local Screens = require("src.ui.Screens")
local realPush = Screens.push
local pushed
Screens.push = function(_, id) pushed = id return "native" end

Version.set("firered")
local stock = require("src.render.TextBox")
T.check(ModUI.forApi(2).TextBox == stock, "an API 2 mod on FireRed keeps the stock TextBox")
T.check(ModUI.forApi(1).TextBox == stock, "an API 1 mod on FireRed keeps the stock TextBox")
T.check(ModUI.forApi(3).TextBox ~= stock, "an API 3 mod on FireRed gets the Gen 3 TextBox")
T.eq(ModUI.forApi(2).push({}, "Legacy"), "native", "an API 2 push on FireRed goes through Screens")
T.eq(pushed, "Legacy", "the API 2 push reached Screens.push")
T.check(ModUI.forApi(2).Menu == require("src.ui.Menu"), "the legacy view still exposes the widgets")
local items = { { label = "A" } }
ModUI.forApi(2).insertAfter(items, "A", { label = "B" })
T.eq(items[2].label, "B", "the legacy view still exposes the helpers")
T.check(ModUI.forApi(3) == ModUI, "API 3 gets the full surface")

Version.current = nil
local ok, err = pcall(function() return ModUI.TextBox end)
T.check(ok, "touching ModUI before a version is chosen does not throw: " .. tostring(err))

Version.current = savedCurrent
Screens.push = realPush
T.finish("mod ui api gate")
