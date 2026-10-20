package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")

local realFfi = package.loaded.ffi
local savedOs, savedFs, savedWindow = love._os, love.filesystem, love.window
local savedGlobals = {
  POKEPORT_EDITOR_MODE = _G.POKEPORT_EDITOR_MODE,
  POKEPORT_DEV_MODE = _G.POKEPORT_DEV_MODE,
  POKEPORT_DISPLAY_COMPANION = _G.POKEPORT_DISPLAY_COMPANION,
}

local hints
local fakeFfi = {
  cdef = function() end,
  load = function(name)
    assert(name == "SDL2", "only SDL2 is loaded")
    return { SDL_SetHint = function(k, v) hints[k] = v; return 1 end }
  end,
}

local function runConf(osName)
  hints = {}
  package.loaded.ffi = fakeFfi
  package.loaded["src.render.WindowsDpi"] = nil
  love._os = osName
  love.filesystem = setmetatable({ setSymlinksEnabled = function() end },
    { __index = savedFs })
  local savedConf = love.conf
  dofile("conf.lua")
  local t = { window = {}, modules = {} }
  love.conf(t)
  love.conf = savedConf
  package.loaded.ffi = realFfi
  return t
end

local t = runConf("Windows")
T.eq(hints.SDL_WINDOWS_DPI_SCALING, "1", "Windows asks SDL for DPI-scaled window units")
T.eq(t.window.highdpi, true, "and opens a high-DPI drawable so text renders at native density")
T.eq(t.window.width, 1024, "the window keeps its 1024 unit design width")
T.eq(t.window.height, 768, "and its 768 unit design height")

for _, osName in ipairs({ "OS X", "Linux" }) do
  t = runConf(osName)
  T.eq(hints.SDL_WINDOWS_DPI_SCALING, nil, osName .. " sets no Windows DPI hint")
  T.check(t.window.highdpi ~= true, osName .. " keeps its low-DPI window")
end

t = runConf("Android")
T.eq(hints.SDL_WINDOWS_DPI_SCALING, nil, "mobile sets no Windows DPI hint")

package.loaded["src.render.WindowsDpi"] = nil
local WindowsDpi = require("src.render.WindowsDpi")

local failing = { cdef = function() end, load = function() error("no SDL2") end }
local t2 = { window = {} }
T.eq(WindowsDpi.apply(t2, "Windows", failing), false, "a missing SDL2 reports failure")
T.check(t2.window.highdpi ~= true, "and leaves the window low-DPI rather than half-configured")

local function fakeWin(dpi, highdpi)
  return {
    getDesktopDimensions = function() return 3840, 2160 end,
    getMode = function() return 1024, 768, { highdpi = highdpi } end,
    getDPIScale = function() return dpi end,
  }
end

local dw, dh = WindowsDpi.desktopDimensions(1, fakeWin(1.5, true), "Windows")
T.eq(dw, 2560, "Windows desktop width comes back in window units")
T.eq(dh, 1440, "and so does its height")
dw = WindowsDpi.desktopDimensions(1, fakeWin(1.25, true), "Windows")
T.eq(dw, 3072, "125% divides the same way")
dw = WindowsDpi.desktopDimensions(1, fakeWin(1.5, false), "Windows")
T.eq(dw, 3840, "a low-DPI Windows window is untouched")
dw = WindowsDpi.desktopDimensions(1, fakeWin(2, false), "OS X")
T.eq(dw, 3840, "macOS is untouched")

local flags = WindowsDpi.modeFlags({ resizable = true }, fakeWin(1.5, true))
T.eq(flags.resizable, true, "mode flags keep the caller's fields")
T.eq(flags.highdpi, true, "and carry the live highdpi flag so setMode does not drop it")
flags = WindowsDpi.modeFlags({ resizable = true }, fakeWin(1, false))
T.eq(flags.highdpi, false, "a low-DPI window stays low-DPI")

love._os, love.filesystem, love.window = savedOs, savedFs, savedWindow
for k, v in pairs(savedGlobals) do _G[k] = v end

T.finish("windows dpi scaling")
