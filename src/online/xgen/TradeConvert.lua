local bit = require("bit")
local Identity = require("src.online.xgen.Identity")
local Datasets = require("src.online.xgen.Datasets")
local Policy = require("src.online.xgen.Policy")
local Project = require("src.online.xgen.Project")

local TradeConvert = {}

local copy = Project.copy

local DERIVED = {
  stats = true, maxHp = true, types = true, name = true, gender = true, shiny = true, isShiny = true,
  nature = true, growthRate = true, speciesNumbering = true, attack = true, defense = true, speed = true,
  spAtk = true, spDef = true, unownLetter = true, traded = true, maxPp = true, abilityId = true,
  ability = true, speciesId = true,
}

local function canonicalString(s)
  return '"' .. s:gsub('[%c"\\]', function(c)
    if c == '"' then return '\\"' end
    if c == "\\" then return "\\\\" end
    return string.format("\\u%04x", c:byte())
  end) .. '"'
end

local function isArray(t)
  local n = #t
  if n == 0 then return next(t) == nil end
  local count = 0
  for _ in pairs(t) do count = count + 1 end
  return count == n
end

local function encode(v, out)
  local t = type(v)
  if t == "boolean" then
    out[#out + 1] = v and "true" or "false"
  elseif t == "number" then
    if v ~= v or v == math.huge or v == -math.huge then
      out[#out + 1] = "null"
    elseif v == math.floor(v) then
      out[#out + 1] = string.format("%.0f", v)
    else
      out[#out + 1] = string.format("%.17g", v)
    end
  elseif t == "string" then
    out[#out + 1] = canonicalString(v)
  elseif t == "table" then
    if isArray(v) then
      out[#out + 1] = "["
      for i = 1, #v do
        if i > 1 then out[#out + 1] = "," end
        encode(v[i], out)
      end
      out[#out + 1] = "]"
    else
      local keys = {}
      for k in pairs(v) do keys[#keys + 1] = k end
      table.sort(keys, function(a, b)
        local ta, tb = type(a), type(b)
        if ta ~= tb then return ta < tb end
        return a < b
      end)
      out[#out + 1] = "{"
      for i, k in ipairs(keys) do
        if i > 1 then out[#out + 1] = "," end
        out[#out + 1] = canonicalString(tostring(k))
        out[#out + 1] = ":"
        encode(v[k], out)
      end
      out[#out + 1] = "}"
    end
  else
    out[#out + 1] = "null"
  end
end

function TradeConvert.canonical(rec)
  local out = {}
  encode(rec, out)
  return table.concat(out)
end

function TradeConvert.digest(rec)
  local Fingerprint = require("src.link.Fingerprint")
  local text = TradeConvert.canonical(rec)
  return ("%08x%08x"):format(Fingerprint.fnv1a32(text, 0x811C9DC5), Fingerprint.fnv1a32(text, 0x050C5D1F))
end

local charTokens = {}
local function tokensFor(generation)
  if charTokens[generation] then return charTokens[generation] end
  local chars = generation == 1 and require("src.save_convert.data.charmap").byToken
    or require("src.save_convert.Gen2Layout").charmap
  local tokens = {}
  for key, value in pairs(chars) do
    local glyph = generation == 1 and key or value
    local code = generation == 1 and value or key
    if type(glyph) == "string" and not glyph:find("[<>@{}]") and code ~= 0x50 then tokens[#tokens + 1] = glyph end
  end
  table.sort(tokens, function(a, b)
    if #a ~= #b then return #a > #b end
    return a < b
  end)
  charTokens[generation] = tokens
  return tokens
end

function TradeConvert.nameFits(text, generation, limit)
  if type(text) ~= "string" or text == "" or text:find("%c") then return false end
  if generation == 3 then
    local codec = require("src.save_convert.Gen3Save").forVersion("emerald")
    return codec.decodeString(codec.encodeString(text, limit, 0xFF), 0, limit) == text
  end
  local tokens = tokensFor(generation)
  local at, count = 1, 0
  while at <= #text do
    local found
    for _, token in ipairs(tokens) do
      if #token > 0 and text:sub(at, at + #token - 1) == token then found = token break end
    end
    if not found then return false end
    at, count = at + #found, count + 1
    if count > limit then return false end
  end
  return true
end

local function fnv(text)
  return require("src.link.Fingerprint").fnv1a32(text, 0x811C9DC5)
end

function TradeConvert.personalityFor(view, destSpecies)
  local tid = math.floor(tonumber(view.otId) or 0) % 65536
  local ratio = destSpecies.genderRatio
  local wantGender = Project.genderDv(ratio, view.dvs)
  local shiny = Project.shinyDv(view.dvs)
  local letter = view.national == 201 and Project.unownLetterDv(view.dvs) - 1 or nil
  local seed = fnv(TradeConvert.canonical({ view.national, tid, view.dvs, view.exp or 0, view.level }))
  local start = seed % 65536
  local function ok(pid)
    if pid % 50 ~= 0 then return false end
    if Project.gender3(ratio, pid) ~= wantGender then return false end
    if letter and Project.unownLetter3(pid) ~= letter then return false end
    return true
  end
  for i = 0, 65535 do
    local high = (start + i) % 65536
    if shiny then
      for k = 0, 7 do
        local low = bit.band(bit.bxor(bit.bxor(tid, high), k), 0xFFFF)
        local pid = high * 65536 + low
        if ok(pid) then return pid end
      end
    else
      local first = (-(high * 65536)) % 50
      for low = first, 65535, 50 do
        local pid = high * 65536 + low
        if bit.bxor(bit.bxor(tid, high), low) >= 8 and ok(pid) then return pid end
      end
    end
  end
  return nil
end

function TradeConvert.dvsFor(view, destGen, destSpecies)
  local iv = view.ivs
  local target = { attack = Policy.dvFromIv(iv.atk), defense = Policy.dvFromIv(iv.def),
    speed = Policy.dvFromIv(iv.spe), special = Policy.dvFromIv(iv.spa) }
  local shiny = Project.shiny3(view.personality, view.otId, view.otSecretId)
  local gender = destGen == 2 and Project.gender3(destSpecies.genderRatio, view.personality) or nil
  local letter = view.national == 201 and Project.unownLetter3(view.personality) or nil
  if letter and letter > 25 then return nil, target end
  local best, score
  for n = 0, 65535 do
    local d = { attack = math.floor(n / 4096), defense = math.floor(n / 256) % 16,
      speed = math.floor(n / 16) % 16, special = n % 16 }
    if Project.shinyDv(d) == shiny and (not gender or Project.genderDv(destSpecies.genderRatio, d) == gender)
        and (not letter or Project.unownLetterDv(d) - 1 == letter) then
      local distance = math.abs(d.attack - target.attack) + math.abs(d.defense - target.defense)
        + math.abs(d.speed - target.speed) + math.abs(d.special - target.special)
      if score == nil or distance < score then
        best, score = d, distance
        if distance == 0 then break end
      end
    end
  end
  if best then best.hp = Project.hpDv(best) end
  return best, target
end

local function itemInfo(data, localItem)
  if localItem == nil or localItem == 0 then return nil end
  local row = data.items.byLocal[localItem]
  if row == nil and data.generation == 3 then row = data.items.byLocal[tonumber(localItem)] end
  return row
end

local function gbStats(data, national, level, dvs, statExp)
  local localKey = data.species[national].localKey
  local def = data.raw.pokemon[localKey]
  if data.generation == 1 then
    return require("src.pokemon.Stats").calc(def, level, dvs, statExp)
  end
  return require("src.battle.gen2.Mon").stats(def.baseStats, dvs, level, statExp)
end

local function gen3Gender(ratio, personality)
  local g = Project.gender3(ratio, personality)
  return g == "female" and "F" or g == "male" and "M" or "U"
end

local function destLegalMoves(dst, national, level, exclude)
  local out = {}
  for move in pairs(Datasets.learnSources(dst, national, level)) do
    if dst.moves[move] and not (exclude and exclude[move]) then out[#out + 1] = move end
  end
  table.sort(out, function(a, b)
    local x, y = dst.moves[a].key or "", dst.moves[b].key or ""
    if x ~= y then return x < y end
    return a < b
  end)
  return out
end
TradeConvert.destLegalMoves = destLegalMoves

function TradeConvert.convert(args)
  local src, dst = args.source and args.source.data, args.target and args.target.data
  local rec = args.mon
  local adjustments = args.adjustments or {}
  local report = { ok = false, blocks = {}, options = {}, changes = {}, accounting = {} }
  local function block(code, field, detail) report.blocks[#report.blocks + 1] = { slot = args.slot, code = code, field = field, detail = detail } end
  local function mark(field, fate, from, to)
    if report.accounting[field] ~= nil then return end
    report.accounting[field] = fate
    if fate == "changed" then
      report.changes[#report.changes + 1] = { slot = args.slot, field = field, from = copy(from), to = copy(to), kind = "change" }
    elseif fate == "lost" then
      report.changes[#report.changes + 1] = { slot = args.slot, field = field, from = copy(from), kind = "loss" }
    end
  end
  local function change(field, from, to)
    report.changes[#report.changes + 1] = { slot = args.slot, field = field, from = copy(from), to = copy(to), kind = "change" }
  end
  local function loss(field, from)
    report.changes[#report.changes + 1] = { slot = args.slot, field = field, from = copy(from), kind = "loss" }
  end
  if type(src) ~= "table" or type(dst) ~= "table" then
    block("missing_import", nil, { need = type(src) ~= "table" and "source" or "target" })
    return report
  end
  local versions = args.versions
  if versions and versions.policy ~= nil and versions.policy ~= Policy.VERSION then
    block("policy_mismatch", nil, { mine = Policy.VERSION, theirs = versions.policy })
  end
  local view, code, detail = Project.read(rec, src)
  if not view then
    block(code, nil, detail)
    return report
  end
  local g1, g2 = src.generation, dst.generation
  local sameGen = g1 == g2
  local national, level = view.national, view.level
  if view.isEgg then block("egg", "isEgg") end
  local srcItem = g1 ~= 1 and itemInfo(src, view.item) or nil
  if (g1 ~= 1 and view.item ~= nil and view.item ~= 0 and not srcItem) then block("item_unknown", "item", { item = view.item }) end
  if rec.mail ~= nil and rec.mail ~= 255 and rec.mail ~= false or (srcItem and srcItem.mail) then
    block("mail", "item", { item = srcItem and srcItem.key })
  end
  local dsp = dst.species[national]
  if not dsp then
    block("species_missing", "species", { national = national, dexMax = dst.dexMax })
    return report
  end
  local ssp = src.species[national]
  local out = {}

  local destLocal = dsp.localKey
  out.species = destLocal
  mark("species", "carried")
  if g2 == 3 then mark("speciesId", "derived") end
  mark("level", "carried")
  out.level = level

  local destExpLo = Datasets.expAt(dst, national, level)
  local destExpHi = level < 100 and (Datasets.expAt(dst, national, level + 1) - 1) or destExpLo
  local exp = view.exp and math.floor(view.exp) or destExpLo
  local clamped = math.max(destExpLo, math.min(destExpHi, exp))
  local expField = rec.exp ~= nil and "exp" or rec.experience ~= nil and "experience" or "exp"
  if view.exp == nil then
    mark(expField, "derived")
  elseif clamped ~= view.exp then
    mark(expField, "changed", view.exp, clamped)
  else
    mark(expField, "carried")
  end
  if rec.exp ~= nil and rec.experience ~= nil then mark("experience", report.accounting.exp) end
  if g2 == 2 then out.experience = clamped else out.exp = clamped end

  local srcDefault = ssp.key
  local nickname = view.nickname
  if nickname and Identity.normalize(nickname) == srcDefault then nickname = nil end
  if nickname then
    if not TradeConvert.nameFits(nickname, g2, Policy.NAME_LIMIT.nickname) then
      block("nickname_unencodable", "nickname", { text = nickname })
    end
    out.nickname = nickname
    mark("nickname", "carried")
  else
    if g2 == 3 then out.nickname = dsp.name end
    if view.nickname and view.nickname ~= (g2 == 3 and dsp.name or nil) then
      mark("nickname", "changed", view.nickname, out.nickname)
    else
      mark("nickname", "carried")
    end
  end

  local ot = view.otName
  if type(ot) ~= "string" or not TradeConvert.nameFits(ot, g2, Policy.NAME_LIMIT.ot) then
    block("ot_unencodable", "otName", { text = ot })
  end
  if type(view.otId) ~= "number" or view.otId % 1 ~= 0 or view.otId < 0 or view.otId > 65535 then
    block("ot_invalid", "otId", { id = view.otId })
  end
  if g2 == 3 then out.otName = ot else out.ot = ot end
  out.otId = view.otId
  mark("ot", "carried")
  mark("otName", "carried")
  mark("otId", "carried")

  if g2 == 3 then
    if g1 == 3 then
      out.otSecretId = view.otSecretId or 0
      mark("otSecretId", "carried")
    else
      out.otSecretId = 0
      change("otSecretId", nil, 0)
    end
  elseif g1 == 3 then
    mark("otSecretId", "lost", rec.otSecretId)
  end

  local legalFlag = {}
  local destMoves = {}
  local adjustMoves = adjustments.moves or {}
  local listed = {}
  for _, m in ipairs(view.moves) do listed[m.move] = true end
  local legalDest = Datasets.learnSources(dst, national, level)
  local moveOptions = nil
  for j, m in ipairs(view.moves) do
    local adj = adjustMoves[j]
    if adj ~= nil then
      if adj == 0 or adj == false then
        change("moves", m.move, 0)
      elseif dst.moves[adj] and legalDest[adj] and not legalFlag[adj] then
        destMoves[#destMoves + 1] = { move = adj, ppUps = 0 }
        legalFlag[adj] = true
        change("moves", m.move, adj)
      else
        block("replacement_not_legal", "moves", { index = j, move = adj })
      end
    else
      local exists = dst.moves[m.move] ~= nil
      local okDest = exists and legalDest[m.move] ~= nil
      local okSrc = exists and Datasets.learnable(src, national, m.move, level)
      if not exists then
        block("move_missing", "moves", { index = j, move = m.move, moveMax = dst.moveMax })
        moveOptions = moveOptions or {}
        moveOptions[j] = destLegalMoves(dst, national, level, listed)
      elseif not (okDest or okSrc) then
        block("move_not_legal", "moves", { index = j, move = m.move })
        moveOptions = moveOptions or {}
        moveOptions[j] = destLegalMoves(dst, national, level, listed)
      elseif not legalFlag[m.move] then
        destMoves[#destMoves + 1] = { move = m.move, ppUps = m.ppUps, pp = m.pp }
        legalFlag[m.move] = true
      end
    end
  end
  if moveOptions then report.options.moves = moveOptions end
  if #destMoves == 0 and #report.blocks == 0 then block("no_moves", "moves") end
  local ppChanged = false
  local outMoves = {}
  for _, m in ipairs(destMoves) do
    local base = dst.moves[m.move].pp
    local max = Policy.maxPp(base, m.ppUps)
    local srcBase = src.moves[m.move] and src.moves[m.move].pp
    if srcBase ~= base or (m.pp ~= nil and m.pp ~= max) then ppChanged = true end
    local localKey = dst.moves[m.move].localKey
    if g2 == 3 then
      outMoves[#outMoves + 1] = { id = localKey, pp = max, ppUps = m.ppUps }
    elseif g2 == 2 then
      outMoves[#outMoves + 1] = { id = localKey, pp = max, ppUps = m.ppUps, maxPp = max }
    else
      outMoves[#outMoves + 1] = { id = localKey, pp = max, ppUps = m.ppUps }
    end
  end
  out.moves = outMoves
  mark("moves", "carried")
  if g1 == 3 then
    for _, key in ipairs({ "pp", "ppBonusesPacked", "ppBonuses" }) do mark(key, ppChanged and "changed" or "carried", rec[key], nil) end
  end
  if ppChanged then change("pp", nil, "full") end

  if g1 == 3 and g2 == 3 then
    out.ivs, out.evs = copy(view.ivs), copy(view.evs)
    mark("ivs", "carried")
    mark("evs", "carried")
    out.personality = view.personality
    mark("personality", "carried")
    out.abilityNum = view.abilityNum
    mark("abilityNum", "carried")
    local pair = dsp.abilities or {}
    out.ability = pair[view.abilityNum + 1] ~= 0 and pair[view.abilityNum + 1] or pair[1]
  elseif g1 < 3 and g2 < 3 then
    out.dvs = copy(view.dvs)
    out.statExp = copy(view.statExp)
    mark("dvs", "carried")
    mark("statExp", "carried")
  elseif g1 < 3 and g2 == 3 then
    local ivs = Project.ivs(view)
    local evs = Project.evs(view)
    out.ivs, out.evs = ivs, evs
    mark("dvs", "changed", view.dvs, ivs)
    mark("statExp", "changed", view.statExp, evs)
    local pid = TradeConvert.personalityFor(view, dsp)
    if not pid then
      block("personality_unrepresentable", "personality")
    else
      out.personality = pid
      change("personality", nil, pid)
    end
    out.abilityNum = Policy.ABILITY_SLOT
    out.ability = (dsp.abilities or {})[1] or 0
    change("abilityNum", nil, Policy.ABILITY_SLOT)
  else
    local dvs, target = TradeConvert.dvsFor(view, g2, dsp)
    if not dvs then
      block("traits_unrepresentable", "personality", { national = national })
      dvs = { attack = target.attack, defense = target.defense, speed = target.speed, special = target.special }
      dvs.hp = Project.hpDv(dvs)
    end
    out.dvs = dvs
    mark("ivs", "changed", view.ivs, dvs)
    local statExp = { hp = Policy.statExpFromEv(view.evs.hp), attack = Policy.statExpFromEv(view.evs.atk),
      defense = Policy.statExpFromEv(view.evs.def), speed = Policy.statExpFromEv(view.evs.spe),
      special = Policy.statExpFromEv(view.evs.spa) }
    out.statExp = statExp
    mark("evs", "changed", view.evs, statExp)
    mark("personality", "lost", view.personality)
    mark("abilityNum", "lost", view.abilityNum)
    loss("nature", view.nature)
    loss("ability", view.ability)
    if view.evs.spd ~= view.evs.spa then loss("evs.spd", view.evs.spd) end
    if view.ivs.hp ~= nil then loss("ivs.hp", view.ivs.hp) end
  end

  local traitsBefore = Project.traits(view, src)
  if g2 == 3 and out.personality then
    out.nature = out.personality % 25
    out.gender = gen3Gender(dsp.genderRatio, out.personality)
  end

  local item, catchRate
  if g1 == 1 then
    if g2 == 2 then
      item = require("src.online.Convert").heldItemFromCatchRate(view.catchRate or ssp.catchRate, dst.raw)
      if item then change("item", view.catchRate, item) end
      mark("catchRate", item and "changed" or "lost", view.catchRate, item)
    elseif g2 == 1 then
      catchRate = view.catchRate or dsp.catchRate
      mark("catchRate", "carried")
    else
      mark("catchRate", "lost", view.catchRate)
    end
  elseif srcItem then
    if g2 == 1 then
      if g1 == 2 then
        catchRate = tonumber(srcItem.index) or 0
        mark("item", "changed", srcItem.key, catchRate)
      else
        block("item_unrepresentable", "item", { item = srcItem.key })
      end
    else
      local mapped = Identity.localItem(dst, srcItem.key)
      if mapped == nil then
        block("item_unrepresentable", "item", { item = srcItem.key })
      else
        item = mapped
      end
      mark("item", "carried")
      mark("heldItem", "carried")
    end
  else
    mark("item", "carried")
    mark("heldItem", "carried")
    if g2 == 1 then catchRate = g1 == 2 and 0 or dsp.catchRate end
  end
  if g2 == 2 then out.item = item elseif g2 == 3 then out.item = item or 0 end
  if g2 == 1 then out.catchRate = catchRate end

  local friendship = view.friendship
  local friendField = g1 == 3 and "friendship" or "happiness"
  if g2 == 1 then
    if friendship ~= nil and g1 ~= 1 then mark(friendField, "lost", friendship) end
  elseif g1 == 1 then
    out[g2 == 2 and "happiness" or "friendship"] = g2 == 2 and Policy.GEN2_BASE_HAPPINESS or dsp.friendship
    change(g2 == 2 and "happiness" or "friendship", nil, out[g2 == 2 and "happiness" or "friendship"])
  else
    local value = friendship
    if value == nil then value = g2 == 2 and Policy.GEN2_BASE_HAPPINESS or dsp.friendship end
    out[g2 == 2 and "happiness" or "friendship"] = value
    mark(friendField, "carried")
  end
  if g1 == 3 then mark("happiness", report.accounting.friendship or "carried") end

  if g2 == 1 then
    if view.pokerus ~= 0 then mark("pokerus", "lost", view.pokerus) else mark("pokerus", "carried") end
  else
    out.pokerus = view.pokerus
    mark("pokerus", "carried")
  end

  if g2 == 2 then
    if g1 == 2 then
      out.caughtLevel, out.caughtTime, out.caughtLocation = rec.caughtLevel, rec.caughtTime, rec.caughtLocation
      out.caughtByGender = rec.caughtByGender or rec.caughtGender
      for _, key in ipairs({ "caughtLevel", "caughtTime", "caughtLocation", "caughtByGender", "caughtGender" }) do mark(key, "carried") end
    else
      out.caughtLevel, out.caughtTime, out.caughtLocation, out.caughtByGender = 0, 0, 0, 0
      change("caughtData", nil, 0)
    end
  elseif g1 == 2 then
    for _, key in ipairs({ "caughtLevel", "caughtTime", "caughtLocation", "caughtByGender", "caughtGender" }) do
      if rec[key] ~= nil and rec[key] ~= 0 then mark(key, "lost", rec[key]) else mark(key, "carried") end
    end
  end

  local GEN3_KEEP = { "otGender", "language", "metLocation", "metLevel", "metGame", "pokeball", "markings",
    "fatefulEncounter", "modernFatefulEncounter" }
  if g2 == 3 then
    if g1 == 3 then
      for _, key in ipairs(GEN3_KEEP) do out[key] = copy(rec[key]); mark(key, "carried") end
      out.contest = copy(rec.contest)
      mark("contest", "carried")
      out.ribbons = require("src.core.game3.rse.ribbons").word(rec)
      mark("ribbons", "carried")
      mark("championRibbon", "carried")
      out.otGender = out.otGender or 0
      out.language = out.language or Policy.GBA_LANGUAGE_ENGLISH
    else
      out.otGender = (g1 == 2 and (rec.caughtByGender or rec.caughtGender)) or 0
      out.language = Policy.GBA_LANGUAGE_ENGLISH
      out.metLocation = Policy.METLOC_IN_GAME_TRADE
      out.metLevel = level
      out.metGame = Policy.GBA_VERSION_ID[dst.version] or 0
      out.pokeball = Policy.ITEM_POKE_BALL
      out.markings = 0
      out.ribbons = national == 151 and 2147483648 or 0
      out.contest = { cool = 0, beauty = 0, cute = 0, smart = 0, tough = 0, sheen = 0 }
      out.fatefulEncounter = false
      -- src/battle_util.c:3898
      out.modernFatefulEncounter = national == 151
      change("origin", nil, { metLocation = out.metLocation, metLevel = level, metGame = out.metGame,
        pokeball = out.pokeball, language = out.language, otGender = out.otGender })
      if out.modernFatefulEncounter then change("modernFatefulEncounter", nil, true) end
    end
    out.isEgg = false
    out.eggCycles = 0
  elseif g1 == 3 then
    for _, key in ipairs(GEN3_KEEP) do
      if rec[key] ~= nil then mark(key, "lost", rec[key]) end
    end
    if rec.contest ~= nil then mark("contest", "lost", rec.contest) end
    local word = require("src.core.game3.rse.ribbons").word(rec)
    if word ~= 0 then mark("ribbons", "lost", word) else mark("ribbons", "carried") end
    mark("championRibbon", word ~= 0 and "lost" or "carried", rec.championRibbon)
  end

  for _, key in ipairs({ "isEgg", "eggSteps", "eggCycles", "isBadEgg", "mail" }) do mark(key, "carried") end

  local hpWas, statusWas = rec.hp, rec.status
  if g2 == 3 then
    local stats = Project.stats3(dsp.base, level, out.ivs, out.evs, out.nature or 0, national)
    out.hp = stats.hp
    out.status = ""
  else
    local stats = gbStats(dst, national, level, out.dvs, out.statExp)
    out.stats = stats
    out.hp = stats.hp
    out.maxHp = stats.hp
    out.status = nil
  end
  if hpWas ~= nil and hpWas ~= out.hp then mark("hp", "changed", hpWas, out.hp) else mark("hp", "derived") end
  if statusWas ~= nil and statusWas ~= "" and statusWas ~= 0 then mark("status", "changed", statusWas, nil) else mark("status", "carried") end
  if rec.sleepTurns ~= nil then mark("sleepTurns", "changed", rec.sleepTurns, nil) end
  if rec.sleep ~= nil then mark("sleep", "changed", rec.sleep, nil) end

  if g2 == 2 then
    out.gender = Project.genderDv(dsp.genderRatio, out.dvs)
    out.shiny = Project.shinyDv(out.dvs)
    if national == 201 then out.unownLetter = Project.unownLetterDv(out.dvs) end
  end
  local destView = { gen = g2, national = national, dvs = out.dvs, personality = out.personality,
    otId = out.otId, otSecretId = out.otSecretId }
  if g2 ~= 3 or out.personality then
    local after = Project.traits(destView, dst)
    if after.shiny ~= traitsBefore.shiny then change("shiny", traitsBefore.shiny, after.shiny) end
    if traitsBefore.gender and after.gender and after.gender ~= traitsBefore.gender then change("gender", traitsBefore.gender, after.gender) end
    if traitsBefore.gender and not after.gender then loss("gender", traitsBefore.gender) end
    if traitsBefore.unownLetter ~= after.unownLetter then change("unownLetter", traitsBefore.unownLetter, after.unownLetter) end
  end

  if not sameGen then
    if rec.extra ~= nil then mark("extra", "lost", rec.extra) end
  else
    out.extra = copy(rec.extra)
    mark("extra", "carried")
  end

  for key in pairs(rec) do
    if report.accounting[key] == nil then
      if DERIVED[key] then mark(key, "derived") else mark(key, "lost", rec[key]) end
    end
  end

  report.result = out
  report.canonical = TradeConvert.canonical(out)
  report.ok = #report.blocks == 0
  if not report.ok then report.result = nil; report.canonical = nil; report.preview = out end
  return report
end

return TradeConvert
