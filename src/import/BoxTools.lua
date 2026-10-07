local Kit = require("src.ui.kit.Kit")
local Theme = require("src.ui.kit.Theme")
local Store = require("src.box.Store")
local Collection = require("src.box.Collection")
local UI = require("src.import.BoxUI")
local Icons = require("src.ui.kit.Icons")
local PAL = Theme.PAL
local Tools = {}
Tools.PAGES = { "List", "Arrange", "Dashboard", "Teams", "Gifts", "Showcase", "Files", "Events", "Migration" }
Tools.SORTS = { "slot", "name", "species", "level", "hp", "attack", "defense", "speed",
  "special", "spAtk", "spDef", "nature", "ability", "gender", "trainer", "friendship" }
Tools.SORT_LABELS = { slot = "Slot order", name = "Nickname", species = "Species", level = "Level",
  hp = "HP", attack = "Attack", defense = "Defense", speed = "Speed", special = "Special",
  spAtk = "Sp. Attack", spDef = "Sp. Defense", nature = "Nature", ability = "Ability",
  gender = "Gender", trainer = "Trainer", friendship = "Friendship" }
Tools.CONTROL_ICONS = { ["stage-slot"] = "save", ["stage-background"] = "paintbrush", ["stage-pattern"] = "grid-2x2",
  ["stage-music"] = "music", ["stage-new-piece"] = "package", ["stage-x"] = "arrow-left-right",
  ["stage-y"] = "arrow-up-down", ["stage-size"] = "expand", ["stage-rotation"] = "rotate-ccw",
  sort = "arrow-up-down", ["arrange-sort"] = "arrow-up-down", ["migration-destination"] = "gamepad-2" }
local ACTION_ICONS = { ["migration-preview"] = "eye", ["exports-folder"] = "folder", arrange = "arrow-up-down",
  ["apply-marks"] = "check", compare = "arrow-left-right", ["stage-wallpaper"] = "paintbrush", ["stage-flip"] = "arrow-left-right" }

local function search(s, query, sort)
  local cache = s._toolsSearch
  if not cache or cache.state ~= s.service.state or cache.size >= 8 then
    cache = { state = s.service.state, results = {}, size = 0 }; s._toolsSearch = cache
  end
  local key = tostring(query) .. "\0" .. tostring(sort)
  if not cache.results[key] then
    cache.results[key], cache.size = Store.search(s.service.state, query, sort), cache.size + 1
  end
  return cache.results[key]
end

local function same(a, b)
  if a == b then return true end
  if type(a) ~= "table" or type(b) ~= "table" then return false end
  for k, v in pairs(a) do if not same(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

local function userExport(s, path, index)
  local fs = s.service.fs
  local bytes = fs.read(path)
  if not bytes then return nil, "Could not read the exported PNG." end
  if not fs.createDirectory("box/exports") then return nil, "Could not create the export folder." end
  local out = "box/exports/showcase-" .. index .. "-" .. os.time() .. ".png"
  local ok, why = fs.write(out, bytes)
  if not ok or fs.read(out) ~= bytes then return nil, why or "Could not verify the exported PNG." end
  local used = false
  for _, box in ipairs(s.service.state.boxes) do if box.wallpaper == path then used = true end end
  if not used and fs.remove and fs.remove(path) then require("src.box.Themes").forget(path) end
  return out
end

local function findEntry(s, id)
  local cache = s._toolsIndex
  if not cache or cache.state ~= s.service.state then
    cache = { state = s.service.state, byId = {} }; s._toolsIndex = cache
    for b = 1, Store.BOXES do
      for slot, entry in pairs(s.service.state.boxes[b].mons) do
        cache.byId[entry.id] = { box = b, slot = slot, entry = entry }
      end
    end
  end
  return cache.byId[id]
end

function Tools.navigation(imp, s, x, y, w, m)
  local gap, h = 8 * m.s, math.max(Kit.tapMin(), m.btnH)
  local navigation = { { id = "Pokémon", label = "Boxes", icon = "package" } }
  for _, page in ipairs(Tools.PAGES) do navigation[#navigation + 1] = { id = page, label = page, icon = UI.ICONS[page] } end
  local helpKey = s.toolsPage or "Box"
  UI.dropdown(imp, x, y, UI.HELP[helpKey] and w - h - gap or w, h, "tools-menu", "Tools: " .. (s.toolsPage or "Boxes"), navigation,
    s.toolsPage or "Pokémon", function(value)
      require("src.box.Showcase").stopMusic(); s.stagePlaying = nil
      UI.change(imp, s, "toolsPage", value ~= "Pokémon" and value or nil, value == "Pokémon" and -1 or 1)
      s.toolsListPage = 1
    end, UI.ICONS[s.toolsPage] or "package")
  if UI.HELP[helpKey] then UI.help(imp, helpKey, x + w - h, y, h) end
  return h + gap
end

function Tools.draw(imp, s, x, y, w, m, api)
  local top, gap, h = y, 8 * m.s, math.max(Kit.tapMin(), m.btnH)
  local function button(id, label, action, disabled, width, bx, active, icon)
    icon = icon or ACTION_ICONS[id] or (id:match("save") and "save" or id:match("remove") and "trash"
      or id:match("export") and "upload" or id:match("import") and "download"
      or id:match("select") and "check" or id:match("restore") and "undo-2"
      or id:match("name") and "pencil" or UI.ICONS[s.toolsPage] or "sliders-horizontal")
    api.button(imp, bx or x, y, width or w, h, "tools-" .. id, label, action, active, disabled, icon)
  end
  local function text(value, muted)
    y = y + Kit.textWrapped("small", value, x, y, w, muted and PAL.muted or PAL.text) + gap
  end
  local function nextRow() y = y + h + gap end
  if not api.navigationDone then y = y + Tools.navigation(imp, s, x, y, w, m) end
  local page = s.toolsPage
  if not page then return y - top, false end
  local refs = api.selected(s.selectedBox)
  local function operation(fn, message) api.perform(imp, fn, message) end
  local function namePrompt(title, initial, callback)
    require("src.import.BoxPrompt").open(imp, title, initial, 64, callback)
  end
  local function cycle(id, label, values, current, apply, column)
    local icon = Tools.CONTROL_ICONS[id] or UI.ICONS[page]
    local function display(value)
      if Tools.SORT_LABELS[value] then return Tools.SORT_LABELS[value] end
      if require("src.core.GameVersion").VERSIONS[value] then return require("src.core.GameVersion").info(value).label end
      if id == "stage-x" or id == "stage-y" then return math.floor(value * 100 + .5) .. "%" end
      if id == "stage-rotation" then return math.floor(value * 180 / math.pi + .5) .. "°" end
      return tostring(value)
    end
    local options = {}; for _, value in ipairs(values) do options[#options + 1] = { id = value, label = display(value), icon = icon } end
    local cw = column and (w - gap) / 2 or w
    UI.dropdown(imp, x + (column == 2 and cw + gap or 0), y, cw, h, "tools-" .. id,
      label .. ": " .. display(current), options, current, apply, icon)
    if column ~= 1 then nextRow() end
  end
  local function actions(items)
    local cw = (w - gap) / 2
    for i, item in ipairs(items) do
      button(item[1], item[2], item[3], item[4], cw, x + (i - 1) % 2 * (cw + gap), item[5], item[6])
      if i % 2 == 0 or i == #items then nextRow() end
    end
  end
  local function sections(key, names)
    s[key] = s[key] or names[1]
    cycle(key, "View", names, s[key], function(value) UI.change(imp, s, key, value) end)
    return s[key]
  end
  local function tiles(rows)
    local cols = w >= 700 * m.s and 4 or 2
    local cw, cardH = (w - (cols - 1) * gap) / cols, 86 * m.s
    for i, row in ipairs(rows) do
      local cx = x + (i - 1) % cols * (cw + gap)
      Theme.card(cx, y, cw, cardH, { shadow = true })
      Icons.draw(row.icon or "package", cx + 12 * m.s, y + 12 * m.s, 22 * m.s, PAL.blue, 1)
      Kit.textBold("button", tostring(row.value), cx + 42 * m.s, y + 12 * m.s, PAL.heading)
      Kit.text("small", row.label, cx + 12 * m.s, y + cardH - 29 * m.s, PAL.muted)
      if i % cols == 0 or i == #rows then y = y + cardH + gap end
    end
  end
  local function picker()
    local options = {}
    for b = 1, Store.BOXES do
      local box = s.service.state.boxes[b]
      local occupied = 0
      for _ in pairs(box.mons) do occupied = occupied + 1 end
      options[#options + 1] = { id = b, label = box.name .. " · " .. occupied .. "/60", icon = "package" }
    end
    UI.dropdown(imp, x, y, w, h, "tools-box-picker", "Box: " .. s.service.state.boxes[s.box].name,
      options, s.box, function(b) UI.change(imp, s, "toolsPage", nil, -1); s.box, s.pageBox, s.view, s.railFirst = b, 1, "box", nil end, "package")
    nextRow()
  end
  if page == "Migration" then
    local Migration=require("src.box.Migration")
    local GameVersion=require("src.core.GameVersion")
    local versions={}
    for _,version in ipairs(GameVersion.ORDER) do
      if require("src.box.Catalog").get(version).ready then versions[#versions+1]=version end
    end
    local selectionKey={}
    for _,ref in ipairs(refs) do selectionKey[#selectionKey+1]=ref.box..":"..ref.slot end
    selectionKey=table.concat(selectionKey,",")
    if s.migrationPreviewKey~=selectionKey or s.migrationPreviewState~=s.service.state then
      s.migrationPreview,s.migrationPreviewKey,s.migrationPreviewState=nil,selectionKey,s.service.state
    end
    if #versions>0 then
      s.migrationVersion=s.migrationVersion or versions[1]
      cycle("migration-destination","Destination",versions,s.migrationVersion,function(value)
        s.migrationVersion,s.migrationPreview=value,nil
      end)
      button("migration-preview","Review "..#refs.." selected",function()
        local preview,why=Migration.preview(s.service.state,refs,s.migrationVersion)
        s.migrationPreview=preview;if not preview then s.notice=why end
      end,#refs==0);nextRow()
      local preview=s.migrationPreview
      if preview then
        local options, ready = {}, 0
        for i, row in ipairs(preview.rows) do
          options[#options + 1] = { id = i, label = row.name .. (row.converted and " · Ready" or " · Blocked"), icon = row.converted and "check" or "lock" }
          if row.converted then ready = ready + 1 end
        end
        text(ready .. " ready · " .. (#preview.rows - ready) .. " blocked")
        s.migrationReviewRow = math.min(s.migrationReviewRow or 1, #preview.rows)
        local row = preview.rows[s.migrationReviewRow]
        if row then
          UI.dropdown(imp, x, y, w, h, "migration-record", row.name, options, s.migrationReviewRow,
            function(value) s.migrationReviewRow = value end, "eye"); nextRow()
          for _, line in ipairs(row.lines) do text(line, true) end
        end
        button("migration-apply","Convert selected",function()
          operation(function() return s.service:migrate(refs,s.migrationVersion,preview) end,"Migration saved with archived originals.")
          s.migrationPreview=nil
        end,not preview.allowed or preview.revision~=s.service.state.revision or s.diskStale);nextRow()
      end
    else text("Import both games first.",true) end
    if #refs==1 then
      local entry=Store.at(s.service.state,refs[1].box,refs[1].slot)
      local originals = entry and entry.archives or {}
      if #originals > 0 then
        s.archiveIndex = math.min(s.archiveIndex or 1, #originals)
        local options = {}; for i, original in ipairs(originals) do options[i] = { id = i,
          label = GameVersion.info(original.version).label .. " · " .. original.display.name, icon = "undo-2" } end
        UI.dropdown(imp, x, y, w, h, "migration-archive", "Archived original", options, s.archiveIndex,
          function(value) s.archiveIndex = value end, "undo-2"); nextRow()
        button("migration-restore","Restore original",function()
          operation(function() return s.service:restoreOriginal(refs[1],s.archiveIndex) end,"Original restored.")
          s.migrationPreview=nil
        end);nextRow()
      end
    end
    UI.help(imp, "MigrationPolicy", x + w - h, y, h); nextRow()
  elseif page == "Events" then
    local Events=require("src.box.Events")
    local source=s.sources[s.sourceIndex]
    local rows=source and Events.list(source.version,2) or {}
    if #rows==0 then text("No tickets for this game.",true) end
    local cache=s._eventStatus
    if not cache or cache.body~=s.pcBody or cache.version~=(source and source.version) then
      cache={body=s.pcBody,version=source and source.version,statuses={}};s._eventStatus=cache
      for _,row in ipairs(rows) do
        local status,why
        if s.pcSave then status,why=Events.status(s.pcSave,row) end
        cache.statuses[row.id]={status=status,why=why}
      end
    end
    local options = {}; for _, row in ipairs(rows) do options[#options + 1] = { id = row.id, label = row.name, icon = "mail" } end
    if #rows > 0 then
      local chosen = rows[1]
      for _, row in ipairs(rows) do if row.id == s.eventChoice then chosen = row end end
      s.eventChoice = chosen.id
      UI.dropdown(imp, x, y, w, h, "event-picker", chosen.name, options, chosen.id,
        function(value) s.eventChoice = value end, "mail"); nextRow()
      local row = chosen
      local status=cache.statuses[row.id].status or "Unavailable"
      text(row.route .. " · " .. status)
      local pending=status=="Ticket pending"
      button("event-"..row.id,pending and "Collect ticket" or row.method=="Record mixing"
        and "Receive ticket" or "Receive card",function()
        operation(function() return s.service:event(source,row.id,pending) end,(pending or row.method=="Record mixing")
          and "Ticket collected. Normal ship requirements still apply." or "Wonder Card received. Collect its ticket here or from the delivery person in-game.")
      end,status~="Available" and not pending);nextRow()
      if cache.statuses[row.id].why then
        UI.help(imp, "Why is this locked?", x, y, h, cache.statuses[row.id].why); nextRow()
      end
    end
  elseif page == "Files" then
    local export = function()
      local ok, path = s.service:exportGCI()
      s.notice = ok and "Exported and verified: " .. path or path
    end
    actions({ { "gci-import", "Import Box save", function() imp:chooseBoxImport() end },
      { "gci-export", "Export GCI", export, not s.service.state.gciTemplate } })
    button("exports-folder", "Exports folder", function()
      if love.system and love.system.openURL then
        if s.service.fs.createDirectory then s.service.fs.createDirectory("box/exports") end
        love.system.openURL("file://"..love.filesystem.getSaveDirectory().."/box/exports")
      end
    end, imp.android or imp.ios or imp.isNX); nextRow()
    local sync = imp._syncEngine and imp:_syncEngine()
    local busy = sync and sync:busy() or false
    local cached = s._latestBackup
    if not cached or cached.sync ~= sync or cached.busy ~= busy then
      cached = { sync = sync, busy = busy, path = not busy and sync and sync.box and sync.box:latestBackup() or nil }
      s._latestBackup = cached
    end
    local backup = cached.path
    button("sync-restore", "Restore sync backup", function()
      s._latestBackup = nil
      local ok, why = sync:restoreBoxBackup(backup)
      if ok then require("src.import.BoxPanel").refresh(imp).notice = "Box and linked saves restored."
      else s.notice = why end
    end, not backup or sync:busy(), w - h - gap)
    UI.help(imp, "Backup", x + w - h, y, h); nextRow()
  elseif page == "Showcase" then
    local Showcase = require("src.box.Showcase")
    local fullX, fullW = x, w
    local beside = w >= 740 * m.s
    if beside then w = (w - 2 * gap) * .48 end
    s.stageIndex = s.stageIndex or 1
    local function loadStage(index)
      Showcase.stopMusic()
      s.stagePlaying = nil
      s.stageDrafts=s.stageDrafts or {}
      if s.stageDraft then s.stageDrafts[s.stageIndex]=s.stageDraft end
      s.stageIndex, s.stagePiece = index, 1
      s.stageDraft = s.stageDrafts[index] or Store.copy(s.service.state.stages and s.service.state.stages[index] or Showcase.new())
      s.stageUndo = {}
    end
    if not s.stageDraft then loadStage(s.stageIndex) end
    local function edit(fn)
      local before = Store.copy(s.stageDraft)
      fn(s.stageDraft)
      if same(before, s.stageDraft) then return end
      s.stageUndo = s.stageUndo or {}
      s.stageUndo[#s.stageUndo+1] = before
      if #s.stageUndo>20 then table.remove(s.stageUndo,1) end
    end
    cycle("stage-slot", "Saved stage", {1,2,3,4,5}, s.stageIndex, loadStage)
    local draft = s.stageDraft
    text(draft.name)
    local previewH = math.max(190*m.s, math.min(300 * m.s, w*.5))
    require("src.import.ShowcaseEditor").draw(imp,s,x,y,w,previewH,m,edit)
    local previewBottom = y + previewH + gap
    if beside then x, y, w = fullX + w + 2 * gap, top, fullW - w - 2 * gap
    else y = previewBottom end
    local function addOptions()
      local out={}
      if #refs>0 then out[#out+1]={label="Add "..#refs.." selected Pokémon",icon="plus",action=function()
        local added,why=Showcase.add(s.stageDraft,refs,s.service.state)
        if added then edit(function() s.stageDraft=added end);s.stagePiece=#added.pieces else s.notice=why end
      end} end
      for _,row in ipairs(search(s,s.query,"species")) do
        out[#out+1]={label=(row.entry.display.national and ("#"..row.entry.display.national.." · ") or "")..
          row.entry.display.name,entry=row.entry,icon="package",action=function()
            local added,why=Showcase.add(s.stageDraft,{{box=row.box,slot=row.slot}},s.service.state)
            if added then edit(function() s.stageDraft=added end);s.stagePiece=#added.pieces else s.notice=why end
          end}
      end
      return out
    end
    UI.dropdown(imp,x,y,(w-gap)/2,h,"stage-add-pokemon","Add Pokémon",addOptions,nil,nil,"plus")
    local scenery={}
    for _,kind in ipairs(Showcase.PIECES) do scenery[#scenery+1]={label=kind,prop=kind,icon="package",action=function()
      if #s.stageDraft.pieces>=1500 then s.notice="The stage is full.";return end
      edit(function(d) d.pieces[#d.pieces+1]={kind=kind,x=.5,y=.5,scale=1.5,rotation=0,flip=false} end)
      s.stagePiece=#s.stageDraft.pieces
    end} end
    UI.dropdown(imp,x+(w+gap)/2,y,(w-gap)/2,h,"stage-add-scenery","Add scenery",scenery,nil,nil,"plus")
    nextRow()
    local function layerOptions()
      local out={}
      for i=#s.stageDraft.pieces,1,-1 do
        local p=s.stageDraft.pieces[i]
        local row=p.entryId and findEntry(s,p.entryId)
        out[#out+1]={id=i,label=i.." · "..(row and row.entry.display.name or p.kind or "Outside Box"),
          icon="package",entry=row and row.entry}
      end
      return out
    end
    UI.dropdown(imp,x,y,w-2*(h+gap),h,"stage-layers","Layers · front to back",layerOptions,s.stagePiece,
      function(v) s.stagePiece=v end,"copy")
    local layer=s.stagePiece
    if layer and s.stageDraft.pieces[layer] then
      button("stage-back","",function() edit(function(d) s.stagePiece=Showcase.reorder(d,layer,layer-1) end) end,
        layer==1,h,x+w-2*h-gap,false,"arrow-down")
      button("stage-front","",function() edit(function(d) s.stagePiece=Showcase.reorder(d,layer,layer+1) end) end,
        layer==#s.stageDraft.pieces,h,x+w-h,false,"arrow-up")
    end
    nextRow()
    local stageSection = sections("stageSection", { "Scene", "Placement", "Export" })
    if stageSection == "Scene" then
    cycle("stage-background", "Background", Showcase.BACKGROUNDS, draft.background, function(value) edit(function(d) d.background=value end) end, 1)
    cycle("stage-pattern", "Pattern", Showcase.PATTERNS, draft.pattern, function(value) edit(function(d) d.pattern=value end) end, 2)
    cycle("stage-music", "Music", Showcase.MUSIC, draft.music, function(value)
      edit(function(d) d.music=value end); Showcase.stopMusic(); s.stagePlaying = nil
    end)
    button("stage-play", s.stagePlaying and "Stop music" or "Play music", function()
      if s.stagePlaying then Showcase.stopMusic(); s.stagePlaying = nil
      else local ok, why = Showcase.playMusic(draft); if not ok then s.notice=why else s.stagePlaying = true end end
    end,draft.music=="Silent",w,nil,false,s.stagePlaying and "square" or "play");nextRow()
    elseif stageSection == "Placement" then
    local function pieceLabel(i)
      local placement = draft.pieces[i]
      local row = placement.entryId and findEntry(s, placement.entryId)
      return i .. " · " .. (row and row.entry.display.name or placement.kind or "Outside Box")
    end
    local function pieces()
      local out = {}
      for i in ipairs(draft.pieces) do out[i] = { id = i, label = pieceLabel(i), icon = "package" } end
      return out
    end
    s.stagePiece = math.min(s.stagePiece or 1, math.max(1, #draft.pieces))
    UI.dropdown(imp, x, y, w, h, "stage-piece", draft.pieces[s.stagePiece] and pieceLabel(s.stagePiece) or "Choose a placement",
      pieces, s.stagePiece, function(value) s.stagePiece = value end, "package"); nextRow()
    local piece=draft.pieces[s.stagePiece or 1]
    if piece then
      local positions={};for i=0,25 do positions[#positions+1]=i/25 end
      cycle("stage-x","X",positions,piece.x,function(value) edit(function() piece.x=value end) end, 1)
      cycle("stage-y","Y",positions,piece.y,function(value) edit(function() piece.y=value end) end, 2)
      cycle("stage-size","Size",{0.25,0.5,0.75,1,1.5,2,3,4},piece.scale,function(value) edit(function() piece.scale=value end) end, 1)
      cycle("stage-rotation","Turn",{-math.pi,-math.pi/2,0,math.pi/2,math.pi},piece.rotation,function(value) edit(function() piece.rotation=value end) end, 2)
      actions({ { "stage-flip", "Flip horizontally", function() edit(function() piece.flip=not piece.flip end) end }, { "stage-remove", "Remove", function()
        edit(function(d) table.remove(d.pieces,s.stagePiece or 1) end);s.stagePiece=math.max(1,math.min(s.stagePiece,#draft.pieces))
      end } })
    else text("Add a pokémon or some furniture first.", true) end
    elseif stageSection == "Export" then
      actions({ { "stage-export", "Export PNG", function()
        local ok,path=s.service:exportStage(s.stageIndex)
        if ok then ok,path=userExport(s,path,s.stageIndex) end
        s.notice=ok and "PNG exported: "..ok or path
      end, not s.service.state.stages or not s.service.state.stages[s.stageIndex] },
      { "stage-wallpaper", "Use as wallpaper", function()
        operation(function() return s.service:exportStage(s.stageIndex,s.box) end,"Wallpaper saved.")
      end, not s.service.state.stages or not s.service.state.stages[s.stageIndex] } })
    end
    button("stage-save", "Save stage", function()
      operation(function() return s.service:saveStage(s.stageIndex,draft) end,"Showcase saved.")
    end, false, (w - gap) / 2)
    UI.dropdown(imp, x + (w + gap) / 2, y, (w - gap) / 2, h, "stage-options", "Options", {
      { label = "Save and use as Box theme", icon = "paintbrush", action = function()
        operation(function()
          local ok,why=s.service:saveStage(s.stageIndex,s.stageDraft)
          if not ok then return nil,why end
          return s.service:exportStage(s.stageIndex,s.box)
        end,"Stage saved as this Box's theme.")
      end },
      { label = "Undo last edit", icon = "undo-2", disabled = not s.stageUndo or #s.stageUndo == 0,
        action = function() s.stageDraft = table.remove(s.stageUndo); s.stagePiece = 1 end },
      { label = "Rename stage", icon = "pencil", action = function()
        namePrompt("Stage name", draft.name, function(value) edit(function(d) d.name = value end) end)
      end },
    }, nil, nil, "ellipsis"); nextRow()
    y, x, w = math.max(y, previewBottom), fullX, fullW
  elseif page == "Gifts" then
    local source = s.sources[s.sourceIndex]
    local cache = s._giftProgress
    if not cache or cache.source ~= source or cache.state ~= s.service.state or cache.body ~= s.pcBody then
      local progress, why = s.service:giftProgress(source)
      cache = { source = source, state = s.service.state, body = s.pcBody, progress = progress, why = why }
      s._giftProgress = cache
    end
    local progress, why = cache.progress, cache.why
    if not progress then text(why, true)
    else
      text(progress.current .. " stored by this trainer · peak " .. progress.peak)
      local giftCols = w >= 700 * m.s and 4 or 2
      local giftW = (w - (giftCols - 1) * gap) / giftCols
      for index, award in ipairs(require("src.box.Gifts").AWARDS) do
        local status = index < progress.nextAward and "Claimed" or index == progress.nextAward
          and progress.eligible and "Ready" or "Locked"
        local cx, cardH = x + (index - 1) % giftCols * (giftW + gap), 104 * m.s
        Theme.card(cx, y, giftW, cardH, { shadow = true })
        Icons.draw(status == "Locked" and "lock" or status == "Claimed" and "check" or "package",
          cx + 12 * m.s, y + 12 * m.s, 24 * m.s, status == "Ready" and PAL.green or PAL.blue, 1)
        Kit.textBold("small", award.name .. " egg", cx + 12 * m.s, y + 43 * m.s, PAL.heading)
        Kit.text("micro", award.threshold .. " stored · " .. status, cx + 12 * m.s, y + 73 * m.s, PAL.muted)
        if index % giftCols == 0 or index == #require("src.box.Gifts").AWARDS then y = y + cardH + gap end
      end
      button("claim-egg", progress.award and "Claim " .. progress.award.name .. " egg" or "All gift eggs claimed", function()
        operation(function() return s.service:claimEgg(s.sources[s.sourceIndex]) end, "Gift egg stored. Withdraw it to hatch in the game.")
      end, not progress.eligible); nextRow()
    end
  elseif page == "List" then
    local query = Kit.textfield("box-search", x, y, w, h, s.query, "Search Pokémon")
    if query ~= s.query then s.query, s.toolsListPage = query, 1 end
    nextRow()
    cycle("sort", "Sort", Tools.SORTS, s.sort, function(value) s.sort, s.toolsListPage = value, 1 end)
    local rows = search(s, s.query, s.sort)
    local first, last, index = Kit.pageBounds(s.toolsListPage or 1, #rows, 8)
    s.toolsListPage = index
    for i = first, last do
      local row, d = rows[i], rows[i].entry.display
      local chosen = s.selectedBox[row.box .. ":" .. row.slot] ~= nil
      local bh = h + Kit.textHeight("micro") + gap
      local spriteW = 56 * m.s
      api.button(imp, x + spriteW, y, w - spriteW, bh, "list-" .. row.entry.id,
        (chosen and "Selected · " or "") .. d.name .. " · Lv. " .. d.level
          .. " · " .. s.service.state.boxes[row.box].name .. " / " .. row.slot, function()
        api.selectEntry(s, "box", row)
      end, chosen, false, "package")
      local art = require("src.box.Catalog").art(row.entry)
      if art then require("src.online.OnlineSprites").drawIcon(art, x + 3 * m.s,
        y + (bh - 48 * m.s) / 2, 48 * m.s, math.floor((s.artTime or 0) * 4)) end
      Kit.text("micro", Kit.ellipsize("micro", table.concat({ d.gender or "—", d.nature or "—", d.ability or "—",
        "HP " .. tostring(d.hp or "?"), "Atk " .. tostring(d.attack or "?"), "Def " .. tostring(d.defense or "?"),
        "Spe " .. tostring(d.speed or "?") }, " · "), w - spriteW - 20 * m.s),
        x + spriteW + 10 * m.s, y + h, chosen and PAL.inverse or PAL.muted)
      y = y + bh + gap
    end
    if #rows == 0 then text("No Pokémon match this view.", true) end
    cycle("list-page", "Page", (function()
      local pages = {}; for i = 1, math.max(1, math.ceil(#rows / 8)) do pages[i] = i end; return pages
    end)(), index, function(value) s.toolsListPage = value end)
    actions({ { "summary", "Summary", function() api.openSummary(s) end, not s.inspect, false, "eye" },
      { "compare", "Compare selected", function() s.comparison = not s.comparison end, #refs == 0 or #refs > 6 } })
    if s.comparison and #refs > 0 and #refs <= 6 then
      local fields = { {"species","Species"},{"level","Level"},{"types","Types"},{"gender","Gender"},
        {"nature","Nature"},{"ability","Ability"},{"hp","HP"},{"attack","Attack"},{"defense","Defense"},
        {"speed","Speed"},{"special","Special"},{"spAtk","Sp. Atk"},{"spDef","Sp. Def"},
        {"friendship","Friendship"},{"trainer","Trainer"},{"item","Held item"},{"moves","Moves"} }
      local entries = {}
      for _,ref in ipairs(refs) do
        local entry=Store.at(s.service.state,ref.box,ref.slot)
        if entry then entries[#entries+1]=entry end
      end
      local labelW=math.min(w*.22,110*m.s)
      local columns=math.max(1,math.min(6,math.floor((w-labelW-gap)/(105*m.s))))
      for start=1,#entries,columns do
        local count=math.min(columns,#entries-start+1)
        local cellW=(w-labelW-gap)/count
        local headerH=0
        for column=1,count do
          local entry=entries[start+column-1]
          headerH=math.max(headerH,Kit.textWrapped("small",entry.display.name,
            x+labelW+gap+(column-1)*cellW,y,cellW-gap,PAL.heading))
        end
        y=y+headerH+gap
        for _,field in ipairs(fields) do
          local values,applicable={},false
          for column=1,count do
            local value=entries[start+column-1].display[field[1]]
            if value~=nil then applicable=true end
            values[column]=value==nil and "N/A" or value=="" and "None" or tostring(value)
          end
          if applicable then
            local rowH=Kit.textWrapped("small",field[2],x,y,labelW,PAL.muted)
            for column=1,count do
              rowH=math.max(rowH,Kit.textWrapped("small",values[column],
                x+labelW+gap+(column-1)*cellW,y,cellW-gap,PAL.text))
            end
            y=y+rowH+gap
          end
        end
        y=y+gap
      end
    end
  elseif page == "Filters" then
    if (s.filterQuery or "") ~= s.query then s.filters = nil end
    s.filters = s.filters or {}
    local function query()
      local parts = {}
      for _, key in ipairs({ "type", "gender", "nature", "ability", "trainer", "mark" }) do
        local value = s.filters[key]
        if value and value ~= "Any" then
          for piece in value:lower():gmatch('[^"]+') do parts[#parts + 1] = key .. ':"' .. piece .. '"' end
        end
      end
      if s.filters.shiny then parts[#parts + 1] = "shiny" end
      if s.filters.egg then parts[#parts + 1] = "egg" end
      s.query, s.pageBox, s.pagePC = table.concat(parts, " "), 1, 1
      s.filterQuery = s.query
    end
    local choiceCache = s._filterChoices
    if not choiceCache or choiceCache.state ~= s.service.state then
      choiceCache = { state = s.service.state }; s._filterChoices = choiceCache
    end
    local function choices(key)
      if choiceCache[key] then return choiceCache[key] end
      local found, out = {}, { "Any" }
      for _, row in ipairs(search(s, "", "slot")) do
        local value = row.entry.display[key == "type" and "types" or key]
        if value then
          local values = key == "type" and (function()
            local types = {}; for item in value:gmatch("[^/]+") do types[#types + 1] = item:match("^%s*(.-)%s*$") end
            return types
          end)() or { tostring(value) }
          for _, v in ipairs(values) do if v ~= "" and not found[v] then found[v], out[#out + 1] = true, v end end
        end
      end
      table.sort(out, function(a, b) if a == "Any" then return true elseif b == "Any" then return false end; return a < b end)
      choiceCache[key] = out
      return out
    end
    for index, key in ipairs({ "type", "gender", "nature", "ability", "trainer" }) do
      cycle("filter-" .. key, key:gsub("^%l", string.upper), choices(key), s.filters[key] or "Any",
        function(value) s.filters[key] = value; query() end, index % 2 == 1 and 1 or 2)
    end
    cycle("filter-mark", "Marked", { "Any", "circle", "square", "triangle", "heart" }, s.filters.mark or "Any",
      function(value) s.filters.mark = value; query() end, 2)
    for index, key in ipairs({ "shiny", "egg" }) do
      button("filter-" .. key, key:gsub("^%l", string.upper) .. " only", function()
        s.filters[key] = not s.filters[key]; query()
      end, false, (w - gap) / 2, x + (index - 1) * (w + gap) / 2, s.filters[key], "check")
    end
    nextRow()
    actions({ { "filter-clear", "Clear", function() s.filters, s.query, s.filterQuery = {}, "", "" end, false, false, "x" },
      { "filter-view", "Show Pokémon", function() UI.change(imp, s, "toolsPage", nil, -1); s.view = "box" end } })
  elseif page == "Arrange" then
    s.arrangeSection = s.arrangeSection or "Sort"
    local section = s.arrangeSection
    local bw = (w - h - 2 * gap) / 2
    UI.button(imp, x, y, bw, h, "tools-arrange-sort-tab", "Sort a box",
      function() UI.change(imp, s, "arrangeSection", "Sort") end,{face="tab",active=section=="Sort",icon="arrow-up-down"})
    UI.button(imp, x + bw + gap, y, bw, h, "tools-arrange-auto-tab", "Auto Box",
      function() UI.change(imp, s, "arrangeSection", "Auto Box") end,{face="tab",active=section=="Auto Box",icon="arrow-left-right"})
    UI.dropdown(imp, x + w - h, y, h, h, "tools-arrangeSection", "",
      UI.values({ "Move", "Sort", "Auto Box", "Labels" }, nil, "ellipsis"), section,
      function(v) UI.change(imp, s, "arrangeSection", v) end, "ellipsis")
    nextRow()
    if section == "Move" then
    actions({ { "select-box", "Select whole Box", function()
      s.selectedBox, s.multi = {}, true
      for slot in pairs(s.service.state.boxes[s.box].mons) do
        s.selectedBox[s.box .. ":" .. slot] = { box = s.box, slot = slot }
      end
    end }, { "move-group", "Move / swap " .. #refs, function()
      s.moving, s.view, s.toolsPage, s.query, s.sort = refs, "box", nil, "", "slot"
      s.notice = "Choose the group's first destination slot. Occupied slots swap back."
    end, #refs == 0 } })
    picker()
    elseif section == "Sort" or section == "Auto Box" then
      y = y + require("src.import.BoxOrganizer").draw(imp, s, x, y, w, m, api, section == "Sort" and "sort" or "rules")
    elseif section == "Labels" then
    s.editMarkings = s.editMarkings or 0
    for i, label in ipairs({ "Circle", "Square", "Triangle", "Heart" }) do
      local mask = 2^(i - 1)
      local checked = math.floor(s.editMarkings / mask) % 2 == 1
      button("mark-" .. i, label, function()
        s.editMarkings = s.editMarkings + (checked and -mask or mask)
      end, false, (w - gap) / 2, x + (i - 1) % 2 * ((w - gap) / 2 + gap), checked, "check")
      if i % 2 == 0 then nextRow() end
    end
    actions({ { "apply-marks", "Apply marks", function()
      operation(function() return s.service:mark(refs, s.editMarkings) end, "Markings saved.")
    end, #refs == 0 }, { "tags", "Set tags", function()
      namePrompt("Local tags", "", function(value)
        operation(function() return s.service:mark(refs, s.editMarkings, value) end, "Tags saved.")
      end)
    end, #refs == 0, false, "pencil" } })
    end
  elseif page == "Dashboard" then
    local dash = s._dashboard
    if not dash or dash.state ~= s.service.state or dash.save ~= s.pcSave then
      dash = { state = s.service.state, save = s.pcSave, report = Collection.dashboard(s.service.state, s.pcSave) }
      s._dashboard = dash
    end
    local report = dash.report
    tiles({ { value = report.total, label = "Stored", icon = "package" }, { value = report.species, label = "Species", icon = "book-open" },
      { value = report.eggs, label = "Eggs", icon = "heart" }, { value = report.shiny, label = "Shiny", icon = "award" } })
    text(report.caught .. " caught in the linked game", true)
    local games = {}; for game in pairs(report.byGame) do games[#games + 1] = game end; table.sort(games)
    for _, game in ipairs(games) do text(require("src.core.GameVersion").info(game).label .. ": " .. report.byGame[game]) end
    local forms = {}; for form in pairs(report.forms) do forms[#forms + 1] = form end; table.sort(forms)
    text("Unown forms held: " .. (#forms == 0 and "None" or table.concat(forms, ", ")))
    local duplicateOptions = {}
    if not s._nationalNames then
      s._nationalNames = {}
      local Catalog, GameVersion = require("src.box.Catalog"), require("src.core.GameVersion")
      local versions = { "emerald" }; for i = #GameVersion.ORDER, 1, -1 do versions[#versions + 1] = GameVersion.ORDER[i] end
      for _, version in ipairs(versions) do
        local data = Catalog.get(version)
        if data.names then
          for dex, species in pairs(data.national.toSpecies or {}) do
            s._nationalNames[dex] = s._nationalNames[dex] or data.names[species]
          end
        else
          for _, def in pairs(data.pokemon or {}) do
            if def.dex then s._nationalNames[def.dex] = s._nationalNames[def.dex] or def.name end
          end
        end
      end
    end
    local function speciesName(dex) return s._nationalNames[dex] or "Species #" .. dex end
    for _, row in ipairs(report.duplicates) do
      duplicateOptions[#duplicateOptions + 1] = { id = row.dex, label = speciesName(row.dex) .. " · " .. row.count .. " held", icon = "copy" }
    end
    UI.dropdown(imp, x, y, w, h, "duplicates", "Duplicates · " .. #report.duplicates, duplicateOptions, nil,
      function(dex) UI.change(imp, s, "toolsPage", "List"); s.query = "dex:" .. dex end, "copy"); nextRow()
    local missing = {}; for _, dex in ipairs(report.missing) do missing[#missing + 1] = { id = dex, label = speciesName(dex), icon = "book-open" } end
    UI.dropdown(imp, x, y, w, h, "missing", "Missing species · " .. #missing, missing, nil,
      function(dex) UI.open(imp, speciesName(dex), {}); imp._boxPopup.message = "you don’t have this species in Box yet." end, "book-open"); nextRow()
  elseif page == "Teams" then
    button("save-team", "Save selected team (" .. #refs .. ")", function()
      namePrompt("Team name", "", function(value)
        operation(function() return s.service:preset(value, refs) end, "Team preset saved.")
      end)
    end, #refs == 0 or #refs > 6); nextRow()
    local presets = s.service.state.presets or {}
    s.teamIndex = math.min(s.teamIndex or 1, math.max(1, #presets))
    if #presets > 0 then
      local options = {}; for index, preset in ipairs(presets) do options[index] = { id = index, label = preset.name, icon = "users" } end
      UI.dropdown(imp, x, y, w, h, "team-picker", presets[s.teamIndex].name, options, s.teamIndex,
        function(value) s.teamIndex = value end, "users"); nextRow()
      local index, preset = s.teamIndex, presets[s.teamIndex]
      local members, missing = {}, false
      for _, id in ipairs(preset.ids) do
        local row = findEntry(s, id)
        members[#members + 1] = row and row.entry.display.name or "Outside Box (#" .. id .. ")"
        if not row then missing = true end
      end
      text(table.concat(members, " · "))
      actions({ { "select-team-" .. index, "Select team", function()
        s.selectedBox = {}
        for _, id in ipairs(preset.ids) do
          local row = Store.find(s.service.state, id)
          if row then s.selectedBox[row.box .. ":" .. row.slot] = { box = row.box, slot = row.slot } end
        end
      end, missing }, { "deploy-team-" .. index, "Send team", function()
        operation(function() return s.service:deployPreset(s.sources[s.sourceIndex], index) end, "Team deployed.")
      end, missing or not s.sources[s.sourceIndex], false, "arrow-right" } })
    end
  end
  return y - top, true
end

return Tools
