package.path = package.path .. ";./?.lua;./?/init.lua;./tools/save-editor/?.lua;./tools/save-editor/panels/?.lua"
love = require("tests.love_stub")
local T = require("tests.harness")
local clock = 200
love.timer.getTime = function() return clock end
local App = require("tools.save-editor.App")
local Ops, Gen, Kit = require("Ops"), require("Gen"), require("Kit")
local SD = require("src.core.SaveData")

local path = os.tmpname() .. "-toast.lua"
local f = assert(io.open(path, "wb"))
f:write(SD.encode(Gen.newGame("red")))
f:close()
local loaded = pcall(App.load, path, { version = "red", embedded = true })
local S = App.getState()
if not loaded or not S or not S.save or S.missingCache then
  os.remove(path)
  print("[skip] save_editor_toast_s6: no red data")
  os.exit(0)
end

T.check(S.toast and (S.toast.kind == "ok" or S.toast.kind == "warn" and S.status:find("quarantine", 1, true)),
  "loading a save raises a green toast, yellow when the game would quarantine")
T.eq(S.toast and S.toast.text, S.status, "the load toast says what the status says")

while #S.save.party < 6 do Ops.partyAdd(S) end
clock = clock + 1
Ops.partyAdd(S)
T.eq(S.toast and S.toast.kind, "error", "a refusal raises a red toast")
T.eq(S.toast and S.toast.text, S.status, "the refusal toast carries the status text")

local mon = S.save.party[1]
clock = clock + 1
Ops.setNickname(S, mon, "TOASTY")
T.eq(S.toast and S.toast.kind, "ok", "a successful edit raises a green toast")
clock = clock + 1
Ops.setNickname(S, mon, "TOASTY")
T.eq(S.toast and S.toast.kind, "info", "a no-op edit raises a blue toast")

clock = clock + 1
Ops.arm(S, "party-remove-1", "Click Remove again to release slot 1")
T.eq(S.toast and S.toast.kind, "warn", "an armed confirm raises a yellow toast")
T.eq(S.toast and S.toast.hold, Ops.ARM_SECONDS, "the confirm toast lasts the arm window")
Ops.disarm(S)
T.eq(S.toast, nil, "disarming drops the confirm toast")

clock = clock + 1
Ops.say(S, "Party is full (6/6)")
local before = S.toast
Ops.selectParty(S, 2)
T.eq(S.toast, before, "selecting a slot does not toast")
T.check(S.note:find("Selected party slot 2", 1, true) ~= nil, "selection narration lands in the status bar note")

clock = clock + 1
Ops.mark(S, "Repeat edit")
local at = S.toast.at
clock = clock + .05
Ops.mark(S, "Repeat edit")
T.eq(S.toast.at, at, "a repeated toast does not slide in again")

clock = clock + 1
T.check(App.save(), "scratch save writes")
T.eq(S.toast and S.toast.kind, "ok", "saving raises a green toast")
T.check(S.toast and S.toast.text:find("Saved ", 1, true) == 1, "the save toast names the save")

T.eq(require("ItemPicker").feedback, nil, "the item picker has no private toast")

local printed = {}
local oldPrint, oldOS = love.graphics.print, love.system.getOS
love.graphics.print = function(text, ...)
  printed[#printed + 1] = tostring(text)
  return oldPrint(text, ...)
end
local function frame(w, h, os)
  love.graphics.getDimensions = function() return w, h end
  love.window.getSafeArea = function() return 0, 0, w, h end
  love.system.getOS = function() return os end
  printed = {}
  clock = clock + .3
  App.draw()
end
local function count(text)
  local n = 0
  for _, line in ipairs(printed) do if line == text then n = n + 1 end end
  return n
end
for _, shape in ipairs({ { 390, 844, "Android" }, { 1360, 860, "OS X" } }) do
  S.tab, S.mobileInspector = "party", false
  clock = clock + 10
  Ops.say(S, "Party is full (6/6)")
  frame(shape[1], shape[2], shape[3])
  frame(shape[1], shape[2], shape[3])
  T.eq(count("Party is full (6/6)"), 1, "the result prints once, in the toast, at " .. shape[3])
  local r = S.toast and S.toast.rect
  T.check(r and r[2] + r[4] <= shape[2] and r[1] >= 0 and r[1] + r[3] <= shape[1],
    "the toast sits on screen at " .. shape[3])
  local selected, revision = S.selectedParty, S.revision
  App.mousepressed(r[1] + r[3] / 2, r[2] + r[4] / 2, 1)
  frame(shape[1], shape[2], shape[3])
  T.eq(S.toast, nil, "tapping the toast dismisses it at " .. shape[3])
  T.eq(S.selectedParty, selected, "the tap does not reach the row under the toast at " .. shape[3])
  T.eq(S.revision, revision, "the tap does not edit anything at " .. shape[3])
end

clock = clock + 10
Ops.say(S, "Party is full (6/6)")
frame(390, 844, "Android")
local low = S.toast.rect[2]
Kit.focus = "mon-nickname"
frame(390, 844, "Android")
T.check(S.toast.rect[2] < 844 / 2 and S.toast.rect[2] < low, "a focused field on a phone moves the toast above the keyboard")
Kit.blur()

local MapBrowser, ItemPicker = require("MapBrowser"), require("ItemPicker")
local function auditFrame(shape)
  love.graphics.getDimensions = function() return shape[1], shape[2] end
  love.window.getSafeArea = function() return 0, 0, shape[1], shape[2] end
  love.system.getOS = function() return shape[3] end
  clock = clock + .3
  Kit.audit = {}
  App.draw()
  local got = Kit.audit
  Kit.audit = nil
  return got
end
local function covered(audit, r)
  local out = {}
  for _, c in ipairs(audit) do
    local x1, y1, x2, y2 = c.x, c.y, c.x + c.w, c.y + c.h
    if c.clip then
      x1, y1 = math.max(x1, c.clip.x), math.max(y1, c.clip.y)
      x2, y2 = math.min(x2, c.clip.x + c.clip.w), math.min(y2, c.clip.y + c.clip.h)
    end
    if c.class == "control" and x1 < x2 and y1 < y2 and x1 < r[1] + r[3] and x2 > r[1]
      and y1 < r[2] + r[4] and y2 > r[2] then
      out[#out + 1] = c.label
    end
  end
  return out
end
local function clear(name, shape)
  local audit = auditFrame(shape)
  local r = S.toast and S.toast.rect
  T.check(r ~= nil, name .. ": the toast is drawn")
  if not r then return end
  local hits = covered(audit, r)
  T.eq(#hits, 0, name .. ": no control sits under the toast [" .. table.concat(hits, ", ") .. "]")
  T.check(r[1] >= 0 and r[1] + r[3] <= shape[1] and r[2] >= 0 and r[2] + r[4] <= shape[2],
    name .. ": the toast stays on screen")
end
local phone, desktop = { 390, 844, "Android" }, { 1360, 860, "OS X" }

S.tab = "items"
Ops.openItemPicker(S, Kit, "bag")
auditFrame(phone); auditFrame(phone)
local item = assert(Ops.itemSearch(S, "potion")[1])
clock = clock + 10
ItemPicker.commit(S, Kit, item)
T.eq(S.toast and S.toast.kind, "ok", "the picker add toasts")
clear("phone item picker after add", phone)
local picker = {}
for _, c in ipairs(auditFrame(phone)) do picker[c.label] = c end
T.check(picker["item-picker"] and picker.Bag and picker.PC, "the picker field and chips are still drawn")
local hdr = S.toastHeader
T.check(hdr and S.toast.rect[2] < picker.Bag.y and hdr.y <= S.toast.rect[2] + S.toast.rect[4],
  "the picker toast sits on the popup header row above the chips")
clear("desktop item picker after add", desktop)
Ops.closeItemPicker(S, Kit)

S.tab, S.mapSection, S.mapFocused = "map", "view", false
MapBrowser.select(S, "PALLET_TOWN")
auditFrame(phone); auditFrame(phone)
S.mapClickCell = { cx = 5, cy = 5 }
clock = clock + 10
Ops.setLastHeal(S)
T.eq(S.toast and S.toast.kind, "ok", "Heal toasts on the phone map")
clear("phone map after Heal", phone)
auditFrame(desktop); auditFrame(desktop)
clock = clock + 10
Ops.setLastHeal(S)
clear("desktop map after Heal", desktop)

S.tab, S.mapSection = "map", "maps"
auditFrame(phone); auditFrame(phone)
clock = clock + 10
Ops.say(S, "Jumped to PALLET_TOWN (5,5)", "ok")
clear("phone map list after a jump", phone)

S.tab, S.mobileInspector = "party", false
Ops.selectParty(S, 1)
auditFrame(phone); auditFrame(phone)
clock = clock + 10
Ops.setNickname(S, S.save.party[1], "TOASTIER")
clear("phone party after nickname edit", phone)

S.mobileInspector, S.monSection, S.inspectorScroll = true, "main", 0
auditFrame(phone); auditFrame(phone)
clock = clock + 10
Ops.say(S, "Party is full (6/6)")
Kit.focus = "mon-nickname"
clear("phone focused nickname field", phone)
T.check(Kit.focusRect ~= nil, "the nickname field is drawn while focused")
Kit.blur()
S.mobileInspector = false

auditFrame(desktop); auditFrame(desktop)
clock = clock + 10
Ops.arm(S, "party-remove", "Click Remove again to release slot 1")
T.eq(S.toast and S.toast.kind, "warn", "arming Remove toasts on the desktop")
local remove
for _, c in ipairs(auditFrame(desktop)) do if c.label == "Confirm?" or c.label == "Remove" then remove = c end end
T.check(remove ~= nil, "the Remove button is drawn while armed")
if remove then
  local r = S.toast.rect
  T.check(r[2] + r[4] <= remove.y or r[2] >= remove.y + remove.h or r[1] >= remove.x + remove.w
    or r[1] + r[3] <= remove.x, "the arm toast does not overlap the Remove button it names")
end
Ops.disarm(S)

love.graphics.print, love.system.getOS = oldPrint, oldOS
os.remove(path)
T.finish("save_editor_toast_s6")
