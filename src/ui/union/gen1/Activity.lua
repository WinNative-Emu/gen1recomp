local Dialog = require("src.ui.union.gen1.Dialog")
local Text = require("src.ui.union.gen1.Text")

local Activity = {}
Activity.__index = Activity

Activity.LINK_SECONDS = 10
Activity.screens = { battle = nil, trade = nil }

local MODES = { battle = true, trade = true }

local function peerOf(room, fallback)
  local xr = room:xgRoom()
  local seat = room.client and room.client.seat and room.client.seat()
  for _, row in ipairs(xr and xr.players or {}) do
    if row.seat ~= seat then
      local av = type(row.avatar) == "table" and row.avatar or {}
      return { id = row.id, name = av.name or row.name or "?", gen = row.gen, game = av.version, seat = row.seat }
    end
  end
  if fallback then
    return { id = fallback.id, name = fallback.name, gen = fallback.gen, game = fallback.game }
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
  assert(MODES[mode], "union activity mode must be battle or trade")
  local self = setmetatable({
    game = game, room = room, mode = mode, opts = opts, session = opts.session,
    prep = nil, peer = peerOf(room, opts.peer), state = "preparing", done = false,
    why = nil, events = {}, started = love.timer.getTime(), linked = false,
  }, Activity)
  if self.session then self.session.activity = self end
  self:show(Text.pleaseWait(game))
  return self
end

function Activity:readyText()
  return Text.say(self.mode == "trade" and "readyTrade" or "readyBattle", self.peer.name)
end

function Activity:show(text)
  self:closeUi()
  self.waiter = Dialog.hold(self.game, text, function(_, input)
    self:tick(input)
  end)
end

function Activity:closeUi()
  if self.waiter then self.waiter:close() end
  self.waiter = nil
end

function Activity:finish(why, text)
  if self.done or self.state == "done" then return end
  if why == "go" and not self.launched then
    self.state = "battle"
    self:closeUi()
    if flow().launch(self, 1) then return end
    why, text = "error", require("src.ui.g3u.Launch").resultText(1, "error")
  end
  self.why = why
  self.state = "done"
  self:closeUi()
  flow().leaveRoom(self)
  self.room:dropPrep()
  local session = self.session
  local onDone = self.opts.onDone
  local function after()
    self.done = true
    if session and session.activity == self then session.activity = nil end
    if onDone then onDone() end
  end
  if text then
    Dialog.say(self.game, text, after)
  else
    after()
  end
end

function Activity:cancel(why)
  local prep = self.prep
  if prep and prep:open() then
    prep:cancel(why or "cancel")
    prep:leave()
  end
  Dialog.sfx(self.game, "Press_AB")
  self:finish(why or "cancel", Text.say("cancelled"))
end

function Activity:abort(why)
  if self.done then return end
  local prep = self.prep
  if prep and prep:open() then
    prep:cancel(why or "left")
    prep:leave()
  end
  self:closeUi()
  self.room:dropPrep()
  self.state = "done"
  self.why = why or "left"
  self.done = true
  if self.session and self.session.activity == self then self.session.activity = nil end
end

function Activity:handle(e)
  self.events[#self.events + 1] = e.kind
  if e.kind == "closed" then
    local mine = e.seat ~= nil and e.seat == self.prep:seat()
    if mine then
      self:finish("closed", Text.say("cancelled"))
    else
      Dialog.sfx(self.game, "Denied")
      self:finish("peer", Text.say("peerCancel", self.peer.name))
    end
    return true
  end
  if e.kind == "blocked" then
    self.prep:cancel("blocked")
    self.prep:leave()
    Dialog.sfx(self.game, "Denied")
    self:finish("blocked", Text.blocked(e.why))
    return true
  end
  return false
end

function Activity:tick(input)
  if self.done or self.state == "done" then return end
  if Dialog.pressed(input, "b") then return self:cancel("cancel") end
  if not self.prep then
    self.prep = self.room:prep()
    if not self.prep then
      if love.timer.getTime() - self.started > Activity.LINK_SECONDS then
        self:finish("gone", Text.say("gone", self.peer.name))
      end
      return
    end
    self.peer = peerOf(self.room, self.opts.peer)
    self.linked = true
  end
  local prep = self.prep
  for _, e in ipairs(prep:poll()) do
    if self:handle(e) then return end
  end
  if prep.state == "closed" then
    return self:finish("peer", Text.say("peerCancel", self.peer.name))
  end
  if prep.state == "prep" and self.state == "preparing" then
    self.state = "ready"
    local screen = Activity.screens[self.mode]
    if screen then
      self:closeUi()
      screen(self)
      return
    end
    self:show(self:readyText())
  end
end

return Activity
