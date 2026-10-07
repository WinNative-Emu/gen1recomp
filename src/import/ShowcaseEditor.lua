local Kit = require("src.ui.kit.Kit")
local Theme = require("src.ui.kit.Theme")
local UI = require("src.import.BoxUI")
local Store = require("src.box.Store")
local Showcase = require("src.box.Showcase")
local Editor = {}
local PAL = Theme.PAL
local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local function angle(x, y) return math.atan2(y, x) end
local function wrap(v) return (v + math.pi) % (2 * math.pi) - math.pi end
local function record(s)
  s.stageUndo = s.stageUndo or {}
  s.stageUndo[#s.stageUndo + 1] = Store.copy(s.stageDraft)
  if #s.stageUndo > 20 then table.remove(s.stageUndo, 1) end
end
local function start(s, kind, index, mx, my, rect)
  local p = s.stageDraft.pieces[index]
  if not p then s.stageGesture = nil; return end
  s.stageGesture = { kind = kind, x = mx, y = my, px = p.x, py = p.y,
    scale = p.scale, rotation = p.rotation, index = index,
    cx = rect.x + p.x * rect.w, cy = rect.y + p.y * rect.h,
    draft = s.stageDraft, stage = s.stageIndex }
end
function Editor.begin(s, kind, mx, my, rect)
  if not s.stageDraft.pieces[s.stagePiece] then return end
  start(s, kind, s.stagePiece, mx, my, rect)
end
local function current(s, mx, my, rect)
  local t = s.stageGesture
  if not t or t.draft == s.stageDraft then return t end
  if t.stage ~= s.stageIndex then s.stageGesture = nil; return nil end
  start(s, t.kind, t.index, mx, my, rect)
  return s.stageGesture
end
function Editor.move(s, mx, my, rect)
  local t = current(s, mx, my, rect)
  local p = t and s.stageDraft.pieces[t.index]
  if not p then return end
  local x, y, scale, rotation = p.x, p.y, p.scale, p.rotation
  if t.kind == "move" then
    x, y = clamp(t.px + (mx - t.x) / rect.w, 0, 1), clamp(t.py + (my - t.y) / rect.h, 0, 1)
  elseif t.kind == "resize" then
    scale = clamp(t.scale * math.exp((mx - t.x - my + t.y) / math.max(70, rect.w * .2)), .25, 4)
  elseif t.kind == "rotate" then
    rotation = wrap(t.rotation + angle(mx - t.cx, my - t.cy) - angle(t.x - t.cx, t.y - t.cy))
  end
  if x == p.x and y == p.y and scale == p.scale and rotation == p.rotation then return end
  if not t.recorded then record(s); t.recorded = true end
  p.x, p.y, p.scale, p.rotation = x, y, scale, rotation
end
function Editor.finish(s) s.stageGesture = nil end
function Editor.pointerPressed(imp,id,x,y)
  local s=imp._boxState
  if imp.tab~="box" or not s or s.toolsPage~="Showcase" or not s.stageRect
      or imp._boxPopup or imp._modalUpNow or Kit.blockClicks then return false end
  local function inside(r)
    local mx,my=Kit.mouseX,Kit.mouseY
    Kit.mouseX,Kit.mouseY=x,y
    local hit=Kit.hit(r.x,r.y,r.w,r.h)
    Kit.mouseX,Kit.mouseY=mx,my
    return hit
  end
  if imp._tabRegionRect and not inside(imp._tabRegionRect) then return false end
  for _,handle in ipairs(s.stageHandles or {}) do
    if inside(handle) then
      if handle.kind=="resize" or handle.kind=="rotate" then
        Editor.begin(s,handle.kind,x,y,s.stageRect);s._stagePointer=id
      else handle.action() end
      return true
    end
  end
  if not inside(s.stageRect) then return false end
  local r=s.stageRect
  s.stagePiece=Showcase.hit(s.stageDraft,r.x,r.y,r.w,r.h,x,y)
  if s.stagePiece then Editor.begin(s,"move",x,y,r);s._stagePointer=id end
  return true
end
function Editor.pointerMoved(imp,id,x,y)
  local s=imp._boxState
  if not s or s._stagePointer~=id then return false end
  Editor.move(s,x,y,s.stageRect)
  return true
end
function Editor.pointerReleased(imp,id)
  local s=imp._boxState
  if not s or s._stagePointer~=id then return false end
  Editor.finish(s);s._stagePointer=nil
  return true
end
function Editor.draw(imp, s, x, y, w, h, m, edit)
  local rect = { x = x, y = y, w = w, h = h }
  Showcase.draw(s.service.state, s.stageDraft, x, y, w, h)
  s.stageRect = rect
  s.stageHandles = {}
  local p = s.stageDraft.pieces[s.stagePiece or 0]
  local toolbar
  if p then
    local size = math.min(w / 8, h / 2) * p.scale
    local cx, cy = x + p.x * w, y + p.y * h
    Theme.strokeRounded(cx - size / 2 - 4, cy - size / 2 - 4, size + 8, size + 8, PAL.blue, 1, 2, 6)
    local bh, gap = math.max(Kit.tapMin(), 30 * m.s), 3 * m.s
    local tw = 5 * bh + 4 * gap
    local tx, ty = clamp(cx - tw / 2, x + 4, math.max(x + 4, x + w - tw - 4)),
      clamp(cy + size / 2 + 10, y + 4, math.max(y + 4, y + h - bh - 4))
    toolbar = { x = tx, y = ty, w = tw, h = bh }
    local actions = {
      { "resize", "expand", function() Editor.begin(s, "resize", Kit.mouseX, Kit.mouseY, rect) end },
      { "flip-h", "arrow-left-right", function() edit(function() p.flip = not p.flip end) end },
      { "flip-v", "arrow-up-down", function() edit(function() p.flipY = not p.flipY end) end },
      { "rotate", "rotate-ccw", function() Editor.begin(s, "rotate", Kit.mouseX, Kit.mouseY, rect) end },
      { "fine", "sliders-horizontal", function() s.stageSection = "Placement"; s.stageFine = true end },
    }
    for index, action in ipairs(actions) do
      s.stageHandles[index]={x=tx+(index-1)*(bh+gap),y=ty,w=bh,h=bh,kind=action[1],action=action[3]}
      UI.button(imp, tx + (index - 1) * (bh + gap), ty, bh, bh, "stage-handle-" .. action[1], "", action[3],
        { icon = action[2], face = "invert" })
    end
  end
  if not Kit.blockClicks and not imp._boxPopup then
    if s.stageGesture then current(s, Kit.mouseX, Kit.mouseY, rect) end
    if s.stageGesture and not s._stagePointer then
      if Kit.mouseDown then Editor.move(s, Kit.mouseX, Kit.mouseY, rect) else Editor.finish(s) end
    elseif Kit.press(x, y, w, h) and not (toolbar and Kit.hit(toolbar.x, toolbar.y, toolbar.w, toolbar.h)) then
      local selected = Showcase.hit(s.stageDraft, x, y, w, h, Kit.mouseX, Kit.mouseY)
      s.stagePiece = selected
      if selected then Editor.begin(s, "move", Kit.mouseX, Kit.mouseY, rect) end
    end
  end
end
return Editor
