local Messages = {}

Messages.GB_WIDTH = 18

local TEXT = {
  missing_import = "Import {need} first.",
  policy_mismatch = "The other player has a different Union Room version.",
  proto_mismatch = "The other player has a different Union Room version.",
  bad_op = "That can't be done here.",
  bad_record = "This Pokemon's data can't be read.",
  species_unknown = "This Pokemon's species is unknown.",
  move_unknown = "One of its moves is unknown.",
  egg = "Eggs can't be used here.",
  mail = "Take the Mail off first.",
  item_unknown = "Its held item is unknown.",
  item_unrepresentable = "The other game has no {item}. Take it off first.",
  species_missing = "{species} doesn't exist in the other game.",
  species_not_in_ruleset = "{species} can't join this battle. Only No. 1 to {dexMax} can.",
  move_not_in_ruleset = "{move} isn't used in this battle.",
  move_unsupported = "{move} can't be used in this battle.",
  move_not_legal = "{species} can't learn {move}.",
  move_missing = "{move} doesn't exist in the other game.",
  replacement_not_legal = "That move can't be chosen.",
  no_legal_moves = "It needs at least one move.",
  no_moves = "It needs at least one move.",
  nickname_unencodable = "Its nickname can't be written in the other game.",
  ot_unencodable = "Its trainer name can't be written in the other game.",
  ot_invalid = "Its trainer ID is invalid.",
  personality_unrepresentable = "It can't keep its looks in the other game.",
  traits_unrepresentable = "It can't keep its looks in the other game.",
  choose_sit_out = "Choose {need} to sit out.",
  team_too_small = "Choose {size} Pokemon.",
  native_needs_same_gen = "This battle needs the same generation.",
  rental_type_mismatch = "A rental Pokemon is unavailable.",
  rental_duplicate_move = "A rental Pokemon is unavailable.",
  rental_bad_moves = "A rental Pokemon is unavailable.",
  unknown_ruleset = "These rules are unknown.",
}

local CHANGE = {
  change = "{field} will change.",
  loss = "{field} will be lost.",
}

local FIELD = {
  dvs = "Its strength values", ivs = "Its strength values", statExp = "Its training", evs = "Its training",
  exp = "Its Exp. Points", experience = "Its Exp. Points", nickname = "Its nickname",
  moves = "A move", pp = "PP", item = "Its held item", heldItem = "Its held item",
  catchRate = "Its held item", happiness = "Its friendship", friendship = "Its friendship",
  pokerus = "Pokerus", ribbons = "Its ribbons", contest = "Its contest stats", nature = "Its nature",
  ability = "Its ability", abilityNum = "Its ability", personality = "Its personality",
  origin = "Where it was met", caughtData = "Where it was met", shiny = "Its color",
  gender = "Its gender", unownLetter = "Its form", species = "The Pokemon",
  hp = "Its HP", status = "Its status", markings = "Its marks", otSecretId = "Its trainer data",
  otGender = "Its trainer data", language = "Its language", metLocation = "Where it was met",
  metLevel = "Where it was met", metGame = "Where it was met", pokeball = "Its Ball",
  caughtLevel = "Where it was met", caughtTime = "When it was met", caughtLocation = "Where it was met",
  caughtByGender = "Its trainer data", caughtGender = "Its trainer data", caught = "Where it was met",
  fatefulEncounter = "Its obedience mark", modernFatefulEncounter = "Its obedience mark",
  championRibbon = "Its ribbons", extra = "Its extra data from mods",
  egg = "Its egg data", eggSteps = "Its egg data", eggCycles = "Its egg data", isEgg = "Its egg data",
  sleep = "Its status", sleepTurns = "Its status",
  ot = "Its trainer data", otId = "Its trainer ID", otName = "Its trainer name", level = "Its level",
  speciesId = "The Pokemon", stats = "Its stats", baseStats = "Its stats", types = "Its type",
  evolution = "How it evolves", mail = "Its Mail", ppBonuses = "PP", ppBonusesPacked = "PP",
}

local function fill(template, detail, names)
  detail = detail or {}
  names = names or {}
  return (template:gsub("{(%w+)}", function(key)
    local value = detail[key]
    if key == "species" then
      local n = detail.national or detail.species
      value = names.species and names.species(n) or (n and ("No. " .. tostring(n))) or "It"
    elseif key == "move" and detail.move ~= nil then
      value = names.move and names.move(detail.move) or ("move " .. tostring(detail.move))
    elseif key == "item" and detail.item ~= nil then
      value = names.item and names.item(detail.item) or tostring(detail.item)
    elseif key == "need" and type(value) == "table" then
      value = "the other game"
    end
    return value ~= nil and tostring(value) or ""
  end))
end

local function wrap(text, width)
  local lines, line = {}, ""
  for word in text:gmatch("%S+") do
    if line == "" then
      line = word
    elseif #line + 1 + #word <= width then
      line = line .. " " .. word
    else
      lines[#lines + 1] = line
      line = word
    end
  end
  if line ~= "" then lines[#lines + 1] = line end
  return lines
end

function Messages.style(gen)
  return (tonumber(gen) or 3) >= 3 and "gba" or "gb"
end

function Messages.format(text, gen)
  if Messages.style(gen) == "gb" then
    return wrap(text:upper(), Messages.GB_WIDTH)
  end
  return { text }
end

function Messages.text(code, detail, names)
  local template = TEXT[code] or "That can't be done."
  return fill(template, detail, names)
end

function Messages.about(name, code, detail, names)
  local template = TEXT[code] or "That can't be done."
  if not template:find("{species}", 1, true) then return tostring(name) .. ": " .. fill(template, detail, names) end
  local own = {}
  for k, v in pairs(names or {}) do own[k] = v end
  own.species = function() return name end
  return fill(template, detail, own)
end

function Messages.render(code, gen, detail, names)
  return Messages.format(Messages.text(code, detail, names), gen)
end

function Messages.block(row, gen, names)
  return Messages.render(row.code, gen, row.detail, names)
end

function Messages.change(row, gen)
  local template = CHANGE[row.kind] or CHANGE.change
  local field = FIELD[row.field] or FIELD[(tostring(row.field):match("^(%a+)"))] or "Some data"
  return Messages.format(fill(template, { field = field }), gen)
end

function Messages.known(code)
  return TEXT[code] ~= nil
end

return Messages
