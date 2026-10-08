local Datasets = require("src.online.xgen.Datasets")
local Policy = require("src.online.xgen.Policy")
local Project = require("src.online.xgen.Project")
local TradeConvert = require("src.online.xgen.TradeConvert")

local Compat = {}

local copy = Project.copy

local function asSet(list)
  local out = {}
  if type(list) ~= "table" then return out end
  for k, v in pairs(list) do
    if v == true then out[tonumber(k) or k] = true
    elseif tonumber(v) then out[tonumber(v)] = true end
  end
  return out
end
Compat.asSet = asSet

local function resolveRuleset(target)
  target = target or {}
  local id = target.ruleset or "g3u"
  if id == "native" then return { id = "native", engine = "native", gen = target.gen } end
  local base = Policy.ruleset(id) or (target.gen and Policy.rulesetForGen(target.gen)) or nil
  local r = { id = base and base.id or id, engine = "g3u", gen = base and base.gen or target.gen,
    dexMax = tonumber(target.dexMax) or (base and base.dexMax), moveMax = tonumber(target.moveMax) or (base and base.moveMax) }
  return r
end
Compat.resolveRuleset = resolveRuleset

function Compat.speciesEligible(national, ruleset)
  national = tonumber(national)
  if not national then return false, "species_unknown" end
  if national > (ruleset.dexMax or 0) then
    return false, "species_not_in_ruleset", { national = national, dexMax = ruleset.dexMax }
  end
  return true
end

function Compat.moveStatus(data, national, level, move, ruleset, unsupported)
  move = tonumber(move)
  if not move or move > (ruleset.moveMax or 0) or not data.moves[move] then
    return "move_not_in_ruleset"
  end
  if unsupported and unsupported[move] then return "move_unsupported" end
  if not Datasets.learnable(data, national, move, level) then return "move_not_legal" end
  return nil
end

function Compat.legalMoves(data, national, level, ruleset, unsupported)
  local out = {}
  for move in pairs(Datasets.learnSources(data, national, level)) do
    if not Compat.moveStatus(data, national, level, move, ruleset, unsupported) then out[#out + 1] = move end
  end
  table.sort(out)
  return out
end

function Compat.moveSuggestions(data, national, level, ruleset, original, exclude, unsupported)
  local orig = data.moves[tonumber(original) or -1]
  local rows = {}
  for _, move in ipairs(Compat.legalMoves(data, national, level, ruleset, unsupported)) do
    if not (exclude and exclude[move]) then
      local mv = data.moves[move]
      rows[#rows + 1] = { move = move, name = mv.name, key = mv.key or "", type = mv.type,
        category = mv.category, power = mv.power,
        sameType = orig ~= nil and mv.type == orig.type,
        sameBand = orig ~= nil and mv.category == orig.category and Policy.powerBand(mv.power) == Policy.powerBand(orig.power) }
    end
  end
  table.sort(rows, function(a, b)
    if a.sameType ~= b.sameType then return a.sameType end
    if a.sameBand ~= b.sameBand then return a.sameBand end
    if a.key ~= b.key then return a.key < b.key end
    return a.move < b.move
  end)
  return rows
end

local function sharesType(a, b)
  for _, x in ipairs(a or {}) do
    for _, y in ipairs(b or {}) do
      if x == y then return true end
    end
  end
  return false
end

function Compat.replacements(data, slotView, owned, ruleset, exclude, unsupported)
  local want = data.species[slotView.national]
  local wantTypes = want and want.types or {}
  local rows = {}
  for index, entry in ipairs(owned or {}) do
    if not (exclude and exclude[index]) then
      local rec = entry.rec or entry
      local view = Project.read(rec, data)
      if view and not view.isEgg and Compat.speciesEligible(view.national, ruleset)
          and #Compat.legalMoves(data, view.national, view.level, ruleset, unsupported) > 0 then
        local types = data.species[view.national].types
        rows[#rows + 1] = { index = index, ref = entry.ref, national = view.national, level = view.level,
          name = data.species[view.national].name,
          sharesType = sharesType(types, wantTypes), samePrimary = types[1] == wantTypes[1],
          distance = math.abs(view.level - slotView.level) }
      end
    end
  end
  table.sort(rows, function(a, b)
    if a.sharesType ~= b.sharesType then return a.sharesType end
    if a.samePrimary ~= b.samePrimary then return a.samePrimary end
    if a.distance ~= b.distance then return a.distance < b.distance end
    return a.index < b.index
  end)
  return rows
end

function Compat.rentalCandidates(data, slotView, rentals)
  local want = data.species[slotView.national]
  local wantTypes = want and want.types or {}
  local rows = {}
  for index, r in ipairs(rentals or {}) do
    local types = r.types or {}
    rows[#rows + 1] = { index = index, rental = true, national = r.national, type = r.type,
      sharesType = sharesType(types, wantTypes), samePrimary = types[1] == wantTypes[1] }
  end
  table.sort(rows, function(a, b)
    if a.sharesType ~= b.sharesType then return a.sharesType end
    if a.samePrimary ~= b.samePrimary then return a.samePrimary end
    return a.index < b.index
  end)
  return rows
end

function Compat.teamSize(mine, theirs, requested)
  mine, theirs = tonumber(mine) or 0, tonumber(theirs) or mine
  local size = math.min(mine, theirs)
  requested = tonumber(requested)
  if requested and requested >= 1 and requested <= size then size = requested end
  return math.max(0, math.min(6, size))
end

local function versionBlocks(args, block)
  local v = args.versions
  if type(v) ~= "table" then return end
  if v.policy ~= nil and v.policy ~= Policy.VERSION then block(nil, "policy_mismatch", nil, { mine = Policy.VERSION, theirs = v.policy }) end
  if v.proto ~= nil and v.proto ~= Policy.PROTO then block(nil, "proto_mismatch", nil, { mine = Policy.PROTO, theirs = v.proto }) end
end

local function battleReport(args, report, block)
  local source = args.source or {}
  local data = source.data
  local ruleset = resolveRuleset(args.target)
  local adjustments = args.adjustments or {}
  local unsupported = asSet(args.unsupported)
  local legacy = not (args.target and args.target.legacyPresent == false)
  if type(data) ~= "table" then block(nil, "missing_import", nil, { need = "source" }) return end
  local mons = args.mons or {}
  local replace = adjustments.replace or {}
  local sitOut = asSet(adjustments.sitOut)
  local active = {}
  for slot = 1, #mons do
    if not sitOut[slot] then active[#active + 1] = slot end
  end
  local size = Compat.teamSize(#mons, args.opponentSize, adjustments.size)
  if #active > size then
    block(nil, "choose_sit_out", "team", { need = #active - size, size = size })
    local choices = {}
    for _, slot in ipairs(active) do choices[#choices + 1] = slot end
    report.options.sitOut = choices
  elseif #active < size or #active == 0 then
    block(nil, "team_too_small", "team", { size = size, have = #active })
  end
  report.options.replacements, report.options.moves, report.options.rentals = {}, {}, {}
  report.options.allowEmpty = true
  local team = {}
  local usedOwned = {}
  for _, slot in ipairs(active) do
    local r = replace[slot]
    if r and r.owned then usedOwned[r.owned] = true end
  end
  for _, entry in ipairs(args.ownedInTeam or {}) do usedOwned[entry] = true end
  if ruleset.engine == "native" then
    if source.gen and ruleset.gen and source.gen ~= ruleset.gen then
      block(nil, "native_needs_same_gen", nil, { mine = source.gen, ruleset = ruleset.gen })
    end
    for _, slot in ipairs(active) do team[#team + 1] = copy(mons[slot]) end
    report.result = { ruleset = ruleset.id, size = size, team = team, slots = copy(active) }
    return
  end
  for _, slot in ipairs(active) do
    local r = replace[slot]
    local rec = mons[slot]
    local rental = nil
    if r and r.owned then
      local entry = (args.owned or {})[r.owned]
      rec = entry and (entry.rec or entry)
      report.changes[#report.changes + 1] = { slot = slot, field = "species", from = slot, to = { owned = r.owned }, kind = "change" }
    elseif r and r.rental then
      rental = (args.rentals or {})[r.rental]
      report.changes[#report.changes + 1] = { slot = slot, field = "species", from = slot, to = { rental = r.rental }, kind = "change" }
    end
    if rental then
      team[#team + 1] = copy(rental.record or rental)
    else
      local view, code, detail = Project.read(rec, data)
      if not view then
        block(slot, code, nil, detail)
      elseif view.isEgg then
        block(slot, "egg", "isEgg")
      else
        local okSpecies, why, info = Compat.speciesEligible(view.national, ruleset)
        if not okSpecies then
          block(slot, why, "species", info)
          report.options.replacements[slot] = Compat.replacements(data, view, args.owned, ruleset, usedOwned, unsupported)
          report.options.rentals[slot] = Compat.rentalCandidates(data, view, args.rentals)
        else
          local moveAdj = (adjustments.moves or {})[slot] or {}
          local final, seen, current = {}, {}, {}
          for _, m in ipairs(view.moves) do current[m.move] = true end
          for j, m in ipairs(view.moves) do
            local adj = moveAdj[j]
            if adj ~= nil then
              if adj == 0 or adj == false then
                report.changes[#report.changes + 1] = { slot = slot, field = "moves", from = m.move, to = 0, kind = "change", index = j }
              else
                local status = Compat.moveStatus(data, view.national, view.level, adj, ruleset, unsupported)
                if status or seen[adj] then
                  block(slot, "replacement_not_legal", "moves", { index = j, move = adj, why = status or "duplicate" })
                else
                  seen[adj] = true
                  final[#final + 1] = { move = adj, ppUps = 0 }
                  report.changes[#report.changes + 1] = { slot = slot, field = "moves", from = m.move, to = adj, kind = "change", index = j }
                end
              end
            else
              local status = Compat.moveStatus(data, view.national, view.level, m.move, ruleset, unsupported)
              if status then
                block(slot, status, "moves", { index = j, move = m.move })
                report.options.moves[slot] = report.options.moves[slot] or {}
                report.options.moves[slot][j] = Compat.moveSuggestions(data, view.national, view.level, ruleset, m.move, current, unsupported)
              elseif not seen[m.move] then
                seen[m.move] = true
                final[#final + 1] = { move = m.move, ppUps = m.ppUps }
              end
            end
          end
          local pending = report.options.moves[slot] ~= nil
          if #final == 0 and not pending then block(slot, "no_legal_moves", "moves") end
          local projected = Project.battleMon(view, data, { moves = final, legacyPresent = legacy })
          if view.gen < 3 then
            report.changes[#report.changes + 1] = { slot = slot, field = "dvs", from = copy(view.dvs), to = copy(projected.ivs), kind = "change" }
            report.changes[#report.changes + 1] = { slot = slot, field = "statExp", from = copy(view.statExp), to = copy(projected.evs), kind = "change" }
          elseif legacy then
            if view.nature ~= Policy.NATURE_NEUTRAL then
              report.changes[#report.changes + 1] = { slot = slot, field = "nature", from = view.nature, to = Policy.NATURE_NEUTRAL, kind = "change" }
            end
            if view.ability and view.ability ~= 0 then
              report.changes[#report.changes + 1] = { slot = slot, field = "ability", from = view.ability, to = 0, kind = "change" }
            end
            if view.item and view.item ~= 0 then
              report.changes[#report.changes + 1] = { slot = slot, field = "item", from = view.item, to = 0, kind = "change" }
            end
          end
          team[#team + 1] = projected
        end
      end
    end
  end
  report.result = { ruleset = ruleset.id, dexMax = ruleset.dexMax, moveMax = ruleset.moveMax,
    size = size, team = team, slots = copy(active) }
end

function Compat.report(args)
  args = args or {}
  local report = { ok = false, blocks = {}, options = {}, changes = {}, result = nil }
  local function block(slot, code, field, detail)
    report.blocks[#report.blocks + 1] = { slot = slot, code = code, field = field, detail = detail }
  end
  versionBlocks(args, block)
  if args.op == "battle" then
    battleReport(args, report, block)
  elseif args.op == "trade" then
    local mon = args.mon or (args.mons or {})[1]
    local t = TradeConvert.convert({ source = args.source, target = args.target, mon = mon,
      adjustments = args.adjustments, slot = args.slot or 1 })
    for _, b in ipairs(t.blocks) do report.blocks[#report.blocks + 1] = b end
    for _, c in ipairs(t.changes) do report.changes[#report.changes + 1] = c end
    report.options = t.options
    report.result = t.result
    report.preview = t.preview
    report.canonical = t.canonical
    report.accounting = t.accounting
  else
    block(nil, "bad_op", nil, { op = args.op })
  end
  report.ok = #report.blocks == 0
  if not report.ok and args.op == "battle" then
    report.preview = report.result
    report.result = nil
  end
  return report
end

return Compat
