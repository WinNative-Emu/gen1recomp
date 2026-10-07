-- #575: Android restarts in-process.  The restartApp alarm relaunch is a
-- background activity start that Android 14 blocks, so the app closed to the
-- home screen instead of coming back; love.quit joins every worker before
-- the restart, so the second PHYSFS_init no longer finds open handles.
-- iOS turns every quit into DONE_RESTART, so it keeps a bare quit().
--   luajit tests/engine/host_restart_android_bug575.lua

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
local restartCalls = 0
love.system = love.system or {}
love.system.getOS = function() return osName end
love.system.restartApp = function() restartCalls = restartCalls + 1 return true end

HostShell.restart()
eq(restartCalls, 0, "Android never schedules the blocked restartApp relaunch")
eq(#quits, 1, "Android restart quits once")
eq(quits[1].arg, "restart", "and it is the in-process quit(\"restart\")")

osName = "iOS"
HostShell.restart()
eq(#quits, 2, "iOS HostShell.restart quits once")
eq(quits[2].n, 0, "iOS uses a bare quit(), which love.cpp turns into a restart")

if not os.getenv("APPIMAGE") then
  osName = "OS X"
  HostShell.restart()
  eq(quits[3] and quits[3].arg, "restart", "desktop restarts in-process")
end

local f = assert(io.open("main.lua", "rb"))
local mainSrc = f:read("*a")
f:close()
check(mainSrc:find('a ~= "restart" and love.system and love.system.getOS() == "Android"', 1, true) ~= nil,
  "love.run lets an Android quit(\"restart\") reach LOVE's boot loop instead of os.exit")

T.finish("host_restart_android_bug575")
