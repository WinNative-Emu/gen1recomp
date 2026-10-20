package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Loader = require("src.mods.Loader")
local Version = require("src.core.GameVersion")
local Versions = require("src.import.gba.versions")
local Profile = require("src.core.game3.profile")
local Runtime = require("src.core.game3.runtime")
local Stack = require("src.ui.game3.stack")
local Hud = require("src.ui.game3.hud")
local UiPass = require("src.ui.game3.ui_pass")
local Message = require("src.ui.game3.message")
local StateStack = require("src.core.StateStack")
local Font = require("src.ui.game3.frlg_font")
local realMeasure = Font.measure
Font.measure = function(text) return #tostring(text) * 6 end

local originalVersion, originalNativeVersion = Version.get(), Versions.active()

local BODY = [[
local mod = ...
local out = mod.exports
out.log = { draws = 0, updates = 0, enters = 0, exits = 0, pops = 0 }
local Probe = {}
Probe.__index = Probe
function Probe.new(game, opts)
  local self = setmetatable({ game = game, opts = opts }, Probe)
  return self
end
function Probe:enter() out.log.enters = out.log.enters + 1 end
function Probe:exit() out.log.exits = out.log.exits + 1 end
function Probe:update(dt)
  out.log.updates = out.log.updates + 1
  local input = self.game.input
  if input:wasPressed("down") then out.log.downs = (out.log.downs or 0) + 1 end
  if input:wasPressed("b") then
    out.log.pops = out.log.pops + 1
    self.game.stack:pop()
  end
end
function Probe:draw()
  out.log.draws = out.log.draws + 1
  out.log.originX = love.graphics.getTransform and nil
  love.graphics.rectangle("fill", 0, 0, 10, 10)
end
mod.content.screens:register("ProbeScreen", { new = function(game, opts) return Probe.new(game, opts) end })
out.factory = { new = function(game, opts) return Probe.new(game, opts) end }
out.open = function(opts) return mod.ui.push(mod.game, "ProbeScreen", opts) end
out.text = function(text, done)
  local TextBox = mod.ui.TextBox
  mod.game.stack:push(TextBox.new(mod.game, text, done))
end
]]

local function press(key)
  return {
    wasPressed = function(_, k) return k == key end,
    isDown = function(_, k) return k == key end,
  }
end
local idle = press("none")

local function setup(version)
  Version.set(version)
  Versions.select(version)
  Profile.reset()
  local data = T.sdk.gen3Data()
  local session = { version = version, party = {}, options = {}, flags = {}, vars = {}, name = "RED" }
  local game = { data = data, session = session, options = session.options, phase = "field", input = idle }
  session.game = game
  T.sdk.captureRuntime()
  local files = {
    ["mods/ui/manifest.json"] = '{"id":"ui","name":"ui","version":"1.0.0","api":3,"games":["all"],"entry":"main.lua"}',
    ["mods/ui/main.lua"] = BODY,
  }
  local loader = Loader.new({ fs = T.sdk.memfs(files), generation = 3, version = version, dev = true })
  loader.game = game
  T.check(loader:load(data), version .. " loads")
  T.check(type(data.screens) == "table" and type(data.screens.ProbeScreen) == "table",
    version .. " mod.content.screens lands in game.data.screens")
  local prevActive, prevSession = Runtime.active, Runtime.session
  Runtime.active, Runtime.session = true, session
  return loader.exports.ui, game, function()
    Runtime.active, Runtime.session = prevActive, prevSession
    Stack.clear()
    T.sdk.restoreRuntime()
  end
end

for _, version in ipairs({ "firered", "emerald", "ruby" }) do
  local out, game, done = setup(version)
  local ok, err = xpcall(function()
    T.eq(Stack.depth(), 0, version .. " starts with an empty stack")
    T.check(not Hud.isMenuOpen(), version .. " field is free before the push")
    local inst = out.open({ x = 1 })
    T.check(inst ~= nil and out.log.enters == 1, version .. " push builds and enters the screen")
    T.eq(Stack.depth(), 1, version .. " the screen is a game3 stack layer")
    T.eq(game.stack:top(), inst, version .. " game.stack:top is the mod state")
    T.check(Hud.isMenuOpen() and Hud.busy(), version .. " the open screen blocks the field")

    UiPass.drawUi()
    T.check(out.log.draws >= 1, version .. " the screen draws in the UI pass")

    game.input = press("down")
    Hud.update(game, 1 / 60)
    T.check(out.log.updates >= 1 and out.log.downs == 1, version .. " the screen receives Gen 3 input")
    T.eq(Stack.depth(), 1, version .. " unrelated input keeps the screen open")

    game.input = press("b")
    Hud.update(game, 1 / 60)
    T.eq(out.log.pops, 1, version .. " B reaches the screen")
    T.eq(Stack.depth(), 0, version .. " the screen pops its layer")
    T.eq(out.log.exits, 1, version .. " exit runs on pop")
    T.check(not Hud.isMenuOpen(), version .. " the field is released after the pop")

    game.input = idle
    out.open()
    out.open()
    T.eq(Stack.depth(), 2, version .. " screens nest")
    Stack.clear()
    T.eq(out.log.exits, 3, version .. " a soft reset clear runs exit on every mod screen")
    T.eq(game.stack:top(), nil, version .. " the facade is empty after the clear")
    T.eq(Stack.depth(), 0, version .. " nothing is left on the stack")

    local finished = 0
    out.text("HELLO", function() finished = finished + 1 end)
    T.check(Message.isOpen(), version .. " TextBox opens the Gen 3 message window")
    T.check(Hud.isMenuOpen(), version .. " TextBox blocks the field")
    for _ = 1, 400 do
      Message.tick()
      game.input = press("a")
      Hud.update(game, 1 / 60)
      game.input = idle
      if finished > 0 then break end
    end
    T.eq(finished, 1, version .. " TextBox completes through A and calls onDone")
    T.check(not Message.isOpen() and Stack.depth() == 0, version .. " TextBox closes and pops")
  end, debug.traceback)
  T.check(ok, version .. " bridge run: " .. tostring(err))
  done()
end

for _, case in ipairs({ { "red", "Gen 1" }, { "gold", "Gen 2" } }) do
  Version.set(case[1])
  local ModUI = require("src.ui.ModUI")
  T.check(ModUI.TextBox == require("src.render.TextBox"), case[2] .. " keeps the stock TextBox")
  local built = {}
  local game = { stack = setmetatable({}, { __index = StateStack }), data = { screens = {
    [case[2]] = { new = function(g) built[#built + 1] = g; return { draw = function() end } end },
  } } }
  game.stack:init()
  ModUI.push(game, case[2])
  T.eq(#built, 1, case[2] .. " push builds the screen")
  T.eq(#game.stack.states, 1, case[2] .. " push uses the StateStack")
  T.eq(require("src.ui.game3.stack").depth(), 0, case[2] .. " leaves the Gen 3 stack alone")
end

Font.measure = realMeasure
Version.set(originalVersion)
Versions.select(originalNativeVersion)
Profile.reset()
T.finish("unified gen3 ui")
