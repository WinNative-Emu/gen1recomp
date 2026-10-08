local Dialog = require("src.ui.gen2.union.Dialog")
local Participant = require("src.online.union.Participant")
local Strings = require("src.core.Strings")
local Text = require("src.ui.gen2.union.Text")

local Talk = {}

Talk.ACTIVITIES = { "xg_battle", "xg_trade" }
Talk.LINK_SECONDS = 15

local function now()
  local t = love and love.timer and love.timer.getTime
  return t and t() or os.clock()
end

local function finish(session)
  session:uiDone()
end

local function sayThen(session, text, after)
  Dialog.say(session.game, text, function()
    if after then after() else finish(session) end
  end)
end

function Talk.wait(session, p, handle)
  local game = session.game
  Dialog.hold(game, Text.say("waiting", p.name), function(w, input)
    if handle.state == "accepted" or handle.why == "crossed" then
      w:close()
      finish(session)
      return
    end
    if handle.state == "closed" then
      w:close()
      Dialog.sfx(game, "Sfx_Wrong")
      sayThen(session, Text.closed(handle.why, p.name))
      return
    end
    if Dialog.pressed(input, "b") then
      session.abandoned[handle] = true
      w:close()
      Dialog.sfx(game, "Sfx_ReadText2")
      sayThen(session, Text.cancelled(game))
    end
  end)
end

function Talk.invite(session, p, activity)
  local handle, why = session.room:invite(p, activity)
  if not handle then
    sayThen(session, Text.closed(why, p.name))
    return
  end
  if handle.state == "closed" then
    sayThen(session, Text.closed(handle.why, p.name))
    return
  end
  Talk.wait(session, p, handle)
end

function Talk.menu(session, p)
  local labels = { Text.MENU.battle, Text.MENU.trade, Text.MENU.cancel }
  Dialog.menu(session.game, Text.say("what", p.name), labels, function(index)
    local activity = Talk.ACTIVITIES[index]
    if not activity then return finish(session) end
    local live = session.room:member(p.id) or p
    if Participant.busy(live) then
      return sayThen(session, Text.say("busy", p.name))
    end
    Talk.invite(session, live, activity)
  end)
end

function Talk.open(session, e)
  local p = e.participant
  session:uiOpen("talk")
  Dialog.sfx(session.game, "Sfx_ReadText2")
  local function body()
    if Participant.busy(session.room:member(p.id) or p) then
      return sayThen(session, Text.say("busy", p.name))
    end
    Talk.menu(session, p)
  end
  local entry = e.avatar
  if entry and (entry.standin or entry.hostStandin) then
    local game = Text.needName(entry.need)
    return sayThen(session, Text.say("standin", p.name, Text.gameName(p.game), game), body)
  end
  body()
end

function Talk.linking(session, name, inv)
  local game = session.game
  local started = now()
  Dialog.hold(game, Text.say("linking", name), function(w)
    if session.room:xgRoom() then
      w:close()
      finish(session)
      return
    end
    if now() - started > Talk.LINK_SECONDS or session.state ~= "joined" then
      w:close()
      sayThen(session, Text.cancelled(game))
    end
  end)
end

function Talk.prompt(session, inv)
  local from = inv.from or {}
  local name = from.name or "?"
  session:uiOpen("prompt")
  local e = from.slot and session:entity(from.slot)
  if e and e.participant.id == inv.fromId then e:facePlayer(session.world and session.world.player) end
  Dialog.sfx(session.game, "Sfx_Call")
  local key = inv.mode == "trade" and "askTrade" or "askBattle"
  Dialog.ask(session.game, Text.say(key, name), function(yes)
    local sent = session.room:reply(inv.id, yes)
    if not yes then return finish(session) end
    if not sent then return sayThen(session, Text.say("gone", name)) end
    Talk.linking(session, name, inv)
  end)
end

function Talk.notice(session, n)
  local game = session.game
  session:uiOpen("notice")
  if n.kind == "connecting" then
    Dialog.hold(game, Strings(Text.S.connecting), function(w, input)
      if session.state ~= "connecting" or Dialog.pressed(input, "b") then
        w:close()
        finish(session)
      end
    end)
  elseif n.kind == "lost" then
    Dialog.hold(game, Strings(Text.S.lost), function(w, input)
      if not session.lost or Dialog.pressed(input, "b") then
        w:close()
        finish(session)
      end
    end)
  elseif n.kind == "error" then
    sayThen(session, Text.error(n.code))
  else
    sayThen(session, n.text or "")
  end
end

return Talk
