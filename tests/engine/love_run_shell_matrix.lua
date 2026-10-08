--   luajit tests/engine/love_run_shell_matrix.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local FsIo = require("tests.fs_io")
local Version = require("src.core.Version")
local HostShell = require("src.core.HostShell")

local SHELLS = {
  { file = "v0.1.24", last = "v0.1.41", shell = 1, legacy = true },
  { file = "v0.1.42", last = "v0.2.24", shell = 1, legacy = true },
  { file = "v0.2.25", last = "v0.2.26", shell = 1, legacy = true },
  { file = "v0.2.27", last = "v0.2.36", shell = 1, legacy = true },
  { file = "v0.2.37", last = "v0.2.38", shell = 1, legacy = true },
  { file = "v0.2.39", last = "v0.2.42", shell = 1, legacy = true },
  { file = "v0.2.43", last = "v0.2.45", shell = 1, legacy = true },
  { file = "v0.2.46", last = "v0.2.50", shell = 1, legacy = true },
  { file = "v0.2.51", last = "v0.3.57", shell = 2, legacy = true },
  { file = "v0.3.58", last = "v0.3.58", shell = 2, legacy = true },
  { file = "shell3", shell = 3, shipped = { { first = "v0.3.59", last = "v0.3.59", declared = 2 } } },
}

local function readFile(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

local function stripComments(src)
  local out, i, n, q = {}, 1, #src, nil
  while i <= n do
    local c = src:sub(i, i)
    if q then
      out[#out + 1] = c
      if c == "\\" then
        out[#out + 1] = src:sub(i + 1, i + 1)
        i = i + 2
      else
        if c == q then q = nil end
        i = i + 1
      end
    elseif c == '"' or c == "'" then
      q = c
      out[#out + 1] = c
      i = i + 1
    elseif src:sub(i, i + 1) == "--" then
      local eqs = src:match("^%-%-%[(=*)%[", i)
      if eqs then
        local _, e = src:find("]" .. eqs .. "]", i, true)
        i = (e or n) + 1
      else
        local nl = src:find("\n", i, true)
        i = nl or (n + 1)
      end
    else
      out[#out + 1] = c
      i = i + 1
    end
  end
  return table.concat(out)
end

local function normalize(src)
  return (stripComments(src):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""))
end

local function loveRunOf(src)
  return src and src:match("\nfunction love%.run%(%)\n.-\nend\n")
end

local mainRun = loveRunOf(readFile("main.lua"))
check(mainRun ~= nil, "main.lua defines function love.run()")

local current
local maxLegacy = 0
for _, fx in ipairs(SHELLS) do
  fx.src = readFile("tests/data/love_run/" .. fx.file .. ".lua")
  check(fx.src ~= nil, "fixture " .. fx.file .. " exists")
  fx.norm = normalize(fx.src or "")
  if fx.legacy and fx.shell > maxLegacy then maxLegacy = fx.shell end
  if mainRun and fx.norm == normalize(mainRun) then current = fx end
end

check(current ~= nil,
  "main.lua love.run matches a tests/data/love_run fixture (a changed love.run is a new shell)")
if current then
  eq(Version.shell, current.shell, "Version.shell names the shell main.lua's love.run implements")
end

local seen = {}
local prev = maxLegacy
for _, fx in ipairs(SHELLS) do
  if not fx.legacy then
    check(fx.shell > prev, "shell " .. fx.shell .. " (" .. fx.file .. ") is newer than every earlier shell")
    check(not seen[fx.shell], "shell " .. fx.shell .. " names one love.run only")
    seen[fx.shell] = true
    prev = math.max(prev, fx.shell)
    for _, rel in ipairs(fx.shipped or {}) do
      check(rel.declared < fx.shell and rel.declared <= maxLegacy,
        fx.file .. " shipped in " .. rel.first .. " under shell " .. rel.declared
        .. ": a misdeclared release may only reuse a legacy shell number")
    end
  end
end
for _, fx in ipairs(SHELLS) do
  if fx.legacy and current and fx ~= current then
    check(fx.norm ~= current.norm or fx.shell == current.shell,
      fx.file .. " has the same love.run as main.lua under a different shell number")
  end
end

local payloadFiles = FsIo.luaFilesUnder("src")
payloadFiles[#payloadFiles + 1] = "main.lua"
check(#payloadFiles > 100, "payload scan found the source tree")
local function callArg(src, open)
  local depth, i, n, q = 0, open, #src, nil
  while i <= n do
    local c = src:sub(i, i)
    if q then
      if c == "\\" then i = i + 1 elseif c == q then q = nil end
    elseif c == '"' or c == "'" then
      q = c
    elseif c == "(" then
      depth = depth + 1
    elseif c == ")" then
      depth = depth - 1
      if depth == 0 then return src:sub(open + 1, i - 1) end
    end
    i = i + 1
  end
  return nil
end

local quitArgs = { [""] = true }
local quitSites = 0
for _, path in ipairs(payloadFiles) do
  local src = stripComments(readFile(path) or "")
  local isHostShell = path:match("src/core/HostShell%.lua$") ~= nil
  local pos = 1
  while true do
    local s, e = src:find("love%.event%.quit%(", pos)
    if not s then break end
    local raw = callArg(src, e)
    check(raw ~= nil, path .. ": love.event.quit( call at offset " .. s .. " never closes")
    pos = e + 1
    local arg = (raw or ""):gsub("^%s+", ""):gsub("%s+$", "")
    quitSites = quitSites + 1
    if arg == "" or arg:match("^%d+$") then
      quitArgs[arg] = true
    else
      check(isHostShell, path .. " sends love.event.quit(" .. arg .. ") outside HostShell.restart")
      check(arg:match('^"[^"]*"$') ~= nil or arg:match("^'[^']*'$") ~= nil,
        path .. " sends love.event.quit(" .. arg .. "): the shell contract needs a literal argument")
    end
  end
end
check(quitSites >= 4, "payload scan found the love.event.quit call sites (" .. quitSites .. ")")

local realExit, realOpen = os.exit, io.open
local EXITED = {}

local queue, exits = {}, {}
local sleeps = 0
local osName = "Android"
local fused = false

local function noop() end

local function installLove()
  love.event = {
    pump = noop,
    poll = function()
      return function()
        local ev = table.remove(queue, 1)
        if ev then return unpack(ev, 1, 7) end
      end
    end,
    quit = function(...)
      local n = select("#", ...)
      queue[#queue + 1] = n == 0 and { "quit" } or { "quit", ... }
    end,
    push = function(name, ...) queue[#queue + 1] = { name, ... } end,
  }
  love.handlers = setmetatable({}, { __index = function() return noop end })
  love.system = love.system or {}
  love.system.getOS = function() return osName end
  love.system.restartApp = nil
  love.filesystem = love.filesystem or {}
  love.filesystem.isFused = function() return fused end
  local now = 0
  love.timer = {
    step = function() now = now + 1 / 60 return 1 / 60 end,
    getTime = function() return now end,
    sleep = function(s)
      sleeps = sleeps + 1
      if sleeps > 10000 then error("frame never ends: love.timer.sleep looped", 0) end
      now = now + (s or 0)
    end,
    getDelta = function() return 1 / 60 end,
  }
  love.graphics = love.graphics or {}
  love.graphics.isActive = function() return true end
  love.graphics.origin = love.graphics.origin or noop
  love.graphics.clear = love.graphics.clear or noop
  love.graphics.getBackgroundColor = love.graphics.getBackgroundColor or function() return 0, 0, 0, 1 end
  love.graphics.present = love.graphics.present or noop
  love.window = love.window or {}
  love.window.isVisible = function() return true end
  love.window.hasFocus = function() return true end
  love.load = noop
  love.update = noop
  love.draw = noop
  love.quit = function() return false end
  love.arg = love.arg or {}
  love.arg.parseGameArguments = love.arg.parseGameArguments or function(a) return a or {} end
end

local function loadShell(fx)
  local chunk, err = loadstring(fx.src, "=love_run/" .. fx.file)
  if not chunk then return nil, err end
  local env = setmetatable({
    pacingEnabled = function() return true end,
    checkEmergencyQuit = noop,
    idlePresentationCap = function() return nil end,
  }, { __index = _G, __newindex = _G })
  setfenv(chunk, env)
  local saved = love.run
  local ok, e = pcall(chunk)
  local run = love.run
  love.run = saved
  if not ok then return nil, e end
  return run
end

local function step(stepper)
  sleeps = 0
  local ok, ret = pcall(stepper)
  if not ok and ret == EXITED then return true, nil, true end
  return ok, ret, false
end

local ACTIONS = {
  { name = "HostShell.restart", fn = function() HostShell.restart() end },
}
for arg in pairs(quitArgs) do
  local n = tonumber(arg)
  ACTIONS[#ACTIONS + 1] = {
    name = "quit(" .. arg .. ")",
    fn = function() if n then love.event.quit(n) else love.event.quit() end end,
  }
end
table.sort(ACTIONS, function(a, b) return a.name < b.name end)

local OSES = { "Android", "iOS", "OS X", "Windows", "Linux" }

os.exit = function(code)
  exits[#exits + 1] = code
  if code ~= nil and type(code) ~= "number" and type(code) ~= "boolean" then
    error("bad argument #1 to 'exit' (number expected, got " .. type(code) .. ")", 2)
  end
  error(EXITED, 0)
end
io.open = function(path, ...)
  if path == "/proc/self/cmdline" then return nil end
  return realOpen(path, ...)
end

local FrameCap = require("src.core.FrameCap")
local capWas = FrameCap.current
local runs = 0
for _, fx in ipairs(SHELLS) do
  if fx.src and fx.shell >= (Version.minShell or 1) then
    for _, os_ in ipairs(OSES) do
      for _, act in ipairs(ACTIONS) do
        local label = fx.file .. " shell on " .. os_ .. ", payload " .. act.name
        osName, fused = os_, false
        for i = #queue, 1, -1 do queue[i] = nil end
        for i = #exits, 1, -1 do exits[i] = nil end
        _G.POKEPORT_LOOP_RESTART = nil
        _G.POKEPORT_LOOP_PANEL_SYNC = nil
        HostShell.restarting = false
        installLove()
        FrameCap.current = capWas
        local run, lerr = loadShell(fx)
        check(run ~= nil, label .. ": fixture loads (" .. tostring(lerr) .. ")")
        if run then
          local okRun, stepper = pcall(run)
          check(okRun and type(stepper) == "function", label .. ": love.run returns a stepper (" .. tostring(stepper) .. ")")
          if okRun and type(stepper) == "function" then
            local ok1, r1 = step(stepper)
            check(ok1 and r1 == nil, label .. ": a default-cap frame runs on the payload's modules (" .. tostring(r1) .. ")")
            FrameCap.applyOptions({ fpsCap = FrameCap.DISPLAY })
            local ok2, r2 = step(stepper)
            check(ok2 and r2 == nil, label .. ": a DISPLAY-option frame runs on the payload's modules (" .. tostring(r2) .. ")")
            FrameCap.current = capWas
            local okA, aerr = pcall(act.fn)
            check(okA, label .. ": payload exit path runs (" .. tostring(aerr) .. ")")
            local ok, ret, exited = step(stepper)
            check(ok, label .. ": shell survives the payload's quit (" .. tostring(ret) .. ")")
            if ok then
              check(exited or ret ~= nil, label .. ": shell ends the frame loop")
              check(exited or type(ret) == "number" or ret == "restart",
                label .. ": shell hands LOVE a number or \"restart\", got " .. tostring(ret))
            end
            runs = runs + 1
          end
        end
      end
    end
  end
end
FrameCap.current = capWas
os.exit, io.open = realExit, realOpen

check(runs >= #SHELLS * #OSES * 2, "every shell ran under every OS (" .. runs .. " runs)")

T.finish("love_run_shell_matrix")
