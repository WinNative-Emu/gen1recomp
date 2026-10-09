package.path = "./?.lua;./?/init.lua;" .. package.path

local FsIo = require("tests.fs_io")

local ALLOW = {
  { "src/render/Renderer.lua", "self.presentCanvas = love.graphics.newCanvas(ww, wh)" },
  { "src/render/Renderer.lua", "self.uiLayerCanvas = love.graphics.newCanvas(ww, wh)" },
  { "src/core/Game2.lua", "pcall(love.graphics.newCanvas, w, h)" },
  { "src/world/gen2/World.lua", "pcall(love.graphics.newCanvas, w, h)" },
  { "src/ui/gen2/BattleTransition.lua", "pcall(love.graphics.newCanvas, w, h)" },
  { "src/render/GameViewport.lua", "love.graphics.newCanvas(rect.width, rect.height)" },
  { "src/render/ShaderFX.lua", "love.graphics.newCanvas(dims.w, dims.h)" },
  { "src/render/ShaderFX.lua", "love.graphics.newCanvas(outW, outH)" },
  { "src/box/Showcase.lua", "love.graphics.newCanvas(1136,432)" },
  { "src/import/LauncherSplash.lua", "love.graphics.newCanvas(width, height)" },
  { "src/import/CartLabelArt.lua", "g.newCanvas(w, h)" },
}

local function rel(path)
  return (path:gsub("^%./", ""))
end

local function allowed(file, line, hits)
  local any = false
  for i, entry in ipairs(ALLOW) do
    if entry[1] == file and line:find(entry[2], 1, true) then
      hits[i] = (hits[i] or 0) + 1
      any = true
    end
  end
  return any
end

local files = FsIo.luaFilesUnder("src")
assert(#files > 100, "src scan found only " .. #files .. " files")

local offenders, hits, calls = {}, {}, 0
for _, path in ipairs(files) do
  local file = rel(path)
  local handle = assert(io.open(path, "rb"))
  local lines = {}
  for line in handle:lines() do lines[#lines + 1] = line end
  handle:close()
  for n, raw in ipairs(lines) do
    local code = raw:gsub("%-%-.*$", "")
    if code:find("newCanvas%s*%(") or code:find("newCanvas%s*,") then
      calls = calls + 1
      local nextLine = (lines[n + 1] or ""):gsub("%-%-.*$", "")
      local hasDpi = code:find("dpiscale", 1, true) or nextLine:find("dpiscale", 1, true)
      if not hasDpi and not allowed(file, code, hits) then
        offenders[#offenders + 1] = ("%s:%d: %s"):format(file, n, (code:gsub("^%s+", "")))
      end
    end
  end
end

assert(calls > 10, "only " .. calls .. " newCanvas calls found")

local miscounted = {}
for i, entry in ipairs(ALLOW) do
  local n = hits[i] or 0
  if n ~= 1 then
    miscounted[#miscounted + 1] = ("%s: %s (expected 1 site, found %d)"):format(entry[1], entry[2], n)
  end
end

if #offenders > 0 or #miscounted > 0 then
  for _, o in ipairs(offenders) do print("FAIL newCanvas without dpiscale " .. o) end
  for _, s in ipairs(miscounted) do print("FAIL allowlist entry " .. s) end
  os.exit(1)
end

print(("canvas dpiscale lint: ok (%d newCanvas calls, %d allowlisted)"):format(calls, #ALLOW))
