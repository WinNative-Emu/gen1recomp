local WinApi = {}

WinApi.DETACHED_PROCESS = 0x00000008
WinApi.CREATE_NEW_PROCESS_GROUP = 0x00000200
WinApi.CREATE_NO_WINDOW = 0x08000000

local CP_UTF8 = 65001

local DECLS = {
  "int MultiByteToWideChar(uint32_t cp, uint32_t flags, const char *s, int n, uint16_t *w, int wn);",
  "int WideCharToMultiByte(uint32_t cp, uint32_t flags, const uint16_t *w, int wn, char *s, int n, const char *def, int *used);",
  "int CloseHandle(void *h);",
  "uint32_t GetModuleFileNameW(void *mod, uint16_t *buf, uint32_t n);",
  -- STARTUPINFOW: 104 bytes on x64, 68 on x86, natural alignment
  [[typedef struct {
    uint32_t cb; uint16_t *lpReserved; uint16_t *lpDesktop; uint16_t *lpTitle;
    uint32_t dwX; uint32_t dwY; uint32_t dwXSize; uint32_t dwYSize;
    uint32_t dwXCountChars; uint32_t dwYCountChars; uint32_t dwFillAttribute;
    uint32_t dwFlags; uint16_t wShowWindow; uint16_t cbReserved2;
    uint8_t *lpReserved2; void *hStdInput; void *hStdOutput; void *hStdError;
  } PP_STARTUPINFOW;]],
  [[typedef struct {
    void *hProcess; void *hThread; uint32_t dwProcessId; uint32_t dwThreadId;
  } PP_PROCESS_INFORMATION;]],
  "int CreateProcessW(const uint16_t *app, uint16_t *cmd, void *pa, void *ta, int inherit, uint32_t flags, void *env, const uint16_t *cwd, PP_STARTUPINFOW *si, PP_PROCESS_INFORMATION *pi);",
  -- SECURITY_ATTRIBUTES: 24 bytes on x64, 12 on x86
  [[typedef struct {
    uint32_t nLength; void *lpSecurityDescriptor; int bInheritHandle;
  } PP_SECURITY_ATTRIBUTES;]],
  "int CreatePipe(void **rd, void **wr, PP_SECURITY_ATTRIBUTES *sa, uint32_t size);",
  "int SetHandleInformation(void *h, uint32_t mask, uint32_t flags);",
  "int ReadFile(void *h, void *buf, uint32_t n, uint32_t *got, void *ov);",
  "uint32_t WaitForSingleObject(void *h, uint32_t ms);",
  "int GetExitCodeProcess(void *h, uint32_t *code);",
}

local HANDLE_FLAG_INHERIT = 0x00000001
local STARTF_USESTDHANDLES = 0x00000100
local INFINITE = 0xFFFFFFFF

local loaded = nil

local function lib()
  if loaded ~= nil then return loaded or nil end
  loaded = false
  local okFfi, ffi = pcall(require, "ffi")
  if not (okFfi and ffi and ffi.os == "Windows") then return nil end
  for _, decl in ipairs(DECLS) do pcall(ffi.cdef, decl) end
  local C = ffi.C
  if not pcall(function()
    return C.MultiByteToWideChar, C.CreateProcessW, C.CloseHandle
  end) then
    return nil
  end
  loaded = ffi
  return ffi
end

function WinApi.available()
  return lib() ~= nil
end

function WinApi.wide(s)
  local ffi = lib()
  if not ffi or type(s) ~= "string" then return nil end
  local C = ffi.C
  local n = C.MultiByteToWideChar(CP_UTF8, 0, s, #s, nil, 0)
  if s ~= "" and (not n or n <= 0) then return nil end
  local buf = ffi.new("uint16_t[?]", n + 1)
  if n > 0 and C.MultiByteToWideChar(CP_UTF8, 0, s, #s, buf, n) <= 0 then
    return nil
  end
  buf[n] = 0
  return buf
end

function WinApi.narrow(w, count)
  local ffi = lib()
  if not ffi or w == nil then return nil end
  local C = ffi.C
  local wn = count or -1
  local n = C.WideCharToMultiByte(CP_UTF8, 0, w, wn, nil, 0, nil, nil)
  if not n or n <= 0 then return nil end
  local buf = ffi.new("char[?]", n)
  if C.WideCharToMultiByte(CP_UTF8, 0, w, wn, buf, n, nil, nil) <= 0 then
    return nil
  end
  if wn == -1 then n = n - 1 end
  return ffi.string(buf, n)
end

function WinApi.modulePath()
  local ffi = lib()
  if not ffi then return nil end
  local ok, path = pcall(function()
    local buf = ffi.new("uint16_t[32768]")
    local n = ffi.C.GetModuleFileNameW(nil, buf, 32768)
    if n == 0 then return nil end
    return WinApi.narrow(buf, n)
  end)
  if ok and type(path) == "string" and path ~= "" then return path end
  return nil
end

function WinApi.quoteArg(arg)
  arg = tostring(arg)
  if arg ~= "" and not arg:find('[ \t\n\v"]') then return arg end
  local out, slashes = { '"' }, 0
  for i = 1, #arg do
    local c = arg:sub(i, i)
    if c == "\\" then
      slashes = slashes + 1
    elseif c == '"' then
      out[#out + 1] = string.rep("\\", slashes * 2 + 1) .. '"'
      slashes = 0
    else
      out[#out + 1] = string.rep("\\", slashes) .. c
      slashes = 0
    end
  end
  out[#out + 1] = string.rep("\\", slashes * 2) .. '"'
  return table.concat(out)
end

function WinApi.commandLine(exe, args)
  local parts = { '"' .. tostring(exe):gsub('"', "") .. '"' }
  for _, arg in ipairs(args or {}) do
    parts[#parts + 1] = WinApi.quoteArg(arg)
  end
  return table.concat(parts, " ")
end

function WinApi.dirOf(path)
  if type(path) ~= "string" then return nil end
  local dir = path:match("^(.*)[\\/][^\\/]*$")
  if not dir or dir == "" then return nil end
  if dir:match("^%a:$") then dir = dir .. "\\" end
  return dir
end

function WinApi.spawn(exe, args, opts)
  local ffi = lib()
  if not ffi or type(exe) ~= "string" or exe == "" then return false end
  opts = opts or {}
  local ok, spawned = pcall(function()
    local cmd = WinApi.wide(opts.commandLine or WinApi.commandLine(exe, args))
    if not cmd then return false end
    local app = nil
    if opts.useApplicationName ~= false then
      app = WinApi.wide(exe)
      if not app then return false end
    end
    local cwd = nil
    if type(opts.cwd) == "string" and opts.cwd ~= "" then
      cwd = WinApi.wide(opts.cwd)
      if not cwd then return false end
    end
    local si = ffi.new("PP_STARTUPINFOW")
    si.cb = ffi.sizeof("PP_STARTUPINFOW")
    local pi = ffi.new("PP_PROCESS_INFORMATION")
    local flags = opts.flags or (WinApi.DETACHED_PROCESS + WinApi.CREATE_NEW_PROCESS_GROUP)
    if ffi.C.CreateProcessW(app, cmd, nil, nil, 0, flags, nil, cwd, si, pi) == 0 then
      return false
    end
    ffi.C.CloseHandle(pi.hThread)
    ffi.C.CloseHandle(pi.hProcess)
    return true
  end)
  return ok and spawned == true
end

function WinApi.run(exe, args, opts)
  local ffi = lib()
  if not ffi or type(exe) ~= "string" or exe == "" then return nil end
  opts = opts or {}
  local C = ffi.C
  local ok, out, code = pcall(function()
    local cmd = WinApi.wide(opts.commandLine or WinApi.commandLine(exe, args))
    if not cmd then return nil end
    local app = nil
    if opts.useApplicationName ~= false then
      app = WinApi.wide(exe)
      if not app then return nil end
    end
    local cwd = nil
    if type(opts.cwd) == "string" and opts.cwd ~= "" then
      cwd = WinApi.wide(opts.cwd)
      if not cwd then return nil end
    end
    local sa = ffi.new("PP_SECURITY_ATTRIBUTES")
    sa.nLength = ffi.sizeof("PP_SECURITY_ATTRIBUTES")
    sa.bInheritHandle = 1
    local rd, wr = ffi.new("void *[1]"), ffi.new("void *[1]")
    local pi = ffi.new("PP_PROCESS_INFORMATION")
    local flags = opts.flags or WinApi.CREATE_NO_WINDOW
    local started, attempted = false, false
    local function launch()
      if attempted then return end
      attempted = true
      pcall(function()
        if C.CreatePipe(rd, wr, sa, 0) == 0 then return end
        C.SetHandleInformation(rd[0], HANDLE_FLAG_INHERIT, 0)
        local si = ffi.new("PP_STARTUPINFOW")
        si.cb = ffi.sizeof("PP_STARTUPINFOW")
        si.dwFlags = STARTF_USESTDHANDLES
        si.hStdOutput = wr[0]
        si.hStdError = wr[0]
        started = C.CreateProcessW(app, cmd, nil, nil, 1, flags, nil, cwd, si, pi) ~= 0
        C.CloseHandle(wr[0])
        if not started then C.CloseHandle(rd[0]) end
      end)
    end
    if type(opts.lock) == "function" then opts.lock(launch) else launch() end
    if not started then return nil end
    C.CloseHandle(pi.hThread)
    local chunks = {}
    local size = 65536
    local buf = ffi.new("uint8_t[?]", size)
    local got = ffi.new("uint32_t[1]")
    while C.ReadFile(rd[0], buf, size, got, nil) ~= 0 and got[0] > 0 do
      chunks[#chunks + 1] = ffi.string(buf, got[0])
    end
    C.CloseHandle(rd[0])
    C.WaitForSingleObject(pi.hProcess, INFINITE)
    local exit = ffi.new("uint32_t[1]")
    local status = nil
    if C.GetExitCodeProcess(pi.hProcess, exit) ~= 0 then status = tonumber(exit[0]) end
    C.CloseHandle(pi.hProcess)
    return table.concat(chunks), status
  end)
  if ok and type(out) == "string" then return out, code end
  return nil
end

return WinApi
