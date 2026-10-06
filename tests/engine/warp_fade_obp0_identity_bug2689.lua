-- home/fade.asm:67

package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.modkit")
local check, eq = T.check, T.eq

T.fixtures.fresh()

local GameVersion = require("src.core.GameVersion")
local PaletteFX = require("src.render.PaletteFX")
local Transition = require("src.render.Transition")
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

local function getUpvalue(fn, name)
  local i = 1
  while true do
    local n, v = debug.getupvalue(fn, i)
    if not n then return nil end
    if n == name then return v end
    i = i + 1
  end
end

local prevVersion, prevMode, prevDark = GameVersion.get(), PaletteFX.mode, PaletteFX.darkWorld()
local prevGame = getUpvalue(OW.warpFade, "Game")
local realSetFadeObp = PaletteFX.setFadeObp

local fade
local game = { stack = { top = function() return fade end, pop = function() end },
               worldBgBattleInStack = function() return false end }
check(setUpvalue(OW.warpFade, "Game", game), "warpFade reads the Game upvalue")

local function armedAt(t)
  local armed, called = nil, false
  PaletteFX.setFadeObp = function(map) armed, called = map, true; realSetFadeObp(map) end
  fade = Transition.new(game, nil, nil, true)
  fade.t = t
  local self_ = setmetatable({}, { __index = OW })
  pcall(OW.drawWorld, self_)
  PaletteFX.setFadeObp = realSetFadeObp
  return armed, called, fade
end

for _, version in ipairs({ "red", "blue" }) do
  GameVersion.set(version)
  PaletteFX.setMode("ogred")
  PaletteFX.setDarkWorld(false)
  local base = PaletteFX.ogObjBase()

  for step = 0, 3 do
    local map, called, f = armedAt(step * 8)
    local obp = f:obp0()
    check(called, ("%s step %d drawWorld arms the fade OBP"):format(version, step))
    check(map ~= nil, ("%s step %d rOBP0 $%02X arms a fade map"):format(version, step, obp))
  end

  local map, _, f = armedAt(8)
  eq(f:obp0(), 0xE4, version .. " FadePal3 is the black-out second step")
  check(map ~= nil and map[0] == 0 and map[1] == 1 and map[2] == 2 and map[3] == 3,
        version .. " FadePal3 rOBP0 $E4 arms the identity map")
  local colors = PaletteFX.ogObjWorld()
  check(colors[2][1] == base[2][1] and colors[2][2] == base[2][2]
        and colors[3][1] == base[3][1] and colors[3][2] == base[3][2],
        version .. " FadePal3 step bakes the raw $E4 ramp, not the $D0 lift")
  PaletteFX.setFadeObp(nil)
end

PaletteFX.setFadeObp = realSetFadeObp
PaletteFX.setFadeObp(nil)
setUpvalue(OW.warpFade, "Game", prevGame)
PaletteFX.setDarkWorld(prevDark)
GameVersion.set(prevVersion)
PaletteFX.setMode(prevMode)

T.finish("warp fade rOBP0 identity #2689")
