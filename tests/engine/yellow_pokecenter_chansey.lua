package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local GameVersion = require("src.core.GameVersion")
local previous = GameVersion.get()
GameVersion.set("yellow")
require("data.scripts")
local MapScripts = require("src.script.MapScripts")

local function isChansey(script)
  if type(script) ~= "table" then return false end
  local cry, text
  for _, row in ipairs(script) do
    if row[1] == "play_cry" then cry = row[2] end
    if row[1] == "show_text" then text = row[2] end
  end
  return cry == "CHANSEY" and text == "_NurseChanseyText"
end

check(isChansey(MapScripts.talkScript("VIRIDIAN_POKECENTER", "TEXT_VIRIDIANPOKECENTER_CHANSEY")),
  "Viridian's Chansey runs PokecenterChanseyText")
check(isChansey(MapScripts.talkScript("INDIGO_PLATEAU_LOBBY", "TEXT_INDIGOPLATEAULOBBY_CHANSEY")),
  "the Indigo lobby Chansey runs PokecenterChanseyText")

local function cacheFile(name)
  local home = os.getenv("HOME")
  if not home or home == "" then return nil end
  local ids = { os.getenv("POKEPORT_IDENTITY"), "g1r-yellow", "pokeport-test-caches" }
  for _, base in ipairs({ home .. "/Library/Application Support/LOVE", home .. "/.local/share/love" }) do
    for i = 1, 3 do
      local id = ids[i]
      if id and id ~= "" then
        local chunk = loadfile(base .. "/" .. id .. "/yellow/data/generated/" .. name .. ".lua")
        local ok, mod = pcall(chunk or error)
        if ok and type(mod) == "table" then return mod end
      end
    end
  end
  return nil
end

local maps, pointers, text = cacheFile("maps"), cacheFile("text_pointers"), cacheFile("text")
if maps and pointers and text then
  check(type(text._NurseChanseyText) == "string", "the Yellow cache carries _NurseChanseyText")
  local found = 0
  for id, def in pairs(maps) do
    for _, o in ipairs(type(def) == "table" and def.objects or {}) do
      local entry = pointers[def.label] and pointers[def.label][o.text]
      if o.sprite == "SPRITE_CHANSEY" and entry and entry.asm and not entry.text then
        found = found + 1
        check(isChansey(MapScripts.talkScript(id, o.text)), id .. " " .. o.text .. " answers")
      end
    end
  end
  eq(found, 12, "twelve Yellow centers call PokecenterChanseyText")
else
  print("[skip] yellow cache checks: no Yellow cache")
end

GameVersion.set(previous)
T.finish("yellow_pokecenter_chansey")
