package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")
love.graphics.setLineJoin = love.graphics.setLineJoin or function() end
love.graphics.newShader = love.graphics.newShader or function() return {} end
local T = require("tests.harness")
local Details = require("src.import.BoxDetails")
local Kit = require("src.ui.kit.Kit")
Kit.fonts = require("src.ui.kit.Theme").fonts(1)
local Store = require("src.box.Store")
local entry = { generation = 3, version = "emerald", mon = {
    ivs = { hp = 31, atk = 15, def = 0, spa = 14, spd = 18, spe = 20 }, evs = { spe = 252 },
    contest = { cool = 0, beauty = 80, sheen = 15 }, ribbons = { cool = 2, champion = 1 },
  }, display = { stats = { hp = 110, attack = 70, defense = 45, spAtk = 66, spDef = 73, speed = 156 },
    experience = 125000, nature = "Jolly", ability = "STATIC", trainer = "Alice", trainerId = 42, secretId = 3,
    metGame = 3, metLevel = 5, location = "Route 1", ball = "POKé BALL", gender = "Female", friendship = 110,
    markings = 5, pokerus = 0x23, fateful = false, item = "", moveDetails = {
      { name = "THUNDERSHOCK", pp = 15, maxPP = 48, ppUps = 3 },
      { name = "THUNDER WAVE", pp = 0, maxPP = 20, ppUps = 0 },
    } } }
local original = Store.copy(entry)
local model = Details.model(entry)
local function field(rows, label)
  for _, row in ipairs(rows) do if row.label == label then return row end end
end
T.eq(field(model.overview, "Experience").value, "125,000", "experience is readable without changing its value")
T.eq(field(model.overview, "Markings").value, "Circle · Triangle", "marks have names rather than a mystery bitmask")
T.eq(field(model.overview, "Pokérus").value, "Strain 2\n3 days left", "virus data is separated into readable lines")
T.eq(field(model.overview, "Held item").value, "None", "no item is explicit")
T.eq(field(model.origin, "Trainer ID").value, "00042", "trainer ID keeps its five-digit form")
T.eq(field(model.origin, "Secret ID").value, "00003", "secret ID keeps leading zeroes")
T.eq(field(model.origin, "Met game").value, "Emerald", "met game uses the save codec's name")
T.eq(field(model.origin, "Fateful encounter").value, "No", "false remains a recorded value")
T.eq(#model.stats, 6, "Gen 3 has six separately formatted stat rows")
T.eq(field(model.stats, "Speed").value, 156, "current speed remains exact")
T.eq(field(model.stats, "Speed").gene, 20, "Speed IV is separate from current speed")
T.eq(field(model.stats, "Speed").effort, 252, "Speed effort remains exact")
T.eq(field(model.stats, "Defense").gene, 0, "zero IV is not replaced by missing")
T.eq(field(model.stats, "HP").effort, 0, "recorded sparse EV tables keep zero effort explicit")
T.eq(field(model.contest, "Cool").value, "0", "zero Contest values stay visible")
T.eq(field(model.ribbons, "Cool").value, "×2", "ribbon counts retain their rank count")
T.eq(field(model.ribbons, "Champion").value, "Earned", "one ribbon has an earned badge")
T.eq(model.moves[1].pp, 15, "move cards retain remaining PP")
T.eq(model.moves[1].maxPP, 48, "move cards retain boosted maximum PP")
T.eq(model.moves[1].ppUps, 3, "PP Ups remain separate")
T.eq(model.moves[2].pp, 0, "exhausted moves remain zero")
T.same(entry, original, "formatting leaves all native fields untouched")

local older = { generation = 2, version = "gold", mon = {
  dvs = { attack = 15, defense = 10, speed = 10, special = 9 },
  statExp = { hp = 100, attack = 400, defense = 500, speed = 600, special = 700 },
}, display = { item = "", stats = { hp = 100, attack = 60, defense = 80, speed = 90,
  specialAttack = 75, specialDefense = 85 }, moveDetails = {} } }
local oldCopy = Store.copy(older)
local second = Details.model(older)
T.eq(#second.stats, 6, "Gen 2 retains six current stats")
T.eq(field(second.stats, "HP").gene, 9, "HP DV is derived from the four stored parity bits")
T.check(second.derivedHP, "derived HP DV is identified")
T.eq(field(second.stats, "Sp. Attack").gene, 9, "Gen 2 Special Attack uses its shared DV")
T.eq(field(second.stats, "Sp. Defense").gene, 9, "Gen 2 Special Defense uses its shared DV")
T.eq(field(second.stats, "Sp. Attack").effort, 700, "Gen 2 shared Special effort remains visible")
T.eq(field(second.stats, "Sp. Defense").effort, 700, "both special stats show the same stored effort")
T.eq(field(second.overview, "Nature"), nil, "older summaries gain no fictional nature")
T.eq(field(second.origin, "Secret ID"), nil, "older summaries gain no fictional secret ID")
T.same(older, oldCopy, "deriving the displayed DV leaves the original untouched")
older.generation, older.version = 1, "red"
older.display.stats = { hp = 100, attack = 60, defense = 80, speed = 90, special = 75 }
local first = Details.model(older)
T.eq(#first.stats, 5, "Gen 1 has its single Special stat")
T.eq(field(first.stats, "Special").effort, 700, "Gen 1 keeps its Special effort")
T.eq(field(first.overview, "Gender"), nil, "Gen 1 has no gender field")

local incomplete = Store.copy(entry)
incomplete.mon.ivs, incomplete.mon.evs = nil, nil
incomplete.display.trainer, incomplete.display.fateful, incomplete.display.pokerus = nil, nil, nil
local missing = Details.model(incomplete)
T.eq(field(missing.origin, "Original Trainer").value, "Not recorded", "unknown trainer stays explicit")
T.eq(field(missing.origin, "Fateful encounter").value, "Not recorded", "unknown encounter flag is not false")
T.eq(field(missing.stats, "HP").gene, nil, "missing genes are not manufactured as zero")
T.eq(field(missing.stats, "HP").effort, nil, "missing training is not manufactured as zero")
incomplete.display.moveDetails = {}; incomplete.mon.contest = nil
T.eq(#Details.model(incomplete).moves, 0, "empty move lists remain empty")

local printed, originalPrint = {}, love.graphics.print
love.graphics.print = function(value, ...) printed[#printed + 1] = tostring(value); return originalPrint(value, ...) end
for _, width in ipairs({ 330, 360, 680, 930 }) do
  for _, section in ipairs(Details.SECTIONS) do
    Kit.scale = 1; Kit.beginFrame(0, 0, false, 0); printed = {}
    local ok, height = pcall(Details.draw, {}, entry, section, 10, 10, width, { s = 1 })
    T.check(ok and height > 0, section .. " reflows at " .. width .. (not ok and ": " .. tostring(height) or ""))
    if section == "Stats" then
      local seen = table.concat(printed, "\n")
      T.check(seen:find("Attack", 1, true) and seen:find("IV", 1, true) and seen:find("EV", 1, true), "stat headings and columns render")
      T.check(not seen:find("attack 70", 1, true), "stats never fall back to a serialized paragraph")
    elseif section == "Moves" then
      T.check(table.concat(printed, "\n"):find("15 / 48", 1, true), "move PP is displayed separately")
    end
    Kit.endFrame()
  end
end
love.graphics.print = originalPrint
T.finish()
