local Stack = require("src.ui.game3.stack")
local ModRuntime = require("src.mods.Runtime")

local Bridge = {}

Bridge.VIEW = { w = 240, h = 160, innerW = 160, innerH = 144, ox = 40, oy = 8 }

local serial = 0
local facades = setmetatable({}, { __mode = "k" })

local function callback(state, name)
  local fn = state and state[name]
  return type(fn) == "function" and fn or nil
end

local function emit(name, state)
  if ModRuntime.wants(name) then ModRuntime.emit(name, { state = state }) end
end

local function adapterFor(state)
  local adapter = { isMenu = true, state = state }
  function adapter.update(dt)
    local update = callback(state, "update")
    if update then update(state, dt) end
  end
  function adapter.handleInput() end
  function adapter.draw()
    local draw = callback(state, "draw")
    if not draw then return end
    local offset = not state.gbaCanvas
    love.graphics.push()
    if offset then love.graphics.translate(Bridge.VIEW.ox, Bridge.VIEW.oy) end
    local ok, err = pcall(draw, state)
    love.graphics.pop()
    if not ok then error(err, 0) end
  end
  return adapter
end

local Facade = {}
Facade.__index = Facade

local function release(entry)
  local exit = callback(entry.state, "exit")
  if exit then exit(entry.state) end
  emit("screen.popped", entry.state)
end

function Facade:prune()
  for i = #self.entries, 1, -1 do
    local entry = self.entries[i]
    if not Stack.has(entry.id) then
      table.remove(self.entries, i)
      release(entry)
    end
  end
end

function Facade:push(state, ...)
  serial = serial + 1
  local id = "modui:" .. serial
  local opaque = state.isOpaque == true
  self.entries[#self.entries + 1] = { id = id, state = state }
  Stack.push(id, adapterFor(state), { isMenu = true, hideBelow = opaque, fullscreen = opaque })
  local enter = callback(state, "enter")
  if enter then enter(state, ...) end
  emit("screen.pushed", state)
end

function Facade:pop()
  self:prune()
  local entry = table.remove(self.entries)
  if not entry then return nil end
  Stack.pop(entry.id)
  release(entry)
  return entry.state
end

function Facade:top()
  self:prune()
  local entry = self.entries[#self.entries]
  return entry and entry.state
end

function Facade:clear()
  while self:top() do self:pop() end
end

function Facade:update(dt)
  local top = self:top()
  if top and top.update then top:update(dt) end
end

function Facade:draw()
  for _, entry in ipairs(self.entries) do
    if entry.state.draw then entry.state:draw() end
  end
end

Stack.onClear(function()
  for facade in pairs(facades) do facade:prune() end
end)

function Bridge.stackFor(game)
  local existing = game.stack
  if existing and getmetatable(existing) == Facade then return existing end
  local facade = setmetatable({ entries = {} }, Facade)
  facades[facade] = true
  game.stack = facade
  return facade
end

function Bridge.push(game, id, ...)
  local Screens = require("src.ui.Screens")
  local screens = game.data and game.data.screens
  if not (screens and screens[id]) then
    error("mod.ui.push: no registered screen '" .. tostring(id)
      .. "' (Gen 3 has no builtin Gen 1 screen of that id; register it in content.screens)", 2)
  end
  Bridge.stackFor(game)
  return Screens.push(game, id, ...)
end

local TextBox = {}
TextBox.__index = TextBox

local Public = {}

function Public.new(game, text, onDone, opts)
  if opts and (opts.choice or opts.stay) then
    error("mod.ui.TextBox on Gen 3 does not support the choice or stay options", 2)
  end
  return setmetatable({ game = game, text = text, onDone = onDone }, TextBox)
end

function TextBox:enter()
  local Message = require("src.ui.game3.message")
  self.finished = false
  Message.show(self.text, { done = function() self.finished = true end })
end

function TextBox:update()
  local Message = require("src.ui.game3.message")
  local input = self.game.input
  if Message.isOpen() and input then
    Message.setSpeedUp(input:isDown("a") or input:isDown("b"))
    if input:wasPressed("a") or input:wasPressed("b") then
      if Message.isWaiting() then Message.advance() else Message.pressAB() end
    end
  end
  if self.finished or not Message.isOpen() then
    self.finished = true
    self.game.stack:pop()
    if self.onDone then self.onDone() end
  end
end

function TextBox:exit()
  local Message = require("src.ui.game3.message")
  if not self.finished and Message.isOpen() then
    Message._done = nil
    Message.close()
  end
end

Bridge.TextBox = setmetatable(Public, { __index = function(_, key)
  return require("src.render.TextBox")[key]
end })

return Bridge
