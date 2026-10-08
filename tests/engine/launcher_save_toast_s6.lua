package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")
local T = require("tests.harness")
local Kit = require("src.ui.kit.Kit")
local UI = require("src.import.BoxUI")
local View = require("src.import.LauncherView")
local Importer = require("src.import.RomImporter")
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
love.graphics.getDimensions = function() return 1024, 768 end
love.graphics.getPixelDimensions = function() return 1024, 768 end
local imp = Importer.new(function() end, { launcher = true })
imp.tab = "red"
Transition.reset(); Kit.blur()
local function draw(click)
  clock = clock + .3; controls, texts = {}, {}
  imp._clickPt = click; imp:draw()
  local queue = imp._uiActions; imp._uiActions = {}
  imp:runActions(queue or {})
end
local function printed(text)
  for _, t in ipairs(texts) do if t:find(text, 1, true) then return true end end
  return false
end

imp.saveNotice = imp.saveNotice or {}
imp.saveNotice.red = { ok = false, text = "Export failed" }
draw(); draw()
local store = imp._toasts and imp._toasts.red
T.eq(store and store.toast and store.toast.kind, "error", "a failed save-card result raises a red toast")
T.eq(imp.saveNotice.red, nil, "the save card no longer keeps the failure text inline")
T.check(controls["box-toast"] ~= nil, "the launcher save toast is drawn and tappable")
T.check(printed("Export failed"), "the toast prints the save-card text")
local r = controls["box-toast"]
draw({ x = r.x + r.w / 2, y = r.y + r.h / 2 }); draw()
T.eq(imp._toasts.red.toast, nil, "tapping the save toast dismisses it")

imp.saveNotice.red = { ok = true, text = "Exported to /tmp/x/red.sav", dir = "/tmp/x" }
draw(); draw()
T.eq(imp._toasts.red.toast and imp._toasts.red.toast.kind, "ok", "an export success raises a green toast")
T.eq(imp.saveNotice.red and imp.saveNotice.red.dir, "/tmp/x", "the export keeps its folder for the inline Open folder button")
T.eq(imp.saveNotice.red and imp.saveNotice.red.text, "", "the export text moves out of the card")
T.check(printed("Open folder"), "the Open folder button stays on the save card")

imp.saveNotice.red = { ok = true, kind = "info", text = "Pick where to save red.sav..." }
draw()
T.eq(imp._toasts.red.toast.kind, "info", "a neutral notice raises a blue toast")

UI.toast(imp, nil, nil, nil, "red")
imp.saveNotice.red = { ok = true, persistent = true, text = "Copy your Red .sav into: sdmc:/x" }
draw(); draw()
T.eq(imp._toasts.red.toast, nil, "persistent instructions raise no toast")
T.eq(imp.saveNotice.red and imp.saveNotice.red.text, "Copy your Red .sav into: sdmc:/x",
  "persistent instructions stay inline")

imp.saveNotice.red = nil
imp.saveNotice.blue = { ok = false, text = "Could not open the save editor (boom)." }
draw()
T.eq(imp._toasts.red.toast and imp._toasts.red.toast.text, "Could not open the save editor (boom).",
  "an editor refusal toasts on the tab the player is on")

View.btn, love.graphics.print = original, printText
T.finish()
