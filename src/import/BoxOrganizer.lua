local Kit = require("src.ui.kit.Kit")
local Theme = require("src.ui.kit.Theme")
local UI = require("src.import.BoxUI")
local Store = require("src.box.Store")
local Organizer = require("src.box.Organizer")
local Catalog = require("src.box.Catalog")
local GameVersion = require("src.core.GameVersion")
local PAL = Theme.PAL
local Panel = {}

local function newRule()
  return { match = "all", firstBox = 1, lastBox = 1, conditions = { { field = "shiny", value = true } } }
end
local function conditionLabel(condition)
  local value = condition.value
  if type(value) == "boolean" then value = value and "Yes" or "No" end
  return (Organizer.FIELD_LABELS[condition.field] or condition.field) .. ": " .. tostring(value or "Choose")
end
local function ruleLabel(rule, index)
  return index .. ". " .. conditionLabel(rule.conditions[1]) .. (#rule.conditions > 1 and " + more" or "")
    .. " → Box " .. rule.firstBox .. (rule.lastBox ~= rule.firstBox and "–" .. rule.lastBox or "")
end
local valueCache = setmetatable({}, { __mode = "k" })
local function computeValues(field, layout, target, source)
  if field == "shiny" or field == "egg" then return { true, false }, { [true] = "Yes", [false] = "No" } end
  if field == "levelMin" or field == "levelMax" then
    local out = {}; for level = 0, 255 do out[#out + 1] = level end; return out
  end
  if field == "game" then
    local labels = {}; for _, version in ipairs(GameVersion.ORDER) do labels[version] = GameVersion.info(version).label end
    return GameVersion.ORDER, labels
  end
  if field == "mark" then return { "circle", "square", "triangle", "heart" } end
  if field == "gender" then return { "Male", "Female", "Genderless" } end
  local out, seen = {}, {}
  local function add(value)
    if type(value) == "string" and value ~= "" and not seen[value:lower()] then
      seen[value:lower()], out[#out + 1] = true, value
    end
  end
  for _, row in ipairs(layout.rows) do
    local d = row.entry.display
    if field == "type" or field == "move" then
      for value in tostring(field == "type" and d.types or d.moves or ""):gmatch(field == "type" and "[^/]+" or "[^,]+") do
        add(value:match("^%s*(.-)%s*$"))
      end
    elseif field == "tag" then add(row.entry.tags)
    else add(d[field]) end
  end
  if field == "species" then
    for _, version in ipairs(target == "pc" and source and { source.version } or GameVersion.ORDER) do
      local data = Catalog.get(version)
      for _, value in pairs(data.names or {}) do add(value) end
      for key, def in pairs(data.pokemon or {}) do add(type(def) == "table" and (def.name or key) or key) end
    end
  end
  table.sort(out, function(a, b) return a:lower() < b:lower() end)
  return out
end
local function values(field, layout, target, source)
  local byLayout = valueCache[layout]
  if not byLayout then byLayout = {}; valueCache[layout] = byLayout end
  local key = tostring(field) .. "|" .. tostring(target) .. "|" .. tostring(source and source.version)
  local hit = byLayout[key]
  if not hit then
    local out, labels = computeValues(field, layout, target, source)
    hit = { out, labels }; byLayout[key] = hit
  end
  return hit[1], hit[2]
end
local function clampBoxes(config, count)
  local out = Store.copy(config)
  if out.box and (out.box < 1 or out.box > count) then out.box = nil end
  for _, rule in ipairs(out.rules or {}) do
    local first = math.max(1, math.min(count, rule.firstBox or 1))
    rule.firstBox, rule.lastBox = first, math.max(first, math.min(count, rule.lastBox or first))
  end
  return out
end
local function findProfile(profiles, mode, key)
  if not key then return nil end
  local hinted = profiles[key.index]
  if hinted and hinted.config and hinted.config.mode == mode and hinted.name == key.name and hinted.target == key.target then
    return key.index
  end
  for i, p in ipairs(profiles) do
    if p.config and p.config.mode == mode and p.name == key.name and p.target == key.target then return i end
  end
end

local function card(x, y, w, h, title, number, m, accent)
  Theme.card(x,y,w,h,{stroke=accent or PAL.line,strokeA=accent and .8 or .35})
  local pad = 14*m.s
  if number then
    Theme.strokeRounded(x+pad,y+pad,26*m.s,26*m.s,PAL.line,.65,1,13*m.s)
    Kit.textCenterBold("micro",tostring(number),x+pad,y+pad+5*m.s,26*m.s,PAL.heading)
  end
  Kit.textBold("small",title,x+pad+(number and 38*m.s or 0),y+pad+3*m.s,PAL.heading)
end
local function changed(o) o.preview,o.previewPage,o.signature=nil,1,nil end
local function previewColumns(w,m,compact,n)
  return compact and n or math.max(2,math.min(6,math.floor(w/(46*m.s))))
end
local function previewActions(imp,s,o,layout,report,why,x,y,w,m,api,compact)
  local gap,h=8*m.s,math.max(Kit.tapMin(),m.btnH)
  Kit.textBold("micro","AFTER APPLYING",x,y,PAL.muted);y=y+Kit.textHeight("micro")+gap
  local boxes=report and report.boxes
  local n=layout.count
  local cols=previewColumns(w,m,compact,n)
  local gridGap=compact and 2*m.s or gap
  local cw=(w-(cols-1)*gridGap)/cols
  local bh=compact and 30*m.s or 54*m.s
  for b=1,n do
    local cx=x+(b-1)%cols*(cw+gridGap)
    local cy=y+math.floor((b-1)/cols)*(bh+gap)
    local box=boxes and boxes[b]
    local count=box and box.after or 0
    local color=PAL.muted
    if o.analysis and o.analysis.reserved[b] then color=PAL.blue end
    Theme.card(cx,cy,cw,bh,{fill=PAL.rowBg,strokeA=.35})
    if not compact then
      Kit.textBold("micro",tostring(b),cx+5*m.s,cy+5*m.s,PAL.heading)
      Kit.text("micro",count.."/"..layout.capacity,cx+5*m.s,cy+25*m.s,PAL.muted)
    end
    local barY=compact and cy or cy+bh-8*m.s
    Theme.fillRounded(cx+2,barY,math.max(1,cw-4),compact and bh or 3*m.s,PAL.raised,1,2)
    if count>0 then Theme.fillRounded(cx+2,barY,math.max(1,(cw-4)*count/layout.capacity),
      compact and bh or 3*m.s,color,1,2) end
  end
  y=y+math.ceil(n/cols)*(bh+gap)
  local status=why or (report and (report.total.." Pokémon · "..report.moved.." moves") or "Choose your rules.")
  y=y+Kit.textWrapped("micro",status,x,y,w,why and PAL.yellow or PAL.muted,3)+gap
  api.button(imp,x,y,(w-gap)/2,h,"organize-preview","Preview",function()
    local source=s.sources[s.sourceIndex]
    local p,err=s.service:previewOrganize(o.target,source,o.effective or o.config)
    o.preview,s.notice,s.noticeKind,o.previewBox=p,err,"error",1
    if p then
      local moves={}
      for _,row in ipairs(p.report.assignments) do
        if row.moved then moves[#moves+1]={label=tostring(row.entry.display.name).." · Box "..row.fromBox.."/"..row.fromSlot..
          " → "..row.box.."/"..row.slot,entry=row.entry} end
      end
      UI.open(imp,"Preview · "..p.report.moved.." moves",moves)
    end
  end,false,why~=nil,"eye")
  api.button(imp,x+(w+gap)/2,y,(w-gap)/2,h,"organize-apply",
    compact and "Apply" or o.target=="pc" and "Apply to game" or "Apply to Box",function()
      if api.perform(imp,function() return s.service:applyOrganize(o.preview) end,
        o.target=="pc" and "Game PC arranged. Saved and backed up." or "Box arranged. Previous layout backed up.") then changed(o) end
    end,false,not o.preview or o.preview.report.moved==0 or why~=nil,"save")
  return y+h
end

function Panel.drawSticky(imp,m)
  local f=imp._boxOrganizerFooter
  if not f or imp.tab~="box" or not imp._boxState or imp._boxState.toolsPage~="Arrange" then return end
  local overlay=Kit._overlay;Kit._overlay=true
  Theme.fillRounded(f.x-8*m.s,f.y-10*m.s,f.w+16*m.s,f.h+20*m.s,PAL.surface,1,10)
  Theme.fill(f.x-8*m.s,f.y-10*m.s,f.w+16*m.s,1,PAL.line,.55)
  previewActions(imp,f.s,f.o,f.layout,f.report,f.why,f.x,f.y,f.w,m,f.api,true)
  Kit._overlay=overlay
end

function Panel.draw(imp,s,x,y,w,m,api,mode)
  local top,gap,h,pad=y,10*m.s,math.max(Kit.tapMin(),m.btnH),14*m.s
  s.organizers=s.organizers or {}
  local pick=s.organizers[mode] or {target="box"}
  s.organizers[mode]=pick
  local function stateFor(target)
    local key=mode..":"..target
    s.organizers[key]=s.organizers[key] or {target=target,ruleIndex=1,conditionIndex=1,
      config={mode=mode,sort="species",descending=false,fallback="keep",rules={newRule()}}}
    return s.organizers[key]
  end
  local o=stateFor(pick.target=="pc" and "pc" or "box")
  local source=s.sources[s.sourceIndex]
  local context=o.target..":"..tostring(source and source.path)
  if o.context~=context then o.context=context;changed(o) end
  if o.preview and o.preview.boxBefore~=s.service.body then changed(o) end
  local config=o.config
  local input=o.target=="pc" and s.pcSave or s.service.state
  if o.layoutInput~=input or o.layoutContext~=context then
    o.layoutInput,o.layoutContext=input,context
    if o.target=="pc" then
      if source and s.pcSave then o.layout,o.layoutError=Organizer.game(s.pcSave,source.version)
      else o.layout,o.layoutError=nil,"Choose a readable game save above." end
    else o.layout,o.layoutError=Organizer.warehouse(s.service.state),nil end
  end
  local layout,why=o.layout,o.layoutError
  local function btn(id,label,fn,bx,bw,active,disabled,icon)
    UI.button(imp,bx or x,y,bw or w,h,"organize-"..id,label,fn,
      {face=active and "tab" or "selection",active=active,enabled=not disabled,icon=icon})
  end
  local function targetCard(info,color)
    local half=(w-2*pad-gap)/2
    local infoH=Kit.wrapHeight("micro",info,w-2*pad,3)
    local cardH=52*m.s+h+6*m.s+infoH+pad
    card(x,y,w,cardH,"Which boxes?",1,m)
    y=y+52*m.s
    btn("target-pc","Game PC",function() pick.target="pc" end,x+pad,half,o.target=="pc",not source,"monitor")
    btn("target-box","Box storage",function() pick.target="box" end,x+pad+half+gap,half,o.target=="box",false,"package")
    y=y+h+6*m.s
    Kit.textWrapped("micro",info,x+pad,y,w-2*pad,color or PAL.muted,3)
    return cardH
  end
  if not layout then return targetCard(tostring(why or ""),PAL.yellow)+gap end
  if not o.signature or o.layoutSource~=(o.target=="pc" and s.pcSave or s.service.state) then
    o.preview=nil;o.signature=true;o.layoutSource=o.target=="pc" and s.pcSave or s.service.state
    o.effective=clampBoxes(config,layout.count)
    o.analysis,o.analysisError=Organizer.analyze(layout,o.effective)
    local planned, result=Organizer.plan(layout,o.effective)
    o.plannedBoxes=planned
    o.planError=not planned and result or nil
  end
  local report=o.preview and o.preview.report or o.plannedBoxes
  local wide=w>=740*m.s
  local fullX,fullW=x,w
  local rightX,rightW
  if wide then w=(w-2*gap)*.6;rightX=x+w+2*gap;rightW=fullW-w-2*gap end
  local view=imp._tabRegionRect
  local footerH
  if not wide and view and view.h>260*m.s then
    local status=o.planError or (report and (report.total.." Pokémon · "..report.moved.." moves") or "")
    footerH=Kit.textHeight("micro")+3*gap+30*m.s+Kit.wrapHeight("micro",status,fullW,3)+h+10*m.s
    local fy=math.min(view.y+view.h,m.H-40*m.s)-footerH
    imp._boxOrganizerFooter={s=s,o=o,layout=layout,report=report,why=o.planError,
      x=fullX,y=fy,w=fullW,h=footerH,api=api}
    Kit.occlude(fullX,fy-10*m.s,fullW,footerH+20*m.s)
  end
  local function dropdown(id,label,choices,current,apply,bx,bw,icon)
    UI.dropdown(imp,bx or x,y,bw or w,h,"organize-"..id,label,choices,current,function(v) apply(v);changed(o) end,icon)
  end
  local profiles=s.service.state.organizerProfiles or {}
  local options={}
  for i,p in ipairs(profiles) do
    if p.config.mode==mode then
      options[#options+1]={label=p.name,icon="save",action=function()
        local t=stateFor(p.target=="pc" and "pc" or "box")
        pick.target=t.target
        t.config,t.profile=Store.copy(p.config),{index=i,name=p.name,target=p.target};t.ruleIndex=1;changed(t)
      end}
    end
  end
  local profileIndex=findProfile(profiles,mode,o.profile)
  local function stalePreset()
    s.notice,s.noticeKind,o.profile="That preset changed. Choose it again.","error",nil
  end
  local function savePreset(update)
    require("src.import.BoxPrompt").open(imp,"Preset name",update and profiles[profileIndex] and profiles[profileIndex].name or "",64,function(name)
      local at=update and findProfile(s.service.state.organizerProfiles or {},mode,o.profile) or nil
      if update and not at then return stalePreset() end
      local target,config=o.target,o.config
      if api.perform(imp,function() return s.service:saveOrganizer(name,target,config,at) end,"Preset saved.") then
        o.profile={index=at or #s.service.state.organizerProfiles,name=name,target=target};changed(o)
      end
    end)
  end
  options[#options+1]={label="Save as new preset",icon="plus",disabled=#profiles>=20,action=function() savePreset(false) end}
  if profileIndex then
    options[#options+1]={label="Update preset",icon="save",action=function() savePreset(true) end}
    options[#options+1]={label="Delete preset",icon="trash",action=function()
      local at=findProfile(s.service.state.organizerProfiles or {},mode,o.profile)
      if not at then return stalePreset() end
      if api.perform(imp,function() return s.service:deleteOrganizer(at) end,"Preset removed.") then o.profile=nil end
    end}
  end
  dropdown("presets",profileIndex and profiles[profileIndex].name or "Presets",options,nil,function() end,x,w,"save")
  y=y+h+gap
  local cardH=targetCard(layout.count.." boxes · "..layout.capacity.." slots each · "..#layout.rows.." Pokémon")
  y=top+h+gap+cardH+gap
  local innerX,innerW=x+pad,w-2*pad
  local boxes,labels={},{}
  for b=1,layout.count do boxes[b],labels[b]=b,"Box "..b end
  if mode=="sort" then
    card(x,y,w,120*m.s,"Choose boxes",2,m)
    y=y+50*m.s
    local scopes={{id=0,label="All boxes",icon="grid-2x2"}}
    for b=1,layout.count do scopes[#scopes+1]={id=b,label=labels[b],icon="package"} end
    dropdown("scope",config.box and labels[config.box] or "All boxes",scopes,config.box or 0,
      function(v) config.box=v~=0 and v or nil end,innerX,innerW,"package")
    y=y+h+gap+pad
  else
    config.rules=config.rules or {newRule()}
    local titleY=y
    card(x,y,w,54*m.s,"Rules",2,m);y=y+62*m.s
    Kit.text("micro","Checked from the top. First match wins.",innerX,y,PAL.muted)
    y=y+Kit.textHeight("micro")+gap
    for index,rule in ipairs(config.rules) do
      local expanded=o.ruleIndex==index
      local counts=o.analysis and o.analysis.ruleCounts[index] or 0
      local start=y
      local lines=#rule.conditions
      local rh=expanded and (h*(lines+2)+gap*(lines+3)+88*m.s) or h+22*m.s
      local needed=math.max(1,math.ceil(counts/layout.capacity))
      local oversized=rule.lastBox-rule.firstBox+1>needed
      if expanded and oversized then rh=rh+h+gap end
      Theme.card(innerX,y,innerW,rh,{fill=PAL.rowBg,strokeA=expanded and .65 or .35})
      UI.button(imp,innerX+8*m.s,y+6*m.s,innerW-16*m.s,h,"organize-rule-"..index,
        ruleLabel(rule,index).." · "..counts.." match",function() o.ruleIndex=expanded and 0 or index end,
        {face="bare",align="left",trailingIcon=expanded and "chevron-up" or "chevron-down"})
      y=y+h+gap+8*m.s
      if expanded then
        local usableX,usableW=innerX+12*m.s,innerW-24*m.s
        local cw=(usableW-gap)/2
        for ci,c in ipairs(rule.conditions) do
          local suffix=index==1 and ci==1 and "" or "-"..index.."-"..ci
          local fields={}
          for _,field in ipairs(Organizer.FIELDS) do
            if Organizer.available(field,o.target=="pc" and source.version or nil) then fields[#fields+1]=field end
          end
          dropdown("field"..suffix,Organizer.FIELD_LABELS[c.field],UI.values(fields,Organizer.FIELD_LABELS,"list-filter"),c.field,function(v)
            c.field=v;local choices=values(v,layout,o.target,source);c.value=choices[1]~=nil and choices[1] or ""
          end,usableX,cw,"list-filter")
          local choices,valueLabels=values(c.field,layout,o.target,source)
          local opts=UI.values(choices,valueLabels,"check")
          if type(c.value)=="string" then
            opts[#opts+1]={label="Type a value…",icon="pencil",action=function()
              require("src.import.BoxPrompt").open(imp,Organizer.FIELD_LABELS[c.field],c.value,128,function(v) c.value=v;changed(o) end)
            end}
          end
          dropdown("value"..suffix,valueLabels and valueLabels[c.value] or tostring(c.value),opts,c.value,
            function(v) c.value=v end,usableX+cw+gap,cw,"check")
          y=y+h+gap
        end
        local actions={
          {label="Add condition",icon="plus",disabled=lines>=8,action=function()
            rule.conditions[#rule.conditions+1]={field="shiny",value=true};changed(o)
          end},
          {label="Remove last condition",icon="minus",disabled=lines==1,action=function() table.remove(rule.conditions);changed(o) end},
          {label="Match all conditions",icon="check",action=function() rule.match="all";changed(o) end},
          {label="Match any condition",icon="check",action=function() rule.match="any";changed(o) end},
          {label="Move earlier",icon="arrow-up",disabled=index==1,action=function()
            config.rules[index],config.rules[index-1]=config.rules[index-1],rule;o.ruleIndex=index-1;changed(o)
          end},
          {label="Move later",icon="arrow-down",disabled=index==#config.rules,action=function()
            config.rules[index],config.rules[index+1]=config.rules[index+1],rule;o.ruleIndex=index+1;changed(o)
          end},
          {label="Remove rule",icon="trash",disabled=#config.rules==1,action=function()
            table.remove(config.rules,index);o.ruleIndex=math.max(1,index-1);changed(o)
          end}}
        dropdown("rule-options"..(index==1 and "" or "-"..index),lines>1 and ("Conditions: "..rule.match) or "Add condition / rule options",
          actions,nil,function() end,usableX,usableW,"plus");y=y+h+gap
        Kit.text("micro","SEND TO",usableX,y,PAL.muted);y=y+Kit.textHeight("micro")+5*m.s
        dropdown("first-box"..(index==1 and "" or "-"..index),labels[rule.firstBox] or "Box "..rule.firstBox,UI.values(boxes,labels,"package"),rule.firstBox,
          function(v) rule.firstBox,rule.lastBox=v,math.max(v,rule.lastBox) end,usableX,cw,"package")
        dropdown("last-box"..(index==1 and "" or "-"..index),"through "..(labels[rule.lastBox] or "Box "..rule.lastBox),UI.values(boxes,labels,"package"),rule.lastBox,
          function(v) rule.lastBox,rule.firstBox=v,math.min(v,rule.firstBox) end,usableX+cw+gap,cw,"package")
        y=y+h+gap
        if oversized then
          UI.button(imp,usableX,y,usableW,h,"organize-shrink-"..index,
            counts.." match · Use only Box "..rule.firstBox.."–"..(rule.firstBox+needed-1),function()
              rule.lastBox=rule.firstBox+needed-1;changed(o)
            end,{icon="undo-2",face="invert"})
          y=y+h+gap
        end
      end
      y=math.max(y,start+rh)+gap
    end
    btn("add-rule","Add another rule",function()
      config.rules[#config.rules+1]=newRule();o.ruleIndex=#config.rules;changed(o)
    end,innerX,innerW,false,#config.rules>=24,"plus");y=y+h+gap
    if y-titleY<54*m.s then y=titleY+54*m.s end
    local remaining=o.analysis and o.analysis.remaining or 0
    local noRoom=config.fallback=="sort" and o.analysis and remaining>o.analysis.freeBoxes*layout.capacity
    card(x,y,w,50*m.s+2*Kit.textHeight("micro")+2*gap+h+pad,"Everyone else",3,m,noRoom and PAL.yellow or nil);y=y+50*m.s
    Kit.text("micro",remaining.." Pokémon don't match any rule.",innerX,y,PAL.muted)
    y=y+Kit.textHeight("micro")+gap
    local cw=(innerW-gap)/2
    btn("fallback-keep","Leave them where they are",function() config.fallback="keep";changed(o) end,
      innerX,cw,config.fallback=="keep",false,"map-pin")
    btn("fallback-sort","Fill other boxes",function() config.fallback="sort";changed(o) end,
      innerX+cw+gap,cw,config.fallback=="sort",false,"package")
    y=y+h+gap
    Kit.text("micro",noRoom and "No room left. Shrink a rule's range or keep their boxes."
      or config.fallback=="keep" and "Same box, same slot." or (o.analysis and o.analysis.freeBoxes or 0).." boxes no rule uses.",
      innerX,y,noRoom and PAL.yellow or PAL.muted);y=y+Kit.textHeight("micro")+pad+gap
  end
  card(x,y,w,116*m.s,"Order inside each box",mode=="sort" and 3 or 4,m)
  y=y+50*m.s
  local cw=(innerW-gap)/2
  dropdown("sort",Organizer.LABELS[config.sort],UI.values(Organizer.SORTS,Organizer.LABELS,"arrow-up-down"),config.sort,
    function(v) config.sort=v end,innerX,cw,"arrow-up-down")
  dropdown("direction",config.descending and "High → Low" or "Low → High",
    UI.values({false,true},{[false]="Low → High",[true]="High → Low"}),config.descending,
    function(v) config.descending=v end,innerX+cw+gap,cw,"arrow-up-down")
  y=y+h+pad+gap
  if wide then
    local cols=previewColumns(rightW-2*pad,m,false,layout.count)
    card(rightX,top,rightW,math.ceil(layout.count/cols)*62*m.s+100*m.s,"",nil,m)
    local bottom=previewActions(imp,s,o,layout,report,o.planError,rightX+pad,top+pad,rightW-2*pad,m,api,false)
    y=math.max(y,bottom+gap);imp._boxOrganizerFooter=nil
  else
    if footerH then
      y=y+footerH+gap
    else y=previewActions(imp,s,o,layout,report,o.planError,x,y,w,m,api,true)+gap end
  end
  return y-top
end
return Panel
