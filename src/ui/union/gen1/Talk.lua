local Activity = require("src.ui.union.gen1.Activity")
local Dialog = require("src.ui.union.gen1.Dialog")
local Participant = require("src.online.union.Participant")
local Protocol2 = require("src.online.Protocol2")
local Text = require("src.ui.union.gen1.Text")

local Talk = {}

Talk.LABELS = { Text.MENU.battle, Text.MENU.trade, Text.MENU.cancel }
Talk.ACTIVITIES = { "xg_battle", "xg_trade" }

local function release(presence, done)
  return function()
    presence:setBusy(false)
    if done then done() end
  end
end

function Talk.invite(game, presence, p, activity, done)
  local room = presence.room
  local finish = release(presence, done)
  local mode = Protocol2.XG_ACTIVITIES[activity]
  local h, why = room:invite(p, activity)
  if not h or h.state == "closed" then
    Dialog.sfx(game, "Denied")
    Dialog.say(game, Text.closed(h and h.why or why, p.name), finish)
    return nil
  end
  presence:track(h)
  Dialog.hold(game, Text.say("waiting", p.name), function(w, input)
    if h.state == "accepted" then
      w:close()
      presence:untrack(h)
      Activity.begin(game, room, mode, { peer = p, onDone = finish, session = presence })
    elseif h.state == "closed" then
      w:close()
      presence:untrack(h)
      Dialog.sfx(game, "Denied")
      Dialog.say(game, Text.closed(h.why, p.name), finish)
    elseif Dialog.pressed(input, "b") then
      Dialog.sfx(game, "Press_AB")
      w:close()
      presence:abandon(h)
      Dialog.say(game, Text.say("cancelled"), finish)
    end
  end)
  return h
end

function Talk.begin(game, presence, member, done)
  local p = presence:participant(member)
  if not p or presence.state ~= "joined" then
    Dialog.say(game, Text.say("gone", member and member.p and member.p.name), done)
    return
  end
  if Participant.busy(p) then
    Dialog.say(game, Text.say("busy", p.name), done)
    return
  end
  presence:setBusy(true, member)
  local finish = release(presence, done)
  local function menu()
    Dialog.menu(game, Text.say("what", p.name), Talk.LABELS, function(i)
      local activity = Talk.ACTIVITIES[i]
      if activity then
        Talk.invite(game, presence, p, activity, done)
      else
        finish()
      end
    end)
  end
  if member.entry and (member.entry.standin or member.entry.hostStandin) then
    Dialog.say(game, Text.standin(p, member.entry), menu)
  else
    menu()
  end
end

function Talk.incoming(game, presence, inv, done)
  local room = presence.room
  local p = inv.from
  local name = p and p.name or nil
  local finish = release(presence, done)
  local member = presence:memberById(inv.fromId)
  presence:setBusy(true, member)
  if member and game.overworld and game.overworld.player then
    member:facePlayer(game.overworld.player)
  end
  Dialog.sfx(game, "Safari_Zone_PA")
  Dialog.ask(game, Text.say(inv.mode == "trade" and "askTrade" or "askBattle", name), function(yes)
    local sent = room:reply(inv.id, yes)
    if not yes then
      finish()
    elseif not sent then
      Dialog.say(game, Text.say("timeout", name), finish)
    else
      Activity.begin(game, room, inv.mode, { peer = p, onDone = finish, session = presence })
    end
  end)
end

return Talk
