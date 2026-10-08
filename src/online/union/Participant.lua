local GameVersion = require("src.core.GameVersion")
local Wire = require("src.link.Wire")

local Participant = {}

Participant.NAME_MAX = 10
Participant.SLOT_MAX = 40
Participant.DEFAULT_STYLE = "player"

local function knownVersion(version)
  return type(version) == "string" and GameVersion.VERSIONS[version] ~= nil
end

function Participant.genOf(version)
  if not knownVersion(version) then return nil end
  return GameVersion.generation(version)
end

local function caps(v)
  if type(v) ~= "table" then return nil end
  return Wire.caps(v)
end

local function groupActivity(row)
  local g = type(row.group) == "table" and row.group or nil
  return g and g.activity or nil
end

function Participant.fromMember(row)
  if type(row) ~= "table" then return nil, "not a row" end
  local id = Wire.playerId(row.id)
  if not id then return nil, "no id" end
  local slot = tonumber(row.slot)
  if not slot or slot ~= math.floor(slot) or slot < 1 or slot > Participant.SLOT_MAX then
    return nil, "no slot"
  end
  local av = type(row.avatar) == "table" and row.avatar or nil
  local version = av and av.version or nil
  if not knownVersion(version) then return nil, "no version" end
  local family = GameVersion.generation(version)
  local gen = av.gen
  local legacy = false
  if gen == nil then
    legacy = true
    gen = family
  elseif gen ~= family then
    return nil, "gen mismatch"
  end
  local name = av.name
  if type(name) ~= "string" or name == "" then name = row.name end
  return {
    slot = slot,
    id = id,
    name = type(name) == "string" and Wire.chars(name, "", Participant.NAME_MAX) or "",
    verified = row.verified == true,
    game = version,
    gen = gen,
    trainerId = math.floor(tonumber(av.trainerId) or 0) % 65536,
    gender = av.gender == 1 and 1 or 0,
    style = Wire.avatarStyle(av.style) or Participant.DEFAULT_STYLE,
    status = type(row.status) == "string" and row.status or "idle",
    activity = groupActivity(row),
    group = row.group,
    online = row.online ~= false,
    caps = caps(row.caps),
    board = row.board,
    legacy = legacy,
  }
end

function Participant.badgeDigit(p)
  if type(p) ~= "table" then return nil end
  local gen = tonumber(p.gen)
  if gen == 1 or gen == 2 or gen == 3 then return gen end
  return nil
end

function Participant.busy(p)
  if type(p) ~= "table" then return true end
  if p.online == false then return true end
  return p.status ~= "idle" and p.status ~= "recruiting" and p.status ~= "waiting"
end

function Participant.same(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then return false end
  for _, k in ipairs({ "id", "slot", "name", "game", "gen", "trainerId", "gender", "style",
                       "status", "activity", "online", "legacy", "verified" }) do
    if a[k] ~= b[k] then return false end
  end
  local ca, cb = a.caps, b.caps
  if (ca == nil) ~= (cb == nil) then return false end
  if ca and (ca.proto ~= cb.proto or ca.policy ~= cb.policy) then return false end
  if ca then
    for gen = 1, 3 do
      local la, lb = ca.gens[tostring(gen)], cb.gens[tostring(gen)]
      if (la == nil) ~= (lb == nil) then return false end
      if la then
        if #la ~= #lb then return false end
        for i = 1, #la do
          if la[i].version ~= lb[i].version or la[i].fp ~= lb[i].fp then return false end
        end
      end
    end
  end
  return true
end

function Participant.wireAvatar(fields)
  fields = type(fields) == "table" and fields or {}
  local style = Wire.avatarStyle(fields.style) or Participant.DEFAULT_STYLE
  return {
    name = Wire.chars(tostring(fields.name or ""), "", Participant.NAME_MAX),
    trainerId = math.floor(tonumber(fields.trainerId) or 0) % 65536,
    gender = (fields.gender == 1 or fields.gender == "female") and 1 or 0,
    version = fields.version,
    style = style,
    canLinkNationally = type(fields.canLinkNationally) == "boolean" and fields.canLinkNationally or nil,
  }
end

return Participant
