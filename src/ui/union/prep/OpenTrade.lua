local GameVersion = require("src.core.GameVersion")
local Messages = require("src.online.xgen.Messages")
local Model = require("src.online.union.TradePrepModel")
local Project = require("src.online.xgen.Project")
local Txn = require("src.online.union.TradeTxn")

local Open = {}

Open.RENDERERS = {
  [1] = "src.ui.union.prep.Gen1TradePrep",
  [2] = "src.ui.union.prep.Gen2TradePrep",
  [3] = "src.ui.union.prep.Gen3TradePrep",
}

local TEXT = {
  title_pick = "Union Trade",
  title_offer = "Your Offer",
  title_moves = "Moves",
  title_wait = "Union Trade",
  title_confirm = "Final Trade",
  title_trading = "Trading",
  title_done = "Trade Done",
  title_closed = "Union Trade",

  with = "Trade with {name}.",
  plays = "{name} is playing {game}.",
  feature = "Trades between generations are a feature of this app, not of the original games.",
  pick = "Choose a Pokémon to offer.",
  rules_wait = "Waiting for the trade to open…",
  becomes = "In {game} it becomes {species} {level}.",
  no_change = "Nothing else changes.",
  changes = "Permanent changes:",
  blocked = "It can't be offered yet:",
  pick_move = "Choose a move {species} can learn in {game}, or remove the move.",
  recommend_ask = "Some moves can't come along. Replace them with the recommended moveset?",
  recommend_wait = "Getting the recommended moveset…",
  recommend_offline = "Couldn't reach the server for a recommended moveset.",
  recommend_server = "The server has no recommended moveset right now.",
  recommend_missing = "There's no recommended moveset for {species}.",
  recommend_none = "None of the recommended moves can come along.",
  recommend_partial = "Some recommended moves can't come along. Fix the rest by hand.",
  move_row = "{type} Power {power} PP {pp}",
  evolves = "{species} may evolve when it arrives.",
  wait_offer = "Waiting for {name} to offer a Pokémon…",
  sent = "You offered {species}.",
  their_offer = "{name} offers {species} {level}.",
  refused = "{name}'s offer can't be accepted here:",
  refused_peer = "{name} can't accept your offer:",
  refused_unknown = "Their game can't take it as it is.",
  you_send = "You send {species} {level}.",
  you_get = "You get {species} {level} from {name}.",
  their_changes = "Changes to what you get:",
  my_changes = "Changes to what you send:",
  final_note = "This is final. The sent Pokémon is gone from your game for good.",
  wait_ready = "Waiting for {name} to agree…",
  changed = "An offer changed. Check the trade again.",
  trading = "Trading… Don't turn off the power.",
  save_failed = "The game couldn't be saved. Trying again…",
  unresolved = "The link was lost during the trade. It will be finished when the server answers.",
  done = "{name} sent {species}!",
  evolved = "{species} evolved into {into}!",
  again = "Trade again?",
  closed_cancel = "{name} stopped trading.",
  closed_self = "Trading stopped.",
  closed_gone = "The link to {name} was lost.",
  closed_other = "The trade was cancelled.",
  aborted = "The trade didn't happen. Both Pokémon stay where they were.",
  recheck = "Your Pokémon changed after it was offered, so the trade was stopped.",

  item_offer = "Offer",
  item_moves = "Fix moves",
  item_recommend = "Use recommended moveset",
  item_back = "Back",
  item_trade = "Trade",
  item_change = "Change",
  item_stop = "Stop",
  item_remove = "Remove move",
  item_ok = "OK",
  item_yes = "Yes",
  item_no = "No",
  item_details = "Details",
  place_party = "party",
  place_box = "Box {box}",
}

local CODE_TEXT = {
  rental = "Rental Pokémon can't be traded.",
  projection = "Battle copies can't be traded.",
  pending = "Its last trade isn't settled yet.",
  not_owned = "That Pokémon isn't there anymore.",
  preview_mismatch = "Their game and this one disagree about how it converts. Both players need the same games imported.",
  wrong_destination = "It was meant for another game.",
  wrong_source = "It doesn't match the other player's game.",
  bad_payload = "Its data can't be read.",
  unsupported_version = "Its game isn't supported.",
  not_valid_here = "This game can't store it as it is.",
  too_big = "It carries too much data to send.",
  not_ready = "It can't be offered yet.",
}

local function fill(template, args)
  args = args or {}
  return (template:gsub("{(%w+)}", function(k)
    local v = args[k]
    return v ~= nil and tostring(v) or ""
  end))
end

local function say(key, args) return fill(TEXT[key] or key, args) end
Open.say = say
Open.TEXT = TEXT
Open.REFUSED = "refused:"

local function gameName(version)
  local info = GameVersion.VERSIONS[version or ""]
  return "Pokémon " .. (info and info.label or tostring(version or "?"))
end

local function item(id, label, extra)
  local out = { id = id, label = label }
  for k, v in pairs(extra or {}) do out[k] = v end
  return out
end

function Open.opponent(room, prep)
  local r = room and room.xgRoom and room:xgRoom() or nil
  local mine = prep and prep.seat and prep:seat() or nil
  for _, p in ipairs(r and r.players or {}) do
    if mine == nil or p.seat ~= mine then
      local av = type(p.avatar) == "table" and p.avatar or {}
      return { name = av.name or p.name, version = av.version, gen = p.gen or av.gen }
    end
  end
  return { name = "?" }
end

local Ctl = {}
Ctl.__index = Ctl
Open.Controller = Ctl

function Ctl.new(opts)
  local self = setmetatable({}, Ctl)
  self.game = opts.game
  self.prep = opts.prep
  self.version = opts.version or GameVersion.get()
  self.gen = GameVersion.generation(self.version)
  self.opponent = opts.opponent or { name = "?" }
  self.adapter = opts.adapter or Txn.newAdapter(self.game, self.version)
  self.model = Model.new({ version = self.version, peerVersion = self.opponent.version, peerName = self.opponent.name,
    owned = self.adapter:owned() })
  self.txn = Txn.new({ game = self.game, prep = self.prep, model = self.model, adapter = self.adapter,
    peerName = self.opponent.name, roomId = opts.roomId })
  self.step = "pick"
  self.cursor = 1
  self.scroll = 0
  self.events = {}
  self.done = false
  self.sentOffer = nil
  self.myData = Model.datasetFor(self.version)
  self.recommendClient = opts.recommendClient
  self.recommend = nil
  return self
end

function Ctl:style() return Messages.style(self.gen) end

function Ctl:label(text)
  if self:style() == "gb" then return (text or ""):upper() end
  return text or ""
end

function Ctl:formatLines(lines)
  local out = {}
  for _, line in ipairs(lines or {}) do
    for _, l in ipairs(Messages.format(line, self.gen)) do out[#out + 1] = l end
  end
  return out
end

function Ctl:levelLabel(level)
  if level == nil then return "" end
  if self.gen <= 2 then return ":L" .. tostring(level) end
  return "Lv" .. tostring(level)
end

function Ctl:names(data)
  data = data or self.myData
  return {
    species = function(n) local sp = data and data.species[tonumber(n) or -1] return sp and sp.name or ("No. " .. tostring(n)) end,
    move = function(m) local mv = data and data.moves[tonumber(m) or -1] return mv and mv.name or ("move " .. tostring(m)) end,
    item = function(i) return tostring(i) end,
  }
end

function Ctl:monLabel(entry)
  local view = entry and entry.rec and self.myData and Project.read(entry.rec, self.myData)
  local name = view and self.myData.species[view.national] and self.myData.species[view.national].name or "?"
  if view and view.isEgg then name = "Egg" end
  return name, view and view.level
end

function Ctl:go(step)
  self.step = step
  self.cursor = 1
  self.scroll = 0
end

function Ctl:close(key, args, reason)
  self.closedText = say(key, args)
  self.closedReason = reason
  self:go("closed")
end

function Ctl:reasonText(code, detail)
  if code == nil or code == "" then return say("refused_unknown") end
  if CODE_TEXT[code] then return CODE_TEXT[code] end
  if Messages.known(code) then return Messages.text(code, detail, self:names()) end
  return say("refused_unknown")
end

function Ctl:blockLines(report, data)
  local lines = {}
  local names = self:names(data)
  for _, b in ipairs(report.blocks or {}) do
    local text = CODE_TEXT[b.code] or Messages.text(b.code, b.detail, names)
    lines[#lines + 1] = "- " .. text
  end
  return lines
end

function Ctl:changeLines(changes)
  local lines, seen = {}, {}
  for _, c in ipairs(changes or {}) do
    local text = Messages.change(c, 3)[1]
    if text and not seen[text] then
      seen[text] = true
      lines[#lines + 1] = "- " .. text
    end
  end
  return lines
end

function Ctl:pagePick()
  local lines = { say("with", { name = self.opponent.name }) }
  if self.opponent.version then
    lines[#lines + 1] = say("plays", { name = self.opponent.name, game = gameName(self.opponent.version) })
  end
  local items = {}
  if self.prep and self.prep.state == "rules_wait" then
    lines[#lines + 1] = say("rules_wait")
    items[#items + 1] = item("stop", TEXT.item_stop)
    return { title = TEXT.title_pick, lines = lines, items = items }
  end
  lines[#lines + 1] = say("pick")
  for i, entry in ipairs(self.model.owned) do
    local name, level = self:monLabel(entry)
    local place = entry.ref.where == "box" and say("place_box", { box = entry.ref.box }) or nil
    local label = name .. " " .. self:levelLabel(level)
    items[#items + 1] = item("mon", label, { arg = i, disabled = entry.locked ~= nil,
      detail = { place and (place .. ".") or nil, entry.locked and (CODE_TEXT[entry.locked] or Messages.text(entry.locked)) or nil } })
  end
  items[#items + 1] = item("stop", TEXT.item_stop)
  return { title = TEXT.title_pick, lines = lines, items = items }
end

function Ctl:pageOffer()
  local m = self.model.mine
  local r = m and m.report or {}
  local lines = {}
  local items = {}
  if r.ok then
    lines[#lines + 1] = say("becomes", { game = gameName(self.opponent.version), species = r.speciesName,
      level = self:levelLabel(r.level) })
    local changes = self:changeLines(r.changes)
    if #changes == 0 then lines[#lines + 1] = say("no_change") else
      lines[#lines + 1] = say("changes")
      for _, l in ipairs(changes) do lines[#lines + 1] = l end
    end
    if r.evolves then lines[#lines + 1] = say("evolves", { species = r.speciesName }) end
    items[#items + 1] = item("offer", TEXT.item_offer)
  else
    lines[#lines + 1] = say("blocked")
    for _, l in ipairs(self:blockLines(r, self.myData)) do lines[#lines + 1] = l end
    local rec = self:recommendState()
    if rec and rec.note then lines[#lines + 1] = rec.note end
    if r.options and r.options.moves and next(r.options.moves) then
      if rec and rec.state == "pending" then
        lines[#lines + 1] = say("recommend_wait")
      elseif not rec then
        lines[#lines + 1] = say("recommend_ask")
        items[#items + 1] = item("recommend", TEXT.item_recommend)
      end
      items[#items + 1] = item("moves", TEXT.item_moves)
    end
  end
  items[#items + 1] = item("back", TEXT.item_back)
  return { title = TEXT.title_offer, lines = lines, items = items, pager = self.pager }
end

function Ctl:recommendState()
  local rec = self.recommend
  if rec and rec.mine == self.model.mine then return rec end
  return nil
end

function Ctl:startRecommend()
  if self:recommendState() then return false end
  local target = self.model:recommendTarget()
  if not target then return false end
  local Recommend = require("src.recommend.Recommend")
  self.recommend = { mine = self.model.mine, target = target, state = "pending",
    job = Recommend.request(target.generation, target.species, { client = self.recommendClient }) }
  self:pumpRecommend()
  return true
end

function Ctl:pumpRecommend()
  local rec = self.recommend
  if not (rec and rec.state == "pending") then return end
  if rec.mine ~= self.model.mine then
    require("src.recommend.Recommend").cancel(rec.job)
    self.recommend = nil
    return
  end
  local Recommend = require("src.recommend.Recommend")
  local status, why = Recommend.poll(rec.job)
  if status == "pending" then return end
  rec.state = "done"
  if status ~= "ok" then
    rec.note = say(why == "server" and "recommend_server" or "recommend_offline")
    return
  end
  local entry = Recommend.get(rec.job, rec.target.species)
  if not entry then
    rec.note = say("recommend_missing", { species = rec.target.species })
    return
  end
  local report, code = self.model:applyRecommended(entry, rec.target)
  if not report then
    rec.note = say(code == "none_legal" and "recommend_none" or "recommend_offline")
  elseif not report.ok then
    rec.note = say("recommend_partial")
  end
end

function Ctl:moveSlot()
  local m = self.model.mine
  local opts = m and m.report and m.report.options and m.report.options.moves
  if not opts then return nil end
  local slots = {}
  for slot in pairs(opts) do slots[#slots + 1] = slot end
  table.sort(slots)
  return slots[1], opts[slots[1]]
end

function Ctl:pageMoves()
  local slot, list = self:moveSlot()
  local peerData = Model.datasetFor(self.opponent.version)
  local r = self.model.mine and self.model.mine.report or {}
  local lines = { say("pick_move", { species = r.sourceName or "?", game = gameName(self.opponent.version) }) }
  local items = {}
  for _, move in ipairs(list or {}) do
    local mv = peerData and peerData.moves[move]
    if mv then
      items[#items + 1] = item("move", mv.name, { arg = { slot = slot, move = move },
        detail = { say("move_row", { type = mv.type or "?", power = mv.power, pp = mv.pp }) } })
    end
  end
  if slot then items[#items + 1] = item("remove", TEXT.item_remove, { arg = { slot = slot } }) end
  items[#items + 1] = item("back", TEXT.item_back)
  return { title = TEXT.title_moves, lines = lines, items = items }
end

function Ctl:peerOfferLines()
  local p = self.model.peer
  local lines = {}
  if p then
    lines[#lines + 1] = say("their_offer", { name = self.opponent.name, species = p.report.speciesName,
      level = self:levelLabel(p.report.level) })
  elseif self.model.refusal then
    lines[#lines + 1] = say("refused", { name = self.opponent.name })
    local code = self.model.refusal.code
    lines[#lines + 1] = "- " .. self:reasonText(code, self.model.refusal.detail)
  end
  return lines
end

function Ctl:pageWait()
  local m = self.model.mine
  local lines = {}
  if m and m.report and m.report.ok then
    lines[#lines + 1] = say("sent", { species = m.report.sourceName })
  end
  local peer = self:peerOfferLines()
  if #peer == 0 then lines[#lines + 1] = say("wait_offer", { name = self.opponent.name }) end
  for _, l in ipairs(peer) do lines[#lines + 1] = l end
  local items = { item("change", TEXT.item_change), item("stop", TEXT.item_stop) }
  return { title = TEXT.title_wait, lines = lines, items = items }
end

function Ctl:confirmLines()
  local s = self.model:summary()
  local lines = {}
  local mine, theirs = s.mine, s.theirs
  lines[#lines + 1] = say("you_send", { species = mine.sourceName, level = self:levelLabel(mine.level) })
  lines[#lines + 1] = say("becomes", { game = gameName(self.opponent.version), species = mine.speciesName,
    level = self:levelLabel(mine.level) })
  local mc = self:changeLines(mine.changes)
  if #mc > 0 then
    lines[#lines + 1] = say("my_changes")
    for _, l in ipairs(mc) do lines[#lines + 1] = l end
  end
  if mine.evolves then lines[#lines + 1] = say("evolves", { species = mine.speciesName }) end
  lines[#lines + 1] = say("you_get", { species = theirs.speciesName, level = self:levelLabel(theirs.level),
    name = self.opponent.name })
  local tc = self:changeLines(theirs.changes)
  if #tc > 0 then
    lines[#lines + 1] = say("their_changes")
    for _, l in ipairs(tc) do lines[#lines + 1] = l end
  end
  if theirs.evolves then lines[#lines + 1] = say("evolves", { species = theirs.speciesName }) end
  lines[#lines + 1] = say("final_note")
  lines[#lines + 1] = say("feature")
  return lines
end

function Ctl:pageConfirm()
  local lines = self:confirmLines()
  if self.notice then table.insert(lines, 1, self.notice) end
  local items = { item("trade", TEXT.item_trade), item("change", TEXT.item_change), item("stop", TEXT.item_stop) }
  return { title = TEXT.title_confirm, lines = lines, items = items, pager = self.pager }
end

function Ctl:pageReady()
  return { title = TEXT.title_confirm, lines = { say("wait_ready", { name = self.opponent.name }) },
    items = { item("change", TEXT.item_change), item("stop", TEXT.item_stop) } }
end

function Ctl:pageTrading()
  local key = "trading"
  if self.txn.state == "saving" and self.txn.saveFailed then key = "save_failed" end
  if self.txn.state == "unresolved" then key = "unresolved" end
  local items = {}
  if self.txn.state == "unresolved" then items[1] = item("leave", TEXT.item_ok) end
  return { title = TEXT.title_trading, lines = { say(key) }, items = items }
end

function Ctl:pageDone()
  local r = self.result or {}
  local lines = { say("done", { name = self.opponent.name, species = r.species or "?" }) }
  if r.evolvedName then lines[#lines + 1] = say("evolved", { species = r.species, into = r.evolvedName }) end
  lines[#lines + 1] = say("again")
  return { title = TEXT.title_done, lines = lines, items = { item("again", TEXT.item_yes), item("stop", TEXT.item_no) } }
end

function Ctl:pageClosed()
  local lines = { self.closedText or say("closed_other") }
  if self.closedReason then lines[2] = "- " .. self.closedReason end
  return { title = TEXT.title_closed, lines = lines, items = { item("leave", TEXT.item_ok) } }
end

local PAGES = { pick = Ctl.pagePick, offer = Ctl.pageOffer, moves = Ctl.pageMoves, wait = Ctl.pageWait,
  confirm = Ctl.pageConfirm, ready = Ctl.pageReady, trading = Ctl.pageTrading, done = Ctl.pageDone,
  closed = Ctl.pageClosed }

function Ctl:page()
  local pg = PAGES[self.step](self)
  pg.step = self.step
  if #pg.items > 0 then
    if self.cursor > #pg.items then self.cursor = #pg.items end
    if self.cursor < 1 then self.cursor = 1 end
  end
  pg.cursor = self.cursor
  pg.scroll = self.scroll
  local sel = pg.items[self.cursor]
  pg.info = sel and sel.detail or nil
  return pg
end

function Ctl:sendOffer()
  local payload, digest = self.model:payload()
  if not payload then return false end
  self.sentOffer = { payload = payload, digest = digest }
  self.prep:offer(payload, digest)
  return true
end

function Ctl:canConfirm()
  local p = self.prep
  return self.model.mine and self.model.mine.digest16 and self.model.peer ~= nil
    and p.mine.offer ~= nil and p.peer.offer ~= nil and p.state == "prep"
end

function Ctl:receivePeer()
  local offer = self.prep.peer.offer
  if not (offer and offer.payload) then return end
  if self.seenPeer == offer then return end
  self.seenPeer = offer
  self.model:receive(offer.payload, function(final) return self.adapter:validate(final) end)
  local r = self.model.refusal
  if r and self.step ~= "trading" and self.step ~= "done" then
    self.prep:cancel(Open.REFUSED .. tostring(r.code))
    self:close("refused", { name = self.opponent.name }, self:reasonText(r.code, r.detail))
  end
end

function Ctl:resetRound()
  self.model.owned = self.adapter:owned()
  self.model.mine, self.model.peer, self.model.refusal = nil, nil, nil
  self.sentOffer, self.seenPeer, self.notice = nil, nil, nil
  self.txn:nextRound()
end

function Ctl:handlePrep(e)
  local k = e.kind
  if k == "closed" then
    if self.step == "trading" or self.step == "closed" then return end
    local why = e.why
    local refused = type(e.detail) == "string" and e.detail:sub(1, #Open.REFUSED) == Open.REFUSED
      and e.detail:sub(#Open.REFUSED + 1) or nil
    if why == "cancel" and refused and e.seat ~= nil and e.seat ~= self.prep:seat() then
      self:close("refused_peer", { name = self.opponent.name }, self:reasonText(refused))
    elseif why == "cancel" and e.seat ~= nil and e.seat ~= self.prep:seat() then
      self:close("closed_cancel", { name = self.opponent.name })
    elseif why == "cancel" then
      self:close("closed_self")
    elseif why == "gone" or why == "left" then
      self:close("closed_gone", { name = self.opponent.name })
    else
      self:close("closed_other")
    end
  elseif k == "nack" and e.of == "xg_offer" and self.sentOffer then
    self.prep:offer(self.sentOffer.payload, self.sentOffer.digest)
  elseif k == "invalidated" or (k == "nack" and e.of == "xg_ready") then
    if self.step == "ready" then
      self.notice = say("changed")
      self:go("confirm")
    end
  elseif k == "go" then
    if self.txn:confirm() then
      self:go("trading")
    else
      self:close(self.txn.why and self.txn.why:find("^recheck") and "recheck" or "aborted")
    end
  elseif k == "trade_round" and self.step == "pick" then
    self:resetRound()
  end
end

function Ctl:handleTxn(e)
  if e.kind == "done" then
    local final = self.model.peer and self.model.peer.report
    local evolvedName
    if e.evolved and self.myData then
      local view = self.adapter:pack(self.adapter:at(self.model.mine.ref))
      local v = view and Project.read(view, self.myData)
      evolvedName = v and self.myData.species[v.national] and self.myData.species[v.national].name
    end
    self.result = { species = final and final.speciesName, evolvedName = evolvedName }
    self:go("done")
  elseif e.kind == "aborted" then
    self:close("aborted")
  elseif e.kind == "failed" then
    self:close("closed_other")
  end
end

function Ctl:poll(dt)
  if self.done then return {} end
  local p = self.prep
  if p then
    for _, e in ipairs(p:poll()) do self:handlePrep(e) end
  end
  for _, e in ipairs(self.txn:pump(dt or 0)) do self:handleTxn(e) end
  self:pumpRecommend()
  if self.step ~= "closed" and self.step ~= "trading" and self.step ~= "done" and p then
    self:receivePeer()
    if (self.step == "wait") and self:canConfirm() then self:go("confirm") end
    if self.step == "confirm" and not self:canConfirm() then self:go("wait") end
    if self.step == "ready" and not p.mine.ready and p.state == "prep" then
      self.notice = say("changed")
      self:go(self:canConfirm() and "confirm" or "wait")
    end
    if p.state == "closed" and self.step ~= "closed" then self:handlePrep({ kind = "closed", why = p.closed and p.closed.why }) end
  end
  local out = self.events
  self.events = {}
  return out
end

function Ctl:choose(it)
  if not it then return end
  local id = it.id
  if it.disabled then return end
  if id == "stop" or id == "leave" then
    if self.step ~= "closed" and self.step ~= "done" then self.prep:cancel("cancel") end
    self:finish()
  elseif id == "mon" then
    self.model:choose(it.arg)
    self:go("offer")
  elseif id == "back" then
    if self.step == "moves" then self:go("offer") else self:go("pick") end
  elseif id == "moves" then
    self:go("moves")
  elseif id == "recommend" then
    self:startRecommend()
  elseif id == "move" then
    self.model:stage(it.arg.slot, it.arg.move)
    self:go("offer")
  elseif id == "remove" then
    self.model:stage(it.arg.slot, false)
    self:go("offer")
  elseif id == "offer" then
    if self:sendOffer() then self:go("wait") end
  elseif id == "change" then
    self.notice = nil
    self:go("pick")
  elseif id == "trade" then
    local digest = self.txn:readyDigest()
    if digest and self.prep:ready(digest) then
      self.notice = nil
      self:go("ready")
    end
  elseif id == "again" then
    self:resetRound()
    self:go("pick")
  end
end

function Ctl:input(key)
  if self.done then return end
  local pg = self:page()
  local n = #pg.items
  if key == "up" then
    if n > 0 then self.cursor = self.cursor > 1 and self.cursor - 1 or n end
  elseif key == "down" then
    if n > 0 then self.cursor = self.cursor < n and self.cursor + 1 or 1 end
  elseif key == "left" then
    self.scroll = math.max(0, self.scroll - 1)
  elseif key == "right" then
    self.scroll = self.scroll + 1
  elseif key == "a" then
    self:choose(pg.items[self.cursor])
  elseif key == "b" then
    if self.step == "moves" then self:go("offer")
    elseif self.step == "offer" then self:go("pick")
    elseif self.step == "closed" then self:finish()
    end
  end
end

function Ctl:finish()
  if self.done then return end
  self.done = true
  self.txn:close()
end

function Open.controller(game, room, prep, opts)
  opts = opts or {}
  return Ctl.new({ game = game, prep = prep, version = opts.version, adapter = opts.adapter, roomId = opts.roomId,
    opponent = opts.opponent or Open.opponent(room, prep), recommendClient = opts.recommendClient })
end

local function isActivity(v)
  return type(v) == "table" and v.prep ~= nil and type(v.finish) == "function" and v.game ~= nil
end

function Open.trade(game, room, prep, onDone, opts)
  local act
  if isActivity(game) then
    act = game
    opts = room or {}
    game, room, prep = act.game, act.room, act.prep
    local peer = act.peer or {}
    opts.opponent = opts.opponent or { name = peer.name, version = peer.game, gen = peer.gen }
    onDone = function(result)
      if prep and prep.open and prep:open() then
        if not result then prep:cancel("cancel") end
        prep:leave()
      end
      act:finish(result and "traded" or "cancel")
    end
  end
  local ctl = Open.controller(game, room, prep, opts)
  local Renderer = require(Open.RENDERERS[ctl.gen] or Open.RENDERERS[1])
  local screen = Renderer.open(game, ctl, function()
    if onDone then onDone(ctl.result) end
  end)
  return screen, ctl
end

Open.ACTIVITIES = { "src.ui.gen2.union.Activity", "src.ui.union.gen1.Activity" }

function Open.register(Activity)
  if type(Activity) ~= "table" then return false end
  Activity.screens = Activity.screens or {}
  Activity.screens.trade = function(act) return Open.trade(act) end
  return true
end

for _, path in ipairs(Open.ACTIVITIES) do
  if type(package.loaded[path]) == "table" then Open.register(package.loaded[path]) end
end

return Open
