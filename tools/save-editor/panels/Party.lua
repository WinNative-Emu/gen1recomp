local PartyMod = require("src.pokemon.Party")
local Theme = require("Theme")
local Ops = require("Ops")
local MonEditor = require("MonEditor")
local PAL = Theme.PAL

local Party = {}

local function rosterWidth(w, s)
  return Theme.clamp(w * 0.27, 250 * s, 340 * s)
end

-- HP colour follows the game's own health bar thresholds.
local function hpColor(frac)
  if frac <= 0.2 then
    return PAL.red
  end
  if frac <= 0.5 then
    return PAL.yellow
  end
  return PAL.green
end

local function hpFrac(mon)
  local maxHp = mon.maxHp or (mon.stats and mon.stats.hp) or 1
  return Ops.clamp((tonumber(mon.hp) or 0) / math.max(maxHp, 1), 0, 1), maxHp
end

local function toolbar(S, Kit, x, y, w, vertical)
  local s, row, gap = Kit.scale, Kit.controlH(), 8 * Kit.scale
  local selected = S.save.party[S.selectedParty or 0] ~= nil and S.editingMon == S.save.party[S.selectedParty]
  local n = #S.save.party
  if Kit.iconButton(x, y, row, row, vertical and "arrow-up" or "arrow-left", "Move up",
      { enabled = selected and S.selectedParty > 1 }) then
    Ops.partyMove(S, -1)
  end
  if Kit.iconButton(x + row + gap, y, row, row, vertical and "arrow-down" or "arrow-right", "Move down",
      { enabled = selected and S.selectedParty < n }) then
    Ops.partyMove(S, 1)
  end
  local armed = Ops.armLabel(S, "party-remove", "Remove") ~= "Remove"
  local removeW = armed and Kit.buttonWidth("Confirm?", { font = "button", icon = "check" }, row) or row
  local rx = x + w - removeW
  if armed then
    if Kit.button(rx, y, removeW, row, "Confirm?", { kind = "danger", font = "button", icon = "check" }) then
      Ops.partyRemove(S)
    end
  elseif Kit.iconButton(rx, y, row, row, "trash", "Remove", { kind = "danger", enabled = selected }) then
    Ops.partyRemove(S)
  end
  local addOpts = { font = "button", icon = "plus", enabled = n < PartyMod.MAX }
  local addW = Kit.buttonWidth("Add", addOpts, row)
  if Kit.button(rx - gap - addW, y, addW, row, "Add", addOpts) then
    Ops.partyAdd(S)
  end
  return row
end

local function drawRoster(S, Kit, x, y, listW, h)
  local s = Kit.scale
  Kit.card(x, y, listW, h)
  local pad = 16 * s
  local cx = x + pad
  local innerW = listW - 2 * pad

  Kit.caption(cx, y + pad, "PARTY")
  Kit.textRight("mono", ("%d/%d"):format(#S.save.party, PartyMod.MAX), cx + innerW, y + pad, PAL.caption)

  local actH = Kit.controlH()
  local actY = y + h - pad - actH
  S.toastBottom = math.min(S.toastBottom or actY, actY)
  local listTop = y + pad + Kit.textHeight("caption") + 14 * s
  local listH = actY - 14 * s - listTop

  if #S.save.party == 0 then
    Kit.emptyBox(cx, listTop, innerW, listH, "Party is empty. Add creates a Lv5 Pokemon owned by the player.")
  else
    local rowH = math.max(76 * s, Kit.tapMin() + 28 * s)
    local rowGap = 8 * s
    S.selectedParty = Ops.clamp(S.selectedParty or 1, 1, #S.save.party)
    local drawn, shift = Kit.list(S, "partyOffset", cx, listTop, innerW, listH, #S.save.party, rowH + rowGap)
    Kit.pushClip(cx, listTop, innerW, listH)
    for i = 1, drawn do
      local slot = S.partyOffset + i
      local mon = S.save.party[slot]
      if not mon then
        break
      end
      local ry = listTop + (i - 1) * (rowH + rowGap) - shift
      local selected = (S.editingMon == mon)
      if Kit.row(cx, ry, innerW, rowH, selected, PAL.text) then
        Ops.selectParty(S, slot)
      end
      local rpad = 10 * s
      local icon = math.min(56 * s, rowH - 12 * s)
      MonEditor.drawSprite(S, Kit, mon.species, cx + rpad, ry + (rowH - icon) / 2, icon, mon)

      local tx = cx + rpad + icon + 10 * s
      local tw = math.max(40 * s, cx + innerW - rpad - tx)
      local lvText = ("Lv %d"):format(mon.level or 0)
      local lvW = Kit.textWidth("small", lvText)
      local nameY = ry + 12 * s
      Kit.textRight("small", lvText, tx + tw, nameY + (Kit.textHeight("monoRow") - Kit.textHeight("small")) / 2, PAL.muted)
      local shiny = MonEditor.isShiny(S, mon)
      local spark = shiny and Kit.textHeight("small") or 0
      local name = Kit.ellipsize("monoRow", MonEditor.displayName(S, mon), tw - lvW - spark - 16 * s)
      Kit.textBold("monoRow", name, tx, nameY, PAL.heading)
      if shiny then
        Kit.icon("sparkles", tx + Kit.textWidth("monoRow", name) + 6 * s,
          nameY + (Kit.textHeight("monoRow") - spark) / 2, spark, PAL.yellow)
      end
      local frac, maxHp = hpFrac(mon)
      Kit.meter(tx, ry + rowH / 2 + 1 * s, tw, 5 * s, frac * 100, hpColor(frac))
      Kit.text("tiny", ("HP %d/%d"):format(mon.hp or 0, maxHp), tx, ry + rowH - 10 * s - Kit.textHeight("tiny"), PAL.muted)
    end
    Kit.popClip()
    Kit.listScrollbar(S, "partyOffset", cx, listTop, innerW, listH)
  end

  Theme.col(PAL.cardBorder, 0.22)
  love.graphics.rectangle("fill", x, actY - 8 * s, listW, 1)
  toolbar(S, Kit, cx, actY, innerW, true)
end

local function drawStrip(S, Kit, x, y, w)
  local s = Kit.scale
  local gap = 10 * s
  local cy = y
  Kit.caption(x, cy, "PARTY")
  Kit.textRight("mono", ("%d/%d"):format(#S.save.party, PartyMod.MAX), x + w, cy, PAL.caption)
  cy = cy + Kit.textHeight("caption") + 12 * s
  local n = #S.save.party
  if n == 0 then
    local boxH = 80 * s
    Kit.emptyBox(x, cy, w, boxH, "Party is empty")
    cy = cy + boxH + gap
  else
    local cols = Theme.clamp(math.floor((w + gap) / (92 * s + gap)), 3, 6)
    local tileW = (w - (cols - 1) * gap) / cols
    local sprite = math.floor(math.min(tileW - 20 * s, 64 * s))
    local tileH = math.ceil(10 * s + sprite + 4 * s + Kit.textHeight("tiny") + 8 * s + 4 * s + 10 * s)
    for i, mon in ipairs(S.save.party) do
      local col, line = (i - 1) % cols, math.floor((i - 1) / cols)
      local tx, ty = x + col * (tileW + gap), cy + line * (tileH + gap)
      if Kit.row(tx, ty, tileW, tileH, S.editingMon == mon, PAL.text) then
        Ops.selectParty(S, i)
      end
      MonEditor.drawSprite(S, Kit, mon.species, tx + (tileW - sprite) / 2, ty + 10 * s, sprite, mon)
      local ly = ty + 10 * s + sprite + 4 * s
      Kit.textCenter("tiny", ("Lv %d"):format(mon.level or 0), tx, ly, tileW, PAL.muted)
      if MonEditor.isShiny(S, mon) then
        local spark = 14 * s
        Kit.icon("sparkles", tx + tileW - spark - 8 * s, ty + 8 * s, spark, PAL.yellow)
      end
      local frac = hpFrac(mon)
      local barW = tileW - 28 * s
      Kit.meter(tx + 14 * s, ly + Kit.textHeight("tiny") + 8 * s, barW, 4 * s, frac * 100, hpColor(frac))
    end
    cy = cy + math.ceil(n / cols) * (tileH + gap)
  end
  cy = cy + toolbar(S, Kit, x, cy, w, false)
  return cy - y
end

function Party.draw(S, Kit, x, y, w, h)
  local s = Kit.scale
  S.inspectorBack = false
  if w < 800 * s then
    MonEditor.draw(S, Kit, x, y, w, h, function(px, py, pw)
      return drawStrip(S, Kit, px, py, pw)
    end)
  else
    local gap = 14 * s
    local listW = rosterWidth(w, s)
    drawRoster(S, Kit, x, y, listW, h)
    MonEditor.draw(S, Kit, x + listW + gap, y, w - listW - gap, h)
  end
end

return Party
