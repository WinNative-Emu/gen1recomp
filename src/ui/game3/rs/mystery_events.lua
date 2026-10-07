local Kit = require("src.ui.game3.rse.scene_kit")
local Pal = require("src.core.game3.pal_fade")
local Chrome = require("src.ui.game3.chrome")
local Event = require("src.core.game3.rs.mystery_event")
local MysteryGift = require("src.core.game3.mystery_gift")
local Strings = require("src.core.Strings")
local M = {VISIBLE = 4, NEWS_LINES = 8}
M.__index = M
function M.new(opts)
  opts = opts or {}
  local saved = opts.save or (not opts.session and Kit.loadRawSave())
  local session = opts.session or (saved and require("src.core.game3.save_schema_firered").fromSaveTable(saved))
  assert(session, "RS Mystery Events require an existing save")
  local self = setmetatable({game = opts.game, session = session, opts = opts, state = "fade_in",
    pal = Pal.new(), ticks = 0, step = Kit.stepper(), cursor = 1, scroll = 0}, M)
  self.pal:beginFade(Pal.ALL, 0, 16, 0, Pal.BLACK)
  return self
end
function M:message(source, vars)
  self.printer = Kit.printer(source, {speed = 2, canSpeedUp = false, ctx = {stringVars = vars or {}}})
end
function M:close()
  if self.job then MysteryGift.cancelOnline(self.job); self.job = nil end
end
function M:exit()
  self:close(); self.state = "exit"
  self.pal:beginFade(Pal.ALL, 0, 0, 16, Pal.BLACK)
end
function M:failed(why)
  self.error = why; self.loading = false
  self:close(); self:message("gSystemText_LoadingError"); self.state = "result_print"
end
function M:startFetch()
  local s = self.session
  self.job = MysteryGift.fetchOnline({family = "rs", version = s.version, session = s,
    transport = self.opts.transport, client = self.opts.client})
  self.state = "fetching"
end
function M:selected()
  return self.rows and self.rows[self.cursor]
end
local function plainIr(text)
  return require("src.core.game3.scripting.text_ir").fromAscii(text)
end
function M:writeSave()
  local save = require("src.core.game3.save_schema_firered").toSaveTable(self.session)
  local writer = self.opts.writeSave or require("src.core.SaveData").save
  local ok, written = pcall(writer, save)
  if not ok or written == false then return false end
  self.saved = save; if self.game then self.game.save = save end
  return true
end
function M:buildRows(result)
  local rows = {}
  if MysteryGift.validateSavedNews(self.session) then
    rows[#rows + 1] = {kind = "news", saved = true, label = MysteryGift.getSavedNews(self.session).titleText,
      news = MysteryGift.getSavedNews(self.session)}
  end
  for _, ev in ipairs(result.events or {}) do rows[#rows + 1] = {kind = "event", label = ev.label, bytes = ev.bytes} end
  for _, n in ipairs(result.news or {}) do
    if not MysteryGift.hasClaimedNews(self.session, n.news) then
      rows[#rows + 1] = {kind = "news", label = n.label, news = n.news}
    end
  end
  return rows
end
function M:receiveNews(row)
  local ok, why = MysteryGift.saveNewsIfNew(self.session, row.news)
  if not ok then
    self:message(plainIr(why == "had" and Strings("You already have this WONDER NEWS.") or Strings("This WONDER NEWS can't be read.")))
    self.state = "result_print"
    return
  end
  MysteryGift.claimNews(self.session, row.news)
  if not self:writeSave() then return self:failed("save_failed") end
  self:message(plainIr(Strings("The WONDER NEWS was saved.")))
  self.state = "result_print"
end
function M:frame(inp)
  self.ticks = self.ticks + 1
  if self.state == "fade_in" then
    -- pokeruby/src/mystery_event_menu.c:98
    if not self.pal:fadeActive() then self:message("gSystemText_LinkStandby"); self.state = "standby_print" end
  elseif self.state == "standby_print" then
    self.printer:run(inp)
    if not self.printer:isActive() then self:startFetch() end
  elseif self.state == "fetching" then
    if inp.new.b then Kit.playSe("SE_SELECT"); self:exit(); return end
    local status, result = MysteryGift.pollOnline(self.job)
    if status == "pending" then return end
    self.job = nil
    if status ~= "ok" then return self:failed(result) end
    self.rows = self:buildRows(result)
    if #self.rows == 0 then return self:failed("no_events") end
    self.cursor, self.scroll, self.state = 1, 0, "list"
  elseif self.state == "list" then
    if inp.new.b then Kit.playSe("SE_SELECT"); self:exit()
    elseif inp.new.up and self.cursor > 1 then
      Kit.playSe("SE_SELECT"); self.cursor = self.cursor - 1
      if self.cursor <= self.scroll then self.scroll = self.cursor - 1 end
    elseif inp.new.down and self.cursor < #self.rows then
      Kit.playSe("SE_SELECT"); self.cursor = self.cursor + 1
      if self.cursor > self.scroll + M.VISIBLE then self.scroll = self.cursor - M.VISIBLE end
    elseif inp.new.a and self:selected().kind == "news" then
      Kit.playSe("SE_SELECT"); self.newsScroll, self.state = 0, "news_view"
    elseif inp.new.a then
      -- pokeruby/src/mystery_event_menu.c:112
      Kit.playSe("SE_PIN"); self:message("gSystemText_LoadEventPressA"); self.state = "ready_print"
    end
  elseif self.state == "news_view" then
    local row = self:selected()
    local last = 0
    for i, line in ipairs(row.news.bodyText or {}) do if line ~= "" then last = i end end
    if inp.new.up and self.newsScroll > 0 then self.newsScroll = self.newsScroll - 1
    elseif inp.new.down and self.newsScroll < math.max(0, last - M.NEWS_LINES) then self.newsScroll = self.newsScroll + 1
    elseif inp.new.a and not row.saved then Kit.playSe("SE_SELECT"); self:receiveNews(row)
    elseif inp.new.a or inp.new.b then Kit.playSe("SE_SELECT"); self.state = "list" end
  elseif self.state == "ready_print" then
    self.printer:run(inp); if not self.printer:isActive() then self.state = "ready" end
  elseif self.state == "ready" then
    if inp.new.b then Kit.playSe("SE_SELECT"); self.printer = nil; self.state = "list"
    elseif inp.new.a then
      -- pokeruby/src/mystery_event_menu.c:168
      Kit.playSe("SE_SELECT"); self:message("gSystemText_DontCutLink"); self.state = "receive_print"; self.loading = true
    end
  elseif self.state == "receive_print" then
    self.printer:run(inp)
    if not self.printer:isActive() then self.state = "execute" end
  elseif self.state == "execute" then
    -- pokeruby/src/mystery_event_menu.c:291 RunMysteryEventScript
    local picked = self:selected()
    self.result = Event.run(picked.bytes, self.session, {adapters = self.opts.adapters,
      saveBlock1Address = self.opts.saveBlock1Address})
    if self.result.save and not self:writeSave() then return self:failed("save_failed") end
    self.loading = false
    self:message(self.result.message, self.result.stringVars); self.state = "result_print"
  elseif self.state == "result_print" then
    self.printer:run(inp)
    if not self.printer:isActive() then self.loading, self.state = false, "result" end
  elseif self.state == "result" then if inp.new.a then Kit.playSe("SE_SELECT"); self:exit() end
  elseif self.state == "exit" and not self.pal:fadeActive() then return "title" end
  self.pal:updateFade()
end
function M:update(input, dt)
  self.step:collect(input)
  return self.step:run(dt, function(inp) return self:frame(inp) end)
end
function M:drawList()
  local FrlgFont = require("src.ui.game3.frlg_font")
  local RomText = require("src.core.game3.rom_text")
  local colors = Kit.messageColors()
  local rows = math.min(M.VISIBLE, #self.rows)
  Chrome.stdFrame(1, 1, 28, rows * 2)
  for i = 1, rows do
    local ev = self.rows[i + self.scroll]
    FrlgFont.draw(ev.label or "", 16, 8 + (i - 1) * 16, {colors = colors})
  end
  FrlgFont.draw(RomText.plain("gText_SelectorArrow3"), 8, 8 + (self.cursor - self.scroll - 1) * 16, {colors = colors})
end
function M:drawNews()
  local FrlgFont = require("src.ui.game3.frlg_font")
  local colors = Kit.messageColors()
  local news = self:selected().news
  Chrome.stdFrame(1, 1, 28, 2)
  FrlgFont.draw(news.titleText or "", 8, 8, {colors = colors})
  Chrome.stdFrame(1, 5, 28, M.NEWS_LINES * 2)
  for i = 1, M.NEWS_LINES do
    FrlgFont.draw((news.bodyText or {})[i + self.newsScroll] or "", 8, 40 + (i - 1) * 16, {colors = colors})
  end
end
function M:draw()
  love.graphics.clear(0, 0, 0, 1)
  if self.state == "news_view" then self:drawNews()
  elseif (self.state == "list" or self.state == "ready_print" or self.state == "ready") and self.rows then self:drawList() end
  if self.printer and self.state ~= "list" then
    Chrome.stdFrame(1, 15, 28, 4)
    self.printer:draw(8, 120, {colors = Kit.messageColors()})
  end
  if self.loading then
    Chrome.stdFrame(7, 6, 16, 2)
    require("src.ui.game3.frlg_font").draw(require("src.core.game3.rom_text").plain("gSystemText_LoadingEvent"),
      56, 48, {colors = Kit.messageColors()})
  end
  Kit.drawFade(self.pal, 0)
end
function M:destroy() self:close() end
return M
