local Progression = {}

local NATIVE_TYPES = {
  [0] = "NORMAL", "FIGHTING", "FLYING", "POISON", "GROUND", "ROCK", "BUG",
  "GHOST", "STEEL", "CURSE_TYPE", "FIRE", "WATER", "GRASS", "ELECTRIC",
  "PSYCHIC_TYPE", "ICE", "DRAGON", "DARK",
}
local NATIVE_TYPE_NUMS = {}
for num, id in pairs(NATIVE_TYPES) do NATIVE_TYPE_NUMS[id] = num end
local TYPE_ALIASES = { PSYCHIC = "PSYCHIC_TYPE", MYSTERY = "CURSE_TYPE" }
local FIRST_CUSTOM_TYPE, LAST_CUSTOM_TYPE = 18, 255
local FIRST_CUSTOM_GROWTH = 6
local FORESIGHT_IGNORED = { ["NORMAL>GHOST"] = true, ["FIGHTING>GHOST"] = true }

local NATIVE_GROWTH = {
  [0] = "MEDIUM_FAST", "ERRATIC", "FLUCTUATING", "MEDIUM_SLOW", "FAST", "SLOW",
}
local NATIVE_GROWTH_NUMS = {}
for num, id in pairs(NATIVE_GROWTH) do NATIVE_GROWTH_NUMS[id] = num end

local EVO_NAMES = {
  "EVO_FRIENDSHIP", "EVO_FRIENDSHIP_DAY", "EVO_FRIENDSHIP_NIGHT",
  "EVO_LEVEL", "EVO_TRADE", "EVO_TRADE_ITEM", "EVO_ITEM",
  "EVO_LEVEL_ATK_GT_DEF", "EVO_LEVEL_ATK_EQ_DEF", "EVO_LEVEL_ATK_LT_DEF",
  "EVO_LEVEL_SILCOON", "EVO_LEVEL_CASCOON", "EVO_LEVEL_NINJASK",
  "EVO_LEVEL_SHEDINJA", "EVO_BEAUTY",
}
local EVO_NUMS = {}
for num, id in ipairs(EVO_NAMES) do EVO_NUMS[id] = num end

local seeded = { growth = {}, evolution = {} }
local state

local function fresh()
  return {
    growthFn = {}, growthIndex = {}, growthId = {},
    typeIndex = {}, typeId = {}, typeName = {}, typePhysical = {},
    evolution = { custom = {}, overridden = {}, any = false },
  }
end
state = fresh()

local function warn(fmt, ...)
  local ok, Logger = pcall(require, "src.core.Logger")
  if ok and Logger and Logger.warn then Logger.warn(fmt, ...) end
end

function Progression.canonicalType(id)
  return TYPE_ALIASES[id] or id
end

function Progression.growthKey(value)
  local n = math.floor(tonumber(value) or 0)
  if state.growthFn[n] then return n end
  return n % FIRST_CUSTOM_GROWTH
end

function Progression.growthCurve(key)
  return state.growthFn[key]
end

function Progression.growthIndexFor(id)
  if type(id) ~= "string" then return nil end
  return NATIVE_GROWTH_NUMS[id] or state.growthIndex[id]
end

function Progression.growthIdFor(num)
  return state.growthId[tonumber(num) or -1]
end

function Progression.typeIndexFor(id)
  if type(id) ~= "string" then return nil end
  id = TYPE_ALIASES[id] or id
  return NATIVE_TYPE_NUMS[id] or state.typeIndex[id]
end

function Progression.typeIdFor(num)
  return state.typeId[tonumber(num) or -1]
end

function Progression.typeNameFor(num)
  return state.typeName[tonumber(num) or -1]
end

function Progression.seedGrowth(registry, _, owner)
  local SummaryData = require("src.core.game3.summary_data")
  for index = 0, 5 do
    local fn = function(level) return SummaryData.nativeExpForLevel(index, level) end
    seeded.growth[index] = fn
    registry:register(NATIVE_GROWTH[index], { expForLevel = fn }, owner)
  end
end

function Progression.seedTypes(registry, _, owner)
  local Types = require("src.core.game3.battle.types")
  for index = 0, 17 do
    registry:register(NATIVE_TYPES[index], {
      index = index,
      category = Types.NATIVE_PHYSICAL[index] and "physical" or "special",
    }, owner)
  end
  local list = Types.NATIVE_TABLE
  local i = 1
  while i <= #list do
    local a, d, m = list[i], list[i + 1], list[i + 2]
    if a ~= -1 then
      registry:register(NATIVE_TYPES[a] .. ">" .. NATIVE_TYPES[d], { multiplier = m }, owner)
    end
    i = i + 3
  end
end

function Progression.seedEvolution(registry, _, owner)
  local Evolution = require("src.core.game3.evolution")
  for num, id in ipairs(EVO_NAMES) do
    local check = Evolution.nativeCheck(num)
    seeded.evolution[num] = check
    registry:register(id, { check = check }, owner)
  end
end

local function prepareGrowth(registry)
  if not registry then return end
  local custom = {}
  for _, id in ipairs(registry.order) do
    local record = registry:get(id)
    if type(record) == "table" and type(record.expForLevel) == "function" then
      local num = NATIVE_GROWTH_NUMS[id]
      if num then
        if record.expForLevel ~= seeded.growth[num] then
          state.growthFn[num] = record.expForLevel
        end
      else
        custom[#custom + 1] = id
      end
    end
  end
  table.sort(custom)
  for offset, id in ipairs(custom) do
    local index = FIRST_CUSTOM_GROWTH + offset - 1
    state.growthIndex[id], state.growthId[index] = index, id
    state.growthFn[index] = registry:get(id).expForLevel
  end
end

local function prepareTypes(registry)
  local Types = require("src.core.game3.battle.types")
  if not registry then Types.clearOverlay(); return end
  local pending = {}
  local changed = false
  for _, id in ipairs(registry.order) do
    if not id:find(">", 1, true) then
      local record = registry:get(id)
      if type(record) == "table" then
        local native = NATIVE_TYPE_NUMS[id]
        if native then
          state.typeIndex[id] = native
          if record.name ~= nil then state.typeName[native] = record.name; changed = true end
          local physical = record.category == "physical"
          if physical ~= (Types.NATIVE_PHYSICAL[native] == true) then changed = true end
          state.typePhysical[native] = physical
        else
          pending[#pending + 1] = { id = id, record = record }
        end
      end
    end
  end
  local taken = {}
  for _, entry in ipairs(pending) do
    local index = entry.record.index
    if index ~= nil then
      if type(index) ~= "number" or index < FIRST_CUSTOM_TYPE or index > LAST_CUSTOM_TYPE
          or index % 1 ~= 0 or taken[index] then
        warn("[gen3] type %s has no usable index (18..255, unique); dropped", entry.id)
        entry.drop = true
      else
        taken[index] = true
        entry.index = index
      end
    end
  end
  table.sort(pending, function(a, b) return a.id < b.id end)
  local nextFree = FIRST_CUSTOM_TYPE
  for _, entry in ipairs(pending) do
    if not entry.drop and not entry.index then
      while taken[nextFree] do nextFree = nextFree + 1 end
      entry.index = nextFree
      taken[nextFree] = true
    end
    if not entry.drop and entry.index <= LAST_CUSTOM_TYPE then
      state.typeIndex[entry.id], state.typeId[entry.index] = entry.index, entry.id
      state.typeName[entry.index] = entry.record.name
      state.typePhysical[entry.index] = entry.record.category == "physical"
      changed = true
    end
  end
  local plain, flagged = {}, {}
  for _, id in ipairs(registry.order) do
    local attacker, defender = id:match("^([^>]+)>([^>]+)$")
    local record = attacker and registry:get(id)
    if type(record) == "table" and type(record.multiplier) == "number" then
      local a, d = state.typeIndex[Progression.canonicalType(attacker)],
        state.typeIndex[Progression.canonicalType(defender)]
      if a and d then
        local list = FORESIGHT_IGNORED[id] and flagged or plain
        list[#list + 1] = { a, d, record.multiplier }
      else
        warn("[gen3] type matchup %s names an unknown type; dropped", id)
      end
    end
  end
  local flat = {}
  for _, row in ipairs(plain) do flat[#flat + 1] = row[1]; flat[#flat + 1] = row[2]; flat[#flat + 1] = row[3] end
  flat[#flat + 1] = -1; flat[#flat + 1] = -1; flat[#flat + 1] = 0
  for _, row in ipairs(flagged) do flat[#flat + 1] = row[1]; flat[#flat + 1] = row[2]; flat[#flat + 1] = row[3] end
  local native = Types.NATIVE_TABLE
  if #flat ~= #native then changed = true
  else
    for i = 1, #flat do if flat[i] ~= native[i] then changed = true; break end end
  end
  if not changed then Types.clearOverlay(); return end
  local physical = {}
  for index, value in pairs(state.typePhysical) do if value then physical[index] = true end end
  Types.useOverlay({ table = flat, physical = physical, names = state.typeName })
end

local function prepareEvolution(registry)
  if not registry then return end
  local info = state.evolution
  for _, id in ipairs(registry.order) do
    local record = registry:get(id)
    if type(record) == "table" and type(record.check) == "function" then
      local num = EVO_NUMS[id]
      if num then
        if record.check ~= seeded.evolution[num] then
          info.overridden[num], info.any = record, true
        end
      else
        info.custom[id], info.any = record, true
      end
    end
  end
end

function Progression.prepare(content)
  state = fresh()
  if type(content) ~= "table" then return end
  prepareGrowth(content.growth_rates)
  prepareTypes(content.type_chart)
  prepareEvolution(content.evolution_methods)
end

function Progression.reset()
  state = fresh()
  local ok, Types = pcall(require, "src.core.game3.battle.types")
  if ok then Types.clearOverlay() end
end

function Progression.evolutionRecord(method)
  local info = state.evolution
  if not info.any or method == nil then return nil end
  if type(method) == "string" and not tonumber(method) then return info.custom[method] end
  return info.overridden[tonumber(method)]
end

Progression.NATIVE_TYPES = NATIVE_TYPES
Progression.NATIVE_GROWTH = NATIVE_GROWTH

return Progression
