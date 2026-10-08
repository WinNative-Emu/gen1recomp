local Setting = {}

Setting.KEY = "unionRoom"

function Setting.enabledIn(opts)
  return not (type(opts) == "table" and opts[Setting.KEY] == false)
end

function Setting.enabled(fs)
  local ok, opts = pcall(function()
    return require("src.core.SaveData").loadOptions(fs)
  end)
  return Setting.enabledIn(ok and opts or nil)
end

function Setting.appliesTo(generation)
  return generation == 1 or generation == 2
end

function Setting.patchesOn(generation, opts)
  if not Setting.appliesTo(generation) then return true end
  if opts ~= nil then return Setting.enabledIn(opts) end
  return Setting.enabled()
end

return Setting
