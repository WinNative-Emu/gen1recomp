local Strings = require("src.core.Strings")

local Units = {}

function Units.metric(species)
  local Pokemon = require("src.core.game3.pokemon")
  if Pokemon._dex == nil then return nil end
  local ok, entry = pcall(Pokemon.dexEntry, species)
  if ok and type(entry) == "table" and entry.heightM and entry.weightKg then return entry end
  return nil
end

local function decimal(value, pad)
  local text = (("%.1f"):format(value or 0):gsub("%.", ","))
  return string.rep(pad or " ", math.max(0, 5 - #text)) .. text
end

function Units.height(entry, pad)
  return decimal(entry.heightM, pad) .. " " .. Strings("m")
end

function Units.weight(entry, pad)
  return decimal(entry.weightKg, pad) .. " " .. Strings("kg")
end

function Units.unknownHeight()
  return "???,? " .. Strings("m")
end

function Units.unknownWeight()
  return "???,? " .. Strings("kg")
end

return Units
