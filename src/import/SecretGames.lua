local GameVersion = require("src.core.GameVersion")
local Json = require("src.link.Json")

local SecretGames = {}

SecretGames.GAMES = { emerald = "secretEmerald" }
SecretGames.TAPS = 20
SecretGames.EMERALD_RELEASE_AT = 1790856000
SecretGames.rev = 0

local unlocked, releasedBuild

local function load()
  unlocked = {}
  local okSave, SaveData = pcall(require, "src.core.SaveData")
  local ok, opts = false, nil
  if okSave then ok, opts = pcall(SaveData.loadOptions) end
  for id, key in pairs(SecretGames.GAMES) do
    unlocked[id] = ok and type(opts) == "table" and opts[key] == true
  end
  releasedBuild = false
  local fs = love and love.filesystem
  local okRead, raw
  if fs and fs.read then okRead, raw = pcall(fs.read, "build-info.json") end
  local okInfo, info = false, nil
  if okRead and type(raw) == "string" then okInfo, info = pcall(Json.decode, raw) end
  local stamp = okInfo and type(info) == "table" and info.builtAt
  if type(stamp) ~= "string" then return end
  local year, month, day, hour, minute, second = stamp:match(
    "^(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d):(%d%d)Z$")
  if not year then return end
  year, month, day = tonumber(year), tonumber(month), tonumber(day)
  hour, minute, second = tonumber(hour), tonumber(minute), tonumber(second)
  local days = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
  if year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0) then days[2] = 29 end
  releasedBuild = year >= 1 and month >= 1 and month <= 12
    and day >= 1 and day <= days[month]
    and hour <= 23 and minute <= 59 and second <= 59
    and stamp >= "2026-10-01T12:00:00Z"
end

function SecretGames.reload()
  unlocked = nil
  SecretGames.rev = SecretGames.rev + 1
end

function SecretGames.visible(id)
  if not SecretGames.GAMES[id] then return true end
  SecretGames.update()
  return unlocked[id] == true
end

function SecretGames.shown(imp, id)
  if type(imp) == "table" and not imp.launcher then return true end
  return SecretGames.visible(id)
end

function SecretGames.anyLocked()
  for id in pairs(SecretGames.GAMES) do
    if not SecretGames.visible(id) then return true end
  end
  return false
end

function SecretGames.order(imp)
  local out = {}
  for _, id in ipairs(GameVersion.ORDER) do
    if SecretGames.shown(imp, id) then out[#out + 1] = id end
  end
  return out
end

function SecretGames.unlock()
  local patch = {}
  for _, key in pairs(SecretGames.GAMES) do patch[key] = true end
  local okSave, SaveData = pcall(require, "src.core.SaveData")
  local saved = okSave and SaveData.saveOptions(patch) ~= nil
  unlocked = {}
  for id in pairs(SecretGames.GAMES) do unlocked[id] = true end
  SecretGames.rev = SecretGames.rev + 1
  return saved
end

function SecretGames.update(now)
  if not unlocked then load() end
  local due = (now or os.time()) >= SecretGames.EMERALD_RELEASE_AT
  if now == nil then due = due or releasedBuild end
  local changed = due and unlocked.emerald ~= true
  if changed then SecretGames.unlock() end
  return due, changed
end

return SecretGames
