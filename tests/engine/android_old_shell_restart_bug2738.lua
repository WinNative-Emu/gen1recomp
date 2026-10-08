package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local HostShell = require("src.core.HostShell")

local quits = {}
love.event = {
  quit = function(...)
    quits[#quits + 1] = { n = select("#", ...), arg = (...) }
  end,
}

local osName = "Android"
local restartApp = nil
love.system = love.system or {}
love.system.getOS = function() return osName end

local exits = {}
local realExit = os.exit
os.exit = function(code)
  exits[#exits + 1] = code
  if code ~= nil and type(code) ~= "number" and type(code) ~= "boolean" then
    error("bad argument #1 to 'exit' (number expected, got " .. type(code) .. ")")
  end
end

local function oldShellStep(a)
  if love.system and love.system.getOS() == "Android" then
    os.exit(a or 0)
  end
  return a or 0
end

local function driveOldShell()
  local errs = {}
  for _, q in ipairs(quits) do
    local ok, err = pcall(oldShellStep, q.arg)
    if not ok then errs[#errs + 1] = tostring(err) end
  end
  return errs
end

local function reset()
  for i = #quits, 1, -1 do quits[i] = nil end
  for i = #exits, 1, -1 do exits[i] = nil end
end

_G.POKEPORT_LOOP_RESTART = nil
love.system.restartApp = nil
HostShell.restart()
eq(#quits, 1, "Android restart on an older shell still quits once")
eq(quits[1] and quits[1].n, 0, "with a bare quit(), never quit(\"restart\")")
local errs = driveOldShell()
eq(#errs, 0, "the old stepper's os.exit(a or 0) never errors: " .. table.concat(errs, "; "))
for _, code in ipairs(exits) do
  check(type(code) == "number", "old stepper exits with a number, got " .. type(code))
end
check(HostShell.canRestart ~= nil and not HostShell.canRestart(),
  "an older Android shell cannot restart in-process")

reset()
local restartCalls = 0
love.system.restartApp = function() restartCalls = restartCalls + 1 return true end
HostShell.restart()
eq(restartCalls, 1, "an older shell with the restartApp bridge relaunches through it")
eq(#quits, 0, "and sends no quit event")

reset()
love.system.restartApp = function() return false end
HostShell.restart()
eq(#quits, 1, "a failed restartApp falls back to one quit")
eq(#driveOldShell(), 0, "which the old stepper exits on cleanly")

for _, mod in ipairs({ "src.core.Game", "src.core.Game3" }) do
  reset()
  love.system.restartApp = nil
  local ok, M = pcall(require, mod)
  if ok and type(M) == "table" and type(M.restartWithMods) == "function" then
    local stub = setmetatable({}, { __index = function() return function() end end })
    pcall(M.restartWithMods, stub)
    for _, q in ipairs(quits) do
      check(type(q.arg) ~= "string", mod .. ":restartWithMods sends no string quit on an older shell")
    end
    eq(#driveOldShell(), 0, mod .. ":restartWithMods survives the old stepper")
  end
end

reset()
local ManagerState = require("src.mods.ManagerState")
ManagerState.restartGame({ game = {} })
for _, q in ipairs(quits) do
  check(type(q.arg) ~= "string", "ManagerState:restartGame sends no string quit on an older shell")
end
eq(#driveOldShell(), 0, "ManagerState:restartGame survives the old stepper")

reset()
_G.POKEPORT_LOOP_RESTART = true
check(HostShell.canRestart and HostShell.canRestart(),"a shell whose love.run sets the flag restarts in-process")
HostShell.restart()
eq(quits[1] and quits[1].arg, "restart", "and HostShell.restart sends quit(\"restart\")")

_G.POKEPORT_LOOP_RESTART = nil
osName = "iOS"
check(HostShell.canRestart and HostShell.canRestart(),"iOS keeps its bare-quit restart")
osName = "OS X"
check(HostShell.canRestart and HostShell.canRestart(),"desktop keeps quit(\"restart\")")

local f = assert(io.open("main.lua", "rb"))
local mainSrc = f:read("*a")
f:close()
local runBody = mainSrc:match("\nfunction love%.run%(%)(.-)\nend\n") or ""
local flagAt = runBody:find("_G.POKEPORT_LOOP_RESTART = true", 1, true)
local loadAt = runBody:find("love.load(", 1, true)
check(flagAt ~= nil and loadAt ~= nil and flagAt < loadAt,
  "love.run advertises restart support before love.load chainloads a payload")
local returnBody = mainSrc:match("local function returnToLauncher%(opts%)(.-)\nend\n") or ""
local gateAt = returnBody:find("canRestart()", 1, true)
local inProcAt = returnBody:find("rebuildLauncherInProcess(opts)", 1, true)
local restartAt = returnBody:find('require("src.core.HostShell").restart()', 1, true)
check(gateAt ~= nil and inProcAt ~= nil and restartAt ~= nil and gateAt < restartAt
    and inProcAt < restartAt,
  "EXIT GAME rebuilds the launcher in-process when the shell cannot restart")

os.exit = realExit
T.finish("android_old_shell_restart_bug2738")
