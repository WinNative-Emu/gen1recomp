package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")
local T = require("tests.harness")
local Kit = require("src.ui.kit.Kit")
local LauncherView = require("src.import.LauncherView")
local RomImporter = require("src.import.RomImporter")
local Store = require("src.box.Store")
local BoxPanel = require("src.import.BoxPanel")
local Transition = require("src.ui.kit.Transition")
love.graphics.setLineJoin = love.graphics.setLineJoin or function() end
love.graphics.newShader = love.graphics.newShader or function() return {} end

local found = false
for _, tab in ipairs(LauncherView.HEADER_TABS) do if tab.id == "box" then found = true end end
T.check(found, "Box is reachable from the launcher header")

local function launcher(w, h)
  love.graphics.getDimensions = function() return w, h end
  love.graphics.getPixelDimensions = function() return w, h end
  local imp = RomImporter.new(function() end, { launcher = true })
  local storage = Store.new()
  imp.tab = "box"
  imp._boxState = { service = { state = storage }, sources = {}, sourceIndex = 1,
    box = 1, pcBox = 1, query = "", sort = "slot", pcRows = {},
    selectedBox = {}, selectedPC = {}, pageBox = 1, pagePC = 1, sourcePage = 1 }
  return imp
end

for _, size in ipairs({ { 360, 780 }, { 1024, 768 }, { 1360, 860 } }) do
  local imp = launcher(size[1], size[2])
  local seen, printed = {}, love.graphics.print
  love.graphics.print = function(text, ...) seen[#seen + 1] = tostring(text); return printed(text, ...) end
  local ok, why = pcall(LauncherView.draw, imp)
  love.graphics.print = printed
  T.check(ok, "Box draws at " .. size[1] .. "×" .. size[2] .. ": " .. tostring(why))
  T.check(table.concat(seen, "\n"):find("1500", 1, true) ~= nil, "capacity is visible")
  T.check((imp._tabScrollMax.box or 0) > 0, "Box content remains reachable through launcher scrolling")
end

local imp = launcher(1024, 768)
Transition.clear()
Kit.focus = "box-search"
imp:textinput("Pikachu")
LauncherView.draw(imp)
T.eq(imp._boxState.query, "Pikachu", "launcher text input reaches Box search")
imp:keypressed("backspace")
LauncherView.draw(imp)
T.eq(imp._boxState.query, "Pikach", "Box search handles backspace")
imp:_switchTab("mods")
T.eq(Kit.focus, nil, "leaving Box releases text focus")
T.eq(BoxPanel.textinput(imp, "x"), false, "Box does not consume another tab's input")

do
  local Catalog = require("src.box.Catalog")
  local Cry = require("src.box.Cry")
  local Animation = require("src.box.Animation")
  local previousCry, cried = Cry.play, {}
  local previousAnimation, animated = Animation.new, {}
  Animation.new = function(entry) if entry then animated[#animated + 1] = entry.id end end
  Cry.play = function(entry) cried[#cried + 1] = entry and entry.id end
  local previousArt, previousButton = Catalog.art, LauncherView.btn
  Catalog.art = function() return nil end
  local demo = launcher(1360, 860)
  Transition.clear()
  LauncherView.draw(demo)
  local previousTime, now = love.timer.getTime, love.timer.getTime() + 1
  love.timer.getTime = function() return now end
  local s = demo._boxState
  local function entry(id)
    return { id = id, version = "emerald", generation = 3,
      mon = { species = 25, level = id + 10 },
      display = { name = "Pikachu " .. id, species = "Pikachu", level = id + 10,
        types = "ELECTRIC", moves = "THUNDERSHOCK", item = "", national = 25 } }
  end
  for i = 1, 3 do s.service.state.boxes[1].mons[i] = entry(i) end
  s._filteredBox = nil
  s.sources = { { version = "emerald", label = "Emerald", slotId = "slot1", path = "saves/emerald/slot1.lua" } }
  s.pcRows = { { where = "box", box = 1, index = 4, key = "box:1:4", entry = entry(4) } }
  local controls = {}
  LauncherView.btn = function(owner, x, y, w, h, id, label, opts)
    controls[id] = { x = x, y = y, w = w, h = h, enabled = opts.enabled ~= false }
    return previousButton(owner, x, y, w, h, id, label, opts)
  end
  local function draw(click)
    now = now + 0.3
    Kit.scale = 1
    Kit.blockClicks = false
    Kit.beginFrame(click and click.x + click.w / 2 or 0, click and click.y + click.h / 2 or 0, click ~= nil, 0)
    controls = {}
    BoxPanel.draw(demo, 10, 10, 1340, 700, { s = 1, btnH = 38 })
    Kit.endFrame()
    local actions = demo._uiActions
    demo._uiActions = {}
    if actions then demo:runActions(actions) end
  end
  local function click(id) local rect = assert(controls[id], id); draw(rect); draw() end
  draw()
  T.eq(controls["box-withdraw"].enabled, false, "withdraw is disabled with no selection")
  T.eq(controls["box-box-1:4"].enabled, false, "empty warehouse slot is disabled")
  click("box-box-1:1")
  click("box-box-1:2")
  T.same(cried, { 1, 2 }, "each native grid popup plays its Pokemon cry")
  T.same(animated, { 1, 2 }, "each grid popup starts its Pokemon animation")
  draw(); draw()
  T.eq(#cried, 2, "steady redraws do not repeat the cry")
  BoxPanel.update(demo, 1 / 60)
  T.eq(#animated, 2, "steady updates and redraws do not restart the animation")
  T.check(s.selectedBox["1:1"] and s.selectedBox["1:2"], "multi-select retains both clicked slots")
  T.eq(s.inspect.id, 2, "detail card follows the last clicked Pokemon")
  T.eq(controls["box-withdraw"].enabled, true, "withdraw becomes enabled after selection")
  click("box-summary")
  T.eq(cried[#cried], 2, "opening full summary plays its Pokemon cry")
  T.eq(animated[#animated], 2, "opening full summary restarts the Pokemon animation")
  click("box-summary-next")
  T.eq(cried[#cried], 3, "next summary plays the new Pokemon cry")
  T.eq(animated[#animated], 3, "next summary starts its Pokemon animation")
  T.check(s.selectedBox["1:1"] and s.selectedBox["1:2"] and not s.selectedBox["1:3"], "summary navigation does not change multiselect")
  click("box-summary-prev")
  T.eq(cried[#cried], 2, "previous summary plays its Pokemon cry")
  T.eq(animated[#animated], 2, "previous summary starts its Pokemon animation")
  click("box-summary-back")
  click("box-multi")
  click("box-box-1:3")
  T.eq(s.selectedBox["1:1"], nil, "single selection clears previous multi-select refs")
  T.check(s.selectedBox["1:3"] ~= nil, "single selection keeps the current Pokemon")
  click("box-view-pc")
  T.eq(controls["box-pc-box:1:1"].enabled, false, "empty PC slots cannot be selected")
  T.eq(controls["box-pc-box:1:4"].enabled, true, "PC preserves native occupied slot positions")
  click("box-pc-box:1:4")
  T.eq(cried[#cried], 4, "game-save PC popup also plays its Pokemon cry")
  T.eq(animated[#animated], 4, "game-save PC popup also starts its Pokemon animation")
  click("box-pc-box:1:4")
  click("box-select-visible")
  T.check(s.selectedPC["box:1:4"] ~= nil, "select visible selects the occupied PC slot")
  T.eq(s.selectedBox["1:1"], nil, "PC bulk selection does not also select warehouse Pokemon")
  click("box-view-box")
  s.railFirst = 22
  draw()
  click("box-thumb-box-25")
  T.eq(s.box, 25, "box preview rail reaches the last warehouse box")
  click("box-active-box-next")
  T.eq(s.box, 1, "active box navigation wraps back from box 25")
  LauncherView.btn, Catalog.art = previousButton, previousArt
  love.timer.getTime = previousTime
  Cry.play = previousCry
  Animation.new = previousAnimation
end
T.finish()
