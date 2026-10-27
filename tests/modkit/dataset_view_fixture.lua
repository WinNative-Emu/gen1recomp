local GameVersion = require("src.core.GameVersion")
local LuaWriter = require("src.import.LuaWriter")
local CacheContract = require("src.import.CacheContract")

local Fixture = {}

local GEN1_MODULES = {
  "constants", "maps", "tilesets", "text", "text_pointers",
  "trainer_headers", "font", "sprites", "pokemon", "moves", "items",
  "type_chart", "trainers", "encounters", "field", "battle_anims",
}
local GEN1_OPTIONAL_MODULES = { "audio", "palettes", "icons" }

local GEN2_MODULES = {
  "pokemon", "moves", "items", "type_chart", "audio", "font", "maps",
  "tilesets", "text", "rom_text", "trainers", "encounters", "sprites",
  "palettes", "icons", "battle_anims", "constants", "landmarks",
  "menu_gfx",
}

local CONTINUATIONS = {
  "CROBAT", "BELLOSSOM", "POLITOED", "SLOWKING", "STEELIX",
  "SCIZOR", "KINGDRA", "PORYGON2", "BLISSEY",
}

local MOVES = {
  "IRON_TAIL", "METAL_CLAW", "STEEL_WING", "RAIN_DANCE", "SUNNY_DAY",
  "SANDSTORM", "SLUDGE_BOMB", "SHADOW_BALL",
}

local function species(id, dex, generation)
  local row = {
    id = id, name = id, dex = dex,
    types = {}, catchRate = 45, baseExp = 64, growthRate = "MEDIUM_FAST",
    tmhm = {}, evolutions = {},
    spriteFront = "assets/generated/battle/front/" .. id:lower() .. ".png",
    spriteBack = "assets/generated/battle/back/" .. id:lower() .. ".png",
  }
  if generation == 2 then
    row.baseStats = { hp = 45, attack = 49, defense = 49, speed = 45,
      specialAttack = 65, specialDefense = 65 }
    row.levelMoves = {}
    row.picSize = 5
  else
    row.baseStats = { hp = 45, attack = 49, defense = 49, speed = 45,
      special = 65 }
    row.level1Moves = {}
    row.learnset = {}
    row.frontSize = 5
  end
  return row
end

local function defaults(version)
  local generation = GameVersion.generation(version)
  local pokemon = { FIXMON = species("FIXMON", 1, generation) }
  local moves = {}
  local items = {}
  local typeChart = {
    matchups = { { attacker = "NORMAL", defender = "ROCK", multiplier = 5 } },
    types = {},
  }
  local tilesets, text, encounters, audio, landmarks = {}, {}, {}, {}, {}
  local menuGfx = {}
  if generation == 2 then
    pokemon.growthRates = {}
    pokemon.tmhmMoves = {}
    if version == "crystal" then
      pokemon.tutorMoves = { "FLAMETHROWER", "THUNDERBOLT", "ICE_BEAM" }
    end
    moves.generation, moves.source = 2, "fixture moves"
    items.generation, items.source, items.pockets = 2, "fixture items", {}
    items.timeCapsule = { [0x19] = "LEFTOVERS" }
    items.ITEM_C3 = { id = "ITEM_C3", index = 0xC3, price = 39321,
      heldEffect = "HELD_NONE", heldParameter = 0 }
    audio.generation, audio.source = 2, "fixture audio"
    audio.cries = { FIXMON = { header = { bank = 60, address = 29929,
      generation = 2 }, pitch = 65529, length = 320 } }
    encounters.generation, encounters.source = 2, "fixture encounters"
    encounters.timeFishGroups = {
      [0] = { day = { species = "FIXMON", level = 20 },
              nite = { species = "FIXMON", level = 20 } },
    }
    landmarks.generation, landmarks.source = 2, "fixture landmarks"
    landmarks.landmarks = { LANDMARK_SPECIAL = { id = "LANDMARK_SPECIAL",
      name = "SPECIAL", index = 0, x = -8, y = -16 } }
    text.generation = 2
    text.labels = { _FixtureText = "6f:5d96" }
    text["6f:5d96"] = "FIXTURE"
    tilesets.waterFrames = "assets/generated/tilesets/water_frames.png"
    tilesets.flowerFrames = "assets/generated/tilesets/flower_frames.png"
    tilesets.flowerCgbFrames = { 2, 4 }
    tilesets.animFrames = { tower_5d = {
      image = "assets/generated/tilesets/anim/tower_5d.png", frames = 5 } }
    menuGfx.battleHud = { balls = "assets/generated/battle/hud/balls.png" }
    menuGfx.emotes = {
      shock = "assets/generated/emotes/shock.png",
      grassRustle = "assets/generated/emotes/grass_rustle.png",
      fishing = "assets/generated/emotes/fishing.png",
      order = { "shock" },
    }
    if version == "crystal" then
      menuGfx.emotes.fishingFemale = "assets/generated/emotes/fishing_female.png"
    end
    tilesets.TILESET_FIXTURE = { id = "TILESET_FIXTURE",
      image = "assets/generated/tilesets/fixture.png", blocks = {} }
    for index, id in ipairs(CONTINUATIONS) do
      pokemon[id] = species(id, 168 + index, generation)
    end
    for index, id in ipairs(MOVES) do
      moves[id] = { id = id, name = id, index = index, type = "STEEL",
        power = 50, accuracy = 100, pp = 15, effect = "NO_ADDITIONAL_EFFECT" }
    end
    typeChart.types.STEEL = { name = "STEEL", category = "physical", index = 9 }
    typeChart.foresightMatchups = {
      { attacker = "NORMAL", defender = "GHOST", multiplier = 0 },
    }
    items.LEFTOVERS = { id = "LEFTOVERS", name = "LEFTOVERS", price = 0,
      heldEffect = "HELD_LEFTOVERS", heldParameter = 0 }
  end
  return {
    constants = {}, maps = {}, tilesets = tilesets, text = text, rom_text = {},
    text_pointers = {},
    trainer_headers = {}, font = {}, sprites = {}, pokemon = pokemon,
    moves = moves, items = items, type_chart = typeChart, trainers = {},
    encounters = encounters, field = { oakSpeech = {} }, battle_anims = {},
    audio = audio, palettes = {}, icons = {}, landmarks = landmarks,
    menu_gfx = menuGfx,
  }
end

function Fixture.cache(files, version, overrides)
  local prefix = GameVersion.cachePrefix(version)
  local generation = GameVersion.generation(version)
  local values = defaults(version)
  for name, value in pairs(overrides or {}) do values[name] = value end
  files[prefix .. "rom-cache.complete"] =
    CacheContract.markerFor(version)
  for _, name in ipairs(generation == 2 and GEN2_MODULES or GEN1_MODULES) do
    local value = values[name]
    files[prefix .. "data/generated/" .. name .. ".lua"] =
      type(value) == "string" and value or LuaWriter.encode(value or {})
  end
  if generation == 1 then
    for _, name in ipairs(GEN1_OPTIONAL_MODULES) do
      files[prefix .. "data/generated/" .. name .. ".lua"] =
        LuaWriter.encode(values[name] or {})
    end
  end
  for _, path in ipairs(CacheContract.requiredFiles(version)) do
    if files[prefix .. path] == nil then
      files[prefix .. path] = path:match("%.lua$") and LuaWriter.encode({}) or "fixture"
    end
  end
  if type(values.pokemon) == "table" then
    for _, row in pairs(values.pokemon) do
      if type(row) == "table" and row.spriteFront then
        files[prefix .. row.spriteFront] = "front"
        files[prefix .. row.spriteBack] = "back"
      end
    end
  end
  local emotes = type(values.menu_gfx) == "table" and values.menu_gfx.emotes
  if type(emotes) == "table" then
    for key, path in pairs(emotes) do
      if key ~= "order" and type(path) == "string" then
        files[prefix .. path] = "emote"
      end
    end
  end
  return files
end

function Fixture.addMod(files, id, body)
  files["mods/" .. id .. "/manifest.json"] = ([[{
    "id": %q, "name": %q, "version": "1.0.0", "entry": "main.lua",
    "api": 2, "games": ["all"]
  }]]):format(id, id)
  files["mods/" .. id .. "/main.lua"] = body
  return "mods/" .. id
end

Fixture.GEN1_MODULES = GEN1_MODULES
Fixture.GEN2_MODULES = GEN2_MODULES
Fixture.CONTINUATIONS = CONTINUATIONS
Fixture.MOVES = MOVES

return Fixture
