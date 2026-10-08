local Flow = {}

Flow.seams = { client = nil, launch = nil }

local function client()
  return Flow.seams.client or require("src.online.Client")
end

function Flow.install(Activity)
  require("src.ui.union.prep.Open").register(Activity)
  require("src.ui.union.prep.OpenTrade").register(Activity)
  return Activity
end

function Flow.gens(list)
  if type(list) ~= "table" then return nil end
  local a, b = tonumber(list[1]), tonumber(list[2])
  if not (a and b) then return nil end
  return { [0] = a, [1] = b }
end

function Flow.myName(game, gen)
  if gen == 3 then
    local s = game and game.session
    if not s then
      local ok, Runtime = pcall(require, "src.core.game3.runtime")
      s = ok and Runtime.getSession and Runtime.getSession() or nil
    end
    return s and s.name or nil
  end
  local player = game and game.save and game.save.player
  return player and player.name or nil
end

function Flow.session(act, gen)
  local bp = act.battlePrep
  if type(bp) ~= "table" then return nil, "no_prep" end
  local C = client()
  local room = C.room and C.room() or nil
  if type(room) ~= "table" or (act.roomId ~= nil and room.room ~= act.roomId) then return nil, "no_room" end
  local seat = tonumber(C.seat and C.seat())
  if seat ~= 0 and seat ~= 1 then return nil, "no_seat" end
  local net = C.roomSession and C.roomSession() or nil
  if not net then return nil, "no_session" end
  local rules = bp.ruleset or {}
  local go = (act.prep and act.prep.go) or bp.go or {}
  go = {
    rev = go.rev or bp.rev, seed = go.seed or bp.seed, match = go.match or bp.match,
    ruleset = go.ruleset or rules.id, size = go.size or bp.size, gen = go.gen or rules.gen,
    dexMax = go.dexMax or rules.dexMax, moveMax = go.moveMax or rules.moveMax, moveGen = go.moveGen or rules.moveGen,
  }
  local gens = Flow.gens(room.xg and room.xg.gens) or Flow.gens(rules.gens)
  if not gens then
    gens = { [0] = gen, [1] = gen }
  end
  local peer = act.peer or {}
  local names = { [seat] = Flow.myName(act.game, gen), [1 - seat] = peer.name }
  return {
    ruleset = go.ruleset, net = net, seat = seat, go = go, gens = gens, names = names,
    records = bp.records, team = bp.team, client = C, roomId = room.room,
  }
end

function Flow.launch(act, gen)
  if act.launched then return true end
  local session, why = Flow.session(act, gen)
  local handle
  if session then
    local Launch = Flow.seams.launch or require("src.ui.g3u.Launch")
    handle, why = Launch.start(act.game, gen, session, act)
  end
  if not handle then
    print("[union] battle launch failed: " .. tostring(why))
    return false, why
  end
  act.launched = true
  act.battle = handle
  return true
end

function Flow.leaveRoom(act)
  local prep = act and act.prep
  if prep and prep.leave then prep:leave() end
end

return Flow
