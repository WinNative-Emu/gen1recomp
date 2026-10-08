package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
_G.love = require("tests.love_stub")

local spawns = 0
package.loaded["src.core.WinApi"] = {
  spawn = function() spawns = spawns + 1 return true end,
  dirOf = function(p) return p:match("^(.*)\\") or p end,
  modulePath = function() return "C:\\Games\\gen1recomp.exe" end,
}
package.loaded["src.core.SessionLifecycle"] = setmetatable({}, {
  __index = function() return function() end end,
})

love.system.getOS = function() return "Windows" end
love.filesystem.isFused = function() return true end
love.filesystem.getSource = function() return "C:\\Games\\gen1recomp.exe" end

local queue = {}
love.event = love.event or {}
love.event.quit = function(...) queue[#queue + 1] = { n = select("#", ...), arg = (...) } end

local loaded, err = pcall(dofile, "main.lua")
check(loaded, "main.lua loads headless: " .. tostring(err))

local HostShell = require("src.core.HostShell")

local function upvalue(fn, name)
  for i = 1, 200 do
    local n = debug.getupvalue(fn, i)
    if n == nil then return nil end
    if n == name then return i end
  end
end

local function setLocal(name, value)
  local fn = love.quit
  local i = upvalue(fn, name)
  if i then
    debug.setupvalue(fn, i, value)
    return true
  end
  local ret = upvalue(fn, "returnToLauncher")
  local _, rtl = debug.getupvalue(fn, ret)
  i = upvalue(rtl, name)
  if i then debug.setupvalue(rtl, i, value) return true end
  return false
end

local function runQuits()
  local exited = false
  while #queue > 0 and not exited do
    table.remove(queue, 1)
    if not love.quit() then exited = true end
  end
  return exited
end

local function reset()
  spawns = 0
  for i = #queue, 1, -1 do queue[i] = nil end
  HostShell.restarting = false
  setLocal("quitToLauncher", false)
  setLocal("processEnded", false)
  love.filesystem.remove("relaunch_to_launcher.txt")
end

reset()
check(setLocal("Game", {}), "a game session is on screen")
HostShell.restart()
eq(spawns, 1, "restartWithMods spawns the new process")
check(runQuits(), "the old process exits")
eq(spawns, 1, "and love.quit does not spawn a second instance")
check(love.filesystem.getInfo("relaunch_to_launcher.txt") ~= nil,
  "the relaunch still lands in the launcher")

reset()
setLocal("Game", {})
love.event.quit()
check(runQuits(), "closing a game window ends this process")
eq(spawns, 1, "and relaunches the launcher exactly once")

T.finish("hostshell_restart_single_spawn_2740")
