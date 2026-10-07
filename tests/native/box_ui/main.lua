local root = assert(os.getenv("BOX_UI_REPO"))
io.stdout:setvbuf("no")
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path
local imp
local co, pending, controls, checks = nil, nil, {}, 0
local awards={}
local function check(value, label) checks = checks + 1; assert(value, label) end
function love.load()
  local CacheFs = require("src.import.CacheFs")
  local CacheBlob = require("src.import.CacheBlob")
  CacheFs.readAt = function(path)
    local file
    for cache in assert(os.getenv("BOX_UI_CACHES")):gmatch("[^:]+") do
      file=io.open(cache.."/"..path,"rb")
      if file then break end
    end
    if not file then return nil end
    local bytes = file:read("*a"); file:close()
    return CacheBlob.decode(path, bytes)
  end
  local SaveData = require("src.core.SaveData")
  local Serializer = require("src.core.SaveSerializer")
  local Store = require("src.box.Store")
  local Service = require("src.box.Service")
  local Catalog = require("src.box.Catalog")
  local state = Store.new()
  local save = { version = "emerald", generation = 3, engine = "game3", name = "Demo",
    trainerId=42,secretId=97,flags={},vars={},modData={},bag={pockets={}},
    party = { { species = 25, level = 20, hp = 52, otId = 42, otSecretId = 97, personality = 345 } },
    storage = { currentBox = 1, boxes = { { name = "Demo PC", wallpaper = 1, mons = {} } } } }
  local species = {1,4,7,25,133,152,155,158,175,246,151,251,52,54,56,58,60,63,66,69,72,74,77,79,81,83,84,86,88,90,92,95,96,98,100,102,104,108,109,111,113,114,115,116,118,120,122,123,127,128,129,131,132,137,147,149,154,157,160,165}
  for i, id in ipairs(species) do
    local mon = { species = id, level = 12 + i, hp = 40, personality = i * 1001,
      otId = 42, otSecretId = 97, otName = "Demo", moves = { 33,45 }, pp={30,35}, friendship=70, language=2,
      ivs={hp=15,atk=15,def=15,spe=15,spa=15,spd=15},evs={},heldItem=0,
      exp=require("src.core.game3.summary_data").expForLevel(Catalog.get("emerald").meta[id].growthRate,12+i), metGame=3,metLevel=5,metLocation=7,pokeball=4 }
    if i == 2 then
      mon.markings, mon.pokerus, mon.modernFatefulEncounter = 5, 0x23, false
      mon.contest = { cool=0, beauty=80, cute=70, smart=45, tough=54, sheen=15 }
      mon.ribbons = { cool=2, champion=1, artist=1 }
    end
    if i <= 24 then save.storage.boxes[1].mons[i] = Store.copy(mon) end
    state.boxes[1].mons[i] = { id = i, version = "emerald", generation = 3,
      mon = mon, display = Catalog.describe("emerald", mon) }
  end
  state.boxes[1].name, state.boxes[2].name, state.boxes[3].name = "Kanto collection", "Starters", "Rare finds"
  for i = 1, 12 do
    local entry = Store.copy(state.boxes[1].mons[i]); entry.id = 60 + i
    state.boxes[2].mons[i] = entry
  end
  for i = 1, 6 do
    local entry = Store.copy(state.boxes[1].mons[i + 8]); entry.id = 72 + i
    state.boxes[3].mons[i * 3] = entry
  end
  state.nextId = 79
  local Showcase=require("src.box.Showcase")
  local stage=Showcase.new();stage.name="Starter garden";stage.pattern="Dots"
  stage=assert(Showcase.add(stage,{{box=1,slot=1},{box=1,slot=2},{box=1,slot=3}},state))
  for i,piece in ipairs(stage.pieces) do piece.x=.28+(i-1)*.22;piece.y=.5;piece.scale=1.4 end
  stage.pieces[#stage.pieces+1]={kind="Platform",x=.5,y=.75,scale=2,rotation=0,flip=false}
  state=assert(Showcase.save(state,1,stage))
  local fs = SaveData.persistenceFs()
  fs.createDirectory("box"); fs.createDirectory("saves/emerald")
  fs.write(Store.PATH, Serializer.encode(state))
  fs.write("saves/emerald/slot1.lua", Serializer.encode(save))
  local second = Store.copy(save); second.name = "Other trainer"; second.trainerId = 99
  if os.getenv("BOX_UI_ID_SYNC_ONLY") then
    second.name, second.secretId = "May", 123
    for _, mon in ipairs(require("src.core.TrainerIdSync").monsOf(second, 3)) do
      mon.otId, mon.otSecretId, mon.otName = 99, 123, "May"
      mon.personality = require("bit").bxor(99, 123, 12345) * 65536 + 12345
    end
    local opts = SaveData.loadOptions()
    opts.saveSlots = opts.saveSlots or {}
    opts.saveSlots.emerald = { active = "slot1", list = { "slot1", "slot2" } }
    SaveData.saveOptions(opts)
  end
  fs.write("saves/emerald/slot2.lua", Serializer.encode(second))
  imp = require("src.import.RomImporter").new(function() end, { launcher = true })
  imp.tab = "box"
  imp.mods, imp.modStraysChecked = {}, true
  imp.findErrors, imp._findFetch, imp.findLoading, imp.findNotice = {}, nil, false, nil
  imp._refreshFindSources = function() end
  imp._refreshFind = function() end
  imp.findLoaded, imp.findSources = true, { { feed = "https://example.invalid/mods.json" } }
  imp.findIndex = { mods = {}, carts = {} }
  imp._ensureMods = function() end
  imp._ensureFind = function() end
  local pcRows = {}
  for i, mon in ipairs(save.storage.boxes[1].mons) do
    pcRows[i] = { where = "box", box = 1, index = i, key = "box:1:" .. i,
      source = "Demo PC", mon = mon, entry = { version = "emerald", generation = 3,
      mon = mon, display = Catalog.describe("emerald", mon) } }
  end
  imp._boxState = { service = assert(Service.open()), sources = {
    { version = "emerald", slotId = "slot1", path = "saves/emerald/slot1.lua", label = "Emerald · Demo" },
    { version = "emerald", slotId = "slot2", path = "saves/emerald/slot2.lua", label = "Emerald · Other trainer" } },
    sourceIndex = 1, box = 1, pcBox = 1, query = "", sort = "slot", pcRows = pcRows,
    pcBody = Serializer.encode(save), selectedBox = {}, selectedPC = {}, pageBox = 1,
    pagePC = 1, sourcePage = 1, pcSave = save, multi = true, view = "box" }
  for _, slot in ipairs({ 1, 2 }) do imp._boxState.selectedBox["1:" .. slot] = { box = 1, slot = slot } end
  imp._boxState.inspect = imp._boxState.service.state.boxes[1].mons[2]
  local View = require("src.import.LauncherView")
  local original = View.btn
  View.btn = function(owner, x, y, w, h, id, label, opts)
    controls[id] = { x=x, y=y, w=w, h=h, label=label, enabled=opts.enabled ~= false, icon=opts.icon }
    return original(owner, x, y, w, h, id, label, opts)
  end
  local Icons=require("src.ui.kit.Icons")
  local drawIcon=Icons.draw
  Icons.draw=function(icon,x,y,...)
    if icon=="award" then awards[#awards+1]={x=x,y=y} end
    return drawIcon(icon,x,y,...)
  end
  co = coroutine.create(run)

end
local UI = require("src.import.BoxUI")
local Transition = require("src.ui.kit.Transition")
local function wait(seconds)
  local untilAt = love.timer.getTime() + (seconds or .3)
  repeat coroutine.yield() until love.timer.getTime() >= untilAt
end
local function click(id)
  wait()
  local o=imp._boxState and imp._boxState.organizer
  local r = assert(controls[id], "missing control " .. id.." (rule "..tostring(o and o.ruleIndex)..
    ", mode "..tostring(o and o.config.mode)..", page "..tostring(imp._boxState and imp._boxState.toolsPage)..")")
  if not imp._boxPopup and not imp._modConfirm and not imp._idSyncResult then
    local view = imp._tabRegionRect
    if r.y < view.y or r.y+r.h > view.y+view.h then
      imp._tabScroll.box = math.max(0, math.min(imp._tabScrollMax.box, imp._tabScroll.box + r.y - view.y - 20))
      wait(); r = assert(controls[id])
    end
  end
  check(r.w > 0 and r.y >= 0 and r.y+r.h <= love.graphics.getHeight(), id .. " reachable")
  imp:mousepressed(r.x+r.w/2, r.y+r.h/2, 1)
  if imp.mousereleased then imp:mousereleased(r.x+r.w/2, r.y+r.h/2, 1) end
  wait()
end
local function shot(name)
  wait(); pending = name
  repeat coroutine.yield() until pending == nil
  wait(.05)
end
local function close()
  imp:keypressed("escape"); wait()
  check(not imp._boxPopup, "escape closed the popup")
end
local function page(name)
  imp._tabScroll.box = 0
  if name=="Filters" then
    imp._boxState.toolsPage=nil;wait();click("box-filters")
    check(imp._boxState.toolsPage=="Filters","filter button opens filters")
    return
  end
  click("box-tools-menu")
  local option
  for i,row in ipairs(imp._boxPopup.options) do if row.id == name then option=i end end
  assert(option, name)
  imp._boxPopup.index, imp._boxPopup.reveal = option, true
  imp:keypressed("return"); wait()
  check(imp._boxState.toolsPage == (name ~= "Pokémon" and name or nil), "tool picker chose " .. name)
end
local function chooseValue(id, value)
  click(id)
  local index
  for i, option in ipairs(imp._boxPopup.options) do if option.id == value then index = i; break end end
  assert(index, "missing choice " .. tostring(value))
  imp._boxPopup.index, imp._boxPopup.reveal = index, true
  imp:keypressed("return"); wait()
end
local function boxInventory(state)
  local out = {}
  for _, box in ipairs(state.boxes) do
    for _, entry in pairs(box.mons) do out[entry.id] = require("src.core.SaveSerializer").encode(entry.mon) end
  end
  return require("src.core.SaveSerializer").encode(out)
end
local function pcInventory(save)
  local out = {}
  for _, row in ipairs(require("src.box.Records").candidates(save, 3)) do
    if row.where == "box" then out[#out + 1] = require("src.core.SaveSerializer").encode(row.mon) end
  end
  table.sort(out)
  return require("src.core.SaveSerializer").encode(out)
end
function run()
  wait()
  if os.getenv("BOX_UI_STUDIO_ONLY") then
    page("Showcase")
    shot("ui-40-showcase-editor-desktop.png")
    click("box-stage-add-pokemon")
    check(#imp._boxPopup.options>50,"Pokémon picker makes stored collection available")
    shot("ui-41-showcase-add-pokemon-desktop.png")
    imp._boxPopup.index=2;imp:keypressed("return");wait()
    local s=imp._boxState
    check(#s.stageDraft.pieces==5,"picker adds a Pokémon directly to the stage")
    click("box-stage-add-scenery")
    local tree
    for i,row in ipairs(imp._boxPopup.options) do if row.label=="Tree" then tree=i end end
    imp._boxPopup.index=tree;imp:keypressed("return");wait()
    check(s.stageDraft.pieces[s.stagePiece].kind=="Tree","new scenery is a real tree")
    local r=s.stageRect
    local p=s.stageDraft.pieces[s.stagePiece]
    local cx,cy=r.x+p.x*r.w,r.y+p.y*r.h
    imp:mousepressed(cx,cy,1);imp:mousemoved(cx+30,cy-20);imp:mousereleased(cx+30,cy-20,1);wait()
    check(p.x>.5 and p.y<.5,"native scene dragging changes placement")
    local handles=s.stageHandles
    local resize=handles[1]
    imp:mousepressed(resize.x+resize.w/2,resize.y+resize.h/2,1)
    imp:mousemoved(resize.x+resize.w/2+35,resize.y+resize.h/2-10)
    imp:mousereleased(0,0,1);wait()
    check(p.scale>1.5,"hold resize changes scenery scale")
    local flip=s.stageHandles[3]
    imp:mousepressed(flip.x+flip.w/2,flip.y+flip.h/2,1);wait()
    check(p.flipY,"vertical flip toggles from pop-out")
    flip=s.stageHandles[3]
    imp:mousepressed(flip.x+flip.w/2,flip.y+flip.h/2,1);wait()
    check(not p.flipY,"vertical flip can be restored from pop-out")
    click("box-tools-stage-back")
    check(s.stagePiece==#s.stageDraft.pieces-1,"layer arrow sends selected object backward")
    shot("ui-42-showcase-selected-tools-desktop.png")
    chooseValue("box-tools-stageSection","Scene")
    chooseValue("box-tools-stage-music","Night")
    local Showcase=require("src.box.Showcase")
    local fingerprints={}
    for i,pattern in ipairs({"Crosses","Bricks","Grid"}) do
      chooseValue("box-tools-stage-pattern",pattern)
      imp._tabScroll.box=0
      shot("ui-"..(46+i).."-showcase-"..pattern:lower().."-desktop.png")
      local canvas=love.graphics.newCanvas(400,200)
      love.graphics.push("all");love.graphics.setCanvas(canvas);love.graphics.origin();love.graphics.setScissor()
      local empty=Showcase.new();empty.pattern=pattern;Showcase.draw(s.service.state,empty,0,0,400,200)
      love.graphics.pop()
      local data=canvas:newImageData();fingerprints[i]=love.data.hash("sha256",data:getString())
      data:release();canvas:release()
    end
    check(fingerprints[1]~=fingerprints[2] and fingerprints[2]~=fingerprints[3] and fingerprints[1]~=fingerprints[3],
      "Crosses, Bricks and Grid render different native pixels")
    click("box-stage-options")
    imp._boxPopup.index=1;imp:keypressed("return");wait()
    check(s.service.state.boxes[1].theme=="Showcase","saved scene is applied as Box theme")
    check(s.service.fs.getInfo(s.service.state.boxes[1].wallpaper),"scene wallpaper PNG exists")
    check(s.service.state.boxes[1].showcaseMusic=="Night","applying scene saves its chosen music")
    page("Pokémon")
    local track,owner,music=Showcase.currentMusic()
    check(track=="Night" and owner=="box" and music:isPlaying(),"applied scene music plays on native Box board")
    shot("ui-50-applied-stage-desktop.png")
    page("Themes");click("box-theme-picker")
    local saved
    for i,row in ipairs(imp._boxPopup.options) do if row.label:find("Stage 1",1,true) then saved=i end end
    check(saved~=nil,"saved stages are selectable from Themes")
    shot("ui-43-saved-stage-theme-desktop.png");close()
    page("Showcase");love.window.setMode(390,844,{resizable=true});imp._tabScroll.box=0;wait()
    shot("ui-44-showcase-editor-portrait.png")
    page("Pokémon")
    s.query="bULba";wait();shot("ui-45-search-context-portrait.png")
    check(#require("src.box.Store").search(s.service.state,s.query,"slot")>0,"mixed-case Pokémon lookup matches")
    page("List");shot("ui-46-list-sprites-portrait.png")
    love.window.setMode(1360,860,{resizable=true});s.query="";page("Pokémon")
    local Store=require("src.box.Store")
    local edited=Store.copy(s.service.state);edited.revision=edited.revision+1
    local shiny=edited.boxes[1].mons[1]
    shiny.mon.personality=require("bit").bxor(42,97,12345)*65536+12345
    shiny.display=require("src.box.Catalog").describe("emerald",shiny.mon)
    check(shiny.display.shiny,"move fixture is actually shiny")
    assert(s.service:commit(edited));s.selectedBox={["1:1"]={box=1,slot=1}};s.inspect=nil;wait()
    local function marked(r)
      for _,a in ipairs(awards) do if a.x>=r.x and a.x<=r.x+r.w and a.y>=r.y and a.y<=r.y+r.h then return true end end
      return false
    end
    check(marked(controls["box-box-1:1"]),"occupied shiny slot has its marker")
    click("box-options");imp._boxPopup.index=1;imp:keypressed("return");wait()
    chooseValue("box-active-box-picker",2);click("box-box-2:20")
    chooseValue("box-active-box-picker",1)
    check(s.service.state.boxes[1].mons[1]==nil,"moving Pokémon empties its old slot")
    check(not marked(controls["box-box-1:1"]),"empty former slot has no leftover shiny marker")
    shot("ui-51-moved-shiny-empty-slot-desktop.png")
    imp:_switchTab("mods");wait()
    imp:_switchTab("box")
    local tr=assert(Transition.get("tabs"),"entering Box keeps its slide")
    check(tr.from=="mods" and tr.to=="box" and love.timer.getTime()-tr.t0<.05,"native Box slide starts after refresh")
    wait(.03)
    tr=assert(Transition.get("tabs"),"default Box transition survives initial native rendering")
    check(tr.p>0 and tr.p<1,"default native Box slide renders an intermediate frame")
    tr.t0=love.timer.getTime()
    tr.dur=1.5
    shot("ui-52-box-tab-slide-desktop.png")
    tr.dur=.18;wait()
    print("BOX_UI_NATIVE_PASS "..checks.." checks; "..love.filesystem.getSaveDirectory())
    love.event.quit(0);return
  end
  if os.getenv("BOX_UI_ID_SYNC_ONLY") then
    imp.activeSlot.emerald = "slot1"
    imp:askIdSync("emerald"); wait()
    check(imp._modConfirm.lines[1]:find("Demo", 1, true), "confirmation names actual trainer")
    check(imp._modConfirm.lines[2]:find("secret ID", 1, true), "confirmation covers full trainer identity")
    shot("ui-36-id-sync-confirm-desktop.png")
    love.window.setMode(390,844,{resizable=true}); wait()
    shot("ui-37-id-sync-confirm-portrait.png")
    local accept = imp._modConfirm.onYes
    imp._modConfirm = nil
    accept()
    while imp._idSync do wait(.05) end
    check(imp._idSyncResult and imp._idSyncResult.title == "ID Sync", "native launcher job succeeds")
    local SaveData = require("src.core.SaveData")
    local other = SaveData.decode(SaveData.readSlotSource("emerald", "slot2"))
    check(other.name == "Demo" and other.trainerId == 42 and other.secretId == 97,
      "native disk save matches selected trainer")
    check(not require("src.core.game3.pokemon").isTradedMon(other.party[1], other),
      "native mon obeys after reload")
    check(require("src.core.game3.pokemon").isShiny(other.party[1]), "native shiny remains shiny after reload")
    check(not require("src.core.TrainerIdSync").newJob({scope="emerald",slot="slot1"}).error,
      "completed journal leaves storage usable")
    shot("ui-38-id-sync-result-portrait.png")
    love.window.setMode(1360,860,{resizable=true}); wait()
    shot("ui-39-id-sync-result-desktop.png")
    print("BOX_UI_NATIVE_PASS "..checks.." checks; "..love.filesystem.getSaveDirectory())
    love.event.quit(0)
    return
  end
  if not os.getenv("BOX_UI_ORGANIZER_ONLY") then
  if not os.getenv("BOX_UI_DETAILS_ONLY") then
  check(controls["box-choose-save"].y == controls["box-tools-menu"].y, "desktop toolbar shares one row")
  check(controls["box-withdraw"].icon ~= nil, "transfer has an icon")
  check(controls["box-withdraw"].label:find("Send 2 to game",1,true), "transfer direction is named")
  shot("ui-01-board-desktop.png")
  click("box-choose-save"); check(#imp._boxPopup.options==2,"game picker shows playthroughs")
  shot("ui-02-game-picker-desktop.png"); close()
  click("box-help-Game"); check(imp._boxPopup.message==UI.HELP.Game,"game help explains the PC")
  shot("ui-03-game-help-desktop.png"); close()
  click("box-tools-menu"); check(#imp._boxPopup.options==11,"all tools remain reachable; filters have their own button")
  shot("ui-04-tool-picker-desktop.png"); close()
  page("Filters"); shot("ui-05-filters-desktop.png")
  click("box-tools-filter-type"); shot("ui-06-filter-picker-desktop.png"); close()
  page("Gifts"); shot("ui-07-gifts-desktop.png")
  page("Dashboard"); shot("ui-08-dashboard-desktop.png")
  page("Showcase"); shot("ui-09-showcase-desktop.png")
  click("box-tools-stageSection"); imp._boxPopup.index=2; imp:keypressed("return"); wait()
  check(imp._boxState.stageSection=="Placement","placement section chosen")
  shot("ui-10-placement-desktop.png")
  page("Pokémon")
  click("box-options"); shot("ui-11-options-desktop.png"); close()
  love.window.setMode(390,844,{resizable=true}); imp._tabScroll.box=0; wait()
  shot("ui-12-board-portrait.png")
  click("box-tools-menu"); shot("ui-13-tool-picker-portrait.png"); close()
  page("Filters"); shot("ui-14-filters-portrait.png")
  click("box-help-Game"); shot("ui-15-help-portrait.png"); close()
  page("Showcase"); shot("ui-16-showcase-portrait.png")
  page("Pokémon")
  click("box-view-pc"); check(imp._boxState.view=="pc","game PC view chosen")
  imp._tabScroll.box=0; shot("ui-17-game-pc-portrait.png")
  click("box-view-box")
  click("box-transfer-target"); shot("ui-18-destination-portrait.png")
  imp:keypressed("end"); wait(); imp:keypressed("return"); wait()
  check(imp._boxState.pcBox==14,"destination picker reaches the last PC box")
  shot("ui-19-transfer-toolbar-portrait.png")
  imp._tabScroll.box=0
  Transition.armed=true; UI.change(imp,imp._boxState,"view","pc",1)
  local tr=assert(Transition.get("box")); tr.t0=love.timer.getTime()-.03
  pending="ui-20-slide-portrait.png"; coroutine.yield()
  wait()
  check(not Transition.active("box"),"slide settles")
  end
  love.window.setMode(1360,860,{resizable=true}); imp._tabScroll.box=0; wait()
  click("box-summary"); check(imp._boxState.summary,"summary opens")
  shot("ui-21-summary-desktop.png")
  click("box-summary-section"); imp._boxPopup.index=2; imp:keypressed("return"); wait()
  check(imp._boxState.summarySection=="Moves","moves section chosen")
  shot("ui-22-moves-desktop.png")
  click("box-summary-section"); imp._boxPopup.index=3; imp:keypressed("return"); wait()
  check(imp._boxState.summarySection=="Stats","stats section chosen")
  shot("ui-23-stats-desktop.png")
  click("box-summary-section"); imp._boxPopup.index=4; imp:keypressed("return"); wait()
  shot("ui-24-origin-desktop.png")
  local r=assert(controls["box-summary-back"])
  local viewport=imp._tabRegionRect
  imp._tabScroll.box=math.max(0,math.min(imp._tabScrollMax.box,imp._tabScroll.box+r.y-viewport.y-20)); wait()
  shot("ui-25-ribbons-desktop.png")
  love.window.setMode(390,844,{resizable=true}); imp._tabScroll.box=0; wait()
  click("box-summary-section"); imp._boxPopup.index=1; imp:keypressed("return"); wait()
  shot("ui-26-overview-portrait.png")
  click("box-summary-section"); imp._boxPopup.index=2; imp:keypressed("return"); wait()
  shot("ui-27-moves-portrait.png")
  click("box-summary-section"); imp._boxPopup.index=3; imp:keypressed("return"); wait()
  shot("ui-28-stats-portrait.png")
  r=assert(controls["box-summary-back"]); viewport=imp._tabRegionRect
  imp._tabScroll.box=math.max(0,math.min(imp._tabScrollMax.box,imp._tabScroll.box+r.y-viewport.y-20)); wait()
  shot("ui-29-contest-portrait.png")
  end
  if not os.getenv("BOX_UI_DETAILS_ONLY") then
    if imp._boxState.summary then click("box-summary-back") end
    love.window.setMode(390,844,{resizable=true}); imp._tabScroll.box = 0; wait()
    page("Arrange")
    chooseValue("box-tools-arrangeSection", "Auto Box")
    chooseValue("box-organize-first-box", 2)
    chooseValue("box-organize-field", "species")
    chooseValue("box-organize-value", "PIKACHU")
    check(imp._boxState.organizer.config.rules[1].firstBox == 2, "Auto Box destination is selected")
    check(imp._boxState.organizer.config.rules[1].conditions[1].value == "PIKACHU", "Auto Box species condition is selected")
    imp._tabScroll.box = 0; shot("ui-30-auto-box-portrait.png")
    local warehouseBefore = boxInventory(imp._boxState.service.state)
    click("box-organize-preview")
    check(boxInventory(imp._boxState.service.state) == warehouseBefore, "rule preview leaves warehouse unchanged")
    check(imp._boxState.organizer.preview.report.moved > 0, "rule preview reports actual moves")
    check(imp._boxState.organizer.ruleIndex==1,"sticky preview does not click rule underneath")
    shot("ui-31-auto-box-preview-portrait.png")
    close()
    love.window.setMode(1360,860,{resizable=true}); imp._tabScroll.box = 0; wait()
    shot("ui-32-auto-box-desktop.png")
    check(imp._boxState.organizer.preview ~= nil, "closing movement review keeps the plan")
    click("box-organize-apply")
    check(boxInventory(imp._boxState.service.state) == warehouseBefore, "Auto Box preserves every native record and entry ID")
    local at = require("src.box.Store").find(imp._boxState.service.state, 4)
    check(at.box == 2, "Auto Box applies species rule")
    click("box-organize-presets")
    imp._boxPopup.index = #imp._boxPopup.options; imp:keypressed("return"); wait()
    check(imp._boxPrompt ~= nil, "preset uses the existing name prompt")
    imp:textinput("Pikachu box"); imp:keypressed("return"); wait()
    check(imp._boxState.service.state.organizerProfiles[1].name == "Pikachu box", "preset saved from UI")
    chooseValue("box-organize-field", "egg")
    click("box-organize-presets")
    imp._boxPopup.index = 1; imp:keypressed("return"); wait()
    check(imp._boxState.organizer.config.rules[1].conditions[1].value == "PIKACHU", "saved preset reloads its conditions")
    click("box-organize-rule-options")
    imp._boxPopup.index = 1; imp:keypressed("return"); wait()
    check(#imp._boxState.organizer.config.rules[1].conditions == 2, "rule editor adds a second condition")
    click("box-organize-rule-options")
    imp._boxPopup.index = 4; imp:keypressed("return"); wait()
    check(imp._boxState.organizer.config.rules[1].match == "any", "rule editor switches to any condition")
    click("box-organize-rule-options")
    imp._boxPopup.index = 2; imp:keypressed("return"); wait()
    check(#imp._boxState.organizer.config.rules[1].conditions == 1, "rule editor removes selected condition")
    chooseValue("box-tools-arrangeSection", "Sort")
    click("box-organize-target-pc")
    imp._tabScroll.box = 0; shot("ui-33-game-sort-desktop.png")
    local pcBefore = pcInventory(imp._boxState.pcSave)
    local partyBefore = require("src.core.SaveSerializer").encode(imp._boxState.pcSave.party)
    click("box-organize-preview")
    check(imp._boxState.organizer.preview.report.moved > 0, "Game PC preview reports actual moves")
    check(pcInventory(imp._boxState.pcSave) == pcBefore, "Game PC preview leaves save unchanged")
    shot("ui-34-game-sort-preview-desktop.png")
    close()
    click("box-organize-apply")
    check(pcInventory(imp._boxState.pcSave) == pcBefore, "Game PC apply preserves all native records")
    check(require("src.core.SaveSerializer").encode(imp._boxState.pcSave.party) == partyBefore, "Game PC sort leaves party untouched")
    local source = imp._boxState.sources[imp._boxState.sourceIndex]
    check(imp._boxState.service.fs.getInfo(source.path .. ".box-bak"), "Game PC sort keeps a native save backup")
    page("Pokémon"); click("box-view-pc")
    imp._boxState.pcBox = 1; imp._tabScroll.box = 0
    shot("ui-35-sorted-game-pc-desktop.png")
  end
  require("src.box.Cry").stop(); require("src.box.Showcase").stopMusic()
  print("BOX_UI_NATIVE_PASS "..checks.." checks; "..love.filesystem.getSaveDirectory())
  love.event.quit(0)
end
function love.update(dt)
  if imp then imp:update(dt) end
  if co and coroutine.status(co)~="dead" then
    local ok, why=coroutine.resume(co)
    if not ok then print("BOX_UI_NATIVE_FAIL "..tostring(why)); love.event.quit(1) end
  end
end
function love.draw()
  if imp then controls={};awards={};imp:draw() end
  if pending then
    local name=pending; pending=nil
    love.graphics.captureScreenshot(function(data)
      assert(love.filesystem.write(name,data:encode("png"):getString()))
    end)
  end
end
function love.errorhandler(why)
  print("BOX_UI_NATIVE_FAIL "..tostring(why)); return function() return 1 end
end
