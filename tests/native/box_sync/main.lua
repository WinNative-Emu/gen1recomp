io.stdout:setvbuf("no")
function love.errorhandler(why)
  print("BOX_NATIVE_FAIL bootstrap: " .. tostring(why))
  return function() return 1 end
end
local repo = assert(os.getenv("BOX_TEST_REPO"))
local url = assert(os.getenv("BOX_TEST_URL"))
assert(url:match("^http://127%.0%.0%.1:%d+$"), "loopback server required")
assert(love.filesystem.getInfo("src/net/fetch_worker.lua"), "native test must bundle the project sources")
package.path = repo .. "/?.lua;" .. repo .. "/?/init.lua;" .. package.path
local realFs = love.filesystem
local SaveData = require("src.core.SaveData")
local Serializer = require("src.core.SaveSerializer")
local Store = require("src.box.Store")
local Engine = require("src.sync.SyncEngine")
local SyncState = require("src.sync.SyncState")
local SyncBox = require("src.sync.SyncBox")
local Fetch = require("src.net.Fetch")
local checks, stage, shots = 0, "starting", {}
local function check(value, label)
  checks = checks + 1; assert(value, label)
end
local function deviceFs(name)
  local fs = setmetatable({}, { __index = realFs })
  for _, method in ipairs({ "read", "write", "getInfo", "remove", "createDirectory", "getDirectoryItems" }) do
    fs[method] = function(path, ...) return realFs[method](name .. "/" .. path, ...) end
  end
  fs.getSaveDirectory = function() return realFs.getSaveDirectory() .. "/" .. name end
  fs.getSource, fs.getWorkingDirectory, fs.getSourceBaseDirectory = realFs.getSource, realFs.getWorkingDirectory, realFs.getSourceBaseDirectory
  fs.getRealDirectory, fs.load = realFs.getRealDirectory, realFs.load
  return fs
end
local function context(fs)
  love.filesystem = fs; SaveData.resetSlotState()
end
local function write(fs, path, value)
  local parent = path:match("^(.*)/[^/]+$"); if parent then assert(fs.createDirectory(parent)) end
  assert(fs.write(path, Serializer.encode(value)))
end
local function newEngine(fs)
  context(fs)
  local state = SyncState.defaults(); state.enabled = true
  return Engine.new({ fs = fs, state = state, baseUrl = url })
end
local function pump(e, fs)
  local deadline = love.timer.getTime() + 15
  repeat
    context(fs); e:update(1 / 60); coroutine.yield()
    assert(love.timer.getTime() < deadline, "sync timeout")
  until not e:busy()
  check(e.phase ~= "error", tostring(e.error))
end
local function read(fs, p)
  local body = fs.read(p)
  return assert(Serializer.decode(body))
end
local function run()
  local fsA, fsB = deviceFs("a"), deviceFs("b")
  local state = Store.new(); state.nextId = 2
  state.boxes[1].mons[1] = { id = 1, version = "red", generation = 1, slotId = "slot1",
    mon = { species = "PIKACHU", level = 12, opaque = "\0\255" }, display = {} }
  state.syncMembers = { ["red/loopback"] = { version = "red", playthroughId = "loopback", slotId = "slot1", path = "saves/red/slot1.lua" } }
  state.presets = { { name = "Native team", ids = { 1 } } }
  state.stages = { require("src.box.Showcase").new() }
  state.gciTemplate = string.rep("GCI template fixture", 300000)
  local pixels = love.image.newImageData(1136, 432)
  pixels:mapPixel(function() return 0.15, 0.35, 0.5, 1 end)
  state.boxes[1].theme, state.boxes[1].wallpaper = "Showcase", "box/showcase/1.png"
  assert(fsA.createDirectory("box/showcase")); local png = pixels:encode("png"):getString()
  assert(fsA.write(state.boxes[1].wallpaper, png)); pixels:release()
  write(fsA, Store.PATH, state)
  write(fsA, "saves/red/slot1.lua", { version = "red", generation = 1, player = { name = "RED" }, party = {}, boxes = { {} },
    pokedex = { seen = {}, owned = {} }, inventory = {}, meta = { playthroughId = "loopback", savedAt = 1700000000 } })
  local A = newEngine(fsA); stage = "uploading native HTTP snapshot"
  assert(A:createAccount("native test A")); pump(A, fsA)
  check(A.state.boxRev == 1, "first collection revision")
  check(#A.box:snapshot(A.saves.list(), A.state).payload.blob > 4 * 1024 * 1024, "reply exceeds ordinary save limit")
  write(fsB, "saves/red/slot1.lua", { version = "red", player = { name = "LOCAL" }, meta = { playthroughId = "independent", savedAt = 1700000000 } })
  write(fsB, "options.lua", { saveSlots = { red = { list = { "slot1" }, active = "slot1" } }, custom = "device B" })
  local B = newEngine(fsB); stage = "receiving on second device"
  assert(B:linkDevice(A.state.code1, A.state.code2, "native test B")); pump(B, fsB)
  local remote = read(fsB, Store.PATH)
  check(remote.syncMembers["red/loopback"].slotId == "slot2", "production adapter remaps slots")
  check(remote.boxes[1].mons[1].slotId == "slot2", "origin remapped")
  check(remote.gciTemplate == state.gciTemplate, "large template unchanged")
  check(remote.presets[1].name == "Native team", "team synced")
  check(remote.stages[1].name == state.stages[1].name, "stage synced")
  check(fsB.read("box/showcase/1.png") == png, "real PNG synced")
  check(read(fsB, "options.lua").custom == "device B", "device options retained")
  check(read(fsB, "saves/red/slot2.lua").meta.playthroughId == "loopback", "production save routing")
  local receivedRev = B.state.boxRev; assert(B:syncNow()); pump(B, fsB)
  check(B.state.boxRev == receivedRev, "no redundant upload after remapping")
  context(fsA); local s = read(fsA, Store.PATH); s.boxes[1].name = "A offline edit"; write(fsA, Store.PATH, s)
  assert(A:syncNow()); pump(A, fsA)
  context(fsB); s = read(fsB, Store.PATH); s.boxes[1].name = "B offline edit"; write(fsB, Store.PATH, s)
  assert(B:syncNow()); pump(B, fsB)
  check(B.conflicts[1] and B.conflicts[1].box, "production HTTP conflict")
  check(not B:resolveConflict(SyncBox.KEY, "both"), "whole collection choice required")
  stage = "capturing Box conflict"
  local imp = require("src.import.RomImporter").new(function() end, { launcher = true })
  imp._sync, imp._syncTransportOk = B, true; imp:_openSync()
  local previousDraw = love.draw
  local pending
  love.draw = function()
    imp:draw()
    if pending then
      local p = pending; pending = nil
      love.graphics.captureScreenshot(function(image)
        local encoded = image:encode("png"):getString()
        assert(realFs.write(p, encoded)); shots[#shots + 1] = p
      end)
    end
  end
  for _, view in ipairs({ { 1024, 768, "conflict-desktop.png" }, { 390, 844, "conflict-portrait.png" } }) do
    love.window.setMode(view[1], view[2], { resizable = true })
    for _ = 1, 3 do imp:update(1 / 60); coroutine.yield() end
    pending = view[3]; while pending do coroutine.yield() end
    for _ = 1, 3 do coroutine.yield() end
  end
  love.draw = previousDraw
  check(#shots == 2, "desktop and portrait conflict rendered")
  assert(B:resolveConflict(SyncBox.KEY, "remote")); pump(B, fsB)
  check(read(fsB, Store.PATH).boxes[1].name == "A offline edit", "remote collection selected")
  check(B.box:latestBackup() ~= nil, "recoverable losing snapshot")
  check(SyncState.load(fsB).boxRev == B.state.boxRev, "sync baseline persisted")
  stage = "complete"
  love.filesystem = realFs
  Fetch.shutdown()
  print(("BOX_NATIVE_PASS %d checks; screenshots: %s"):format(checks, realFs.getSaveDirectory()))
  love.event.quit(0)
end
local co
function love.load() co = coroutine.create(run) end
function love.update()
  if coroutine.status(co) == "dead" then return end
  local ok, why = coroutine.resume(co)
  if not ok then
    print("BOX_NATIVE_FAIL " .. stage .. ": " .. tostring(why)); love.filesystem = realFs
    Fetch.shutdown(); love.event.quit(1)
  end
end
function love.draw()
  love.graphics.clear(0.04, 0.06, 0.1); love.graphics.print(stage, 30, 30)
end
