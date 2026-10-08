package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")
local T = require("tests.harness")
local Kit = require("src.ui.kit.Kit")
local UI = require("src.import.BoxUI")
local View = require("src.import.LauncherView")
local Importer = require("src.import.RomImporter")
local Store = require("src.box.Store")
local Transition = require("src.ui.kit.Transition")
love.graphics.setLineJoin = love.graphics.setLineJoin or function() end
love.graphics.newShader = love.graphics.newShader or function() return {} end
local clock = 100
love.timer.getTime = function() return clock end
local controls, texts, original = {}, {}, View.btn
View.btn = function(imp, x, y, w, h, id, label, opts)
  controls[id] = { x = x, y = y, w = w, h = h, label = label, opts = opts }
  return original(imp, x, y, w, h, id, label, opts)
end
local printText = love.graphics.print
love.graphics.print = function(value, ...)
  texts[#texts + 1] = tostring(value); return printText(value, ...)
end
local function launcher(width, height)
  love.graphics.getDimensions = function() return width, height end
  love.graphics.getPixelDimensions = function() return width, height end
  local imp = Importer.new(function() end, { launcher = true })
  local service = { state = Store.new() }
  service.read = function(_, source)
    service.lastRead = source.path
    return { version = source.version, party = {}, boxes = {} }, nil, source.path
  end
  imp.tab = "box"
  imp._boxState = { service = service, sources = {
    { version = "red", label = "Red · First", path = "first", slotId = "slot1" },
    { version = "emerald", label = "Emerald · Second", path = "second", slotId = "slot2" } },
    sourceIndex = 1, box = 1, pcBox = 1, query = "", sort = "slot", pcRows = {},
    selectedBox = {}, selectedPC = {}, pageBox = 1, pagePC = 1, view = "box", multi = true }
  Transition.reset(); Kit.blur()
  return imp
end
local function draw(imp, click)
  clock = clock + .3; controls, texts = {}, {}
  imp._clickPt = click; View.draw(imp)
  local queue = imp._uiActions; imp._uiActions = {}
  imp:runActions(queue or {})
end
local function click(imp, id)
  local r = assert(controls[id], id)
  draw(imp, { x = r.x + r.w / 2, y = r.y + r.h / 2 }); draw(imp)
end
local function settle(imp) draw(imp); draw(imp) end
local function keyboardChoice(imp, key)
  imp:keypressed(key); settle(imp)
end

for _, size in ipairs({ { 360, 780 }, { 390, 844 }, { 1024, 768 }, { 1360, 860 }, { 640, 360 } }) do
  local imp = launcher(size[1], size[2]); settle(imp)
  T.check(controls["box-choose-save"].opts.icon and controls["box-tools-menu"].opts.icon,
    "game and tools pickers have icons at " .. size[1])
  T.check(not table.concat(texts):find("Game save", 1, true), "ambiguous Game save label is gone")
  click(imp, "box-choose-save")
  T.eq(View.modalKey(imp), "_boxPopup", "game picker owns the modal input layer")
  T.eq(imp._boxPopup.index, 1, "picker opens at the current playthrough")
  click(imp, "box-popup-option-2")
  T.eq(imp._boxState.sourceIndex, 2, "choosing a game changes the linked playthrough")
  T.eq(imp._boxState.service.lastRead, "second", "picker reloads the chosen game's PC")
  T.eq(imp._boxState.view, "pc", "choosing a game opens its Game PC")
  T.eq(imp._boxPopup, nil, "choice closes the popup")
  click(imp, "box-tools-menu")
  T.eq(#imp._boxPopup.options, 11, "tools retain every page except the separate Filters control")
  keyboardChoice(imp, "end")
  T.check(imp._boxPopup.scroll > 0, "keyboard reveals tools below the visible rows")
  keyboardChoice(imp, "return")
  T.eq(imp._boxState.toolsPage, "Items", "last tool is reachable without a button wall")
  click(imp, "box-help-Items")
  T.eq(imp._boxPopup.message, UI.HELP.Items, "context help explains the selected tool")
  T.check(#imp._boxPopup.message < 150, "context explanation stays short")
  local bounds = controls["box-popup-close"]
  T.check(bounds.x >= 0 and bounds.y >= 0 and bounds.x + bounds.w <= size[1]
    and bounds.y + bounds.h <= size[2], "popup close remains on screen")
  keyboardChoice(imp, "escape")
end

local imp = launcher(1024, 768); settle(imp)
click(imp, "box-tools-menu")
Kit.focus = "box-chooser-filter"
imp:textinput("Dashboard"); settle(imp)
T.eq(imp._boxPopup.query, "Dashboard", "launcher typing reaches the picker search")
T.eq(#imp._boxPopup.rows, 1, "picker search narrows actual options")
keyboardChoice(imp, "return")
T.eq(imp._boxState.toolsPage, "Dashboard", "Enter applies the filtered choice")
imp._boxState.toolsPage = nil; settle(imp)
click(imp, "box-options")
for _, option in ipairs(imp._boxPopup.options) do
  if option.label == "Box theme" then option.action() end
end
settle(imp)
T.eq(imp._boxPopup.title, "Box theme", "Options opens the Box theme picker")
keyboardChoice(imp, "end")
local old = imp._boxState.service.state.boxes[1].theme
keyboardChoice(imp, "return")
T.check(imp._boxPopup ~= nil, "disabled Showcase wallpaper cannot be chosen")
T.eq(imp._boxState.service.state.boxes[1].theme, old, "disabled option leaves the box unchanged")
keyboardChoice(imp, "escape")

imp._boxState.toolsPage, imp._boxState.view = nil, "box"; settle(imp)
click(imp, "box-options")
T.eq(imp._boxPopup.index, 1, "action menu starts at its first enabled action")
for id, r in pairs(controls) do
  if id:match("^box%-popup%-option") then T.check(not r.opts.active, "action rows have no false selected checks") end
end
local behind = controls["box-choose-save"]
draw(imp, { x = behind.x + 10, y = behind.y + behind.h / 2 }); settle(imp)
T.eq(imp._boxPopup, nil, "outside tap dismisses without opening the game picker beneath it")
T.eq(imp._boxState.view, "box", "a popup shields the board from taps")
if imp._boxPopup then keyboardChoice(imp, "escape") end
click(imp, "box-options")
click(imp, "box-popup-option-1")
T.check(imp._boxPrompt ~= nil and not imp._boxPopup, "rename opens the existing name prompt")
keyboardChoice(imp, "escape")

imp._boxState.notice, imp._boxState.noticeKind = "That bag pocket is full.", "error"; settle(imp)
local function boxToast() return imp._toasts and imp._toasts.box and imp._toasts.box.toast end
T.eq(boxToast() and boxToast().kind, "error", "a failed operation shows a red toast")
T.eq(imp._boxState.notice, nil, "notices no longer print inline")
T.check(controls["box-toast"] ~= nil, "the toast is drawn and tappable")
local toastRect = controls["box-toast"]
draw(imp, { x = toastRect.x + toastRect.w / 2, y = toastRect.y + toastRect.h / 2 }); settle(imp)
T.eq(boxToast(), nil, "tapping the toast dismisses it")
imp._boxState.notice, imp._boxState.noticeKind = "Pokémon deposited.", "ok"; settle(imp)
T.eq(boxToast().kind, "ok", "a success shows a green toast")
clock = clock + 10; settle(imp)
T.eq(boxToast(), nil, "a success toast times out")
UI.toast(imp, "Export failed", "error", nil, "red"); settle(imp)
T.eq(controls["box-toast"], nil, "another tab's toast is not drawn on the box tab")
T.eq(UI.currentToast(imp), nil, "another tab's toast does not occlude the box tab")
imp._toasts.red = nil

local changes = 0
UI.open(imp, "Pick", { { id = 1, label = "One" } }, nil, function() changes = changes + 1 end)
settle(imp)
local staleAction = controls["box-popup-option-1"].opts.action
staleAction(); staleAction()
T.eq(changes, 1, "a retired popup action cannot apply twice")
settle(imp)
UI.open(imp, "Box", UI.values((function() local out = {}; for i = 1, 25 do out[i] = i end; return out end)()), 1,
  function(value) changes = value end)
settle(imp); imp._padCursorActive = false; imp.isNX = false
for _ = 1, 10 do imp:gamepadpressed(nil, "dpdown"); settle(imp) end
T.eq(imp._boxPopup.index, 11, "controller navigation crosses the visible row boundary")
T.check(imp._boxPopup.scroll > 0, "controller reveals the selected option")
imp:gamepadpressed(nil, "a"); settle(imp)
T.eq(changes, 11, "controller A applies the revealed option")
UI.open(imp, "Box", UI.values((function() local out = {}; for i = 1, 25 do out[i] = i end; return out end)()), 1,
  function(value) changes = value end)
settle(imp)
local row = controls["box-popup-option-2"]
local fx, fy = row.x + row.w / 2, row.y + row.h / 2
View.touchpressed(imp, "finger", fx, fy)
for step = 1, 8 do View.touchmoved(imp, "finger", fx, fy - step * 30) end
settle(imp)
T.check(imp._boxPopup.scroll > 0, "a finger drag scrolls a long popup list")
local scrolled = imp._boxPopup.scroll
View.touchmoved(imp, "finger", fx, fy); settle(imp)
T.check(imp._boxPopup.scroll < scrolled, "dragging back scrolls the popup list up")
View.touchreleased(imp, "finger", fx, fy); settle(imp)
T.check(imp._boxPopup ~= nil, "a drag does not pick an option")
keyboardChoice(imp, "escape")
UI.open(imp, "Box", {}, nil); settle(imp)
imp:gamepadpressed(nil, "b"); settle(imp)
T.eq(imp._boxPopup, nil, "controller B closes help")
UI.open(imp, "Box", {}, nil); settle(imp)
draw(imp, { x = 1, y = 1 }); settle(imp)
T.eq(imp._boxPopup, nil, "outside tap closes without activating the launcher")
UI.open(imp, "Box", {}, nil); Kit.focus = "box-chooser-filter"
imp:_switchTab("mods")
T.eq(imp._boxPopup, nil, "leaving Box dismisses its popup")
T.eq(Kit.focus, nil, "leaving Box releases picker text focus")

Transition.reset(); Transition.armed = true; Transition.reduceMotion = false
local state = { view = "box" }
UI.change(imp, state, "view", "pc", 1)
Transition.update(clock + .06)
local positions, blocked = {}, {}
UI.pages(imp, state, 10, 20, 300, 400, {}, function(_, s, x)
  positions[s.view] = x; blocked[#blocked + 1] = Kit.blockClicks; return 400
end)
T.check(positions.box < 10 and positions.pc > 10, "both pages slide in the requested direction")
T.check(blocked[1] and blocked[2], "neither moving page accepts input")
Transition.update(clock + 1)
local draws = 0
UI.pages(imp, state, 10, 20, 300, 400, {}, function() draws = draws + 1; return 400 end)
T.eq(draws, 1, "finished slide draws only the current page")
T.eq(state.motionFrom, nil, "finished slide releases the old view")
Transition.reduceMotion = true
UI.change(imp, state, "view", "box", -1)
T.check(not Transition.active("box"), "reduced motion changes Box instantly")
Transition.reduceMotion = false; Transition.reset()
View.btn, love.graphics.print = original, printText
T.finish()
