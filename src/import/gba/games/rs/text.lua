return function(V)
  local Source = require("src.import.gba.versions_text_rs")
  local function offsets(names)
    local out = {}
    for _, name in ipairs(names) do out[name] = V.sym(name) end
    return out
  end
  V.NAMED_TEXTS = offsets(Source.NAMED_TEXTS)
  V.NAMED_BATTLE_TEXTS = offsets(Source.NAMED_BATTLE_TEXTS)
  V.BATTLE_STRING_IDS = Source.BATTLE_STRING_IDS
  V.TEXT_TABLES = {}
  for i, t in ipairs(Source.TEXT_TABLES) do
    V.TEXT_TABLES[i] = {
      name = t.name, addr = V.sym(t.name), stride = t.stride,
      count = V.count(t.name, t.stride * (t.inner or 1)),
      inner = t.inner, battle = t.battle or t.name == "gBattleStringsTable", inline = t.inline, ids = t.ids,
    }
  end

  V.TEXT_PLACEHOLDERS = {}
  local Placeholders = require("src.import.gba.text_placeholders_extract")
  for name, label in pairs(Placeholders.rsSymbols(V.GAME)) do V.TEXT_PLACEHOLDERS[name] = V.sym(label) end
end
