local PokedexEntriesExtract = {}

PokedexEntriesExtract.CACHE_SUB = "pokemon/pokedex"
PokedexEntriesExtract.REQUIRED = { "pokemon/pokedex/entries.lua", "pokemon/pokedex/regional.lua" }

function PokedexEntriesExtract.files()
  local L = require("src.import.gba.layouts.registry").active()
  local files = { "entries.lua" }
  if L.regionalDex then files[#files + 1] = "regional.lua" end
  return files
end

function PokedexEntriesExtract.run(rom, cache, opts)
  opts = opts or {}
  local root = (opts.cacheRoot or "data/generated/gba") .. "/" .. PokedexEntriesExtract.CACHE_SUB
  require("src.import.gba.pokedex_chrome_extract").extractEntries(rom, cache, root)
  return { root = root }
end

function PokedexEntriesExtract.ready(cache, cacheRoot)
  if not (cache and cache.exists) then return false end
  local root = (cacheRoot or "data/generated/gba") .. "/" .. PokedexEntriesExtract.CACHE_SUB .. "/"
  for _, f in ipairs(PokedexEntriesExtract.files()) do
    if not cache:exists(root .. f) then return false end
  end
  local okL, L = pcall(function() return require("src.import.gba.layouts.registry").active() end)
  if okL and type(L) == "table" and L.id == "rs" then
    local body = cache.read and cache:read(root .. "entries.lua")
    return body ~= nil and body:find("descriptionLabel", 1, true) ~= nil
  end
  return true
end

return PokedexEntriesExtract
