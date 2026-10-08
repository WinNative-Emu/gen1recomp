local LinkTags = {}

LinkTags.PLATE_H = 11
LinkTags.PAD = 2
LinkTags.ICON_GAP = 1
LinkTags.MAX_TEXT_W = 44
LinkTags.TEXT_DY = -2
LinkTags.HEAD_OVERLAP = 2
LinkTags.EDGE = 1
LinkTags.BLENDER_EM_BASE = 0x7F00
LinkTags.BLENDER_RS_BASE = 0xF0
LinkTags.MAX_SEATS = 5
LinkTags.BADGE_GAP = 1
LinkTags.NEAR_CELLS = 2
LinkTags.UNION_PAD = 3
LinkTags.UNION_HEAD_GAP = 1
LinkTags.RS_TEXT_DY = -6

LinkTags.PLATE = { 0.06, 0.07, 0.12, 0.62 }
LinkTags.PLATE_SELF = { 0.08, 0.2, 0.46, 0.7 }

LinkTags.COLORS = {
  ["#"] = { 0.12, 0.12, 0.16, 1 },
  w = { 0.97, 0.97, 0.97, 1 },
  b = { 0.3, 0.6, 1, 1 },
  o = { 1, 0.58, 0.18, 1 },
  r = { 0.92, 0.22, 0.2, 1 },
  y = { 1, 0.86, 0.3, 1 },
}

LinkTags.ICONS = {
  chat = {
    ".#######.",
    "#wwwwwww#",
    "#w#w#w#w#",
    "#wwwwwww#",
    ".#ww####.",
    ".#w#.....",
    ".##......",
  },
  trade = {
    "......#...",
    "#######b#.",
    "#bbbbbbbb#",
    "#######b#.",
    "...#..#...",
    ".#o#######",
    "#oooooooo#",
    ".#o#######",
    "...#......",
  },
  battle = {
    "##.....##",
    "#w#...#w#",
    ".#w#.#w#.",
    "..#w#w#..",
    "...#w#...",
    "..##.##..",
    ".rr#.#rr.",
    "#r#...#r#",
    "##.....##",
  },
  busy = {
    "#######",
    "#yyyyy#",
    ".#yyy#.",
    "..#y#..",
    ".#y.y#.",
    "#yyyyy#",
    "#######",
  },
}

LinkTags._images = nil
LinkTags._widths = {}
LinkTags._widthCount = 0
LinkTags._src = { byVobj = {}, player = nil }
LinkTags._rows = {}
LinkTags._self = {}

function LinkTags.iconSize(kind)
  local rows = LinkTags.ICONS[kind]
  if not rows then return 0, 0 end
  return #rows[1], #rows
end

local function union()
  return package.loaded["src.core.game3.link.union_room"]
end

local function linkPlayers()
  return package.loaded["src.core.game3.link.link_players"]
end

local function link()
  return package.loaded["src.core.game3.link"]
end

local function tagRow(i)
  local row = LinkTags._rows[i]
  if not row then
    row = {}
    LinkTags._rows[i] = row
  end
  row.badge, row.union, row.near = nil, nil, nil
  return row
end

local function badgeModule()
  return require("src.online.union.Badge")
end

local function localKind()
  local LT = package.loaded["src.core.game3.link.trade"]
  if LT and LT.isActive and LT.isActive() then return "trade" end
  local LB = package.loaded["src.core.game3.link.battle"]
  if LB and LB.isActive and LB.isActive() then return "battle" end
  local Chat = package.loaded["src.core.game3.link.chat"]
  if Chat and Chat.isActive and Chat.isActive() then return "chat" end
  local U = union()
  if U and U.isActive and U.isActive() and U.state == "in_activity" then
    return U.memberStatusKind({ activity = U.activity })
  end
  return nil
end

local function blenderPartners(src, n)
  local L = link()
  local lk = L and L.link
  if not (lk and lk.isOpen and lk:isOpen() and lk.players) then return n, false end
  local V = package.loaded["src.core.game3.virtual_objects"]
  if not V then return n, false end
  local ok, players = pcall(lk.players, lk)
  if not ok or type(players) ~= "table" then return n, false end
  local any = false
  for i, player in ipairs(players) do
    local seat = tonumber(player.seat) or (i - 1)
    if seat >= 0 and seat < LinkTags.MAX_SEATS and type(player.name) == "string" then
      for _, id in ipairs({ LinkTags.BLENDER_EM_BASE + seat, LinkTags.BLENDER_RS_BASE - seat }) do
        if V.get(id) then
          n = n + 1
          local row = tagRow(n)
          row.name, row.kind = player.name, nil
          src.byVobj[id] = row
          any = true
        end
      end
    end
  end
  return n, any
end

function LinkTags.sources()
  local src = LinkTags._src
  for k in pairs(src.byVobj) do src.byVobj[k] = nil end
  src.player = nil
  local active, n = false, 0
  local U = union()
  local inUnion = U and U.isActive and U.isActive() and U.onUnionRoomMap and U.onUnionRoomMap()
  if inUnion then
    active = true
    local P = package.loaded["src.core.game3.player"]
    local px, py = P and tonumber(P.cellX), P and tonumber(P.cellY)
    for slot = 1, U.capacity() do
      local p = U.players[slot]
      if p and not p.gone and type(p.name) == "string" then
        n = n + 1
        local row = tagRow(n)
        row.name, row.kind = p.name, U.memberStatusKind(p)
        row.badge = tonumber(p.sourceGen) or 3
        row.union = true
        local cx, cy = U.avatarCell(slot)
        row.near = U._talkSlot == slot or (px ~= nil and cx ~= nil
          and math.abs(cx - px) + math.abs(cy - py) <= LinkTags.NEAR_CELLS)
        src.byVobj[U.vobjId(slot)] = row
      end
    end
  end
  local LP = linkPlayers()
  if LP and LP._mapId then
    active = true
    for seat in pairs(LP.remotes()) do
      local name = LP.nameOf(seat)
      if name then
        n = n + 1
        local row = tagRow(n)
        row.name, row.kind = name, LP.statusKind(seat)
        src.byVobj[LP.VOBJ_BASE + seat] = row
      end
    end
  end
  local blender
  n, blender = blenderPartners(src, n)
  active = active or blender
  if not active then return nil end
  local L = link()
  local s = L and L.session and L.session()
  local me = LinkTags._self
  me.name = type(s) == "table" and tostring(s.name or s.playerName or ""):sub(1, 7) or nil
  me.kind = localKind()
  me.badge, me.hidden = nil, inUnion and true or nil
  if me.name and me.name ~= "" then src.player = me end
  return src
end

function LinkTags.tagFor(src, a)
  if not (src and a) then return nil end
  if a.kind == "player" then return src.player end
  local eo = a.eventObject
  local id = eo and eo.virtualId
  return id and src.byVobj[id] or nil
end

function LinkTags.textWidth(name, measure)
  local w = LinkTags._widths[name]
  if w then return w end
  if measure then
    w = measure(name)
  else
    local FrlgFont = require("src.ui.game3.frlg_font")
    local ok, got = pcall(FrlgFont.measure, name, { small = true })
    w = ok and tonumber(got) or (#name * 6)
  end
  w = math.min(LinkTags.MAX_TEXT_W, math.max(0, w))
  if LinkTags._widthCount > 256 then
    LinkTags._widths, LinkTags._widthCount = {}, 0
  end
  LinkTags._widths[name] = w
  LinkTags._widthCount = LinkTags._widthCount + 1
  return w
end

function LinkTags.layout(tag, headX, headY, viewW, measure, out)
  local textW = LinkTags.textWidth(tag.name, measure)
  local iconW = tag.kind and LinkTags.iconSize(tag.kind) or 0
  local lead = iconW > 0 and (iconW + LinkTags.ICON_GAP) or 0
  local badgeW = tag.badge and (badgeModule().SIZE + LinkTags.BADGE_GAP) or 0
  local w = LinkTags.PAD * 2 + textW + lead + badgeW
  local x = math.floor(headX - w / 2 + 0.5)
  if viewW then
    x = math.max(LinkTags.EDGE, math.min(viewW - w - LinkTags.EDGE, x))
  end
  out = out or {}
  out.x, out.y, out.w, out.h = x, math.floor(headY - LinkTags.PLATE_H + LinkTags.HEAD_OVERLAP), w, LinkTags.PLATE_H
  out.textW, out.iconW, out.textX = textW, iconW, x + LinkTags.PAD + lead
  out.badgeX = tag.badge and (out.textX + textW + LinkTags.BADGE_GAP) or nil
  return out
end

local LAYOUT = {}
local TEXT_OPTS = { small = true, colors = nil, maxWidth = 0 }

local function iconImages()
  if LinkTags._images then return LinkTags._images end
  local out = {}
  for kind, rows in pairs(LinkTags.ICONS) do
    local w, h = #rows[1], #rows
    local data = love.image.newImageData(w, h)
    for y = 1, h do
      for x = 1, w do
        local c = LinkTags.COLORS[rows[y]:sub(x, x)]
        if c then data:setPixel(x - 1, y - 1, c[1], c[2], c[3], c[4]) end
      end
    end
    local img = love.graphics.newImage(data)
    img:setFilter("nearest", "nearest")
    out[kind] = img
  end
  LinkTags._images = out
  return out
end

local function plate(x, y, w, h, color)
  love.graphics.setColor(color)
  love.graphics.rectangle("fill", x + 1, y, w - 2, h)
  love.graphics.rectangle("fill", x, y + 1, 1, h - 2)
  love.graphics.rectangle("fill", x + w - 1, y + 1, 1, h - 2)
end

local opaqueTops = setmetatable({}, { __mode = "k" })

local function opaqueTop(spr)
  local top = opaqueTops[spr]
  if top then return top end
  top = 0
  local data = spr.imageData
  local w, h = tonumber(spr.width), tonumber(spr.height)
  if data and data.getPixel and w and h then
    pcall(function()
      for y = 0, h - 1 do
        for x = 0, w - 1 do
          local _, _, _, alpha = data:getPixel(x, y)
          if alpha > 0 then
            top = y
            return
          end
        end
      end
    end)
  end
  opaqueTops[spr] = top
  return top
end

local function foreignHeight(eo)
  local Avatars = require("src.online.union.Avatars")
  local entry = Avatars.resolve(eo.foreign, eo.foreign.host)
  if entry.standin then return Avatars.STANDIN_H end
  return tonumber(entry.h) or Avatars.GB_FRAME
end

local function headTop(a, camY)
  local eo = a.eventObject
  if eo and eo.foreign then return a.y - camY + 16 - foreignHeight(eo) end
  local h, offY, top = 32, 0, 0
  local Ow = package.loaded["src.core.game3.ow_sprites"]
  if Ow and Ow.getDraw and a.graphicsId ~= nil then
    local ok, spr = pcall(Ow.getDraw, a.graphicsId)
    if ok and type(spr) == "table" then
      h = tonumber(spr.height) or h
      offY = tonumber(spr.drawOffY) or 0
      top = opaqueTop(spr)
    end
  end
  return a.y - camY + 16 - h + offY + top
end

local function textDy()
  local Family = require("src.core.game3.link.family")
  return Family.isRubySapphire(Family.activeVersion()) and LinkTags.RS_TEXT_DY or LinkTags.TEXT_DY
end

function LinkTags.unionLayout(tag, headX, headY, viewW, measure, out)
  local Badge = badgeModule()
  out = out or {}
  local bs = Badge.SIZE
  if not tag.near then
    out.x, out.y, out.w, out.h = math.floor(headX - bs / 2), math.floor(headY - bs - LinkTags.UNION_HEAD_GAP), bs, bs
    out.textW, out.badgeX, out.badgeY, out.plate = 0, out.x, out.y, false
    return out
  end
  local textW = LinkTags.textWidth(tag.name, measure)
  local pad = LinkTags.UNION_PAD
  local w = pad + textW + LinkTags.BADGE_GAP + 1 + bs + 1
  local h = LinkTags.PLATE_H
  local x = math.floor(headX - w / 2)
  if viewW then x = math.max(LinkTags.EDGE, math.min(viewW - w - LinkTags.EDGE, x)) end
  local y = math.floor(headY - h - LinkTags.UNION_HEAD_GAP)
  out.x, out.y, out.w, out.h, out.textW, out.plate = x, y, w, h, textW, true
  out.textX = x + pad
  out.badgeX = x + w - 1 - bs
  out.badgeY = y + math.floor((h - bs) / 2)
  return out
end

local function windowPlate(x, y, w, h)
  local FrlgFont = require("src.ui.game3.frlg_font")
  local Chrome = require("src.ui.game3.chrome")
  local fill = Chrome.windowFillColor()
  local edge = FrlgFont.COLOR.NORMAL.fg
  local g = love.graphics
  g.setColor(edge[1], edge[2], edge[3], 1)
  g.rectangle("fill", x + 1, y, w - 2, h)
  g.rectangle("fill", x, y + 1, w, h - 2)
  g.setColor(fill[1], fill[2], fill[3], 1)
  g.rectangle("fill", x + 1, y + 1, w - 2, h - 2)
end

local function drawUnionTag(a, tag, camX, camY, viewW)
  local L = LinkTags.unionLayout(tag, math.floor(a.x - camX) + 8, math.floor(headTop(a, camY)), viewW, nil, LAYOUT)
  if L.plate then
    windowPlate(L.x, L.y, L.w, L.h)
    local FrlgFont = require("src.ui.game3.frlg_font")
    TEXT_OPTS.colors, TEXT_OPTS.maxWidth = FrlgFont.COLOR.NORMAL, L.textW
    pcall(FrlgFont.draw, tag.name, L.textX, L.y + textDy(), TEXT_OPTS)
  end
  badgeModule().draw(L.badgeX, L.badgeY, tag.badge, tag.badge, 1)
end

local function drawTag(a, tag, camX, camY, viewW, isSelf)
  if tag.union then return drawUnionTag(a, tag, camX, camY, viewW) end
  local L = LinkTags.layout(tag, a.x - camX + 8, headTop(a, camY), viewW, nil, LAYOUT)
  plate(L.x, L.y, L.w, L.h, isSelf and LinkTags.PLATE_SELF or LinkTags.PLATE)
  if tag.kind then
    local img = iconImages()[tag.kind]
    if img then
      local _, ih = LinkTags.iconSize(tag.kind)
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(img, L.x + LinkTags.PAD, L.y + math.floor((L.h - ih) / 2))
    end
  end
  local FrlgFont = require("src.ui.game3.frlg_font")
  TEXT_OPTS.colors, TEXT_OPTS.maxWidth = FrlgFont.COLOR.WHITE, L.textW
  pcall(FrlgFont.draw, tag.name, L.textX, L.y + textDy(), TEXT_OPTS)
  if L.badgeX then
    local Badge = badgeModule()
    Badge.draw(L.badgeX, L.y + math.floor((L.h - Badge.SIZE) / 2), tag.badge, tag.badge, 1)
  end
end

local function drawList(src, list, camX, camY, viewW, billboard)
  if not list then return end
  for _, a in ipairs(list) do
    local tag = LinkTags.tagFor(src, a)
    if tag and tag.name and tag.name ~= "" and not tag.hidden then
      local pushed = billboard and billboard(a.x, a.y, camX, camY)
      drawTag(a, tag, camX, camY, viewW, a.kind == "player")
      if pushed then love.graphics.pop() end
    end
  end
end

function LinkTags.draw(under, over, camX, camY, viewW, _viewH, billboard)
  if not (love and love.graphics) then return false end
  local src = LinkTags.sources()
  if not src then return false end
  drawList(src, under, camX, camY, viewW, billboard)
  drawList(src, over, camX, camY, viewW, billboard)
  love.graphics.setColor(1, 1, 1, 1)
  return true
end

return LinkTags
