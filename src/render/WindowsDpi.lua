local WindowsDpi = {}

WindowsDpi.HINT = "SDL_WINDOWS_DPI_SCALING"

function WindowsDpi.apply(t, osName, ffiLike)
  if osName ~= "Windows" then return false end
  local ok, set = pcall(function()
    local ffi = ffiLike or require("ffi")
    pcall(ffi.cdef, "int SDL_SetHint(const char *name, const char *value);")
    return ffi.load("SDL2").SDL_SetHint(WindowsDpi.HINT, "1")
  end)
  if not (ok and set ~= nil and set ~= 0) then return false end
  t.window.highdpi = true
  return true
end

function WindowsDpi.desktopDimensions(display, win, osName)
  win = win or love.window
  osName = osName or (love and love._os)
  local dw, dh = win.getDesktopDimensions(display)
  if osName ~= "Windows" or not (dw and dh) then return dw, dh end
  local _, _, flags = win.getMode()
  if not (flags and flags.highdpi) then return dw, dh end
  local d = tonumber(win.getDPIScale and win.getDPIScale())
  if not d or d <= 0 or d == 1 then return dw, dh end
  return math.floor(dw / d), math.floor(dh / d)
end

function WindowsDpi.modeFlags(extra, win)
  win = win or (love and love.window)
  local flags = {}
  for k, v in pairs(extra or {}) do flags[k] = v end
  if win and win.getMode then
    local ok, _, _, cur = pcall(win.getMode)
    if ok and type(cur) == "table" and cur.highdpi ~= nil then
      flags.highdpi = cur.highdpi
    end
  end
  return flags
end

return WindowsDpi
