package.path = "./?.lua;./?/init.lua;" .. package.path

local GameCache = require("tests.game3_cache")
local CacheBlob = require("src.import.CacheBlob")
local TmCaseExtract = require("src.import.gba.tm_case_extract")

local root = GameCache.root(TmCaseExtract.CACHE_SUB .. "/manifest.lua")
if not root then
  print("[skip] game3_tm_case_disc_cache_3061_test: " .. tostring(GameCache.reason))
  os.exit(0)
end

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
  return cond
end

local function read(rel)
  local path = root .. "/" .. rel
  local f = io.open(path, "rb")
  if not f then return nil end
  local data = CacheBlob.decode(path, f:read("*a"))
  f:close()
  return data
end

local function colors(data)
  local counts, keys = {}, {}
  for i = 0, 32 * 32 - 1 do
    local r, g, b, a = data:byte(i * 4 + 1, i * 4 + 4)
    if a == 255 then
      local k = r .. "," .. g .. "," .. b
      if not counts[k] then keys[#keys + 1] = k end
      counts[k] = (counts[k] or 0) + 1
    end
  end
  table.sort(keys)
  local sig = {}
  for i, k in ipairs(keys) do sig[i] = k .. "x" .. counts[k] end
  return counts, table.concat(sig, " ")
end

local sigs, sets = {}, {}
for t = 0, 17 do
  for _, hm in ipairs({ "", "hm_" }) do
    local rel = string.format("%s/disc_%s%d.rgba", TmCaseExtract.CACHE_SUB, hm, t)
    local data = read(rel)
    if check(data and #data == 32 * 32 * 4, rel .. " is a 32x32 disc") then
      local counts, sig = colors(data)
      check(sig ~= "", rel .. " has opaque pixels")
      if hm == "" then sigs[t], sets[t] = sig, counts end
    end
  end
end

-- src/tm_case.c:396 sTMSpritePaletteOffsetByType
check(sigs[9] ~= nil and sigs[9] == sigs[0], "TYPE_MYSTERY tints like TYPE_NORMAL")
for a = 0, 17 do
  for b = a + 1, 17 do
    if a ~= 9 and b ~= 9 and sigs[a] and sigs[b] and sigs[a] == sigs[b] then
      check(false, string.format("types %d and %d share a disc palette", a, b))
    end
  end
end
check(sets[17] and sets[17]["82,156,165"] == 56, "the Dark disc carries the Dark teal accent")
check(sets[10] and sets[10]["239,173,33"] == 56, "the Fire disc carries the Fire orange accent")
check(sets[11] and sets[11]["74,165,239"] == 56, "the Water disc carries the Water blue accent")

if failed > 0 then
  print(string.format("%d failure(s)", failed))
  os.exit(1)
end
print("all checks passed")
