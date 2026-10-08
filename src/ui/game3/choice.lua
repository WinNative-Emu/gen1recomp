-- Yes/No + multichoice (pret yesnobox / multichoice / multichoicegrid). Writes VAR_RESULT via callback.

local Window = require("src.ui.game3.window")
local Display = require("src.core.game3.display")
local RomText = require("src.core.game3.rom_text")
local SE = require("src.core.game3.se_ids")

local Choice = {}

Choice.active = false
Choice.kind = nil -- "yesno" | "multi"
Choice.options = nil
Choice.cursor = 1
Choice.done = nil
Choice.left = nil
Choice.top = nil
Choice.cols = 1
Choice.ignoreBPress = false

function Choice.isOpen()
  return Choice.active and true or false
end

-- pokefirered/src/main.c:480
function Choice.reset()
  Choice.active = false
  Choice.kind = nil
  Choice.options = nil
  Choice.cursor = 1
  Choice.done = nil
  Choice.left = nil
  Choice.top = nil
  Choice.cols = 1
  Choice.ignoreBPress = false
  Choice.style = nil
  return true
end

local function uiProfile()
  local okR, Runtime = pcall(require, "src.core.game3.runtime")
  local session = okR and type(Runtime) == "table" and Runtime.getSession and Runtime.getSession() or nil
  local okP, Profile = pcall(require, "src.core.game3.profile")
  local okF, row = pcall(function() return okP and Profile.forSession(session) end)
  return okF and type(row) == "table" and type(row.ui) == "table" and row.ui or nil
end

function Choice.fieldLayout()
  local ui = uiProfile()
  return ui and ui.saveMenu == "rs" and "rs" or "frlg"
end

-- pokeemerald/src/menu.c:98, pokefirered/src/new_menu_helpers.c:48
function Choice.yesNoWidth()
  local ui = uiProfile()
  return ui and ui.saveMenu == "rse" and 5 or 6
end

function Choice.yesNo(cb, layout)
  Choice.active = true
  Choice.kind = "yesno"
  layout = layout or {}
  Choice.style = layout.style
  if layout.style == "battle" then
    -- pokefirered/src/battle_message.c:1288
    local yes, no = RomText.plain("gText_BattleYesNoChoice"):match("^(.-)\n(.*)$")
    Choice.options = { yes, no }
  else
    -- pokefirered/src/strings.c:414
    Choice.options = { RomText.plain("gText_Yes"), RomText.plain("gText_No") }
  end
  Choice.cursor = 1
  Choice.done = cb
  if layout.style == "battle" then
    Choice.left = tonumber(layout.left) or 24
    Choice.top = tonumber(layout.top) or 9
  elseif Choice.fieldLayout() == "rs" then
    -- pokeruby/src/script_menu.c:765, pokeruby/src/start_menu.c:698
    Choice.left = tonumber(layout.left) or 20
    Choice.top = tonumber(layout.top) or 8
  else
    -- pokeemerald/src/script_menu.c:198, pokefirered/src/script_menu.c:864
    Choice.left = 21
    Choice.top = 9
  end
  Choice.maxRight = nil
  Choice.cols = 1
  Choice.ignoreBPress = layout.ignoreBPress or false
end

function Choice.multi(options, defaultIdx, cb, layout)
  Choice.active = true
  Choice.kind = "multi"
  Choice.style = nil
  Choice.options = options or {}
  Choice.cursor = (tonumber(defaultIdx) or 0) + 1
  if Choice.cursor < 1 then Choice.cursor = 1 end
  if Choice.cursor > #Choice.options then Choice.cursor = 1 end
  Choice.done = cb
  layout = layout or {}
  Choice.left = tonumber(layout.left) or (Display.COLS - 10)
  Choice.top = tonumber(layout.top) or 5
  Choice.maxRight = tonumber(layout.maxRight)
  Choice.cols = tonumber(layout.cols) or 1
  Choice.ignoreBPress = layout.ignoreBPress or false
end

function Choice.move(dy, dx)
  if not Choice.active or not Choice.options then return end
  local n = #Choice.options
  if n < 1 then return end
  local cols = Choice.cols or 1
  if cols <= 1 then
    local delta = dy or 0
    if delta == 0 and dx then delta = dx end
    if delta ~= 0 then
      Choice.cursor = ((Choice.cursor - 1 + delta) % n) + 1
      pcall(function() require("src.core.game3.audio").playSe(SE.SE_SELECT) end)
    end
    return
  end

  -- 2D Grid navigation
  local rows = math.ceil(n / cols)
  local cur = Choice.cursor - 1
  local curCol = cur % cols
  local curRow = math.floor(cur / cols)

  if dy and dy ~= 0 then
    curRow = (curRow + dy) % rows
  end
  if dx and dx ~= 0 then
    curCol = (curCol + dx) % cols
  end

  local target = curRow * cols + curCol
  if target >= n then
    target = n - 1
  end
  if target + 1 ~= Choice.cursor then
    Choice.cursor = target + 1
    pcall(function() require("src.core.game3.audio").playSe(SE.SE_SELECT) end)
  end
end

function Choice.confirm()
  if not Choice.active then return end
  pcall(function() require("src.core.game3.audio").playSe(SE.SE_SELECT) end)
  local cb = Choice.done
  local kind = Choice.kind
  local cursor = Choice.cursor
  Choice.active = false
  Choice.kind = nil
  Choice.options = nil
  Choice.cols = 1
  Choice.ignoreBPress = false
  Choice.done = nil
  if not cb then return end
  if kind == "yesno" then
    cb(cursor == 1)
  else
    cb(cursor - 1)
  end
end

function Choice.cancel()
  if not Choice.active then return end
  if Choice.ignoreBPress then
    return
  end
  pcall(function() require("src.core.game3.audio").playSe(SE.SE_SELECT) end) -- pokefirered/src/menu_helpers.c:57
  local cb = Choice.done
  local kind = Choice.kind
  Choice.active = false
  Choice.kind = nil
  Choice.options = nil
  Choice.cols = 1
  Choice.ignoreBPress = false
  Choice.done = nil
  if not cb then return end
  if kind == "yesno" then
    cb(false)
  else
    cb(127) -- FRLG B-cancel often 0x7F
  end
end

function Choice.autoPick(indexOrYes)
  if not Choice.active then return end
  if Choice.kind == "yesno" then
    Choice.cursor = indexOrYes and 1 or 2
  else
    Choice.cursor = (tonumber(indexOrYes) or 0) + 1
  end
  Choice.confirm()
end

-- pokefirered/src/menu.c:531
function Choice.drawYesNo(L, Tp, cursor, labels)
  if Choice.fieldLayout() == "rs" then
    -- pokeruby/src/menu.c:608
    Window.stdFrame(Window.template(L + 1, Tp + 1, 5, 4))
    for i, lab in ipairs(labels) do
      -- pokeruby/src/menu.c:602
      Window.printPx(lab, (L + 1) * 8, (Tp + 1 + 2 * (i - 1)) * 8)
    end
    -- pokeruby/src/menu.c:721, :750
    require("src.ui.game3.rs.menu_cursor").draw((L + 1) * 8, (Tp + 1) * 8 + (cursor - 1) * 16, 40)
    return
  end
  Window.stdFrame(Window.template(L, Tp, Choice.yesNoWidth(), 4))
  for i, lab in ipairs(labels) do
    local rowPx = Tp * 8 + 2 + (i - 1) * 14
    if i == cursor then Window.cursorPx(L * 8, rowPx) end
    Window.printPx(lab, L * 8 + 8, rowPx)
  end
end

function Choice.battleYesNoGeometry(layout, L, Tp)
  L, Tp = L or 24, Tp or 9
  if layout == "rs" then
    -- pokeruby/src/battle_script_commands.c:5273
    return {
      frame = { left = L + 1, top = Tp, width = 4, height = 4 },
      cursor = "rs", cursorX = (L + 1) * 8, cursorWidth = 32,
      -- pokeruby/src/battle_script_commands.c:9617
      rowY = function(i) return Tp * 8 + (i - 1) * 16 end,
      -- pokeruby/src/battle_script_commands.c:5274
      textX = (L + 1) * 8, textDy = 0,
    }
  elseif layout == "emerald" then
    -- pokeemerald/include/battle_script_commands.h:11
    return {
      frame = { left = L + 1, top = Tp, width = 4, height = 4 },
      -- pokeemerald/src/battle_script_commands.c:10206
      cursor = "arrow", cursorX = (L + 1) * 8,
      rowY = function(i) return (Tp + (i - 1) * 2) * 8 end,
      -- pokeemerald/src/battle_message.c:1600
      textX = (L + 2) * 8, textDy = 1,
    }
  end
  -- pokefirered/src/battle_script_commands.c:5149
  return {
    frame = { left = L, top = Tp, width = 5, height = 4 },
    -- pokefirered/src/battle_script_commands.c:9775
    cursor = "arrow", cursorX = L * 8,
    rowY = function(i) return (Tp + (i - 1) * 2) * 8 end,
    -- pokefirered/src/battle_message.c:2570
    textX = (L + 1) * 8, textDy = 2,
  }
end

-- pokeruby/src/script_menu.c:626
local function rsWidthTiles(labels)
  local FrlgFont = require("src.ui.game3.frlg_font")
  local w = 0
  for _, lab in ipairs(labels) do
    local px = FrlgFont.measure(tostring(lab or ""))
    local tiles = math.floor((px + 7) / 8)
    if tiles > w then w = tiles end
  end
  return w
end

-- pokeruby/src/menu.c:458
local function rsGridRows(n, cols)
  if cols == 1 or cols == n or not (math.floor(n / 2) < cols or n % 2 ~= 0) then
    return math.floor(n / cols)
  end
  return math.floor(n / cols) + 1
end

function Choice.rsMultiGeometry(labels, left, top, cols)
  local n = #labels
  local w = rsWidthTiles(labels)
  local tx, ty = left, top
  if cols <= 1 then
    -- pokeruby/src/script_menu.c:647
    if tx + w > 29 then tx = 29 - w end
    local cells = {}
    for i = 1, n do
      cells[i] = { x = tx * 8, y = (ty + 2 * (i - 1)) * 8 }
    end
    return { frame = { tx, ty, w, 2 * n }, cells = cells, barWidth = w * 8 }
  end
  -- pokeruby/src/menu.c:454
  local rows = rsGridRows(n, cols)
  local total = cols * (w + 1) - 1
  local cells = {}
  for i = 1, n do
    local c = (i - 1) % cols
    local r = math.floor((i - 1) / cols)
    cells[i] = { x = (tx + c * (w + 1)) * 8, y = (ty + 2 * r) * 8 }
  end
  return { frame = { tx, ty, total, 2 * rows }, cells = cells, barWidth = w * 8 }
end

-- pokeruby/src/script_menu.c:655, pokeruby/src/menu.c:524
function Choice.drawRsMulti()
  local g = Choice.rsMultiGeometry(Choice.options, Choice.left or 20, Choice.top or 5, Choice.cols or 1)
  Window.stdFrame(Window.template(g.frame[1], g.frame[2], g.frame[3], g.frame[4]))
  for i, lab in ipairs(Choice.options) do
    Window.printPx(lab, g.cells[i].x, g.cells[i].y)
  end
  local cur = g.cells[Choice.cursor] or g.cells[1]
  if cur then
    -- pokeruby/src/menu.c:748
    require("src.ui.game3.rs.menu_cursor").draw(cur.x, cur.y, g.barWidth)
  end
end

function Choice.draw()
  if not Choice.active or not Choice.options then return end
  if Choice.style == "battle" and Choice.kind == "yesno" then
    local okB, BattleChrome = pcall(require, "src.ui.game3.battle_chrome")
    local layout = okB and type(BattleChrome) == "table" and BattleChrome.layout and BattleChrome.layout() or "frlg"
    local g = Choice.battleYesNoGeometry(layout, Choice.left, Choice.top)
    local okR, Runtime = pcall(require, "src.core.game3.runtime")
    local session = okR and type(Runtime) == "table" and Runtime.getSession and Runtime.getSession()
    local opts = type(session) == "table" and session.options or nil
    local frameType = tonumber(type(opts) == "table" and opts.frameType or nil) or 0
    -- pokefirered/src/battle_bg.c:694
    Window.userFrame(Window.template(g.frame.left, g.frame.top, g.frame.width, g.frame.height), frameType)
    for i, lab in ipairs(Choice.options) do
      local rowPx = g.rowY(i)
      if i == Choice.cursor and g.cursor == "arrow" then Window.cursorPx(g.cursorX, rowPx) end
      Window.printPx(lab, g.textX, rowPx + g.textDy)
    end
    if g.cursor == "rs" then
      require("src.ui.game3.rs.menu_cursor").draw(g.cursorX, g.rowY(Choice.cursor), g.cursorWidth)
    end
    return
  end

  if Choice.kind == "yesno" then
    Choice.drawYesNo(Choice.left, Choice.top, Choice.cursor, Choice.options)
    return
  end

  if Choice.fieldLayout() == "rs" then
    Choice.drawRsMulti()
    return
  end

  local n = #Choice.options
  local cols = Choice.cols or 1
  if cols <= 1 then
    local tw = 8
    for _, lab in ipairs(Choice.options) do
      local need = math.min(18, math.max(6, math.floor(#tostring(lab) * 0.7) + 2))
      if need > tw then tw = need end
    end
    local th = math.max(2, math.ceil((n * Window.OPTION_HEIGHT) / 8))
    local tx = Choice.left or (Display.COLS - tw - 2)
    if Choice.kind == "multi" and Choice.maxRight and tx + tw > Choice.maxRight then
      tx = Choice.maxRight - tw
    end
    local ty = Choice.top or 5
    Window.stdFrame(Window.template(tx, ty, tw, th))
    local leftPx = tx * 8
    local topPx = ty * 8
    for i, lab in ipairs(Choice.options) do
      local yPx = Window.menuRowPx(topPx, i)
      if i == Choice.cursor then Window.cursorPx(leftPx, yPx) end
      Window.printPx(lab, leftPx + Window.CURSOR_WIDTH, yPx)
    end
  else
    -- Multi-column grid
    local rows = math.ceil(n / cols)
    local colTileWidths = {}
    for c = 1, cols do
      local maxW = 4
      for r = 1, rows do
        local idx = (r - 1) * cols + c
        if idx <= n then
          local lab = tostring(Choice.options[idx] or "")
          local need = math.floor(#lab * 0.7) + 2
          if need > maxW then maxW = need end
        end
      end
      colTileWidths[c] = maxW
    end
    local totalTileW = 0
    for c = 1, cols do
      totalTileW = totalTileW + colTileWidths[c]
    end
    local th = math.max(2, math.ceil((rows * Window.OPTION_HEIGHT) / 8))
    local tx = Choice.left or 2
    if Choice.maxRight and tx + totalTileW > Choice.maxRight then
      tx = Choice.maxRight - totalTileW
    end
    if tx < 0 then tx = 0 end
    local ty = Choice.top or 5
    Window.stdFrame(Window.template(tx, ty, totalTileW, th))

    local topPx = ty * 8
    for i, lab in ipairs(Choice.options) do
      local idx0 = i - 1
      local c = (idx0 % cols) + 1
      local r = math.floor(idx0 / cols) + 1

      local colOffsetTiles = 0
      for prevC = 1, c - 1 do
        colOffsetTiles = colOffsetTiles + colTileWidths[prevC]
      end
      local colLeftPx = (tx + colOffsetTiles) * 8
      local yPx = Window.menuRowPx(topPx, r)

      if i == Choice.cursor then
        Window.cursorPx(colLeftPx, yPx)
      end
      Window.printPx(lab, colLeftPx + Window.CURSOR_WIDTH, yPx)
    end
  end
end

return Choice
