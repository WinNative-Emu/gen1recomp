package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local EXE = "D:\\- Oyun install\\0 - Pokemon Gameboy D\xC4\xB1\xC5\x9F\xC4\xB1 Oyunlar"
  .. "\\- Pok\xC3\xA9mon Gen 1 Recompilation Project\\gen1recomp-win64\\gen1recomp.exe"
local DIR = "D:\\- Oyun install\\0 - Pokemon Gameboy D\xC4\xB1\xC5\x9F\xC4\xB1 Oyunlar"
  .. "\\- Pok\xC3\xA9mon Gen 1 Recompilation Project\\gen1recomp-win64"

local function utf16Units(s)
  local n, i = 0, 1
  while i <= #s do
    local b = s:byte(i)
    if b < 0x80 then i = i + 1
    elseif b < 0xE0 then i = i + 2
    elseif b < 0xF0 then i = i + 3
    else i = i + 4 n = n + 1 end
    n = n + 1
  end
  return n
end

local conversions, creates, closes = {}, {}, 0
local createResult = 1

local fakeFfi = { os = "Windows" }
function fakeFfi.cdef() end
function fakeFfi.new(ct)
  if ct == "PP_STARTUPINFOW" then return { cb = 0 } end
  if ct == "PP_PROCESS_INFORMATION" then return { hProcess = "proc", hThread = "thread" } end
  return {}
end
function fakeFfi.sizeof(ct)
  if ct == "PP_STARTUPINFOW" then return 104 end
  return 0
end
fakeFfi.C = {
  MultiByteToWideChar = function(cp, flags, s, n, w, wn)
    conversions[#conversions + 1] = { cp = cp, flags = flags, s = s, n = n, fill = w ~= nil }
    local units = utf16Units(s)
    if w ~= nil then
      assert(wn == units, "buffer sized from the probe")
      w.src = s
    end
    return units
  end,
  CreateProcessW = function(app, cmd, pa, ta, inherit, flags, env, cwd, si, pi)
    creates[#creates + 1] = {
      app = app and app.src, cmd = cmd and cmd.src, cwd = cwd and cwd.src,
      inherit = inherit, flags = flags, cb = si.cb, pa = pa, ta = ta, env = env, pi = pi,
    }
    return createResult
  end,
  CloseHandle = function() closes = closes + 1 return 1 end,
}
package.loaded.ffi = fakeFfi

local quits = {}
love = {
  system = { getOS = function() return "Windows" end },
  filesystem = {
    isFused = function() return true end,
    getSource = function() return EXE end,
    getExecutablePath = function() return EXE end,
  },
  event = {
    quit = function(...)
      quits[#quits + 1] = { n = select("#", ...), arg = (...) }
    end,
  },
}
package.loaded["src.core.Platform"] = { canSpawnProcess = function() return true end }

local shellCalls = 0
os.execute = function() shellCalls = shellCalls + 1 return 0 end
io.popen = function() shellCalls = shellCalls + 1 return nil end

local HostShell = require("src.core.HostShell")
local WinApi = require("src.core.WinApi")

eq(WinApi.quoteArg("plain"), "plain", "bare argument stays bare")
eq(WinApi.quoteArg("two words"), '"two words"', "space forces quotes")
eq(WinApi.quoteArg(""), '""', "empty argument is an explicit empty string")
eq(WinApi.quoteArg("C:\\dir with space\\"), '"C:\\dir with space\\\\"',
  "trailing backslash doubled before the closing quote")
eq(WinApi.quoteArg('say "hi"'), '"say \\"hi\\""', "embedded quote escaped")
eq(WinApi.quoteArg('a\\"b'), '"a\\\\\\"b"', "backslashes before a quote doubled plus one")
eq(WinApi.quoteArg("a\\\\b c"), '"a\\\\b c"', "backslashes not before a quote stay literal")
eq(WinApi.quoteArg("Pok\xC3\xA9mon"), "Pok\xC3\xA9mon", "non-ASCII bytes pass through untouched")
eq(WinApi.commandLine(EXE, { "--x=1", "a b" }), '"' .. EXE .. '" --x=1 "a b"',
  "argv0 always quoted, args quoted per CommandLineToArgvW")
eq(WinApi.dirOf(EXE), DIR, "cwd is the exe's folder")
eq(WinApi.dirOf("D:\\gen1recomp.exe"), "D:\\", "drive root keeps its backslash")

HostShell.restart()
eq(shellCalls, 0, "restart never goes through cmd.exe or the ANSI CRT")
eq(#creates, 1, "restart spawns the exe once")
local c = creates[1] or {}
eq(c.app, EXE, "CreateProcessW gets the exe as the exact UTF-8 bytes, widened")
eq(c.cmd, '"' .. EXE .. '"', "command line is the quoted exe")
eq(c.cwd, DIR, "working directory is the install folder")
eq(c.flags, 0x00000008 + 0x00000200, "DETACHED_PROCESS | CREATE_NEW_PROCESS_GROUP")
eq(c.inherit, 0, "no inherited handles")
eq(c.cb, 104, "STARTUPINFOW.cb set")
local sawExe = false
for _, conv in ipairs(conversions) do
  check(conv.cp == 65001, "every conversion is CP_UTF8, got " .. tostring(conv.cp))
  if conv.s == EXE and conv.fill then
    sawExe = true
    eq(conv.n, #EXE, "conversion covers every UTF-8 byte")
  end
end
check(sawExe, "MultiByteToWideChar asked to widen the reporter's UTF-8 path")
eq(closes, 2, "process and thread handles closed")
eq(#quits, 1, "restart quits once after spawning")
eq(quits[1] and quits[1].n, 0, "plain quit, the new process is the restart")

createResult = 0
HostShell.restart()
eq(#creates, 2, "second restart attempts the spawn")
eq(closes, 2, "failed spawn closes nothing")
eq(#quits, 2, "failed spawn still quits once")
eq(quits[2] and quits[2].arg, "restart", "failed spawn falls back to the in-process restart")
eq(shellCalls, 0, "fallback never shells out")

createResult = 1
check(HostShell.spawnSelfDetached({ "--display-companion=50000,tok en" }) == true,
  "companion spawn succeeds")
local s = creates[3] or {}
eq(s.cmd, '"' .. EXE .. '" "--display-companion=50000,tok en"', "companion argv quoted")
eq(s.cwd, DIR, "companion runs from the install folder")
createResult = 0
check(HostShell.spawnSelfDetached({}) == false, "companion spawn failure reported")
eq(shellCalls, 0, "companion never shells out")

T.finish("hostshell_win_restart_2721")
