local Base = require("src.core.game3.profiles.rs_rules")

local Rules = setmetatable({}, { __index = Base })

local function union() return require("src.core.game3.rse.union_rs") end

local function healCenterFront(session)
  local heal = type(session.healMap) == "string" and session.healMap or nil
  if not heal then return nil end
  local U = union()
  for id, c in pairs(U.centers) do
    if c.oneF == heal then return U.originFor(id) end
  end
  return nil
end

function Rules.unionReturn(session, game)
  if not union().inRoom(session) then
    return require("src.core.game3.link.union_save_spot").live(session, game)
  end
  return union().saveOrigin(session) or healCenterFront(session)
end

function Rules.saveLocation(session, game)
  local o = Rules.unionReturn(session, game)
  if not o then return nil end
  return o.map, o.x, o.y, o.facing
end

-- pokeruby/src/load_save.c:38
function Rules.saveWarpFields(session)
  local o = Rules.unionReturn(session)
  if o then return 1, { map = o.map, warpId = -1, x = o.x, y = o.y } end
  return Base.saveWarpFields(session)
end

-- pokeruby/src/load_save.c:38
function Rules.useContinueGameWarp(session, mounted)
  local fromRoom = union().inRoom(session)
  local map, x, y, facing = session.map, tonumber(session.x), tonumber(session.y), session.facing
  Base.useContinueGameWarp(session, mounted)
  if session.map == map and tonumber(session.x) == x and tonumber(session.y) == y then session.facing = facing end
  local o = Rules.unionReturn(session)
  if o then
    session.map, session.x, session.y, session.facing = o.map, o.x, o.y, o.facing
  elseif fromRoom then
    session.facing = "up"
  end
end

return Rules
