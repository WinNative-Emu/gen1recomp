local Catalog = require("src.box.Catalog")
local Store = require("src.box.Store")
local Rng = require("src.core.game3.rng")
local GameVersion = require("src.core.GameVersion")
local Gifts = {}
Gifts.AWARDS = {
  { name = "Swablu", national = 333, threshold = 0, moves = { 64, 45, 206 } },
  { name = "Zigzagoon", national = 263, threshold = 100, moves = { 33, 45, 39, 245 } },
  { name = "Skitty", national = 300, threshold = 500, moves = { 45, 33, 39, 6 } },
  { name = "Pichu", national = 172, threshold = 1499, moves = { 84, 204, 57 } },
}
local MET_GAME = { sapphire = 1, ruby = 2, emerald = 3, firered = 4, leafgreen = 5 }

function Gifts.trainerId(save)
  local tid = tonumber(save.trainerId or save.player and save.player.trainerId)
  local sid = tonumber(save.secretId or save.player and save.player.secretId)
  if tid == nil or sid == nil then return nil end
  return tid % 65536 + (sid % 65536) * 65536
end

function Gifts.identity(source, save)
  return table.concat({ source.version, source.path, tostring(Gifts.trainerId(save)),
    tostring(save.meta and save.meta.playthroughId or save.name or save.playerName or "") }, "|")
end

function Gifts.flags(save)
  return require("src.core.game3.save_mon").boxFlags(save) or 0
end

function Gifts.setFlags(save, value)
  require("src.core.game3.save_mon").setBoxFlags(save, value)
end

function Gifts.progress(state, source, save)
  if GameVersion.generation(source.version) ~= 3 then return nil, "Original Box gift eggs require a Gen 3 save." end
  local tid = Gifts.trainerId(save)
  if not tid then return nil, "This save needs a recorded trainer ID and secret ID for Box gifts." end
  local count = 0
  for _, box in ipairs(state.boxes) do
    for _, entry in pairs(box.mons) do
      if entry.generation == 3 and entry.depositorId == tid then count = count + 1 end
    end
  end
  local key = Gifts.identity(source, save)
  local peak = math.max(count, state.progress and state.progress[key] or 0)
  local flags = Gifts.flags(save)
  local nextAward = flags % 2 == 0 and 1 or math.floor(flags / 2) % 4 + 2
  local award = Gifts.AWARDS[nextAward]
  return { current = count, peak = peak, flags = flags, key = key,
    nextAward = nextAward, award = award, eligible = award ~= nil and peak >= award.threshold }
end

function Gifts.recordProgress(state, source, save)
  local progress = Gifts.progress(state, source, save)
  if progress then state.progress = state.progress or {}; state.progress[progress.key] = progress.peak end
end

function Gifts.create(version, index, seed)
  local award, data = Gifts.AWARDS[index], Catalog.get(version)
  if not award or not data.ready then return nil, "Import this game's complete species and move data first." end
  local species = (data.national.toSpecies or {})[award.national]
  local meta = species and data.meta[species]
  if not meta or meta.eggCycles == nil or meta.growthRate == nil then return nil, "The gift species data is incomplete." end
  if seed == nil then seed = math.floor((love and love.timer and love.timer.getTime() or os.clock()) * 1000000) end
  seed = math.floor(seed) % 4294967296
  local function random()
    seed = (Rng.mulU32(seed, 0x41C64E6D) + 0x6073) % 4294967296
    return math.floor(seed / 65536)
  end
  local high, low = random(), random()
  local first, second = random(), random()
  local ivs = { hp = first % 32, atk = math.floor(first / 32) % 32,
    def = math.floor(first / 1024) % 32, spe = second % 32,
    spa = math.floor(second / 32) % 32, spd = math.floor(second / 1024) % 32 }
  local mon = { species = species, speciesId = species, speciesNumbering = "internal",
    personality = high * 65536 + low, ivs = ivs, evs = {}, contest = {},
    exp = require("src.core.game3.summary_data").expForLevel(meta.growthRate, 5), level = 5,
    nickname = "EGG", otName = "AZUSA", ot = "AZUSA", otId = 0, otSecretId = 0,
    language = 1, otGender = 1, isEgg = true, friendship = meta.eggCycles,
    eggCycles = meta.eggCycles, pokeball = 4, metLocation = 255, metLevel = 0,
    metGame = MET_GAME[version], moves = Store.copy(award.moves), pp = {},
    ribbons = 0, markings = 0, pokerus = 0, heldItem = 0, ppBonusesPacked = 0,
    cartExtra = { nicknameBytes = { 0x60, 0x6F, 0x8B, 0xFF }, nicknameLanguage = 1 } }
  local pair = data.abilities[species] or {}
  mon.abilityNum = pair[2] and pair[2] ~= 0 and mon.personality % 2 or 0
  for i, move in ipairs(mon.moves) do
    local battle = data.battleMoves[move]
    if not battle or battle.pp == nil then return nil, "The gift move data is incomplete." end
    mon.pp[i] = battle.pp
  end
  return mon, seed
end

return Gifts
