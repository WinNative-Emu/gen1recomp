local Table = require("src.battle.g3u.Table")

local Wire = {}

Wire.TYPES = { "g3u_table", "g3u_party", "g3u_action", "g3u_replace", "g3u_hash", "g3u_bye" }

Wire.MAX_BYTES = {
  g3u_table = 16384, g3u_party = 4096, g3u_action = 128, g3u_replace = 96, g3u_hash = 96, g3u_bye = 128,
}

Wire.BYE = { forfeit = true, desync = true, illegal = true, timeout = true, quit = true, error = true,
  bad_table = true, bad_party = true }

Wire.MAX_TURN = 4096
Wire.MAX_NICK_CHARS = 10

local function int(v, lo, hi)
  return type(v) == "number" and v == v and v == math.floor(v) and v >= lo and v <= hi
end

local function keys(t, allowed)
  for k in pairs(t) do
    if not allowed[k] then return false end
  end
  return true
end

local function chars(s)
  local n = 0
  for i = 1, #s do
    local b = s:byte(i)
    if b < 0x80 or b >= 0xC0 then n = n + 1 end
  end
  return n
end

function Wire.size(msg)
  return #require("src.link.Json").encode(msg)
end

function Wire.table(t)
  return { type = "g3u_table", table = t }
end

function Wire.party(records)
  return { type = "g3u_party", records = records }
end

function Wire.action(turn, act)
  local m = { type = "g3u_action", turn = turn, kind = act.kind }
  if act.kind == "move" then m.slot = act.slot end
  if act.kind == "switch" then m.index = act.index end
  return m
end

function Wire.replace(turn, index)
  return { type = "g3u_replace", turn = turn, index = index }
end

function Wire.hash(turn, hash)
  return { type = "g3u_hash", turn = turn, hash = hash }
end

function Wire.bye(why)
  return { type = "g3u_bye", why = why }
end

function Wire.toAction(m)
  if m.kind == "move" then return { kind = "move", slot = m.slot } end
  if m.kind == "switch" then return { kind = "switch", index = m.index } end
  return { kind = "forfeit" }
end

local V = {}

function V.g3u_table(m, ctx)
  if not keys(m, { type = true, table = true }) then return nil, "unknown_key" end
  local ok, why = Table.validate(m.table, ctx and ctx.gen)
  if not ok then return nil, "bad_table:" .. tostring(why) end
  return m
end

local REC_KEYS = { species = true, level = true, hp = true, maxHp = true, atk = true, def = true,
  spAtk = true, spDef = true, speed = true, moves = true, nickname = true, gender = true,
  friendship = true, ivs = true }
local IV_KEYS = { hp = true, atk = true, def = true, spe = true, spa = true, spd = true }
local MOVE_KEYS = { id = true, pp = true, ppUps = true }

-- pokefirered/src/pokemon.c:2093
local function statCap(level) return math.floor((2 * 255 + 31 + 63) * level / 100) + 5 end
local function hpCap(level) return math.floor((2 * 255 + 31 + 63) * level / 100) + level + 10 end

function Wire.record(r, t)
  if type(r) ~= "table" or not keys(r, REC_KEYS) then return nil, "record_shape" end
  if not int(r.species, 1, t.dexMax) then return nil, "species" end
  if not int(r.level, 1, 100) then return nil, "level" end
  if not int(r.maxHp, 1, hpCap(r.level)) or not int(r.hp, 1, r.maxHp) then return nil, "hp" end
  for _, k in ipairs({ "atk", "def", "spAtk", "spDef", "speed" }) do
    if not int(r[k], 1, statCap(r.level)) then return nil, "stat_" .. k end
  end
  if type(r.moves) ~= "table" or #r.moves < 1 or #r.moves > 4 then return nil, "moves" end
  local count, seen = 0, {}
  for _ in pairs(r.moves) do count = count + 1 end
  if count ~= #r.moves then return nil, "moves" end
  local illegal = Table.illegalSet(t)
  for _, mv in ipairs(r.moves) do
    if type(mv) ~= "table" or not keys(mv, MOVE_KEYS) then return nil, "move_shape" end
    if not int(mv.id, 1, t.moveMax) or seen[mv.id] then return nil, "move_id" end
    if illegal[mv.id] then return nil, "move_unsupported" end
    seen[mv.id] = true
    local base = t.moves[mv.id][4]
    if not int(mv.ppUps or 0, 0, 3) then return nil, "pp_ups" end
    if not int(mv.pp, 0, math.min(64, base + math.floor(base * 3 / 5))) then return nil, "pp" end
  end
  if r.nickname ~= nil and (type(r.nickname) ~= "string" or #r.nickname > Wire.MAX_NICK_CHARS * 4
      or chars(r.nickname) > Wire.MAX_NICK_CHARS) then
    return nil, "nickname"
  end
  if r.gender ~= nil and not int(r.gender, 0, 2) then return nil, "gender" end
  if r.friendship ~= nil and not int(r.friendship, 0, 255) then return nil, "friendship" end
  if r.ivs ~= nil then
    if type(r.ivs) ~= "table" or not keys(r.ivs, IV_KEYS) then return nil, "ivs" end
    for _, v in pairs(r.ivs) do
      if not int(v, 0, 31) then return nil, "ivs" end
    end
  end
  return r
end

function V.g3u_party(m, ctx)
  if not keys(m, { type = true, records = true }) then return nil, "unknown_key" end
  local t = ctx and ctx.table
  if type(t) ~= "table" then return nil, "no_table" end
  local recs = m.records
  if type(recs) ~= "table" or #recs < 1 or #recs > 6 then return nil, "party_size" end
  local count = 0
  for _ in pairs(recs) do count = count + 1 end
  if count ~= #recs then return nil, "party_size" end
  for i, r in ipairs(recs) do
    local ok, why = Wire.record(r, t)
    if not ok then return nil, "record_" .. i .. ":" .. why end
  end
  return m
end

function V.g3u_action(m)
  if not int(m.turn, 1, Wire.MAX_TURN) then return nil, "turn" end
  if m.kind == "move" then
    if not keys(m, { type = true, turn = true, kind = true, slot = true }) then return nil, "unknown_key" end
    if not int(m.slot, 0, 4) then return nil, "slot" end
  elseif m.kind == "switch" then
    if not keys(m, { type = true, turn = true, kind = true, index = true }) then return nil, "unknown_key" end
    if not int(m.index, 1, 6) then return nil, "index" end
  elseif m.kind == "forfeit" then
    if not keys(m, { type = true, turn = true, kind = true }) then return nil, "unknown_key" end
  else
    return nil, "kind"
  end
  return m
end

function V.g3u_replace(m)
  if not keys(m, { type = true, turn = true, index = true }) then return nil, "unknown_key" end
  if not int(m.turn, 0, Wire.MAX_TURN) then return nil, "turn" end
  if not int(m.index, 1, 6) then return nil, "index" end
  return m
end

function V.g3u_hash(m)
  if not keys(m, { type = true, turn = true, hash = true }) then return nil, "unknown_key" end
  if not int(m.turn, 0, Wire.MAX_TURN) then return nil, "turn" end
  if type(m.hash) ~= "string" or not m.hash:match("^%x%x%x%x%x%x%x%x$") then return nil, "hash" end
  return m
end

function V.g3u_bye(m)
  if not keys(m, { type = true, why = true }) then return nil, "unknown_key" end
  if type(m.why) ~= "string" or not Wire.BYE[m.why] then return nil, "why" end
  return m
end

Wire.VALIDATORS = V

function Wire.validate(m, ctx)
  if type(m) ~= "table" or type(m.type) ~= "string" then return nil, "not_a_message" end
  local fn = V[m.type]
  if not fn then return nil, "unknown_type" end
  if ctx and ctx.bytes and ctx.bytes > Wire.MAX_BYTES[m.type] then return nil, "too_big" end
  return fn(m, ctx)
end

return Wire
