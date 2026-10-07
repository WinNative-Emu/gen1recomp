local Link = require("src.core.game3.link.init")
local Strings = require("src.core.Strings")

local CableEntry = {}

-- pokeemerald/include/link.h:86
CableEntry.WIRE = {
  [0x1133] = "trade",
  [0x2233] = "battle_single",
  [0x2244] = "battle_double",
  [0x2255] = "battle_multi",
  [0x2266] = "battle_tower",
  [0x2277] = "battle_tower_open",
  [0x3311] = "record_corner",
  [0x4411] = "berry_blender",
  [0x5501] = "mystery_event",
}
-- pokeemerald/include/link.h:105
CableEntry.CONTEST = { [0x6601] = true, [0x6602] = true }
-- pokeemerald/include/constants/union_room.h:73
CableEntry.CONTEST_WIRES = { [0] = "contest_cool", "contest_beauty", "contest_cute", "contest_smart", "contest_tough" }
CableEntry.DIRECT = {
  battle_single = true, battle_double = true, battle_multi = true, trade = true,
  record_corner = true, berry_blender = true, contest_cool = true, contest_beauty = true,
  contest_cute = true, contest_smart = true, contest_tough = true,
}
CableEntry.CONNECT_TICKS = 1200
-- pokefirered/src/cable_club.c:483
CableEntry.READY_TICKS = 600
CableEntry.LOST_TICKS = 120
CableEntry.AWAY_TICKS = 600

local function contestCategory(ctx)
  local ok, id = pcall(function()
    return require("src.core.game3.constants").active(Link.session()):var("VAR_CONTEST_CATEGORY")
  end)
  return Link.getVar(ctx, ok and id or 0x8011)
end

function CableEntry.classOf(linkType)
  linkType = tonumber(linkType)
  if CableEntry.CONTEST[linkType] then return "contest" end
  return CableEntry.WIRE[linkType]
end

function CableEntry.wireFor(spec, ctx)
  if type(spec) ~= "table" then return nil end
  if spec.wire then return spec.wire end
  local linkType = tonumber(spec.linkType)
  if CableEntry.CONTEST[linkType] then
    return CableEntry.CONTEST_WIRES[contestCategory(ctx)]
  end
  return CableEntry.WIRE[linkType]
end

function CableEntry.matched(room, stale)
  return type(room) == "table" and room.stage == "battling" and room.match ~= nil
    and (stale == nil or room.match ~= stale)
end

local function protocol()
  return require("src.online.Protocol2")
end

-- pokefirered/src/cable_club.c:76
function CableEntry.run(ctx, adapters, spec, handshake)
  assert(type(spec) == "table", "cable service missing")
  local live = Link.link
  if live and live.isOpen and live:isOpen() then return handshake(ctx, adapters) end
  local wire = CableEntry.wireFor(spec, ctx)
  if not wire then
    Link.setResult(ctx, Link.LINKUP.FAILED)
    return false, Link.LINKUP.FAILED
  end
  local N = require("src.core.game3.scripting.natives")
  local UI = require("src.ui.game3.rs.cable_lobby")
  local P = protocol()
  local watchDirect = CableEntry.DIRECT[wire] == true
  local ruleset = P.ACTIVITY_RULESET[wire]
  local min, max = tonumber(spec.min) or 2, tonumber(spec.max) or 2
  local autoLead = min == max
  local phase, ticks, done, role, pending, answered = "connect", 0, false, nil, nil, {}
  local seenGroup, goneTicks, awayTicks, joining = false, 0, 0, nil
  local avatar = spec.avatar or Link.avatar()
  local profile = spec.profile
  local room0 = Link.clientCall("room")
  local stale = type(room0) == "table" and room0.match or nil
  local function unwatch()
    Link.clientCall("groupList", nil)
    if watchDirect then Link.clientCall("directList", nil) end
  end
  local function finish(code)
    if joining then Link.clientCall("leaveRoom") end
    Link.clientCall("leaveGroup")
    unwatch()
    Link.closeLink("cable_entry_failed")
    UI.close()
    Link.setStatus("busy")
    Link.setResult(ctx, code)
    done = true
  end
  local function offline(member)
    if type(member) ~= "table" then return false end
    if member.online == false then return true end
    for _, entry in ipairs(Link.clientCall("lobby") or {}) do
      if type(entry) == "table" and entry.id ~= nil and entry.id == member.id then return entry.online == false end
    end
    return false
  end
  local function liveMembers(group)
    local members = type(group) == "table" and type(group.members) == "table" and group.members or {}
    local out = {}
    for _, member in ipairs(members) do
      if not offline(member) then out[#out + 1] = member end
    end
    return out, #out == #members
  end
  local function joinRows()
    local out = {}
    for _, g in ipairs(Link.clientCall("groups", wire) or {}) do
      if type(g) == "table" and g.leader ~= nil then
        local av = g.avatar or {}
        out[#out + 1] = { kind = "group", id = g.leader, label = av.name or g.name or "",
          disabled = (tonumber(g.joined) or 0) >= (tonumber(g.max) or max) }
      end
    end
    if watchDirect then
      for _, e in ipairs(Link.clientCall("directEntries", wire) or {}) do
        if type(e) == "table" and e.kind == "room" and e.room ~= nil then
          local av = type(e.avatar) == "table" and e.avatar or {}
          out[#out + 1] = { kind = "room", id = e.room, label = av.name or e.name or "",
            disabled = e.locked == true }
        end
      end
    end
    return out
  end
  local function rows()
    if phase == "mode" then
      return { { id = "leader", label = Strings("CREATE GROUP") }, { id = "join", label = Strings("JOIN GROUP") } }
    end
    if phase == "ask" then return { { id = "yes", label = Strings("YES") }, { id = "no", label = Strings("NO") } } end
    if role == "leader" then
      local out = {}
      local members, all = liveMembers(Link.clientCall("group"))
      for _, member in ipairs(members) do
        local av = member.avatar or {}
        out[#out + 1] = { label = av.name or member.name or "", disabled = true }
      end
      out[#out + 1] = { id = "start", label = Strings("START"), disabled = not all or #members < min or #members > max }
      return out
    end
    if phase == "list" then return joinRows() end
    return {}
  end
  local function select(row)
    if phase == "mode" then
      role, phase = row.id, "list"
      if role == "leader" then
        Link.clientCall("openGroup", wire, profile, avatar)
      else
        Link.clientCall("groupList", wire, profile)
        if watchDirect then Link.clientCall("directList", wire, profile, avatar) end
      end
    elseif phase == "ask" then
      answered[pending.id] = true
      Link.clientCall("acceptGroup", pending.id, row.id == "yes")
      pending, phase = nil, "list"
    elseif role == "leader" and row.id == "start" then
      Link.clientCall("startGroup")
      phase, ticks = "starting", 0
    elseif role == "join" and row.kind == "room" then
      joining = Link.clientCall("joinRoom", row.id, "player", profile, nil)
      phase, ticks = "joining", 0
    elseif role == "join" then
      Link.clientCall("joinGroup", row.id, profile, avatar)
      phase, ticks, seenGroup, goneTicks = "waiting", 0, false, 0
    end
  end
  local function enter()
    profile = profile or Link.liveProfile(ruleset)
    Link.setStatus("idle")
    phase, ticks = "mode", 0
    UI.cursor = 1
  end
  local function leaderTick(g)
    local requests = type(g) == "table" and type(g.pending) == "table" and g.pending or {}
    if phase == "ask" then
      local still = false
      for _, request in ipairs(requests) do
        if pending and request.id == pending.id and not offline(request) then still = true end
      end
      if not still then
        if pending then answered[pending.id] = true end
        pending, phase = nil, "list"
        UI.cursor = 1
      end
    elseif phase == "list" then
      local members, all = liveMembers(g)
      for _, request in ipairs(requests) do
        if not answered[request.id] and not offline(request) then
          if autoLead then
            -- pokeemerald/src/cable_club.c:225
            answered[request.id] = true
            Link.clientCall("acceptGroup", request.id, #members < max)
          else
            pending, phase = request, "ask"
          end
          break
        end
      end
      if phase == "list" and autoLead and all and #members >= max then
        Link.clientCall("startGroup")
        phase, ticks = "starting", 0
      end
    elseif phase == "starting" and type(g) == "table" then
      local members, all = liveMembers(g)
      if not all or #members < min then phase, ticks = "list", 0 end
    end
  end
  local function joinTick(g)
    if phase == "joining" then
      local p = joining
      if type(p) ~= "table" or (p.done and p.reason ~= nil) then
        joining, phase = nil, "list"
        UI.cursor = 1
      end
      return
    end
    if phase ~= "waiting" then return end
    if type(g) == "table" then
      seenGroup, goneTicks = true, 0
      local leader
      for _, member in ipairs(type(g.members) == "table" and g.members or {}) do
        if member.id == g.leader then leader = member end
      end
      awayTicks = offline(leader) and awayTicks + 1 or 0
      if awayTicks > CableEntry.AWAY_TICKS then return finish(Link.LINKUP.CONNECTION_ERROR) end
      ticks = 0
    elseif seenGroup then
      goneTicks = goneTicks + 1
      if goneTicks > CableEntry.LOST_TICKS then
        phase, seenGroup, goneTicks = "list", false, 0
        UI.cursor = 1
      end
    end
  end
  if not Link.online() then
    local ok = (spec.connect or Link.connect)()
    if not ok then
      finish(Link.LINKUP.CONNECTION_ERROR)
      return false, Link.LINKUP.CONNECTION_ERROR
    end
  else
    enter()
  end
  N.yieldHost(ctx, adapters, function() end)
  Link.setResult(ctx, Link.LINKUP.ONGOING)
  local poll
  poll = function()
    if done then return true end
    ticks = ticks + 1
    if phase == "connect" then
      if Link.online() then
        enter()
      elseif ticks > CableEntry.CONNECT_TICKS or Link.connectState() == "error" then
        finish(Link.LINKUP.CONNECTION_ERROR)
      end
      return done
    end
    if not Link.online() then finish(Link.LINKUP.CONNECTION_ERROR); return true end
    if phase == "ready" then
      local lk = Link.link
      if not (lk and lk:isOpen()) then finish(Link.LINKUP.CONNECTION_ERROR); return true end
      if lk:isReady() then
        UI.close()
        Link.setStatus("busy")
        local yielded, value = handshake(ctx, adapters)
        if not yielded then
          Link.setResult(ctx, value or Link.getVar(ctx, Link.VAR_RESULT))
          return true
        end
        return false
      elseif ticks > CableEntry.READY_TICKS then
        finish(Link.LINKUP.CONNECTION_ERROR)
        return true
      end
      return false
    end
    if CableEntry.matched(Link.clientCall("room"), stale) then
      UI.close()
      unwatch()
      joining = nil
      if not Link.openRelay({ linkType = spec.linkType, game = spec.game, hello = spec.hello }) then
        finish(Link.LINKUP.CONNECTION_ERROR)
        return true
      end
      phase, ticks = "ready", 0
      return false
    end
    local g = Link.clientCall("group")
    if role == "leader" then leaderTick(g) elseif role == "join" then joinTick(g) end
    if not done and phase == "starting" and ticks > CableEntry.CONNECT_TICKS then
      finish(Link.LINKUP.CONNECTION_ERROR)
    end
    return done
  end
  ctx.nativePoll = poll
  UI.show({
    rows = rows,
    select = select,
    tick = function() if ctx.nativePoll == poll then poll() end end,
    title = function()
      if phase == "ask" then return Strings("ADD %s?", (pending.avatar or {}).name or pending.name or "") end
      return Strings((wire:upper():gsub("_", " ")))
    end,
    cancel = function()
      if phase == "waiting" or phase == "joining" then
        if phase == "joining" then Link.clientCall("leaveRoom") else Link.clientCall("leaveGroup") end
        joining, phase = nil, "list"
        UI.cursor = 1
        return
      end
      finish(Link.LINKUP.FAILED)
    end,
  })
  return true
end

return CableEntry
