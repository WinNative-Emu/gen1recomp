local Dialog = require("src.ui.gen2.union.Dialog")
local Strings = require("src.core.Strings")
local Text = require("src.ui.gen2.union.Text")

local Activity = {}
Activity.__index = Activity

Activity.screens = { battle = nil, trade = nil }

local function peerOf(room)
  local xr = room:xgRoom()
  local seat = room.client.seat and room.client.seat()
  for _, row in ipairs(xr and xr.players or {}) do
    if row.seat ~= seat then
      local av = type(row.avatar) == "table" and row.avatar or {}
      return { id = row.id, name = av.name or row.name or "?", gen = row.gen, game = av.version, seat = row.seat }
    end
  end
  return { name = "?" }
end

local function flow()
  return require("src.ui.union.Flow")
end

function Activity.begin(game, room, mode, opts)
  opts = opts or {}
  if not Activity.installed then
    Activity.installed = true
    flow().install(Activity)
  end
  local self = setmetatable({
    game = game, room = room, mode = mode == "trade" and "trade" or "battle",
    session = opts.session, prep = room:prep(), peer = peerOf(room),
    state = "preparing", done = false, why = nil, events = {},
  }, Activity)
  if self.session then self.session:uiOpen("activity") end
  self:show()
  return self
end

function Activity:readyText()
  return Text.say(self.mode == "trade" and "readyTrade" or "readyBattle", self.peer.name)
end

function Activity:show()
  self.waiter = Dialog.hold(self.game, self:readyText(), function(_, input)
    self:tick(input)
  end)
end

function Activity:closeUi()
  if self.waiter then self.waiter:close() end
  self.waiter = nil
end

function Activity:finish(why, text)
  if self.done then return end
  if why == "go" and not self.launched then
    self.state = "battle"
    self:closeUi()
    if flow().launch(self, 2) then return end
    why, text = "error", require("src.ui.g3u.Launch").resultText(2, "error")
  end
  self.why = why
  self.state = "done"
  self:closeUi()
  flow().leaveRoom(self)
  local session = self.session
  local function after()
    self.done = true
    if session then session:uiDone() end
  end
  if text then
    Dialog.say(self.game, text, after)
  else
    after()
  end
end

function Activity:cancel(why)
  local prep = self.prep
  if prep then
    prep:cancel(why or "cancel")
    prep:leave()
  end
  Dialog.sfx(self.game, "Sfx_ReadText2")
  self:finish(why or "cancel", Text.cancelled(self.game))
end

function Activity:abort(why)
  if self.done then return end
  local prep = self.prep
  if prep and prep:open() then
    prep:cancel(why or "left")
    prep:leave()
  end
  self:closeUi()
  self.state = "done"
  self.why = why or "left"
  self.done = true
end

function Activity:handle(e)
  self.events[#self.events + 1] = e.kind
  if e.kind == "closed" then
    local mine = e.seat ~= nil and e.seat == self.prep:seat()
    if mine then
      self:finish("closed", Text.cancelled(self.game))
    else
      Dialog.sfx(self.game, "Sfx_Wrong")
      self:finish("peer", Text.say("peerCancel", self.peer.name))
    end
    return true
  end
  if e.kind == "blocked" then
    self.prep:cancel("blocked")
    self.prep:leave()
    self:finish("blocked", Strings(Text.S.mismatch))
    return true
  end
  return false
end

function Activity:tick(input)
  if self.done or self.state == "done" then return end
  local prep = self.prep
  if not prep then return self:finish("gone", Text.cancelled(self.game)) end
  for _, e in ipairs(prep:poll()) do
    if self:handle(e) then return end
  end
  if prep.state == "prep" and self.state == "preparing" then
    self.state = "ready"
    local screen = Activity.screens[self.mode]
    if screen then
      self:closeUi()
      screen(self)
      return
    end
  end
  if Dialog.pressed(input, "b") then self:cancel("cancel") end
end

return Activity
