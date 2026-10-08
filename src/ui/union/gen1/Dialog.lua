local Menu = require("src.ui.Menu")
local Sound = require("src.core.Sound")
local Strings = require("src.core.Strings")
local TextBox = require("src.render.TextBox")

local Dialog = {}

Dialog.MENU_TX, Dialog.MENU_BOTTOM = 11, 12

local function popIf(stack, state)
  if state and stack:top() == state then
    stack:pop()
    return true
  end
  return false
end

Dialog.popIf = popIf

function Dialog.sfx(game, name)
  return Sound.play(game.data, name)
end

function Dialog.say(game, text, onDone)
  local box = TextBox.new(game, text, onDone)
  game.stack:push(box)
  return box
end

function Dialog.ask(game, text, onAnswer)
  local box = TextBox.new(game, text, nil, {
    choice = function(yes) onAnswer(yes and true or false) end,
  })
  game.stack:push(box)
  return box
end

function Dialog.menu(game, text, labels, onChoose)
  local stack = game.stack
  local box, menu
  local function finish(index)
    popIf(stack, menu)
    popIf(stack, box)
    onChoose(index)
  end
  box = TextBox.new(game, text, nil, { stay = { onShown = function()
    local items = {}
    for i, label in ipairs(labels) do
      items[i] = { label = Strings(label), keepOpen = true, onSelect = function() finish(i) end }
    end
    local th = #items * 2 + 2
    menu = Menu.new(game, items, {
      tx = Dialog.MENU_TX, ty = Dialog.MENU_BOTTOM - th, th = th, tw = 20 - Dialog.MENU_TX,
      keepOnCancel = true, onCancel = function() finish(#items) end,
    })
    stack:push(menu)
  end } })
  stack:push(box)
  return box
end

local Waiter = {}
Waiter.__index = Waiter
Waiter.isOpaque = false

function Waiter:update()
  if self.closed then return end
  self.tick(self, self.game and self.game.input)
end

function Waiter:draw() end

function Waiter:close()
  if self.closed then return end
  self.closed = true
  local stack = self.game.stack
  popIf(stack, self)
  popIf(stack, self.box)
end

function Dialog.hold(game, text, tick)
  local stack = game.stack
  local waiter = setmetatable({ game = game, tick = tick, closed = false, text = text }, Waiter)
  waiter.box = TextBox.new(game, text, nil, { stay = { onShown = function()
    if not waiter.closed then stack:push(waiter) end
  end } })
  stack:push(waiter.box)
  return waiter
end

function Dialog.pressed(input, key)
  return input and input.wasPressed and input:wasPressed(key) and true or false
end

return Dialog
