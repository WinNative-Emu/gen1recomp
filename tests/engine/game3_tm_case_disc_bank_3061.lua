package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local check, eq = T.check, T.eq

local Versions = require("src.import.gba.versions")
local Extract = require("src.import.gba.extract_island1")
local TmCaseExtract = require("src.import.gba.tm_case_extract")
local TmCaseChrome = require("src.ui.game3.tm_case_chrome")

local ROOT = Extract.CACHE_ROOT or "data/generated/gba"

-- src/tm_case.c:396 sTMSpritePaletteOffsetByType
local BANK_BY_TYPE = {
  [0] = 0, [1] = 9, [2] = 8, [3] = 12, [4] = 6, [5] = 5, [6] = 11, [7] = 10, [8] = 14,
  [9] = 0, [10] = 1, [11] = 2, [12] = 3, [13] = 4, [14] = 13, [15] = 7, [16] = 16, [17] = 15,
}

local bytes = {}
local function put(at, list)
  for i, b in ipairs(list) do bytes[at + i - 1] = b end
end
local function lz(raw)
  local out = { 0x10, #raw % 256, math.floor(#raw / 256) % 256, math.floor(#raw / 65536) % 256 }
  for i = 1, #raw, 8 do
    out[#out + 1] = 0
    for j = i, math.min(i + 7, #raw) do out[#out + 1] = raw[j] end
  end
  return out
end
local function fill(n, v)
  local t = {}
  for i = 1, n do t[i] = v end
  return t
end
local function colorFor(bank, c)
  return bank * 64 + c + 1
end
local function palBytes(firstBank, count)
  local t = {}
  for b = firstBank, firstBank + count - 1 do
    for c = 0, 15 do
      local v = colorFor(b, c)
      t[#t + 1] = v % 256
      t[#t + 1] = math.floor(v / 256)
    end
  end
  return t
end

local KEYS = {
  "TM_CASE_BG_GFX", "TM_CASE_MENU_TILEMAP", "TM_CASE_BG_TILEMAP", "TM_CASE_MENU_MALE_PAL",
  "TM_CASE_MENU_FEMALE_PAL", "TM_CASE_DISC_GFX", "TM_CASE_DISC_TYPES1_PAL", "TM_CASE_DISC_TYPES2_PAL",
  "TM_CASE_HM_GFX", "TM_CASE_PAL3_OVERRIDE", "TM_CASE_DISC_PAL_OFFSETS",
}
local saved = {}
for i, k in ipairs(KEYS) do
  saved[k] = Versions[k]
  Versions[k] = 0x100000 + i * 0x1000
end

put(Versions.TM_CASE_BG_GFX, lz(fill(32, 0)))
put(Versions.TM_CASE_MENU_TILEMAP, lz(fill(8, 0)))
put(Versions.TM_CASE_BG_TILEMAP, lz(fill(8, 0)))
put(Versions.TM_CASE_MENU_MALE_PAL, lz(fill(32, 0)))
put(Versions.TM_CASE_MENU_FEMALE_PAL, lz(fill(32, 0)))
put(Versions.TM_CASE_DISC_GFX, lz(fill(1024, 0x21)))
put(Versions.TM_CASE_DISC_TYPES1_PAL, lz(palBytes(0, 16)))
put(Versions.TM_CASE_DISC_TYPES2_PAL, lz(palBytes(16, 1)))
put(Versions.TM_CASE_HM_GFX, fill(128, 0))
put(Versions.TM_CASE_PAL3_OVERRIDE, { 0x08, 0x21, 0x1E, 0x1A })
for t = 0, 17 do
  local off = BANK_BY_TYPE[t] * 16
  put(Versions.TM_CASE_DISC_PAL_OFFSETS + t * 2, { off % 256, math.floor(off / 256) })
end

local rom = { get = function(_, i) return bytes[i] or 0 end }
local files = {}
local cache = {
  write = function(_, path, data) files[path] = data; return true end,
  exists = function(_, path) return files[path] ~= nil end,
  read = function(_, path) return files[path] end,
}

local ok, err = pcall(TmCaseExtract.run, rom, cache, { cacheRoot = ROOT })
for _, k in ipairs(KEYS) do Versions[k] = saved[k] end
check(ok, "TM case extract runs on the fixture ROM: " .. tostring(err))

local reads = {}
TmCaseChrome._cache = {
  read = function(_, rel)
    local data = files[rel]
    reads[#reads + 1] = { rel = rel, data = data }
    return data
  end,
}

local function rgb8(c)
  local r5, g5, b5 = c % 32, math.floor(c / 32) % 32, math.floor(c / 1024) % 32
  return math.floor(r5 * 255 / 31 + 0.5), math.floor(g5 * 255 / 31 + 0.5), math.floor(b5 * 255 / 31 + 0.5)
end

local function discRead(typeIdx, isHm)
  reads = {}
  TmCaseChrome._discs, TmCaseChrome._discsHm = {}, {}
  TmCaseChrome.loadDisc(typeIdx, isHm)
  return reads[1]
end

local NAMES = { [10] = "Fire", [11] = "Water", [8] = "Steel", [16] = "Dragon", [17] = "Dark", [9] = "Mystery" }
for t = 0, 17 do
  for _, isHm in ipairs({ false, true }) do
    local label = (NAMES[t] or ("type " .. t)) .. (isHm and " HM" or " TM")
    local r = discRead(t, isHm)
    local want = string.format("disc_%s%d.rgba", isHm and "hm_" or "", t)
    eq(r and r.rel:match("(disc_[%w_]*%.rgba)$"), want, label .. " reads the per-type disc file")
    local data = r and r.data
    if check(data and #data == 32 * 32 * 4, label .. " disc is in the cache") then
      local er, eg, eb = rgb8(colorFor(BANK_BY_TYPE[t], 1))
      eq(table.concat({ data:byte(1, 4) }, ","), table.concat({ er, eg, eb, 255 }, ","),
        label .. " disc uses palette bank " .. BANK_BY_TYPE[t])
    end
  end
end

check(TmCaseChrome.discBank == nil, "the UI carries no type to palette bank table")

local required = {}
for _, rel in ipairs(TmCaseExtract.REQUIRED or {}) do required[rel] = true end
check(required["items/tm_case/disc_17.rgba"], "disc_17 is a required cache file")
check(required["items/tm_case/disc_hm_17.rgba"], "disc_hm_17 is a required cache file")
check(TmCaseExtract.ready(cache, ROOT), "TmCaseExtract.ready sees every required file")

local plan = require("src.import.gba.plans.frlg")
local inPlan = false
for _, m in ipairs(plan.pokemonAfter or {}) do
  if m == "src.import.gba.tm_case_extract" then inPlan = true end
end
check(inPlan, "the FRLG import plan runs the TM case extract")

T.finish()
