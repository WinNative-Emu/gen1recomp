package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local CacheContract = require("src.import.CacheContract")
local DatasetViews = require("src.mods.DatasetViews")
local GameVersion = require("src.core.GameVersion")
local Logger = require("src.core.Logger")
local Schemas = require("src.mods.Schemas")

local VERSIONS = { "red", "blue", "yellow", "gold", "silver", "crystal" }

local function slurp(path)
  local file = io.open(path, "rb")
  if not file then return nil end
  local body = file:read("*a")
  file:close()
  return body
end

local function rootFor(version)
  local home = os.getenv("HOME")
  if not home or home == "" then return nil end
  local identities = { "g1r-" .. version, "pokeport-test-caches" }
  local own = os.getenv("POKEPORT_IDENTITY")
  if own and own ~= "" then table.insert(identities, 1, own) end
  local prefix = GameVersion.cachePrefix(version)
  for _, base in ipairs({ home .. "/Library/Application Support/LOVE",
      home .. "/.local/share/love" }) do
    for _, identity in ipairs(identities) do
      local root = base .. "/" .. identity .. "/"
      if CacheContract.markerMatches(version,
          slurp(root .. prefix .. CacheContract.MARKER_PATH)) then
        return root
      end
    end
  end
  return nil
end

local roots, found = {}, 0
for _, version in ipairs(VERSIONS) do
  roots[GameVersion.cachePrefix(version)] = rootFor(version)
  if roots[GameVersion.cachePrefix(version)] then found = found + 1 end
end
if found == 0 then
  print("[skip] dataset_views_real_cache_walk: no imported Gen 1 or Gen 2 cache")
  os.exit(0)
end

local bodies = {}
local function full(path)
  local prefix = path:match("^[^/]+/")
  local root = prefix and roots[prefix]
  return root and root .. path
end
local fs = {
  read = function(path)
    if bodies[path] == nil then
      local where = full(path)
      bodies[path] = where and slurp(where) or false
    end
    return bodies[path] or nil
  end,
}
fs.getInfo = function(path)
  local body = fs.read(path)
  if not body then return nil end
  return { type = "file", size = #body }
end

local warnings = {}
local originalWarn = Logger.warn
Logger.warn = function(fmt, ...)
  warnings[#warnings + 1] = select("#", ...) > 0 and fmt:format(...) or fmt
end

local names = {}
for name in pairs(Schemas.REGISTRIES) do names[#names + 1] = name end
table.sort(names)

for _, version in ipairs(VERSIONS) do
  if not roots[GameVersion.cachePrefix(version)] then
    print("[info] no " .. version .. " cache; skipped")
  else
    local service = DatasetViews.new(fs)
    local view = service:open(version)
    T.check(view ~= nil, version .. " opens")
    for _, name in ipairs(names) do
      if not view then break end
      warnings = {}
      local ok, err = pcall(function()
        for _ in view.content[name]:each() do end
      end)
      local again, reason = service:open(version)
      T.check(ok, version .. " " .. name .. " each does not throw: " .. tostring(err))
      T.check(again ~= nil, version .. " " .. name .. " walk keeps the view: "
        .. tostring(reason))
      T.eq(warnings[1], nil, version .. " " .. name .. " walk logs no rejection")
      if not again then
        service = DatasetViews.new(fs)
        view = service:open(version)
      end
    end
    if view and GameVersion.generation(version) == 2 then
      local emotes = view.content.field:get("emotes")
      T.check(type(emotes) == "table", version .. " field emotes resolves")
      emotes = emotes or {}
      T.eq(emotes.fishing, "assets/generated/emotes/fishing.png",
        version .. " emotes.fishing is the fishing sheet")
      local info = emotes.fishing and view.assets:info(emotes.fishing)
      T.eq(info and info.type, "file", version .. " fishing sheet resolves as a file")
      if version == "crystal" then
        local female = emotes.fishingFemale and view.assets:info(emotes.fishingFemale)
        T.eq(female and female.type, "file", version .. " fishingFemale resolves as a file")
      else
        T.eq(emotes.fishingFemale, nil, version .. " has no fishingFemale")
      end
      local ids = {}
      for id in view.content.field:each() do ids[#ids + 1] = id end
      T.same(ids, { "emotes" }, version .. " field lists only emotes")
    end
  end
end

Logger.warn = originalWarn
T.finish("dataset_views_real_cache_walk")
