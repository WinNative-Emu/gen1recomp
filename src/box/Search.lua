local Search = {}
local FOLD = { ["É"]="e",["é"]="e",["È"]="e",["è"]="e",["Ê"]="e",["ê"]="e",
  ["À"]="a",["à"]="a",["Á"]="a",["á"]="a",["Ä"]="a",["ä"]="a",
  ["Í"]="i",["í"]="i",["Ï"]="i",["ï"]="i",["Ó"]="o",["ó"]="o",["Ö"]="o",["ö"]="o",
  ["Ú"]="u",["ú"]="u",["Ü"]="u",["ü"]="u",["Ñ"]="n",["ñ"]="n",["Ç"]="c",["ç"]="c" }
function Search.normalize(value)
  return (tostring(value or ""):gsub("[%z\1-\127\194-\244][\128-\191]*",function(glyph)
    return FOLD[glyph] or glyph:lower()
  end))
end

function Search.compile(query)
  local terms = {}
  local token, quoted = "", false
  for ch in Search.normalize(query):gmatch(".") do
    if ch == '"' then quoted = not quoted
    elseif ch:match("%s") and not quoted then
      if token ~= "" then terms[#terms + 1], token = token, "" end
    else token = token .. ch end
  end
  if token ~= "" then terms[#terms + 1] = token end
  return function(entry, boxName)
    if #terms == 0 then return true end
    local d = entry.display
    local fields = { name = d.name, species = d.species, dex = d.national,
      type = d.types, move = d.moves, item = d.item, game = entry.version, box = boxName,
      trainer = d.trainer, gender = d.gender, nature = d.nature, ability = d.ability,
      location = d.location, tag = entry.tags }
    local all = Search.normalize(table.concat({ tostring(d.name or ""), tostring(d.species or ""),
      tostring(d.national or ""), tostring(d.types or ""), tostring(d.moves or ""),
      tostring(d.item or ""), tostring(d.level or ""), entry.version, tostring(boxName or ""),
      tostring(d.trainer or ""), tostring(d.nature or ""), tostring(d.ability or ""),
      tostring(d.gender or ""), tostring(entry.tags or "") }, " "))
    for _, raw in ipairs(terms) do
      local term, negate = raw, false
      if term:sub(1, 1) == "-" then term, negate = term:sub(2), true end
      local matched
      local property, operator, number = term:match("^(%a+)([<>=]+)(%d+)$")
      local numeric = { level = d.level, lv = d.level, hp = d.hp, attack = d.attack,
        defense = d.defense, speed = d.speed, special = d.special, spatk = d.spAtk,
        spdef = d.spDef, friendship = d.friendship }
      if property and numeric[property] ~= nil then
        local value, wanted = tonumber(numeric[property]) or 0, tonumber(number)
        matched = operator == "<" and value < wanted or operator == ">" and value > wanted
          or operator == "<=" and value <= wanted or operator == ">=" and value >= wanted
          or operator == "=" and value == wanted
      elseif term == "shiny" then matched = d.shiny == true
      elseif term == "egg" then matched = d.egg == true
      elseif term:match("^mark:") then
        local mark = ({ circle = 1, square = 2, triangle = 4, heart = 8 })[term:sub(6)]
        local value = tonumber(entry.generation == 3 and entry.mon.markings or entry.markings) or 0
        matched = mark ~= nil and math.floor(value / mark) % 2 == 1
      else
        local key, value = term:match("^(%a+):(.+)$")
        local text = key and fields[key]
        if key == "gender" and text ~= nil then matched = Search.normalize(text) == value
        elseif text ~= nil then matched = Search.normalize(text):find(value, 1, true) ~= nil
        else matched = all:find(term, 1, true) ~= nil end
      end
      if (matched and negate) or (not matched and not negate) then return false end
    end
    return true
  end
end

return Search
