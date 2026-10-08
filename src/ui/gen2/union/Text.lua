local GameVersion = require("src.core.GameVersion")
local Strings = require("src.core.Strings")

local Text = {}

Text.MENU = {
  battle = Strings.source("BATTLE"),
  trade = Strings.source("TRADE"),
  cancel = Strings.source("CANCEL"),
}

local S = {
  what = Strings.source("With %s,\nwhat'll you do?"),
  busy = Strings.source("%s is\nbusy right now."),
  waiting = Strings.source("Waiting for\n%s…"),
  declined = Strings.source("%s said no."),
  timeout = Strings.source("%s didn't\nanswer."),
  gone = Strings.source("%s left the\nUNION ROOM."),
  refused = Strings.source("%s can't do\nthat right now."),
  askBattle = Strings.source("%s wants\nto battle. OK?"),
  askTrade = Strings.source("%s wants\nto trade. OK?"),
  linking = Strings.source("Linking up with\n%s…"),
  readyBattle = Strings.source("Getting ready to\nbattle %s…"),
  readyTrade = Strings.source("Getting ready to\ntrade with %s…"),
  peerCancel = Strings.source("%s cancelled."),
  standin = Strings.source("%s is playing\n%s.\fImport %s\nto see them here."),
  connecting = Strings.source("Connecting to the\nUNION ROOM…"),
  offline = Strings.source("Couldn't connect.\fNo other trainers\ncan be seen now."),
  serverOld = Strings.source("The UNION ROOM\nserver is too old.\fNo other trainers\ncan be seen now."),
  clientOld = Strings.source("This game is too\nold to link up.\fUpdate it to meet\nother trainers."),
  joinFailed = Strings.source("Couldn't enter\nthe UNION ROOM.\fNo other trainers\ncan be seen now."),
  lost = Strings.source("The link was lost.\nReconnecting…"),
  lostForGood = Strings.source("Couldn't link up\nagain.\fNo other trainers\ncan be seen now."),
  mismatch = Strings.source("Your games can't\nlink up for this."),
}
Text.S = S

local function clean(name)
  name = tostring(name or "")
  name = name:gsub("[{}%c]", "")
  if name == "" then name = "?" end
  return name
end

Text.clean = clean

function Text.say(key, ...)
  local args = { ... }
  for i = 1, select("#", ...) do args[i] = clean(args[i]) end
  return Strings(S[key], unpack(args, 1, select("#", ...)))
end

function Text.gameName(version)
  local info = GameVersion.VERSIONS[version or ""]
  local label = info and info.label or tostring(version or "?")
  return "POKéMON " .. label:upper()
end

function Text.needName(need)
  if type(need) ~= "table" or not need[1] then return "?" end
  return Text.gameName(need[1])
end

Text.CLOSED = {
  declined = "declined", timeout = "timeout", busy = "busy",
  offline = "gone", target_left = "gone", sender_left = "gone",
}

function Text.closed(why, name)
  return Text.say(Text.CLOSED[why or ""] or "refused", name)
end

Text.ERRORS = {
  server_outdated = "serverOld", client_outdated = "clientOld",
  offline = "offline", lost = "lostForGood",
}

function Text.error(code)
  return Strings(S[Text.ERRORS[code or ""] or "joinFailed"])
end

-- data/text/common_2.asm:216
function Text.cancelled(game)
  local text = game and game.data and game.data.text
  local line = text and text._MysteryGiftCanceledText
  assert(type(line) == "string", "gen2 cache has no _MysteryGiftCanceledText")
  return line
end

return Text
