local U = require("tests.drivers.util")
return function(game)
  U.wait(20)
  package.path = package.path .. ";./tools/save-editor/?.lua;./tools/save-editor/panels/?.lua"
  local App, path, tmp
  local dim, safe, osName, getTime = love.graphics.getDimensions, love.window.getSafeArea, love.system.getOS,
    love.timer.getTime
  local failures = 0
  local function pass(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then failures = failures + 1 end
  end
  local clock = 1000
  love.timer.getTime = function() return clock end
  local ok, err = xpcall(function()
    App = require("tools.save-editor.App")
    local Gen, Ops, Kit = require("Gen"), require("Ops"), require("Kit")
    local ItemPicker = require("ItemPicker")
    local Serializer = require("src.core.SaveSerializer")
    local version = require("src.core.GameVersion").get()
    local dir = assert(os.getenv("POKEPORT_SHOT_DIR"))
    tmp = os.tmpname()
    path = tmp .. "-toast-s6.lua"
    local file = assert(io.open(path, "wb"))
    file:write(Serializer.encode(Gen.newGame(version))); file:close()
    App.load(path, { version = version, embedded = true })
    local S = App.getState()
    assert(S.save and not S.loadError and not S.missingCache, S.status)
    Ops.partyAdd(S)
    Ops.selectParty(S, 1)
    local W, H, platform = 390, 844, "Android"
    local function render(draw, name)
      love.graphics.getDimensions = function() return W, H end
      love.window.getSafeArea = function() return 0, 0, W, H end
      love.system.getOS = function() return platform end
      local canvas = love.graphics.newCanvas(W, H, { msaa = 0 })
      love.graphics.push("all")
      love.graphics.setCanvas(canvas)
      love.graphics.origin()
      love.graphics.setScissor()
      love.graphics.setShader()
      require("src.render.GameViewport").reset()
      love.graphics.clear(0, 0, 0, 1)
      draw()
      love.graphics.setCanvas()
      love.graphics.pop()
      if name then
        local pixels = canvas:newImageData()
        local bytes = pixels:encode("png"):getString()
        pixels:release()
        local out = assert(io.open(dir .. "/" .. version .. "-" .. name .. ".png", "wb"))
        out:write(bytes); out:close()
      end
      canvas:release()
      love.graphics.getDimensions, love.window.getSafeArea, love.system.getOS = dim, safe, osName
    end
    local function frame(name) render(App.draw, name) end
    local function settle(name)
      frame()
      clock = clock + 1
      frame(name)
    end
    local function placed(label)
      local r = S.toast and S.toast.rect
      local statusH = (Kit.desktop and 28 or 38) * Kit.scale
      pass(r ~= nil and r[1] >= 0 and r[1] + r[3] <= W and r[2] >= 0 and r[2] + r[4] <= H - statusH,
        version .. " " .. label .. " toast is on screen above the status bar")
    end

    S.tab, S.monSection, S.mobileInspector = "party", "main", false
    Ops.setNickname(S, S.save.party[1], "TOASTY")
    settle("s6_01_ok_phone")
    pass(S.toast and S.toast.kind == "ok", version .. " phone nickname edit shows a green toast")
    placed("phone ok")

    while #S.save.party < 6 do Ops.partyAdd(S) end
    clock = clock + 10
    Ops.partyAdd(S)
    settle("s6_02_error_phone")
    pass(S.toast and S.toast.kind == "error" and S.toast.text == S.status,
      version .. " phone party-full refusal shows a red toast")
    placed("phone error")

    clock = clock + 10
    Ops.openItemPicker(S, Kit, "bag")
    frame(); frame()
    local item = assert(Ops.itemSearch(S, "potion")[1])
    ItemPicker.commit(S, Kit, item)
    settle("s6_03_ok_over_item_picker_phone")
    pass(S.itemPicker ~= nil and S.toast and S.toast.kind == "ok",
      version .. " item add toasts over the open picker")
    placed("phone picker")
    Ops.closeItemPicker(S, Kit)

    clock = clock + 10
    Ops.say(S, "Party is full (6/6)")
    S.mobileInspector, S.monSection, S.inspectorScroll = true, "main", 0
    Kit.focus = "mon-nickname"
    frame()
    clock = clock + 1
    Kit.focus = "mon-nickname"
    frame("s6_04_error_clear_of_focused_inspector_phone")
    local r, fr = S.toast and S.toast.rect, Kit.focusRect
    local rects, n = Kit.trackedControls()
    local covered = 0
    for i = 1, n do
      local c = rects[i]
      if r and c[1] < r[1] + r[3] and c[1] + c[3] > r[1] and c[2] < r[2] + r[4] and c[2] + c[4] > r[2] then
        covered = covered + 1
      end
    end
    pass(r ~= nil and fr ~= nil and n > 0 and covered == 0 and r[2] >= 0 and r[2] + r[4] <= H,
      version .. " focused phone field keeps the toast clear of every control (" .. covered .. " covered)")
    Kit.blur()
    S.mobileInspector = false
    frame()
    r = S.toast.rect
    local selected = S.selectedParty
    App.mousepressed(r[1] + r[3] / 2, r[2] + r[4] / 2, 1)
    frame()
    pass(S.toast == nil and S.selectedParty == selected, version .. " tapping the toast dismisses it and nothing under it")

    W, H, platform = 1360, 860, "OS X"
    clock = clock + 10
    Ops.arm(S, "party-remove-1", "Click Remove again to release slot 1")
    settle("s6_05_warn_arm_desktop")
    pass(S.toast and S.toast.kind == "warn", version .. " desktop arm shows a yellow toast")
    placed("desktop warn")
    clock = clock + 10
    Ops.setNickname(S, S.save.party[1], "SHINY")
    settle("s6_06_ok_desktop")
    pass(S.toast and S.toast.kind == "ok", version .. " desktop edit shows a green toast")
    placed("desktop ok")
    clock = clock + 10
    Ops.partyAdd(S)
    settle("s6_07_error_desktop")
    pass(S.toast and S.toast.kind == "error", version .. " desktop refusal shows a red toast")
    placed("desktop error")

    App.unload()
    App = nil

    local Importer = require("src.import.RomImporter")
    local Store = require("src.box.Store")
    local View = require("src.import.LauncherView")
    local imp = Importer.new(function() end, { launcher = true })
    local service = { state = Store.new() }
    service.read = function(_, source) return { version = source.version, party = {}, boxes = {} }, nil, source.path end
    imp.tab = "box"
    imp._boxState = { service = service, sources = {
      { version = "red", label = "Red", path = "first", slotId = "slot1" } },
      sourceIndex = 1, box = 1, pcBox = 1, query = "", sort = "slot", pcRows = {},
      selectedBox = {}, selectedPC = {}, pageBox = 1, pagePC = 1, view = "box", multi = true }
    W, H, platform = 1024, 768, "OS X"
    local function launcher(name) render(function() View.draw(imp) end, name) end
    launcher(); launcher()
    imp._boxState.notice, imp._boxState.noticeKind = "That bag pocket is full.", "error"
    launcher(); clock = clock + 1; launcher("s6_08_box_error_toast_desktop")
    local box = imp._toasts and imp._toasts.box and imp._toasts.box.toast
    pass(box ~= nil and box.kind == "error" and box.rect ~= nil, "BOX error toast still draws through BoxUI")
  end, debug.traceback)
  if App then App.unload() end
  love.graphics.getDimensions, love.window.getSafeArea, love.system.getOS = dim, safe, osName
  love.timer.getTime = getTime
  if path then
    os.remove(path)
    for _, backup in ipairs(require("tests.fs_io").globPrefix(path .. ".bak-")) do os.remove(backup) end
  end
  if tmp then os.remove(tmp) end
  if not ok then print("FAIL save_editor_toast_s6: " .. tostring(err)) end
  love.event.quit((ok and failures == 0) and 0 or 1)
end
