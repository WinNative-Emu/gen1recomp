package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")
local T = require("tests.harness")
local Kit = require("src.ui.kit.Kit")
local Prompt = require("src.import.BoxPrompt")
local Tools = require("src.import.BoxTools")
local View = require("src.import.LauncherView")
local Importer = require("src.import.RomImporter")
local Transition = require("src.ui.kit.Transition")
local Store = require("src.box.Store")
love.graphics.setLineJoin = love.graphics.setLineJoin or function() end
love.graphics.newShader = love.graphics.newShader or function() return {} end

local imp = Importer.new(function() end, { launcher = true })
imp.tab = "box"
local saved
local s = { service = { state = Store.new(), preset = function(_, name, refs)
  saved = { name = name, refs = refs }; return true
end }, selectedBox = { ["1:1"] = { box = 1, slot = 1 } }, toolsOpen = true, toolsPage = "Teams" }
local controls = {}
Kit.layout(1360, 860)
Tools.draw(imp, s, 0, 0, 1000, { s = 1, btnH = 38 }, {
  button = function(_, _, _, _, _, id, _, action) controls[id] = action end,
  selected = function() return { { box = 1, slot = 1 } } end,
  perform = function(_, fn) return fn() end,
})
controls["tools-save-team"]()
T.check(imp._boxPrompt ~= nil, "desktop team button opens a visible text modal")
T.eq(Kit.VirtualKeyboard.active, false, "desktop does not depend on handheld keyboard")
T.eq(View.modalKey(imp), "_boxPrompt", "prompt shields underlying launcher controls")
Transition.clear()
imp:textinput("Starter team")
imp:keypressed("return")
T.eq(saved.name, "Starter team", "physical keyboard saves the team name through its UI action")
T.same(saved.refs, { { box = 1, slot = 1 } }, "named team keeps the selected record references")
T.eq(imp._boxPrompt, nil, "confirmed prompt closes")
imp:keypressed("return")
T.eq(saved.name, "Starter team", "closed prompt cannot repeat its callback")

local result, calls = nil, 0
local function callback(value) result = value; calls = calls + 1 end
Prompt.open(imp, "Local tags", "", 3, callback)
imp:textinput("éABCD")
T.eq(imp._boxPrompt.text, "éAB", "prompt cap counts UTF-8 characters")
imp:keypressed("backspace")
T.eq(imp._boxPrompt.text, "éA", "backspace removes one complete character")
imp:keypressed("backspace"); imp:keypressed("backspace")
T.eq(imp._boxPrompt.text, "", "backspace removes accented character without leaving invalid bytes")
imp:textinput("tag")
imp:keypressed("escape")
T.eq(calls, 0, "Escape cancels without applying tags")
T.eq(imp._boxPrompt, nil, "Escape removes the modal")

Prompt.open(imp, "Stage name", "Garden", 64, callback)
imp._boxState = { service = { state = Store.new() }, sources = {}, sourceIndex = 1,
  box = 1, pcBox = 1, query = "", sort = "slot", pcRows = {}, selectedBox = {}, selectedPC = {} }
for _, size in ipairs({ { 390, 844 }, { 1360, 860 } }) do
  love.graphics.getDimensions = function() return size[1], size[2] end
  love.graphics.getPixelDimensions = love.graphics.getDimensions
  T.check(pcall(View.draw, imp), "naming modal renders at " .. size[1] .. " pixel width")
end
Transition.clear()
imp:gamepadpressed(nil, "b")
T.eq(imp._boxPrompt, nil, "controller B cancels the prompt")
T.eq(calls, 0, "controller cancellation leaves the stage unchanged")
Prompt.open(imp, "Box name", "Names", 32, callback)
Prompt.close(imp, true)
T.eq(result, "Names", "modal Save uses the same confirmation callback")
T.eq(calls, 1, "Save invokes the callback once")
Prompt.open(imp, "Box name", "Discard", 32, callback)
imp:_switchTab("mods")
T.eq(imp._boxPrompt, nil, "leaving Box cancels a pending name edit")
T.eq(calls, 1, "leaving Box cannot commit an edit")
T.finish()
