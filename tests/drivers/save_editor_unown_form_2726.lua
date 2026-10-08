local U = require("tests.drivers.util")
return function(game)
  U.wait(20)
  package.path = package.path .. ";./tools/save-editor/?.lua;./tools/save-editor/panels/?.lua"
  local App, Paint, Kit, path, tmp, oldPaint
  local dim, safe, osName, getTime = nil, nil, nil, love.timer.getTime
  local clock = 1000
  love.timer.getTime = function() return clock end
  local failures = 0
  local function pass(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then failures = failures + 1 end
  end
  local ok, err = xpcall(function()
    App = require("tools.save-editor.App")
    local Gen, Ops, MonOps = require("Gen"), require("Ops"), require("MonOps")
    local Touch, History = require("TouchEditor"), require("History")
    local Serializer = require("src.core.SaveSerializer")
    local version = require("src.core.GameVersion").get()
    local dir = assert(os.getenv("POKEPORT_SHOT_DIR"))
    Kit, Paint = require("Kit"), require("src.ui.kit.Button")
    dim, safe, osName = love.graphics.getDimensions, love.window.getSafeArea, love.system.getOS
    local controls = {}
    oldPaint = Paint.draw
    Paint.draw = function(owner, x, y, w, h, label, opts, hot, focused)
      if owner == Kit then controls[opts.id or label] = { x = x, y = y, w = w, h = h, label = label } end
      return oldPaint(owner, x, y, w, h, label, opts, hot, focused)
    end
    tmp = os.tmpname()
    path = tmp .. "-unown-2726.lua"
    local file = assert(io.open(path, "wb"))
    file:write(Serializer.encode(Gen.newGame(version))); file:close()
    App.load(path, { version = version, embedded = true })
    local S = App.getState()
    assert(S.save and not S.loadError and not S.missingCache, S.status)
    local g = Gen.ofState(S)
    local mon = MonOps.create(S.data, g == 3 and MonOps.SPECIES_UNOWN_G3 or "UNOWN", 25, g)
    if g == 3 then
      mon.otId, mon.otSecretId = S.save.player and S.save.player.trainerId or 0, S.save.player and S.save.player.secretId or 0
    end
    S.save.party = { mon }
    Ops.selectParty(S, 1)
    local seed = g == 3 and 5 or 6
    if Ops.unownForm(S, mon) == seed then assert(Ops.setUnownForm(S, mon, seed + 1), "seed form G") end
    assert(Ops.setUnownForm(S, mon, seed), "seed form F")
    S.dirty = false
    local W, H, platform = 390, 844, "Android"
    local function frame(name)
      controls = {}
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
      App.draw()
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
    local function tap(id)
      local r = assert(controls[id], "missing control " .. id)
      App.mousepressed(r.x + r.w / 2, r.y + r.h / 2, 1)
      frame()
      frame()
    end
    local function current() return Ops.unownForm(S, S.save.party[1]) end
    local function letterName() return Ops.unownFormName(S, current()) end
    local function pick(letter)
      local p = assert(S.editPopup, "form popup open")
      p.query, p.index = "", nil
      for i, o in ipairs(p.options) do if o[1] == letter then p.index = i end end
      assert(p.index, "option present")
      Touch.commit(S, Kit)
      frame()
    end

    local Toast = require("src.ui.kit.Toast")
    S.tab, S.monSection, S.mobileInspector = "party", "main", false
    Toast.clear(S)
    frame(); frame("2726_01_roster_unown_f_phone")
    pass(letterName() == "F", version .. " roster seeded with UNOWN F")

    S.mobileInspector = true
    frame(); frame()
    local r = controls["choice-form"]
    for _ = 1, 40 do
      if r and r.y >= H * 0.3 and r.y + r.h <= H * 0.7 then break end
      S.inspectorScroll = (S.inspectorScroll or 0) + 40
      frame()
      r = controls["choice-form"]
    end
    frame("2726_02_form_picker_row_phone")
    pass(r ~= nil, version .. " phone inspector shows the Unown form picker")
    pass(r and r.label == "Unown form: F", version .. " picker reads the current letter (" .. tostring(r and r.label) .. ")")
    tap("choice-form")
    pass(S.editPopup and S.editPopup.id == "form", version .. " tapping the picker opens the touch chooser")
    pass(S.editPopup and #S.editPopup.options == (g == 3 and 28 or 26), version .. " chooser lists every form")
    frame("2726_03_form_chooser_open_phone")
    local target = g == 3 and 27 or 17
    pick(target)
    pass(current() == target, version .. " chooser sets the form to " .. letterName())
    pass(S.dirty, version .. " form edit marks the save dirty")
    frame()
    clock = clock + 1
    frame("2726_04_form_set_" .. letterName():gsub("%?", "qmark") .. "_phone")
    pass(History.undo(S) and letterName() == "F", version .. " undo restores F")
    pass(History.redo(S) and current() == target, version .. " redo reapplies")
    Ops.selectParty(S, 1)

    W, H, platform = 1100, 720, "Linux"
    S.inspectorScroll = 0
    Toast.clear(S)
    frame(); frame()
    for _ = 1, 40 do
      r = controls["choice-form"]
      if r and r.y >= 0 and r.y + r.h <= H then break end
      S.inspectorScroll = (S.inspectorScroll or 0) + 80
      frame()
    end
    frame("2726_05_desktop_docked_picker_and_roster")
    pass(controls["choice-form"] ~= nil, version .. " desktop docked inspector shows the picker")

    assert(App.save(), "save")
    App.unload()
    App.load(path, { version = version, embedded = true })
    S = App.getState()
    mon = S.save.party[1]
    pass(Ops.unownForm(S, mon) == target, version .. " reopened save keeps the form")
  end, debug.traceback)
  if App then App.unload() end
  if Paint and oldPaint then Paint.draw = oldPaint end
  if dim then love.graphics.getDimensions, love.window.getSafeArea, love.system.getOS = dim, safe, osName end
  love.timer.getTime = getTime
  if path then
    os.remove(path)
    for _, backup in ipairs(require("tests.fs_io").globPrefix(path .. ".bak-")) do os.remove(backup) end
  end
  if tmp then os.remove(tmp) end
  if not ok then print("FAIL save_editor_unown_form_2726: " .. tostring(err)) end
  love.event.quit((ok and failures == 0) and 0 or 1)
end
