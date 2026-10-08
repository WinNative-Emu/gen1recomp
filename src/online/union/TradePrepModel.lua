local Datasets = require("src.online.xgen.Datasets")
local GameVersion = require("src.core.GameVersion")
local Policy = require("src.online.xgen.Policy")
local Project = require("src.online.xgen.Project")
local TradeConvert = require("src.online.xgen.TradeConvert")

local Model = {}
Model.__index = Model

Model.PAYLOAD_VERSION = 1
Model.MAX_STRING = 256
Model.MAX_KEY = 64
Model.MAX_DEPTH = 7
Model.MAX_BYTES = 8192
-- pokefirered/src/trade_scene.c:1073
Model.GEN3_TRADED_FRIENDSHIP = 70

Model.TRADE_EVOLUTION = {
  [1] = { TRADE = true },
  [2] = { EVOLVE_TRADE = true },
  -- include/constants/pokemon.h:270
  [3] = { [5] = true, [6] = true, EVO_TRADE = true, EVO_TRADE_ITEM = true },
}

local copy = Project.copy

local function genOf(version)
  if not (type(version) == "string" and GameVersion.VERSIONS[version]) then return nil end
  return GameVersion.generation(version)
end
Model.genOf = genOf

local function isArray(t)
  local n = #t
  if n == 0 then return false end
  local count = 0
  for _ in pairs(t) do count = count + 1 end
  return count == n
end

local function encodeKey(k)
  if type(k) == "number" then
    if k ~= k or k ~= math.floor(k) then return nil end
    return ("#%.0f"):format(k)
  end
  if type(k) ~= "string" then return nil end
  if k:sub(1, 1) == "#" then return "#" .. k end
  return k
end

local function decodeKey(k)
  if type(k) ~= "string" then return k end
  if k:sub(1, 2) == "##" then return k:sub(2) end
  if k:sub(1, 1) == "#" then return tonumber(k:sub(2)) end
  return k
end

function Model.toWire(v, depth)
  depth = depth or 0
  local t = type(v)
  if t == "string" then
    if #v > Model.MAX_STRING then return nil, "too_big" end
    return v
  end
  if t == "number" then
    if v ~= v or v == math.huge or v == -math.huge then return nil, "bad_record" end
    return v
  end
  if t == "boolean" then return v end
  if t ~= "table" then return nil, "bad_record" end
  if depth >= Model.MAX_DEPTH then return nil, "too_big" end
  local out = {}
  if isArray(v) then
    for i = 1, #v do
      local item, why = Model.toWire(v[i], depth + 1)
      if item == nil then return nil, why end
      out[i] = item
    end
    return out
  end
  for k, val in pairs(v) do
    local key = encodeKey(k)
    if not key or #key > Model.MAX_KEY then return nil, "bad_record" end
    local item, why = Model.toWire(val, depth + 1)
    if item == nil then return nil, why end
    out[key] = item
  end
  return out
end

function Model.fromWire(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, val in pairs(v) do
    local key = decodeKey(k)
    if key ~= nil then out[key] = Model.fromWire(val) end
  end
  return out
end

function Model.plain(v, depth)
  depth = depth or 0
  local t = type(v)
  if t == "table" then
    if depth > 12 then return nil end
    local out = {}
    for k, val in pairs(v) do
      local kt = type(k)
      if kt == "string" or kt == "number" then
        local item = Model.plain(val, depth + 1)
        if item ~= nil then out[k] = item end
      end
    end
    return out
  end
  if t == "string" or t == "number" or t == "boolean" then return v end
  return nil
end

Model.datasetSource = nil

function Model.dataset(version)
  if type(Model.datasetSource) == "function" then return Model.datasetSource(version) end
  local data = Datasets.get(version)
  return data
end

function Model.datasetFor(version)
  local gen = genOf(version)
  if not gen then return nil end
  local exact = Model.dataset(version)
  if exact then return exact, version end
  for _, v in ipairs(GameVersion.ORDER) do
    if v ~= version and GameVersion.generation(v) == gen then
      local d = Model.dataset(v)
      if d then return d, v end
    end
  end
  return nil
end

function Model.receiveRules(destGen, result)
  local final = copy(result)
  local changes = {}
  if destGen == 3 and not final.isEgg then
    local was = final.friendship
    final.friendship = Model.GEN3_TRADED_FRIENDSHIP
    if was ~= final.friendship then
      changes[#changes + 1] = { field = "friendship", from = was, to = final.friendship, kind = "change", rule = "received" }
    end
  end
  return final, changes
end

function Model.tradeEvolution(data, national)
  local sp = type(data) == "table" and data.species and data.species[tonumber(national) or -1]
  if not sp then return nil end
  local methods = Model.TRADE_EVOLUTION[data.generation] or {}
  for _, evo in ipairs(sp.evolutions or {}) do
    if methods[evo.method] and data.species[evo.into] then
      return evo.into, data.species[evo.into].name
    end
  end
  return nil
end

local function refusal(code, detail)
  return { ok = false, blocks = { { code = code, detail = detail } }, changes = {}, options = {} }
end

function Model.convert(srcVersion, dstVersion, rec, adjustments)
  local src, srcUsed = Model.datasetFor(srcVersion)
  local dst, dstUsed = Model.datasetFor(dstVersion)
  if not src then return refusal("missing_import", { need = srcVersion }) end
  if not dst then return refusal("missing_import", { need = dstVersion }) end
  if type(rec) ~= "table" then return refusal("bad_record") end
  if rec.rental == true then return refusal("rental") end
  if rec.projected == true or rec.projection ~= nil or rec.sourceGen ~= nil then return refusal("projection") end
  local report = TradeConvert.convert({ source = { data = src }, target = { data = dst }, mon = rec,
    adjustments = adjustments, versions = { policy = Policy.VERSION } })
  report.datasets = { source = srcUsed, target = dstUsed }
  local destGen = dst.generation
  if report.ok then
    local final, extra = Model.receiveRules(destGen, report.result)
    for _, c in ipairs(extra) do report.changes[#report.changes + 1] = c end
    report.final = final
    report.finalCanonical = TradeConvert.canonical(final)
    local view = Project.read(final, dst)
    report.national = view and view.national
    report.speciesName = view and dst.species[view.national] and dst.species[view.national].name
    local into, name = Model.tradeEvolution(dst, report.national)
    if into then report.evolves = { national = into, name = name } end
  end
  local view = Project.read(rec, src)
  report.sourceNational = view and view.national
  report.sourceName = view and src.species[view.national] and src.species[view.national].name
  report.level = view and view.level
  return report
end

function Model.new(opts)
  opts = opts or {}
  local self = setmetatable({
    version = opts.version,
    gen = genOf(opts.version),
    peerVersion = opts.peerVersion,
    peerGen = genOf(opts.peerVersion),
    peerName = opts.peerName,
    owned = opts.owned or {},
    mine = nil,
    peer = nil,
    refusal = nil,
  }, Model)
  return self
end

function Model:setPeer(version, name)
  if version ~= self.peerVersion then
    self.peerVersion, self.peerGen = version, genOf(version)
    if self.mine then self:choose(self.mine.index) end
  end
  if name then self.peerName = name end
end

function Model:entry(index)
  return self.owned[tonumber(index) or -1]
end

function Model:choose(index)
  local entry = self:entry(index)
  if not entry then return nil, "not_owned" end
  if entry.locked then return refusal(entry.locked) end
  local rec = Model.plain(entry.rec)
  self.mine = { index = index, ref = copy(entry.ref), rec = rec, adjust = { moves = {} } }
  return self:refresh()
end

function Model:refresh()
  local m = self.mine
  if not m then return nil end
  local entry = self:entry(m.index)
  local report
  if entry and entry.locked then
    report = refusal(entry.locked)
  else
    report = Model.convert(self.version, self.peerVersion, m.rec, m.adjust)
  end
  m.report = report
  m.offerable = report.ok == true
  return report
end

function Model:stage(slot, move)
  local m = self.mine
  slot = tonumber(slot)
  if not (m and slot and slot >= 1 and slot <= Policy.MAX_MOVES) then return nil, "bad_slot" end
  if move == nil then
    m.adjust.moves[slot] = nil
  else
    m.adjust.moves[slot] = move == false and 0 or move
  end
  return self:refresh()
end

function Model:moveOptions(slot)
  local m = self.mine
  local opts = m and m.report and m.report.options and m.report.options.moves
  return opts and opts[tonumber(slot) or -1] or nil
end

function Model:movesBlocked()
  local m = self.mine
  local opts = m and m.report and m.report.options and m.report.options.moves
  return opts ~= nil and next(opts) ~= nil
end

function Model:recommendTarget()
  local m = self.mine
  if not (m and self:movesBlocked()) then return nil end
  local src = Model.datasetFor(self.version)
  local dst, dstUsed = Model.datasetFor(self.peerVersion)
  local view = src and dst and Project.read(m.rec, src)
  local sp = view and dst.species[view.national]
  if not sp then return nil end
  return { generation = dst.generation, species = sp.name, version = dstUsed, national = view.national,
    level = view.level, slots = math.min(#view.moves, Policy.MAX_MOVES) }
end

function Model.recommendedMoves(entry, dst, dstVersion, national, level)
  local keys = require("src.recommend.Recommend").resolveMoves(entry, dstVersion)
  local legal = Datasets.learnSources(dst, national, level)
  local out, dropped, seen = {}, {}, {}
  for _, key in ipairs(keys) do
    local id = dst.localToMove[key]
    if id and dst.moves[id] and legal[id] and not seen[id] then
      seen[id] = true
      out[#out + 1] = id
    else
      dropped[#dropped + 1] = key
    end
  end
  return out, dropped
end

function Model:applyRecommended(entry, target)
  local m = self.mine
  target = target or self:recommendTarget()
  if not (m and target) then return nil, "not_blocked" end
  local dst = Model.datasetFor(target.version)
  if not dst then return nil, "missing_import" end
  local moves, dropped = Model.recommendedMoves(entry, dst, target.version, target.national, target.level)
  if #moves == 0 then return nil, "none_legal", dropped end
  for slot = 1, Policy.MAX_MOVES do
    m.adjust.moves[slot] = slot <= target.slots and moves[slot] or nil
  end
  return self:refresh(), nil, dropped
end

function Model:stagedMoves()
  local out = {}
  if not self.mine then return out end
  for slot, move in pairs(self.mine.adjust.moves) do out[#out + 1] = { slot = slot, move = move } end
  table.sort(out, function(a, b) return a.slot < b.slot end)
  return out
end

local function half(srcVersion, dstVersion, source, final)
  return { src = srcVersion, dst = dstVersion, source = TradeConvert.canonical(source),
    result = TradeConvert.canonical(final) }
end

function Model.offerDigest(h)
  return TradeConvert.digest({ v = Model.PAYLOAD_VERSION, policy = Policy.VERSION, src = h.src, dst = h.dst,
    source = h.source, result = h.result })
end

function Model:payload()
  local m = self.mine
  if not (m and m.offerable) then return nil, "not_ready" end
  local adjust = {}
  for slot, move in pairs(m.adjust.moves) do adjust[#adjust + 1] = { slot = slot, move = move } end
  table.sort(adjust, function(a, b) return a.slot < b.slot end)
  local body = { v = Model.PAYLOAD_VERSION, policy = Policy.VERSION, src = self.version, dst = self.peerVersion,
    source = m.rec, adjust = adjust, preview = m.report.final }
  local wire, why = Model.toWire(body)
  if not wire then return nil, why end
  local ok, text = pcall(require("src.link.Json").encode, wire)
  if not ok or #text > Model.MAX_BYTES then return nil, "too_big" end
  m.half = half(self.version, self.peerVersion, m.rec, m.report.final)
  m.digest16 = Model.offerDigest(m.half)
  return wire, m.digest16
end

function Model:receive(payload, verify)
  self.peer = nil
  self.refusal = nil
  local function refuse(code, detail)
    self.refusal = { code = code, detail = detail }
    return nil, code, detail
  end
  if type(payload) ~= "table" then return refuse("bad_payload") end
  local body = Model.fromWire(payload)
  if body.v ~= Model.PAYLOAD_VERSION then return refuse("bad_payload", { field = "v" }) end
  if body.policy ~= Policy.VERSION then return refuse("policy_mismatch", { mine = Policy.VERSION, theirs = body.policy }) end
  if not genOf(body.src) then return refuse("unsupported_version", { version = body.src }) end
  if body.dst ~= self.version then return refuse("wrong_destination", { claimed = body.dst, mine = self.version }) end
  if self.peerVersion and body.src ~= self.peerVersion then
    return refuse("wrong_source", { claimed = body.src, peer = self.peerVersion })
  end
  if type(body.source) ~= "table" or type(body.preview) ~= "table" then return refuse("bad_payload") end
  local adjust = { moves = {} }
  for _, row in ipairs(type(body.adjust) == "table" and body.adjust or {}) do
    local slot = tonumber(type(row) == "table" and row.slot)
    if not slot or slot < 1 or slot > Policy.MAX_MOVES or slot % 1 ~= 0 or adjust.moves[slot] ~= nil then
      return refuse("bad_payload", { field = "adjust" })
    end
    adjust.moves[slot] = row.move
  end
  local report = Model.convert(body.src, self.version, body.source, adjust)
  if not report.ok then
    local b = report.blocks[1] or {}
    return refuse(b.code or "bad_record", b.detail)
  end
  local claimed = TradeConvert.canonical(body.preview)
  if claimed ~= report.finalCanonical then
    return refuse("preview_mismatch", { used = report.datasets and report.datasets.source })
  end
  if type(verify) == "function" then
    local ok, code, detail = verify(report.final, report)
    if not ok then return refuse(code or "not_valid_here", detail) end
  end
  self.peer = { source = body.source, adjust = adjust, report = report, final = report.final,
    half = half(body.src, self.version, body.source, report.final), version = body.src }
  self.peer.digest16 = Model.offerDigest(self.peer.half)
  return true
end

function Model.agreedDigest(seat0, seat1)
  local function h(x)
    return { offerRev = tonumber(x.offerRev) or 0, src = x.src, dst = x.dst, source = x.source, result = x.result }
  end
  return TradeConvert.digest({ v = Model.PAYLOAD_VERSION, policy = Policy.VERSION, seats = { h(seat0), h(seat1) } })
end

function Model:agreed(mySeat, myOfferRev, peerOfferRev)
  local m, p = self.mine, self.peer
  if not (m and m.half and p and p.half) then return nil end
  local mine = copy(m.half)
  mine.offerRev = myOfferRev
  local theirs = copy(p.half)
  theirs.offerRev = peerOfferRev
  if mySeat == 1 then return Model.agreedDigest(theirs, mine) end
  return Model.agreedDigest(mine, theirs)
end

local function side(report, versionFrom, versionTo, name)
  if not report then return nil end
  return {
    from = versionFrom, to = versionTo, trainer = name,
    sourceName = report.sourceName, speciesName = report.speciesName, national = report.national,
    level = report.level, final = report.final, changes = report.changes or {}, blocks = report.blocks or {},
    evolves = report.evolves, ok = report.ok == true,
  }
end

function Model:summary()
  return {
    mine = self.mine and side(self.mine.report, self.version, self.peerVersion, nil) or nil,
    theirs = self.peer and side(self.peer.report, self.peer.version, self.version, self.peerName) or nil,
    refusal = self.refusal,
  }
end

return Model
