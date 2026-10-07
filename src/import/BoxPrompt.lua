local Kit = require("src.ui.kit.Kit")
local Prompt = {}

function Prompt.close(imp, confirmed)
  local own = imp._boxPromptKeyboard
  if own then
    imp._boxPromptKeyboard = nil
    local VK = Kit.VirtualKeyboard
    if VK.active and VK.onDone == own then VK.close(false) end
  end
  local prompt = imp._boxPrompt
  if not prompt then return end
  imp._boxPrompt = nil
  Kit.blur()
  imp:_disarmTextInput()
  if confirmed then prompt.callback(prompt.text) end
end

function Prompt.open(imp, title, text, maxLen, callback)
  Kit.blur()
  local onDone
  onDone = function(value, confirmed)
    if imp._boxPromptKeyboard == onDone then imp._boxPromptKeyboard = nil end
    if confirmed then callback(value) end
  end
  local opts = { title = title, text = text or "", maxLen = maxLen, onDone = onDone }
  if Kit.VirtualKeyboard.open(opts) then imp._boxPromptKeyboard = onDone; return end
  imp._boxPrompt = { title = title, text = text or "", maxLen = maxLen, callback = callback }
  imp:_armTextInput(text)
end

function Prompt.openKeyboard(imp)
  local prompt = imp._boxPrompt
  if not prompt then return false end
  local onDone
  onDone = function(newText, confirmed)
    if imp._boxPromptKeyboard == onDone then imp._boxPromptKeyboard = nil end
    if confirmed and imp._boxPrompt == prompt then prompt.text = newText end
  end
  if not Kit.VirtualKeyboard.open({ text = prompt.text, title = prompt.title,
      maxLen = prompt.maxLen, onDone = onDone }) then
    return false
  end
  imp._boxPromptKeyboard = onDone
  return true
end

return Prompt
