package.path = package.path .. ";./tools/save-editor/?.lua;./tools/save-editor/panels/?.lua"
_G.love = require("tests.love_stub")
local App = require("tools.save-editor.App")
local Ops, Gen, Kit = require("Ops"), require("Gen"), require("Kit")
local History = require("History")
local SD = require("src.core.SaveData")

local count = 0
local function check(ok, msg)
  count = count + 1
  assert(ok, msg)
end

local path = os.tmpname() .. "-inspector-layout.lua"
local f = assert(io.open(path, "wb"))
f:write(SD.encode(Gen.newGame("red")))
f:close()
App.load(path, { version = "red", embedded = true })
local S = App.getState()
assert(S.save and not S.loadError, S.status)
Ops.partyAdd(S)
Ops.partyAdd(S)
Ops.selectParty(S, 1)
local mon = S.editingMon
S.dirty = false

local function window(w, h, os)
  love.graphics.getDimensions = function() return w, h end
  love.window.getSafeArea = function() return 0, 0, w, h end
  love.system.getOS = function() return os end
end

local function controls()
  App.draw()
  Kit.audit = {}
  App.draw()
  local list = Kit.audit
  Kit.audit = nil
  return list
end

local function find(list, id)
  for _, c in ipairs(list) do
    if c.id == id then return c end
  end
end

local printed = {}
local realPrint = love.graphics.print
love.graphics.print = function(text, ...)
  printed[#printed + 1] = tostring(text)
  return realPrint(text, ...)
end

window(1280, 900, "OS X")
S.tab, S.monSection, S.inspectorScroll = "party", "main", 0
local list = controls()
local seen = {}
for _, text in ipairs(printed) do seen[text] = true end
love.graphics.print = realPrint
check(seen.Saved and seen["Save editor"], "title bar shows the save state as plain text")
for text in pairs(seen) do
  check(not text:find("●", 1, true), "no status dot in the title bar")
end
check(find(list, "tab-monSection-moves") ~= nil, "wide inspectors use section tabs")
check(find(list, "change-species") ~= nil, "species has a Change button")

local box = assert(find(list, "value-level"), "level value box")
local undo = #S.undoStack
App.mousepressed(box.x + box.w / 2, box.y + box.h / 2, 1)
App.draw()
check(Kit.focus == "value-edit-level", "tapping the value box edits it inline")
for _ = 1, 4 do App.keypressed("backspace") end
App.textinput("4x2")
App.draw()
App.keypressed("return")
App.draw()
check(mon.level == 42, "typed level commits on Enter (got " .. tostring(mon.level) .. ")")
check(#S.undoStack == undo + 1, "one commit is one undo")

list = controls()
box = assert(find(list, "value-level"), "level value box after commit")
App.mousepressed(box.x + box.w / 2, box.y + box.h / 2, 1)
App.draw()
App.textinput("9")
App.draw()
App.keypressed("escape")
App.draw()
check(mon.level == 42 and Kit.focus == nil, "Escape discards an inline edit")

local slider = assert(find(list, "slider-level"), "level slider")
undo = #S.undoStack
local sy = slider.y + slider.h / 2
App.touchpressed("slide", slider.x + slider.w * 0.2, sy)
App.draw()
App.touchmoved("slide", slider.x + slider.w * 0.6, sy)
App.draw()
App.touchmoved("slide", slider.x + slider.w * 0.95, sy)
App.draw()
check(mon.level == 42, "dragging the slider only previews")
App.touchreleased("slide", slider.x + slider.w * 0.95, sy)
App.draw()
check(mon.level > 90, "releasing the slider commits (got " .. tostring(mon.level) .. ")")
check(#S.undoStack == undo + 1, "a whole drag is one undo")

local first = next(S.data.moves)
Ops.setMove(S, mon, 1, S.data.moves[first].id or first)
Ops.setPpUps(S, mon, 1, 2)
S.monSection, S.inspectorScroll = "moves", 0
list = controls()
local zero = assert(find(list, "ppup-1-0"), "PP Ups segment 0")
App.mousepressed(zero.x + zero.w / 2, zero.y + zero.h / 2, 1)
App.draw()
check(require("MonOps").getPpUps(mon, 1) == 0, "PP Ups segment sets the count")
check(find(list, "move-1") ~= nil and find(list, "slider-pp-1") ~= nil, "move card has Change and a PP slider")

window(390, 844, "Android")
S.monSection, S.inspectorScroll = "main", 0
list = controls()
local tiles = {}
for _, c in ipairs(list) do
  if c.class == "row" then tiles[#tiles + 1] = c end
end
check(#tiles >= 2, "phone shows the party grid above the inspector")
local heal
for _, c in ipairs(list) do
  if c.label == "Full heal" then heal = c end
end
check(heal and heal.y > tiles[#tiles].y, "phone shows the inspector below the party grid")
App.touchpressed("tile", tiles[2].x + tiles[2].w / 2, tiles[2].y + tiles[2].h / 2)
App.touchreleased("tile", tiles[2].x + tiles[2].w / 2, tiles[2].y + tiles[2].h / 2)
App.draw()
check(S.editingMon == S.save.party[2], "tapping a party tile selects it")

History.undo(S)
os.remove(path)
print(("save editor inspector layout: %d checks passed"):format(count))
