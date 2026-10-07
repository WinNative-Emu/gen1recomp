package.path = package.path .. ";./?.lua;./?/init.lua;./tools/save-editor/?.lua;./tools/save-editor/panels/?.lua"
love = require("tests.love_stub")
local T = require("tests.harness")
local bit = require("bit")
local Version = require("src.core.GameVersion")
local Serializer = require("src.core.SaveSerializer")
local K = require("tests.save_compat._codec")
local D = require("tests.save_compat._gen3_decode")
local G3 = require("tests.fixtures.save.gen3_build")
local B = require("tests.fixtures.save.bytes")
local Gen, Ops = require("Gen"), require("Ops")
local State, History = require("State"), require("History")
local Kit, Touch = require("Kit"), require("TouchEditor")
local Trainer, Items = require("Trainer"), require("Items")

local FAMILY = { firered = "frlg", leafgreen = "frlg", emerald = "emerald" }

local function state(save, version)
  local s = State.new()
  s.save, s.version = save, version
  s.save.pcItems = s.save.pcItems or {}
  Gen.ensureBoxes(s.save)
  return s
end
local function snapshot(s)
  return { bytes = Serializer.encode(s.save), dirty = s.dirty, revision = s.revision,
    token = s.historyToken, undo = #(s.undoStack or {}), redo = #(s.redoStack or {}) }
end
local function unchanged(s, before, message)
  T.same(snapshot(s), before, message)
end
local function cart(v, powder)
  local w = G3.base(v)
  B.le(w.sb2, w.F.powder, bit.bxor(powder, w.key) % 4294967296, 4)
  return G3.emit(w)
end

for _, v in ipairs({ "firered", "emerald" }) do
  local fam = FAMILY[v]
  Version.set(v)
  for _, value in ipairs({ 0, 1234, 99999 }) do
    local raw = cart(v, 500)
    local s = state(assert(K.import(3, v, raw)), v)
    T.eq(Gen.berryPowder(s.save, s.version), 500, v .. " editor reads imported powder")
    local unedited = assert(K.export(3, v, Serializer.decode(Serializer.encode(s.save)), nil))
    T.eq(Ops.setTrainerProperty(s, "berryPowder", value), true, v .. " accepted powder " .. value)
    T.eq(s.save.berryPowder, value, v .. " canonical powder written")
    T.eq(s.dirty, true, v .. " powder edit marks dirty")
    T.eq(#s.undoStack, 1, v .. " one powder edit has one history entry")
    T.eq(s.status, "Berry Powder updated", v .. " status names the currency")
    local out = assert(K.export(3, v, Serializer.decode(Serializer.encode(s.save)), nil))
    local d = assert(D.decode(out, fam))
    T.eq(d.powder, value, v .. " exported powder decrypts to " .. value)
    T.eq(d.key, D.decode(unedited, fam).key, v .. " encryption key kept")
    T.eq(d.money, D.decode(unedited, fam).money, v .. " money unchanged")
    local unrelated = 0
    for at = 0, #out - 1 do
      if out:byte(at + 1) ~= unedited:byte(at + 1) then unrelated = unrelated + 1 end
    end
    T.check(unrelated <= 6, v .. " only powder word and sector checksum change (" .. unrelated .. ")")
    local back = assert(K.import(3, v, out))
    T.eq(back.berryPowder, value, v .. " reimport preserves powder")
    T.eq(History.undo(s), true, v .. " powder edit can undo")
    T.eq(Gen.berryPowder(s.save, s.version), 500, v .. " undo restores powder")
    T.eq(s.dirty, false, v .. " undo to initial save is clean")
    T.eq(History.redo(s), true, v .. " powder edit can redo")
    T.eq(Gen.berryPowder(s.save, s.version), value, v .. " redo restores powder")
    local same = snapshot(s)
    T.eq(Ops.setTrainerProperty(s, "berryPowder", value), true, v .. " equal value accepted")
    unchanged(s, same, v .. " equal value adds no history")
  end

  local s = state(assert(K.import(3, v, cart(v, 42))), v)
  T.eq(Ops.setTrainerProperty(s, "berryPowder", "777"), true, v .. " numeric string draft accepted")
  T.eq(s.save.berryPowder, 777, v .. " string draft stored as number")
  for _, draft in ipairs({ { -1 }, { 100000 }, { 2.5 }, { 0/0 }, { math.huge }, { "" }, { "x" }, { "3.5" }, { false }, {} }) do
    local before = snapshot(s)
    T.eq(Ops.setTrainerProperty(s, "berryPowder", draft[1]), false, v .. " invalid powder refused")
    unchanged(s, before, v .. " invalid powder makes no save/history change")
    T.eq(s.status, "Berry Powder must be a whole number from 0 to 99999", v .. " invalid powder feedback")
  end
end

local rows = {}
local realValue = Touch.value
Touch.value = function(s, kit, id, title, value, limits, x, y, w, apply, issue)
  rows[id] = { title = title, value = value, limits = limits }
  return realValue(s, kit, id, title, value, limits, x, y, w, apply, issue)
end
local function panel(s, which)
  rows = {}
  Kit.layout(720, 1400)
  Kit.blockClicks = false
  Kit.beginFrame(-1, -1, false, 0)
  if which == "wallet" then s.itemView = "wallet"; Items.draw(s, Kit, 0, 0, 720, 1400)
  else Trainer.draw(s, Kit, 0, 0, 720, 1400) end
  Kit.endFrame()
  return rows[(which == "wallet" and "wallet-" or "trainer-") .. "berryPowder"]
end
for _, edition in ipairs(Version.ORDER) do
  local info = assert(Version.info(edition))
  Version.set(edition)
  local s = state({ version = edition, generation = info.generation, player = { name = "ASH" },
    berryPowder = 7 }, edition)
  local eligible = edition == "firered" or edition == "leafgreen" or edition == "emerald"
  T.eq(Gen.hasBerryPowder(s.save, s.version), eligible, "edition eligibility " .. edition)
  local before = snapshot(s)
  T.eq(Ops.setTrainerProperty(s, "berryPowder", 15), eligible, "Ops edition gate " .. edition)
  if not eligible then
    unchanged(s, before, "ineligible edition unchanged " .. edition)
    T.eq(s.status, "Berry Powder is only in FireRed, LeafGreen and Emerald", "ineligible feedback " .. edition)
  end
  for _, which in ipairs({ "trainer", "wallet" }) do
    local prior = snapshot(s)
    local row = panel(s, which)
    T.eq(row ~= nil, eligible, which .. " row gate " .. edition)
    unchanged(s, prior, which .. " draw leaves save unchanged " .. edition)
    if row then
      T.eq(row.title, "Berry Powder", which .. " row title")
      T.eq(row.value, 15, which .. " row reads canonical powder")
      T.eq(row.limits.lo, 0, which .. " row lower limit")
      T.eq(row.limits.hi, 99999, which .. " row cap")
      T.check(row.limits.help:find("Berry Crush", 1, true), which .. " row explains Berry Powder")
    end
  end
end
Touch.value = realValue
Version.set("red")
T.finish("save_editor_berry_powder_2698")
