package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")
local T = require("tests.harness")
local Kit = require("src.ui.kit.Kit")
local View = require("src.import.LauncherView")
local RomImporter = require("src.import.RomImporter")
local Transition = require("src.ui.kit.Transition")
love.graphics.setLineJoin = love.graphics.setLineJoin or function() end
love.graphics.newShader = love.graphics.newShader or function() return {} end

for _, tab in ipairs(View.HEADER_TABS) do
  T.check(tab.id ~= "find", "Search has no separate launcher header button")
end

local originalButton, originalTime = Kit.button, love.timer.getTime
local controls, now = {}, originalTime() + 1
love.timer.getTime = function() return now end
Kit.button = function(x, y, w, h, label, opts)
  if opts and opts.id then
    controls[opts.id] = { x = x, y = y, w = w, h = h, active = not not opts.active }
  end
  return originalButton(x, y, w, h, label, opts)
end

for _, size in ipairs({ { 390, 844 }, { 1360, 860 } }) do
  love.graphics.getDimensions = function() return size[1], size[2] end
  love.graphics.getPixelDimensions = love.graphics.getDimensions
  local imp = RomImporter.new(function() end, { launcher = true })
  imp.mods, imp.modStraysChecked = {}, true
  imp.findLoaded, imp.findSources = true, { { feed = "https://example.invalid/mods.json" } }
  imp.findIndex = { mods = {}, carts = {} }
  imp._ensureMods = function() end
  imp._ensureFind = function() end
  imp:_switchTab("mods")
  local function draw(click)
    now = now + 0.5
    Transition.clear()
    controls = {}
    imp._clickPt = click and { x = click.x + click.w / 2, y = click.y + click.h / 2 } or nil
    View.draw(imp)
    local actions = imp._uiActions
    imp._uiActions = {}
    if actions then imp:runActions(actions) end
  end
  local function click(id)
    local rect = assert(controls[id], id)
    draw(rect)
    draw()
  end
  draw()
  T.check(controls["mods-inner-installed"].active, "Installed starts selected")
  T.check(not controls["mods-inner-search"].active, "Search starts inactive")
  T.check(controls["tab-find"] == nil, "Find header control is absent")
  T.check(controls["mods-inner-search"].x + controls["mods-inner-search"].w <= size[1],
    "inner tabs fit the window")
  click("mods-inner-search")
  T.eq(imp.tab, "find", "Search opens the existing discovery page")
  T.check(controls["tab-mods"].active, "Mods remains the selected header button in Search")
  T.check(controls["mods-inner-search"].active, "Search inner tab is selected")
  T.eq(imp._busy, nil, "opening Search does not raise a blocking loader")
  imp.findQuery, imp.findGame, imp.findCategory = "sprite", "emerald", "graphics"
  imp._findSearchFocus = true
  click("mods-inner-installed")
  T.eq(imp.tab, "mods", "Installed returns to local mods")
  T.eq(imp._findSearchFocus, false, "leaving Search releases its text focus")
  click("mods-inner-search")
  T.eq(imp.findQuery, "sprite", "Search query survives inner tab switches")
  T.eq(imp.findGame, "emerald", "game filter survives inner tab switches")
  T.eq(imp.findCategory, "graphics", "category filter survives inner tab switches")
  imp:_cycleTab(1)
  T.eq(imp.tab, "online", "controller navigation treats both inner pages as Mods")
  draw()
  click("tab-mods")
  T.eq(imp.tab, "find", "Mods header remembers its last selected inner page")
end

Kit.button, love.timer.getTime = originalButton, originalTime
T.finish("launcher mods inner tabs")
