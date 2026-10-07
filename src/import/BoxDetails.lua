local Kit = require("src.ui.kit.Kit")
local Theme = require("src.ui.kit.Theme")
local Icons = require("src.ui.kit.Icons")
local UI = require("src.import.BoxUI")
local Details = {}
local PAL = Theme.PAL
Details.SECTIONS = { "Overview", "Moves", "Stats", "Origin" }
Details.HELP = {
  Overview = "the basics for this pokémon. marks are just labels you can add. held items stay with it when you move it.",
  Moves = "PP is how many uses the move has left. PP Ups increase its maximum. the bar shows what’s left right now.",
  Stats = "current stats, built-in potential and training effort sit in separate columns. — means it wasn’t recorded.",
  Origin = "who caught it and where it came from. trainer IDs distinguish trainers with the same name. missing details say Not recorded.",
}
function Details.help(entry, section)
  if section ~= "Stats" then return Details.HELP[section] end
  return entry.generation == 3
    and "IVs are the pokémon’s built-in potential. EVs are effort from training. — means it wasn’t recorded."
    or "DVs are the pokémon’s built-in potential. Stat Exp is effort from training. Gen 2 shares its Special DV and effort between both special stats."
end
local OVERVIEW = { Experience = true, Gender = true, ["Friendship / egg cycles"] = true,
  Nature = true, Ability = true, Markings = true, ["Pokérus"] = true }
local STAT_FIELDS = { Stats = true, IVs = true, DVs = true, EVs = true, ["Stat experience"] = true, Contest = true }
local STAT_ORDER = { "hp", "attack", "defense", "spAtk", "spDef", "speed", "special" }
local ALIASES = { atk = "attack", def = "defense", spe = "speed", spa = "spAtk", spd = "spDef",
  specialAttack = "spAtk", specialDefense = "spDef" }
local LABELS = { hp = "HP", attack = "Attack", defense = "Defense", speed = "Speed",
  spAtk = "Sp. Attack", spDef = "Sp. Defense", special = "Special" }
local FIELD_ICONS = { Experience = "award", Gender = "user-round", Nature = "paintbrush", Ability = "shield-check",
  Friendship = "heart", ["Egg cycles"] = "heart", ["Held item"] = "backpack", Markings = "check",
  ["Pokérus"] = "heart", ["Original Trainer"] = "user-round", ["Trainer ID"] = "users", ["Secret ID"] = "lock",
  ["Poké Ball"] = "package", ["Met game"] = "flag", ["Met location"] = "map-pin", ["Met level"] = "award",
  ["Fateful encounter"] = "flag", Tags = "file-pen-line" }
local function human(key)
  return LABELS[key] or tostring(key):gsub("(%l)(%u)", "%1 %2"):gsub("_", " "):gsub("^%l", string.upper)
end
local function normalized(values)
  local out = {}
  for key, value in pairs(values or {}) do if not ALIASES[key] then out[key] = value end end
  for key, value in pairs(values or {}) do
    if ALIASES[key] then
      if out[ALIASES[key]] == nil then out[ALIASES[key]] = value
      elseif out[ALIASES[key]] ~= value then out[key] = value end
    end
  end
  return out
end
local function number(value)
  local text = tostring(value)
  local sign, whole, tail = text:match("^(-?)(%d+)(.*)$")
  if not whole then return text end
  return sign .. whole:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "") .. tail
end
local function shown(value)
  if value == nil then return "Not recorded" end
  if value == true then return "Yes" elseif value == false then return "No" end
  return tostring(value)
end
local function statRows(entry)
  local mon, gen = entry.mon, entry.generation
  local stats = normalized(entry.display.stats)
  local genes = normalized(gen == 3 and mon.ivs or mon.dvs)
  local effort = normalized(gen == 3 and mon.evs or mon.statExp)
  local derived
  if gen <= 2 and genes.hp == nil and genes.attack ~= nil and genes.defense ~= nil
      and genes.speed ~= nil and genes.special ~= nil then
    genes.hp = require("src.battle.gen2.Mon").hpDV(genes); derived = true
  end
  if gen == 2 then
    for _, key in ipairs({ "spAtk", "spDef" }) do
      genes[key] = genes.special ~= nil and genes.special or genes[key]
      effort[key] = effort.special ~= nil and effort.special or effort[key]
    end
  end
  local keys, seen = {}, {}
  local function add(key)
    if not seen[key] then keys[#keys + 1], seen[key] = key, true end
  end
  for _, key in ipairs(STAT_ORDER) do
    if stats[key] ~= nil or genes[key] ~= nil or effort[key] ~= nil then
      if gen ~= 2 or key ~= "special" or stats.special ~= nil then add(key) end
    end
  end
  local extras = {}
  for _, values in ipairs({ stats, genes, effort }) do
    for key in pairs(values) do
      if not seen[key] and not (gen == 2 and key == "special") then extras[key] = true end
    end
  end
  local sorted = {}; for key in pairs(extras) do sorted[#sorted + 1] = key end
  table.sort(sorted, function(a, b) return tostring(a) < tostring(b) end)
  for _, key in ipairs(sorted) do add(key) end
  local rows = {}
  local effortRecorded = type(gen == 3 and mon.evs or mon.statExp) == "table"
  for _, key in ipairs(keys) do rows[#rows + 1] = { label = human(key), value = stats[key], gene = genes[key],
    effort = effort[key] ~= nil and effort[key] or effortRecorded and 0 or nil } end
  return rows, derived
end

function Details.model(entry)
  local d, mon = entry.display, entry.mon
  local model = { overview = {}, origin = {}, moves = d.moveDetails or {}, ribbons = {}, contest = {} }
  local moveNames = {}; for _, move in ipairs(model.moves) do moveNames[move.name] = true end
  for _, field in ipairs(require("src.box.Metadata").summary(entry)) do
    local label, value = field[1], field[2]
    if not STAT_FIELDS[label] and not moveNames[label] and label ~= "Ribbons" then
      local group = OVERVIEW[label] and model.overview or model.origin
      if label == "Experience" and d.experience ~= nil then value = number(d.experience)
      elseif label == "Friendship / egg cycles" then label = d.egg and "Egg cycles" or "Friendship"
      elseif label == "Markings" and tonumber(value) then
        local marks = {}; for i, mark in ipairs({ "Circle", "Square", "Triangle", "Heart" }) do
          if math.floor(tonumber(value) / 2 ^ (i - 1)) % 2 == 1 then marks[#marks + 1] = mark end
        end
        value = #marks > 0 and table.concat(marks, " · ") or "None"
      elseif label == "Pokérus" and tonumber(value) then
        local status = tonumber(value)
        value = status == 0 and "None" or "Strain " .. math.floor(status / 16) .. "\n"
          .. (status % 16 == 0 and "Recovered" or status % 16 .. " days left")
      elseif label == "Fateful encounter" then value = shown(d.fateful)
      elseif (label == "Trainer ID" or label == "Secret ID") and tonumber(value) then
        value = string.format("%05d", tonumber(value))
      elseif label == "Met game" and tonumber(value) then
        for _, layout in ipairs({ "rs", "emerald", "frlg" }) do
          local version = require("src.save_convert.gen3_layouts." .. layout).GAME_CODES[tonumber(value)]
          if version then value = require("src.core.GameVersion").info(version).label; break end
        end
      end
      group[#group + 1] = { label = label, value = value, icon = FIELD_ICONS[label] }
    end
  end
  model.overview[#model.overview + 1] = { label = "Held item", value = d.item == nil and "Not recorded" or d.item ~= "" and d.item or "None", icon = "backpack" }
  if entry.tags and entry.tags ~= "" then model.overview[#model.overview + 1] = { label = "Tags", value = entry.tags, icon = "file-pen-line" } end
  model.stats, model.derivedHP = statRows(entry)
  local contestKeys = {}; for key in pairs(mon.contest or {}) do contestKeys[#contestKeys + 1] = key end
  table.sort(contestKeys, function(a, b) return tostring(a) < tostring(b) end)
  for _, key in ipairs(contestKeys) do model.contest[#model.contest + 1] = { label = human(key), value = tostring(mon.contest[key]), icon = "award" } end
  if entry.generation == 3 then
    local Ribbons = require("src.core.game3.rse.ribbons")
    for _, key in ipairs(Ribbons.COUNTED) do
      local count = Ribbons.get(mon, key)
      if count > 0 then model.ribbons[#model.ribbons + 1] = { label = human(key), value = count > 1 and "×" .. count or "Earned", icon = "award" } end
    end
    model.hasRibbons = true
  end
  return model
end

local function fields(rows, x, y, w, m)
  local gap, pad = 10 * m.s, 12 * m.s
  local cols = w >= 580 * m.s and 3 or w >= 270 * m.s and 2 or 1
  local cw = (w - (cols - 1) * gap) / cols
  for first = 1, #rows, cols do
    local height = 0
    for i = first, math.min(#rows, first + cols - 1) do
      local row = rows[i]
      local labelH = math.max(18 * m.s, Kit.wrapHeight("micro", row.label, cw - 2 * pad - 24 * m.s))
      height = math.max(height, 2 * pad + labelH + 8 * m.s + Kit.wrapHeight("button", row.value, cw - 2 * pad))
    end
    for i = first, math.min(#rows, first + cols - 1) do
      local row, cx = rows[i], x + (i - first) * (cw + gap)
      Theme.card(cx, y, cw, height, { shadow = true })
      Icons.draw(row.icon or "book-open", cx + pad, y + pad, 18 * m.s, PAL.blue, 1)
      local labelH = math.max(18 * m.s, Kit.textWrapped("micro", row.label, cx + pad + 24 * m.s,
        y + pad, cw - 2 * pad - 24 * m.s, PAL.muted))
      Kit.textWrapped("button", row.value, cx + pad, y + pad + labelH + 8 * m.s, cw - 2 * pad,
        row.value == "Not recorded" and PAL.muted or PAL.heading)
    end
    y = y + height + gap
  end
  return y
end
local function heading(imp, label, help, x, y, w, m)
  local h = math.max(Kit.tapMin(), Kit.textHeight("button"))
  Kit.textBold("button", label, x, y + (h - Kit.textHeight("button")) / 2, PAL.heading)
  if help then UI.help(imp, label, x + w - h, y, h, help) end
  return y + h + 8 * m.s
end
local function statTable(entry, model, x, y, w, m)
  local gen = entry.generation
  local compact = w < 580 * m.s
  local pad, rowH = 12 * m.s, (compact and 30 or 38) * m.s
  local headerH = (compact and 28 or 34) * m.s
  Theme.card(x, y, w, 2 * pad + headerH + #model.stats * rowH, { shadow = true })
  local inner, labelW = w - 2 * pad, (w - 2 * pad) * .37
  local numberW = (inner - labelW) / 3
  local headers = { "Value", gen == 3 and "IV" or "DV", gen == 3 and "EV" or "Stat Exp" }
  Kit.text("micro", "Stat", x + pad, y + pad + 6 * m.s, PAL.muted)
  for i, label in ipairs(headers) do Kit.textCenter("micro", label, x + pad + labelW + (i - 1) * numberW,
    y + pad + 6 * m.s, numberW, PAL.muted) end
  local cy = y + pad + headerH
  for i, row in ipairs(model.stats) do
    if i % 2 == 1 then Theme.fillRounded(x + 4 * m.s, cy, w - 8 * m.s, rowH, PAL.raised, .8, 5 * m.s) end
    Kit.text("small", row.label, x + pad, cy + (rowH - Kit.textHeight("small")) / 2, PAL.text)
    for column, key in ipairs({ "value", "gene", "effort" }) do
      local value = row[key] == nil and "—" or tostring(row[key])
      Kit.textCenterBold(column == 1 and "button" or "small", value, x + pad + labelW + (column - 1) * numberW,
        cy + (rowH - Kit.textHeight(column == 1 and "button" or "small")) / 2, numberW,
        column == 1 and PAL.heading or row[key] == nil and PAL.muted or PAL.blue)
    end
    cy = cy + rowH
  end
  y = cy + pad + 10 * m.s
  Kit.text("micro", "— not recorded" .. (model.derivedHP and " · HP DV is derived" or ""), x, y, PAL.muted)
  return y + Kit.textHeight("micro") + 10 * m.s
end
local function moves(rows, x, y, w, m)
  local pad, gap = 14 * m.s, 10 * m.s
  for _, move in ipairs(rows) do
    local h = 2 * pad + Kit.textHeight("button") + Kit.textHeight("micro") + 20 * m.s
    local ppW = math.min(116 * m.s, w * .34)
    local titleW = w - 2 * pad - 30 * m.s - ppW - gap
    local titleH = Kit.wrapHeight("button", tostring(move.name), titleW)
    if titleH > Kit.textHeight("button") then h = h + titleH - Kit.textHeight("button") end
    Theme.card(x, y, w, h, { shadow = true })
    Icons.draw("book-open", x + pad, y + pad, 22 * m.s, PAL.blue, 1)
    Kit.textWrapped("button", tostring(move.name), x + pad + 30 * m.s, y + pad, titleW, PAL.heading)
    Kit.textRight("button", (move.pp == nil and "—" or move.pp) .. " / " .. (move.maxPP == nil and "—" or move.maxPP),
      x + w - pad, y + pad, PAL.heading)
    Kit.text("micro", tostring(move.ppUps or 0) .. " PP Ups", x + pad + 30 * m.s, y + h - pad - Kit.textHeight("micro"), PAL.muted)
    Kit.textRight("micro", "PP", x + w - pad, y + h - pad - Kit.textHeight("micro"), PAL.muted)
    local trackW, trackH = w - 2 * pad, 3 * m.s
    Theme.fillRounded(x + pad, y + h - 7 * m.s, trackW, trackH, PAL.line, .4, trackH)
    if type(move.pp) == "number" and type(move.maxPP) == "number" and move.maxPP > 0 then
      Theme.fillRounded(x + pad, y + h - 7 * m.s, trackW * math.max(0, math.min(1, move.pp / move.maxPP)), trackH,
        move.pp == 0 and PAL.red or PAL.blue, 1, trackH)
    end
    y = y + h + gap
  end
  if #rows == 0 then y = fields({ { label = "Moves", value = "None recorded", icon = "book-open" } }, x, y, w, m) end
  return y
end
local modelCache = setmetatable({}, { __mode = "k" })
function Details.draw(imp, entry, section, x, y, w, m)
  local hit = modelCache[entry]
  if not hit or hit.display ~= entry.display or hit.mon ~= entry.mon or hit.tags ~= entry.tags then
    hit = { display = entry.display, mon = entry.mon, tags = entry.tags, model = Details.model(entry) }
    modelCache[entry] = hit
  end
  local top, model = y, hit.model
  if section == "Overview" then y = fields(model.overview, x, y, w, m)
  elseif section == "Moves" then y = moves(model.moves, x, y, w, m)
  elseif section == "Stats" then
    y = statTable(entry, model, x, y, w, m)
    if #model.contest > 0 then y = heading(imp, "Contest", nil, x, y, w, m); y = fields(model.contest, x, y, w, m) end
  else
    y = fields(model.origin, x, y, w, m)
    if model.hasRibbons then
      y = heading(imp, "Ribbons", nil, x, y, w, m)
      y = fields(#model.ribbons > 0 and model.ribbons or { { label = "Ribbons", value = "None", icon = "award" } }, x, y, w, m)
    end
  end
  return y - top
end
return Details
