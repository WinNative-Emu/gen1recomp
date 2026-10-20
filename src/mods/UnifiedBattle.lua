local UnifiedBattle = {}

local MODULES = {
  "src.battle.BattleAPI", "src.battle.gen2.BattleAPI", "src.battle.game3.BattleAPI",
}
local TYPES = { [0] = "NORMAL", "FIGHTING", "FLYING", "POISON", "GROUND",
  "ROCK", "BUG", "GHOST", "STEEL", "MYSTERY", "FIRE", "WATER", "GRASS",
  "ELECTRIC", "PSYCHIC", "ICE", "DRAGON", "DARK" }


local function copy(value, seen)
  if type(value) ~= "table" then
    local kind = type(value)
    if kind == "string" or kind == "number" or kind == "boolean" then return value end
    return nil
  end
  seen = seen or {}
  if seen[value] then return seen[value] end
  local out = {}
  seen[value] = out
  for key, item in pairs(value) do
    if type(key) == "string" or type(key) == "number" then out[key] = copy(item, seen) end
  end
  return out
end

local function integer(value, low, high)
  return type(value) == "number" and value == value and value % 1 == 0
    and value >= low and value <= high
end

local function activeState(game, generation)
  if generation == 3 then
    local B = package.loaded["src.core.game3.battle.init"]
      or package.loaded["src.core.game3.battle"]
    return B and B.isActive and B.isActive() and B.getState and B.getState() or nil
  end
  local states = game and game.stack and game.stack.states or {}
  for i = #states, 1, -1 do
    local state = states[i]
    if (generation == 1 and state.isBattleState)
      or (generation == 2 and (state.isGen2BattleState or state.screenId == "Gen2BattleState")) then
      return generation == 2 and state.battle or state
    end
  end
end

local function battler(state, generation, id)
  if not state then return nil end
  local b = id == 0 and state.player or id == 1 and state.enemy
    or state.battlers and state.battlers[id]
  return b, generation == 2 and b or b and b.mon
end

local FIELDS = {
  menu = { choice = true }, move = { slot = true }, target = { target = true },
  back = {}, safari = { action = true }, mimic = { index = true },
}
local MENU = { fight = true, party = true, item = true, run = true }

local function intentCopy(intent)
  if type(intent) ~= "table" or getmetatable(intent) ~= nil then
    return nil, "intent must be a plain table"
  end
  if not integer(intent.id, 1, 9007199254740991) then
    return nil, "intent id must be a positive integer"
  end
  if not integer(intent.revision, 1, 9007199254740991) then
    return nil, "invalid battle revision"
  end
  local fields = type(intent.kind) == "string" and FIELDS[intent.kind]
  if not fields then return nil, "unknown battle intent" end
  for key in pairs(intent) do
    if key ~= "id" and key ~= "revision" and key ~= "kind" and not fields[key] then
      return nil, "unknown battle intent field"
    end
  end
  local kind = intent.kind
  if kind == "menu" and (type(intent.choice) ~= "string" or not MENU[intent.choice]) then
    return nil, "unknown battle menu choice"
  elseif kind == "move" and not integer(intent.slot, 1, 4) then
    return nil, "invalid move slot"
  elseif kind == "target" and not integer(intent.target, 0, 3) then
    return nil, "target must be a battler id 0-3"
  elseif kind == "mimic" and not integer(intent.index, 1, 4) then
    return nil, "invalid mimic index"
  elseif kind == "safari" and type(intent.action) ~= "string" then
    return nil, "invalid safari action"
  end
  return copy(intent)
end

function UnifiedBattle.new(gameProvider, generation, version, engineRequire)
  local req = engineRequire or require
  local facade = {}
  local owners = {}

  local function resolve()
    local game = gameProvider()
    if not game then return nil, nil, "no battle" end
    if not MODULES[generation] then return nil, nil, "unsupported generation" end
    local owner = owners[generation]
    if not owner then
      owner = { adapters = setmetatable({}, { __mode = "k" }) }
      owners[generation] = owner
    end
    local api = owner.adapters[game]
    if not api then
      api = req(MODULES[generation]).new(game)
      owner.adapters[game] = api
    end
    if owner.current and owner.current ~= api then
      api.revision = math.max(api.revision or 0, owner.current.revision or 0) + 1
      api.lastIntentId = math.max(api.lastIntentId or 0, owner.current.lastIntentId or 0)
      api.signature = nil
    end
    owner.current = api
    return game, api
  end

  local function dataOf(game)
    local data = {}
    for key, value in pairs(game.data or {}) do data[key] = value end
    if generation == 3 then
      data.gen3Pokemon = data.gen3Pokemon or package.loaded["src.core.game3.pokemon"]
      data.gen3Moves = data.gen3Moves or package.loaded["src.core.game3.battle.moves"]
      data.gen3Items = data.gen3Items or package.loaded["src.core.game3.items_data"]
    end
    return data
  end

  function facade:snapshot()
    local game, api, err = resolve()
    if not api then return nil, err end
    local native, reason = api:snapshot()
    if not native then return nil, reason or "no battle" end
    local Records = req("src.mods.UnifiedRecords")
    local data, state = dataOf(game), activeState(game, generation)
    local out = copy(native)
    out.double = generation == 3 and native.double == true or false
    out.active = out.double and native.active or 0
    out.catchable = native.catchable == true
    out.targets = copy(native.targets) or {}

    local function monView(raw, summary)
      local mon = Records.mon(raw or summary, generation, data, version)
      if mon then mon.active = summary and summary.active == true or false end
      return mon
    end

    local _, player = battler(state, generation, out.active)
    local _, enemy = battler(state, generation, 1)
    out.player, out.enemy = monView(player, native.player), monView(enemy, native.enemy)
    out.battlers = {}
    local summaries = {}
    for _, row in ipairs(native.battlers or {}) do summaries[row.id] = row end
    for id = 0, (out.double and 3 or 1) do
      local b, raw = battler(state, generation, id)
      local summary = summaries[id] or (id == 0 and native.player or id == 1 and native.enemy)
      local row = monView(raw, summary)
      if row then
        row.id, row.side = id, id % 2 == 0 and "player" or "enemy"
        row.absent = (state and state.absent and state.absent[id] == true)
          or (summary and summary.absent == true) or false
        row.active = not row.absent
        row.partyIndex = (b and b.partyIndex) or (summary and summary.partyIndex)
        out.battlers[#out.battlers + 1] = row
      end
    end

    local party = generation == 3 and state and state.playerParty
      or game.save and game.save.party or state and state.party or {}
    out.party = {}
    for i, summary in ipairs(native.party or {}) do
      out.party[i] = monView(party[i], summary)
      out.party[i].slot = i
    end

    out.moves = {}
    for i, move in ipairs(native.moves or {}) do
      local row = copy(move)
      local view = Records.mon({ moves = { { id = move.id, pp = move.pp,
        maxPp = move.maxPp } } }, generation, data, version)
      row.id = view.moves[1] and view.moves[1].id or tostring(move.id)
      row.pp = move.pp or 0
      row.maxPp = move.maxPp or (view.moves[1] and view.moves[1].maxPp) or row.pp
      row.disabled = move.disabled == true
      if generation == 3 and type(row.type) == "number" then row.type = TYPES[row.type] end
      out.moves[i] = row
    end

    out.items = {}
    for i, item in ipairs(native.items or {}) do
      local row = copy(item)
      row.id = Records.mon({ item = item.id }, generation, data, version).item
      row.ball, row.needsTarget = item.ball == true, item.needsTarget == true
      row.catchable = row.ball and out.catchable
      row.catchChance = nil
      if row.catchable then
        if generation == 3 and state then
          local Catching = req("src.core.game3.battle.catching")
          local Runtime = package.loaded["src.core.game3.runtime"]
          local session = game.session or (Runtime and Runtime.getSession and Runtime.getSession())
          local target = Catching.targetFor(state, out.active)
          if target then
            local odds = Catching.catchOdds(item.id, target, state, session)
            if type(odds) == "number" and odds == odds then
              if odds >= 255 then row.catchChance = 100
              elseif odds > 0 then
                local threshold = math.floor(1048560 / math.sqrt(math.sqrt(16711680 / odds)))
                row.catchChance = (math.min(65536, threshold) / 65536) ^ 4 * 100
              else row.catchChance = 0 end
            end
          end
        elseif type(item.catchChance) == "number" and item.catchChance == item.catchChance then
          row.catchChance = math.max(0, math.min(100, item.catchChance))
        end
      end
      out.items[i] = row
    end
    if out.mimicMoves then
      for _, move in ipairs(out.mimicMoves) do
        local view = Records.mon({ moves = { { id = move.id } } }, generation, data, version)
        move.id = view.moves[1] and view.moves[1].id or tostring(move.id)
      end
    end
    return copy(out)
  end

  function facade:submit(intent)
    local game, api, err = resolve()
    if not api then return nil, err end
    local normalized, reason = intentCopy(intent)
    if not normalized then return nil, reason end
    return api:submit(normalized)
  end

  return facade
end

return UnifiedBattle
