-- engine/events/hidden_events/indigo_plateau_statues.asm:5
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")

local OW = require("src.world.OverworldController")

local function setUpvalue(fn, name, val)
  local i = 1
  while true do
    local n = debug.getupvalue(fn, i)
    if not n then return false end
    if n == name then debug.setupvalue(fn, i, val); return true end
    i = i + 1
  end
end

local pushed
local textBoxStub = {
  new = function(_, text, onDone, opts)
    return { text = text, onDone = onDone, opts = opts }
  end,
}
local fakeGame = {
  data = { text = {
    _IndigoPlateauStatuesText1 = "PLAQUE",
    _IndigoPlateauStatuesText2 = "ULTIMATE GOAL",
    _IndigoPlateauStatuesText3 = "HIGHEST AUTHORITY",
  } },
  stack = { push = function(_, box) pushed = box end },
}
T.check(setUpvalue(OW.tryBookshelf, "TextBox", textBoxStub),
  "TextBox upvalue on tryBookshelf")
T.check(setUpvalue(OW.tryBookshelf, "Game", fakeGame),
  "Game upvalue on tryBookshelf")

local map = {
  def = { tileset = "PLATEAU" },
  inBounds = function() return true end,
  cellTile = function() return 0x30 end,
}

local function read(cellX)
  pushed = nil
  local self_ = setmetatable({ player = { facing = "up", cellX = cellX, cellY = 6 },
    map = map }, { __index = OW })
  local ok = self_:tryBookshelf(cellX, 5)
  return ok, pushed and pushed.text
end

for _, x in ipairs({ 9, 11 }) do
  local ok, text = read(x)
  T.eq(ok, true, "odd X " .. x .. " statue is consumed")
  T.eq(text, "PLAQUE\fULTIMATE GOAL", "odd X " .. x .. " prints Text2")
end
for _, x in ipairs({ 8, 10 }) do
  local ok, text = read(x)
  T.eq(ok, true, "even X " .. x .. " statue is consumed")
  T.eq(text, "PLAQUE\fHIGHEST AUTHORITY", "even X " .. x .. " prints Text3")
end

T.finish("indigo_statues_bug2683")
