local Policy = {}

Policy.VERSION = 1
Policy.RENTALS = 1
Policy.PROTO = 1

Policy.RULESETS = {
  ["g3u-gen1"] = { id = "g3u-gen1", engine = "g3u", gen = 1, dexMax = 151, moveMax = 165 },
  ["g3u-gen2"] = { id = "g3u-gen2", engine = "g3u", gen = 2, dexMax = 251, moveMax = 251 },
  ["g3u-gen3"] = { id = "g3u-gen3", engine = "g3u", gen = 3, dexMax = 386, moveMax = 354 },
}

function Policy.ruleset(id)
  return Policy.RULESETS[id]
end

function Policy.rulesetForGen(gen)
  return Policy.RULESETS["g3u-gen" .. tostring(gen)]
end

Policy.GEN_LIMITS = {
  [1] = { dexMax = 151, moveMax = 165 },
  [2] = { dexMax = 251, moveMax = 251 },
  [3] = { dexMax = 386, moveMax = 354 },
}

Policy.STAT_ORDER = { "hp", "atk", "def", "spe", "spa", "spd" }
Policy.GB_STAT = { hp = "hp", atk = "attack", def = "defense", spe = "speed", spa = "special", spd = "special" }
Policy.GB_STAT_ORDER = { "hp", "attack", "defense", "speed", "special" }
Policy.EV_TOTAL = 510
Policy.EV_MAX = 255
Policy.STAT_EXP_MAX = 65535
Policy.NATURE_NEUTRAL = 0
Policy.ABILITY_SLOT = 0
Policy.LEVEL = { min = 1, max = 100 }
Policy.RENTAL_LEVEL = 50
Policy.MAX_MOVES = 4

-- constants/pokemon_data_constants.asm:231
Policy.GEN2_BASE_HAPPINESS = 70
-- include/constants/region_map_sections.h:228
Policy.METLOC_IN_GAME_TRADE = 0xFE
-- include/constants/items.h:13
Policy.ITEM_POKE_BALL = 4
-- include/constants/global.h:8
Policy.GBA_VERSION_ID = { sapphire = 1, ruby = 2, emerald = 3, firered = 4, leafgreen = 5 }
Policy.GBA_LANGUAGE_ENGLISH = 2

Policy.NAME_LIMIT = { nickname = 10, ot = 7 }

Policy.POWER_BANDS = { 0, 40, 70, 100 }

function Policy.powerBand(power)
  power = tonumber(power) or 0
  if power <= 0 then return 0 end
  for i = 2, #Policy.POWER_BANDS do
    if power <= Policy.POWER_BANDS[i] then return i - 1 end
  end
  return #Policy.POWER_BANDS
end

function Policy.maxPp(base, ups)
  base = tonumber(base) or 0
  return base + (tonumber(ups) or 0) * math.floor(base / 5)
end

function Policy.ivFromDv(dv)
  return (tonumber(dv) or 0) * 2 + 1
end

function Policy.dvFromIv(iv)
  return math.floor((tonumber(iv) or 0) / 2)
end

function Policy.evFromStatExp(statExp)
  return math.min(Policy.EV_MAX, math.floor(math.sqrt(math.max(0, tonumber(statExp) or 0))))
end

function Policy.statExpFromEv(ev)
  local v = math.max(0, tonumber(ev) or 0)
  return math.min(Policy.STAT_EXP_MAX, v * v)
end

Policy.BATTLE = {
  { field = "species", rule = "national dex kept; must be <= ruleset dexMax" },
  { field = "level", rule = "kept" },
  { field = "ivs", rule = "Gen 3 IVs kept; Gen 1/2 DV d -> IV 2d+1 (HP from the derived HP DV); Special DV -> SpA and SpD" },
  { field = "evs", rule = "Gen 3 EVs kept; Gen 1/2 Stat Exp s -> EV min(255, floor(sqrt(s))); Special -> SpA and SpD; 510 total cap applied in HP, Atk, Def, Spe, SpA, SpD order" },
  { field = "baseStats", rule = "owner's own game base stats; Gen 1 base Special used for both SpA and SpD" },
  { field = "stats", rule = "Gen 3 formula from projected IV/EV, owner's base stats and nature" },
  { field = "nature", rule = "neutral (Hardy) when a Gen 1/2 player is present, else the Gen 3 nature" },
  { field = "ability", rule = "off when a Gen 1/2 player is present, else the Gen 3 ability" },
  { field = "item", rule = "off when a Gen 1/2 player is present" },
  { field = "types", rule = "owner's own game types, canonical names" },
  { field = "moves", rule = "canonical id <= ruleset moveMax and learnable per the owner's game data; illegal moves are replaced by the player or left empty; order kept" },
  { field = "pp", rule = "owner's base PP with the same PP Up count; current PP full" },
  { field = "gender", rule = "Gen 2 DV rule, Gen 3 personality rule, none for Gen 1" },
  { field = "shiny", rule = "Gen 1/2 DV rule, Gen 3 personality rule" },
  { field = "hp", rule = "full" },
  { field = "status", rule = "clear" },
}

Policy.TRADE = {
  { field = "species", rule = "national dex kept; must exist in the destination game" },
  { field = "level", rule = "kept" },
  { field = "exp", rule = "kept, clamped to the destination growth curve range of the kept level" },
  { field = "dvs", rule = "Gen 3 -> Gen 1/2: nearest DVs to floor(IV/2) that keep shininess, Gen 2 gender and Unown letter; Special from SpA; HP DV derived" },
  { field = "ivs", rule = "Gen 1/2 -> Gen 3: IV = 2*DV+1, HP from the HP DV, SpA and SpD from Special" },
  { field = "statExp", rule = "Gen 3 EV e -> Stat Exp min(65535, e*e); Special from SpA" },
  { field = "evs", rule = "Gen 1/2 Stat Exp s -> EV min(255, floor(sqrt(s))); Special -> SpA and SpD; 510 cap in slot order" },
  { field = "personality", rule = "Gen 1/2 -> Gen 3: deterministic search from the record digest for a Hardy, even personality that keeps gender, shininess and Unown letter with Secret ID 0" },
  { field = "nature", rule = "from personality" },
  { field = "ability", rule = "Gen 1/2 -> Gen 3: slot 0; Gen 3 -> Gen 3: kept; Gen 3 -> Gen 1/2: lost" },
  { field = "moves", rule = "canonical id must exist in the destination; kept when learnable in the destination game OR learnable in the source game; replacements limited to moves the species learns in the destination game" },
  { field = "pp", rule = "destination base PP with the same PP Up count, full" },
  { field = "nickname", rule = "kept when the destination charset can encode it, else refused; a nickname equal to the species name becomes the destination default" },
  { field = "ot", rule = "OT name and ID kept when encodable, else refused" },
  { field = "item", rule = "kept by canonical name when it exists in the destination, else refused until removed; mail refused; Gen 2 -> Gen 1 stored as catch rate; Gen 1 -> Gen 2 from catch rate" },
  { field = "friendship", rule = "kept; Gen 1 -> Gen 2 is 70; Gen 1 -> Gen 3 is the species base; Gen 1 target loses it" },
  { field = "pokerus", rule = "kept Gen 2 <-> Gen 3; Gen 1 target loses it" },
  { field = "origin", rule = "Gen 3 target: met in a trade, met level = level, Poke Ball, destination game id; Gen 2 target from another gen: caught data cleared; Gen 3 -> Gen 3 kept" },
  { field = "ribbons", rule = "kept Gen 3 -> Gen 3, else lost" },
  { field = "contest", rule = "kept Gen 3 -> Gen 3, else lost" },
  { field = "egg", rule = "refused" },
  { field = "mail", rule = "refused" },
  { field = "hp", rule = "full" },
  { field = "status", rule = "clear" },
  { field = "evolution", rule = "not run here; the destination game applies its own trade evolution after receipt" },
}

return Policy
