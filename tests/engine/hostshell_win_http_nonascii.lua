package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local SAVE = "C:/Users/H\xC3\xBCseyin/AppData/Roaming/LOVE/gen1recomp"
local SAVE_WIN = "C:\\Users\\H\xC3\xBCseyin\\AppData\\Roaming\\LOVE\\gen1recomp"
local MARK = "\n__gen1recomp_http__"
local URL = "https://example.com/a.zip"

local creates, closes, pipeOutput, createResult = {}, {}, "", 1

local fakeFfi = { os = "Windows" }
function fakeFfi.cdef() end
function fakeFfi.new(ct)
  if ct == "PP_STARTUPINFOW" then return { cb = 0, dwFlags = 0 } end
  if ct == "PP_PROCESS_INFORMATION" then return { hProcess = "proc", hThread = "thread" } end
  return {}
end
function fakeFfi.sizeof(ct)
  if ct == "PP_STARTUPINFOW" then return 104 end
  if ct == "PP_SECURITY_ATTRIBUTES" then return 24 end
  return 0
end
function fakeFfi.string(buf, n) return buf.data:sub(1, n) end
fakeFfi.C = {
  MultiByteToWideChar = function(cp, _, s, _, w)
    assert(cp == 65001, "CP_UTF8")
    if w ~= nil then w.src = s end
    return #s
  end,
  CreatePipe = function(rd, wr, sa)
    assert(sa.bInheritHandle == 1, "inheritable write end")
    rd[0], wr[0] = "rd", "wr"
    return 1
  end,
  SetHandleInformation = function() return 1 end,
  CreateProcessW = function(app, cmd, _, _, inherit, flags, _, cwd, si)
    creates[#creates + 1] = {
      app = app and app.src, cmd = cmd and cmd.src, cwd = cwd and cwd.src,
      inherit = inherit, flags = flags, si = si,
    }
    return createResult
  end,
  ReadFile = function(_, buf, _, got)
    if pipeOutput == "" then got[0] = 0 return 0 end
    buf.data, got[0], pipeOutput = pipeOutput, #pipeOutput, ""
    return 1
  end,
  WaitForSingleObject = function() return 0 end,
  GetExitCodeProcess = function(_, code) code[0] = 0 return 1 end,
  CloseHandle = function(h) closes[#closes + 1] = h return 1 end,
}
package.loaded.ffi = fakeFfi

local files, removed = {}, {}
local osName = "Windows"
love = {
  system = { getOS = function() return osName end },
  filesystem = {
    getSaveDirectory = function() return SAVE end,
    write = function(name, data) files[name] = data return true end,
    remove = function(name) removed[#removed + 1] = name files[name] = nil return true end,
  },
}

local shellCalls, lastShell = 0, nil
os.execute = function() shellCalls = shellCalls + 1 return 0 end
io.popen = function(cmd)
  shellCalls, lastShell = shellCalls + 1, cmd
  return {
    read = function() return "body" .. MARK .. "200" end,
    close = function() return true end,
  }
end

local HostShell = require("src.core.HostShell")
HostShell.haveCurl = function() return true end

local function ascii(s) return not s:find("[\128-\255]") end

local cwd, rels = HostShell.winRelative({ SAVE .. "/mods/x.zip", SAVE .. "/etag/x.etag" })
eq(cwd, SAVE_WIN, "common folder of the paths becomes the cwd")
eq(rels[1], "mods\\x.zip", "first path relative to it")
eq(rels[2], "etag\\x.etag", "second path relative to it")
cwd = HostShell.winRelative({ "D:/x.zip" })
eq(cwd, "D:\\", "drive root keeps its backslash")
cwd = HostShell.winRelative({ "\\\\server\\share\\x.zip" })
eq(cwd, "\\\\server\\share", "UNC prefix kept")
cwd, rels = HostShell.winRelative({ SAVE .. "/Pok\xC3\xA9/x.zip", SAVE .. "/a.etag" })
eq(rels[1], nil, "a non-ASCII relative name is not offered")
eq(rels[2], "a.etag", "the ASCII one still is")

pipeOutput = MARK .. "200"
local ok, err = HostShell.httpDownload(URL, SAVE .. "/mods/x.zip", "ua", nil, 90,
  SAVE .. "/etag/x.etag")
eq(ok, true, "download succeeds: " .. tostring(err))
eq(shellCalls, 0, "download never goes through cmd.exe or the ANSI CRT")
eq(#creates, 1, "curl spawned once")
local c = creates[1] or {}
eq(c.app, nil, "curl resolved through the search path")
eq(c.cwd, SAVE_WIN, "curl runs in the save folder, passed wide")
check(c.cmd and ascii(c.cmd), "no non-ASCII byte reaches curl's argv")
check(c.cmd and c.cmd:find(" -o mods\\x.zip ", 1, true) ~= nil, "-o is relative")
check(c.cmd and c.cmd:find("--etag-compare etag\\x.etag --etag-save etag\\x.etag", 1, true) ~= nil,
  "etag paths are relative")
check(c.cmd and c.cmd:find('"User-Agent: ua"', 1, true) ~= nil, "header quoted per CommandLineToArgvW")
check(c.cmd and c.cmd:sub(-#URL) == URL, "url last")
eq(c.flags, 0x08000000, "CREATE_NO_WINDOW")
eq(c.inherit, 1, "pipe write end inherited")
eq(c.si and c.si.dwFlags, 0x100, "STARTF_USESTDHANDLES")
eq(c.si and c.si.hStdOutput, "wr", "stdout to the pipe")
eq(c.si and c.si.hStdError, "wr", "stderr merged into the pipe")
eq(table.concat(closes, ","), "wr,thread,rd,proc", "every handle closed")

closes = {}
pipeOutput = "{\"tag\":1}" .. MARK .. "200"
local body = HostShell.httpGet("https://example.com/api", "ua")
eq(body, "{\"tag\":1}", "httpGet returns the body read from the pipe")
eq(creates[2] and creates[2].cwd, nil, "a GET with no paths keeps the inherited cwd")
eq(shellCalls, 0, "httpGet never shells out")

pipeOutput = MARK .. "201"
ok, err = HostShell.httpPost("https://example.com/logs", "log body", "text/plain", "ua", 10)
eq(ok, true, "post succeeds: " .. tostring(err))
local p = creates[3] or {}
eq(p.cwd, SAVE_WIN, "post runs in the save folder")
local staged = p.cmd and p.cmd:match("%-%-data%-binary @(%S+)")
check(staged and staged:find("^gen1recomp%-post%-") ~= nil, "body is staged by a relative name")
check(p.cmd and ascii(p.cmd), "post argv is ASCII")
eq(removed[#removed], staged, "staged body removed through love.filesystem")
eq(shellCalls, 0, "post never shells out")

pipeOutput = "ok" .. MARK .. "200"
local resp, rerr, status = HostShell.httpRequest("https://example.com/sync",
  { method = "PUT", headers = { ["x-token"] = "t" }, body = "{}" })
eq(resp, "ok", "request body returned: " .. tostring(rerr))
eq(status, 200, "request status returned")
local r = creates[4] or {}
eq(r.cwd, SAVE_WIN, "request runs in the save folder")
check(r.cmd and r.cmd:find("-H @gen1recomp-req-head-", 1, true) ~= nil, "header file relative")
check(r.cmd and r.cmd:find("--data-binary @gen1recomp-req-body-", 1, true) ~= nil, "body file relative")
check(r.cmd and ascii(r.cmd), "request argv is ASCII")
eq(next(files), nil, "every staged file removed")
eq(shellCalls, 0, "request never shells out")

createResult = 0
body = HostShell.httpGet("https://example.com/api", "ua")
eq(shellCalls, 1, "a failed wide spawn falls back to the shell")
eq(body, "body", "and the fallback still answers")
createResult = 1

osName = "OS X"
shellCalls = 0
HostShell.httpGet("https://x/y", "ua")
eq(lastShell, "'curl' -sSL --proto =http,https --proto-redir =http,https --connect-timeout 10 "
  .. "--max-time 40 -H 'User-Agent: ua' -w '\\n__gen1recomp_http__%{http_code}' 'https://x/y' 2>&1",
  "POSIX command line unchanged")
eq(#creates, 5, "POSIX never spawns through WinApi")

T.finish("hostshell_win_http_nonascii")
