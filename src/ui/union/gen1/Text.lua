local GameVersion = require("src.core.GameVersion")
local Messages = require("src.online.xgen.Messages")
local Strings = require("src.core.Strings")

local Text = {}

Text.MENU = {
  battle = Strings.source("BATTLE"),
  trade = Strings.source("TRADE"),
  cancel = Strings.source("CANCEL"),
}

local S = {
  what = Strings.source("Do what with\n%s?"),
  busy = Strings.source("%s looks\nbusy right now."),
  waiting = Strings.source("Waiting for\n%s…"),
  declined = Strings.source("%s\nsaid no."),
  timeout = Strings.source("%s\ndidn't answer."),
  gone = Strings.source("%s\nhas left."),
  refused = Strings.source("%s can't\ndo that now."),
  askBattle = Strings.source("%s wants\nto BATTLE!\fWill you accept?"),
  askTrade = Strings.source("%s wants\nto TRADE!\fWill you accept?"),
  linking = Strings.source("Linking up with\n%s…"),
  readyBattle = Strings.source("Getting ready to\nBATTLE %s…"),
  readyTrade = Strings.source("Getting ready to\nTRADE: %s…"),
  peerCancel = Strings.source("%s\ncanceled."),
  cancelled = Strings.source("The request was\ncanceled."),
  standin = Strings.source("%s\nplays %s!\fImport %s\nto see them here."),
  connecting = Strings.source("Linking to the\nUNION ROOM…"),
  offline = Strings.source("No link could be\nmade.\fNo other TRAINERS\nare here for now."),
  serverOld = Strings.source("The UNION ROOM\nlink is too old.\fNo other TRAINERS\nare here for now."),
  clientOld = Strings.source("This game is too\nold to link up.\fUpdate it to meet\nother TRAINERS."),
  joinFailed = Strings.source("The UNION ROOM\ncouldn't be used.\fNo other TRAINERS\nare here for now."),
  lost = Strings.source("The link was lost.\nReconnecting…"),
  lostForGood = Strings.source("The link couldn't\nbe made again.\fNo other TRAINERS\nare here for now."),
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
  local n = select("#", ...)
  local args = { ... }
  for i = 1, n do args[i] = clean(args[i]) end
  return Strings(S[key], unpack(args, 1, n))
end

function Text.gameName(version)
  local info = GameVersion.VERSIONS[version or ""]
  local label = info and info.label or tostring(version or "?")
  return label:upper()
end

function Text.needName(need)
  if type(need) ~= "table" or not need[1] then return "?" end
  return Text.gameName(need[1])
end

function Text.standin(p, entry)
  return Text.say("standin", p and p.name, Text.gameName(p and p.game), Text.needName(entry and entry.need))
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

function Text.blocked(code, detail)
  local lines = Messages.render(code, 1, detail)
  local out = {}
  for i, line in ipairs(lines) do
    if i > 1 then out[#out + 1] = (i % 2 == 0) and "\n" or "\f" end
    out[#out + 1] = line
  end
  return table.concat(out)
end

-- pokered/data/text/text_4.asm:209
function Text.pleaseWait(game)
  local text = game and game.data and game.data.text
  local line = text and text._CableClubNPCPleaseWaitText
  assert(type(line) == "string", "gen1 cache has no _CableClubNPCPleaseWaitText")
  return line
end

return Text
