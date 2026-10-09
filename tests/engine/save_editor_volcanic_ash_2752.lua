-- #2752: RSE Volcanic Ash is VAR_ASH_GATHER_COUNT, not a separate wallet field.
package.path = package.path .. ";./?.lua;./?/init.lua;./tools/save-editor/?.lua;./tools/save-editor/panels/?.lua"
love = require("tests.love_stub")
local T = require("tests.harness")
local Version = require("src.core.GameVersion")
local Serializer = require("src.core.SaveSerializer")
local Codec = require("src.save_convert.Gen3Save")
local Compat = require("src.save_convert.Compat")
local Gen, Ops = require("Gen"), require("Ops")
local State, History = require("State"), require("History")
local Kit, Touch = require("Kit"), require("TouchEditor")
local Trainer, Items = require("Trainer"), require("Items")
local ASH = 0x4048 -- pokeemerald/include/constants/vars.h:92; pokeruby VAR_ASH_GATHER_COUNT
local SUPPORTED = { ruby = true, sapphire = true, emerald = true }
local PREFIX = { ruby = "RU_", sapphire = "SA_", emerald = "EM_" }

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
local function unchanged(s, before, msg) T.same(snapshot(s), before, msg) end
local function amount(save) return Gen.getVar(save, ASH) end
local function seed(v)
  return { version = v, generation = 3, map = PREFIX[v] .. "LITTLEROOT_TOWN", x = 5, y = 8,
    name = "BRENDAN", trainerId = 1234, secretId = 5678, gender = 0,
    money = 123456, coins = 4321, vars = { [ASH] = 500, [ASH + 1] = 987 },
    party = {}, pcItems = {}, boxes = {} }
end
local function export(v, save)
  local bytes, err = Codec.forVersion(v).exportPort(save, {
    version = v, metGame = Version.gameCode(v), itemId = tonumber,
    toNational = function() return nil end,
    mapLayoutId = function() return 1 end,
    healWarp = function() return { group = 0, num = 9, warpId = -1, x = 5, y = 8 } end,
  })
  return assert(bytes, err)
end
for _, v in ipairs({ "ruby", "sapphire", "emerald" }) do
  Version.set(v)
  local C = Codec.forVersion(v)
  local raw = export(v, seed(v))
  for _, value in ipairs({ 0, 1234, 9999 }) do
    local s = state(assert(C.importPort(raw, v)), v)
    T.eq(amount(s.save), 500, v .. " reads imported ash variable")
    local baseline = export(v, Serializer.decode(Serializer.encode(s.save)))
    T.eq(Ops.setTrainerProperty(s, "volcanicAsh", value), true, v .. " accepts ash " .. value)
    T.eq(amount(s.save), value, v .. " writes canonical ash variable")
    T.eq(s.save.volcanicAsh, nil, v .. " does not invent a duplicate currency field")
    T.eq(s.dirty, true, v .. " edit marks dirty")
    T.eq(#(s.undoStack or {}), 1, v .. " edit records one undo")
    T.eq(s.status, "Volcanic Ash updated", v .. " edit status")
    local persisted = Serializer.decode(Serializer.encode(s.save))
    T.eq(amount(persisted), value, v .. " Lua persistence keeps ash")
    local out = export(v, persisted)
    local cart = assert(C.decode(out))
    T.eq(cart.vars[ASH] or 0, value, v .. " cart variable stores ash")
    T.eq(cart.vars[ASH + 1], 987, v .. " neighboring variable unchanged")
    T.eq(cart.money, 123456, v .. " money unchanged")
    T.eq(cart.coins, 4321, v .. " coins unchanged")
    local changed = 0
    for i = 1, #out do if out:byte(i) ~= baseline:byte(i) then changed = changed + 1 end end
    T.check(changed <= 4, v .. " only ash u16 and sector checksum change (" .. changed .. ")")
    local family = v == "emerald" and "emerald" or "rs"
    local blocks = assert(Compat.gen3Blocks(out, family))
    local original = assert(Compat.gen3Blocks(baseline, family))
    -- Independent raw SaveBlock1 offset check (not the editor/codec var getter).
    -- pokeemerald vars start at 0x139C; pokeruby vars start at 0x1340.
    local ashOff = (v == "emerald" and 0x139C or 0x1340) + (ASH - 0x4000) * 2
    T.eq(blocks.sb1:byte(ashOff + 1) + blocks.sb1:byte(ashOff + 2) * 256, value,
      v .. " raw cartridge ash word")
    local normalized = blocks.sb1:sub(1, ashOff) .. original.sb1:sub(ashOff + 1, ashOff + 2)
      .. blocks.sb1:sub(ashOff + 3)
    T.eq(normalized, original.sb1, v .. " all other SaveBlock1 bytes preserved")
    T.eq(blocks.sb2, original.sb2, v .. " all SaveBlock2 bytes preserved")
    T.eq(blocks.storage, original.storage, v .. " all storage bytes preserved")
    T.eq(amount(assert(C.importPort(out, v))), value, v .. " cart reimport keeps ash")
    T.eq(History.undo(s), true, v .. " undo succeeds")
    T.eq(amount(s.save), 500, v .. " undo restores imported ash")
    T.eq(s.dirty, false, v .. " undo to initial save is clean")
    T.eq(History.redo(s), true, v .. " redo succeeds")
    T.eq(amount(s.save), value, v .. " redo restores ash")
    local before = snapshot(s)
    T.eq(Ops.setTrainerProperty(s, "volcanicAsh", value), true, v .. " same value accepted")
    unchanged(s, before, v .. " same value adds no history or mutations")
  end
  local s = state(seed(v), v)
  T.eq(Ops.setTrainerProperty(s, "volcanicAsh", "777"), true, v .. " numeric string accepted")
  T.eq(amount(s.save), 777, v .. " numeric string stored as number")
  for _, draft in ipairs({ { -1 }, { 10000 }, { 1.5 }, { 0/0 }, { math.huge }, { -math.huge },
    { "" }, { "ash" }, { "3.5" }, { false }, {} }) do
    local before = snapshot(s)
    T.eq(Ops.setTrainerProperty(s, "volcanicAsh", draft[1]), false, v .. " invalid ash rejected")
    unchanged(s, before, v .. " invalid ash leaves save/history unchanged")
    if Gen.setVolcanicAsh then
      T.eq(Gen.setVolcanicAsh(s.save, draft[1], v), false, v .. " direct setter rejects invalid ash")
      unchanged(s, before, v .. " invalid direct setter leaves save/history unchanged")
    end
    T.eq(s.status, "Volcanic Ash must be a whole number from 0 to 9999", v .. " validation feedback")
  end
end

-- Capture the real touch-value controls and test their apply callbacks too.
local rows, realValue = {}, Touch.value
Touch.value = function(s, kit, id, title, value, limits, x, y, w, apply, issue)
  rows[id] = { title = title, value = value, limits = limits, apply = apply }
  return realValue(s, kit, id, title, value, limits, x, y, w, apply, issue)
end
local function panel(s, which, width, height)
  rows = {}
  Kit.layout(width, height)
  Kit.blockClicks = false
  Kit.beginFrame(-1, -1, false, 0)
  if which == "wallet" then s.itemView = "wallet"; Items.draw(s, Kit, 0, 0, width, height)
  else Trainer.draw(s, Kit, 0, 0, width, height) end
  Kit.endFrame()
  return rows[(which == "wallet" and "wallet-" or "trainer-") .. "volcanicAsh"]
end
for _, v in ipairs(Version.ORDER) do
  local info = assert(Version.info(v))
  Version.set(v)
  local eligible = SUPPORTED[v] == true
  local s = state({ version = v, generation = info.generation, player = { name = "ASH" },
    vars = { [ASH] = 7 } }, v)
  local before = snapshot(s)
  if Gen.hasVolcanicAsh then T.eq(Gen.hasVolcanicAsh(s.save, s.version), eligible, v .. " adapter edition gate") end
  if not eligible and Gen.setVolcanicAsh then
    T.eq(Gen.setVolcanicAsh(s.save, 15, s.version), false, v .. " direct unsupported setter rejected")
    unchanged(s, before, v .. " direct unsupported setter does not mutate")
    T.eq(Gen.volcanicAsh(s.save, s.version), 0, v .. " unsupported currency reads zero")
  end
  T.eq(Ops.setTrainerProperty(s, "volcanicAsh", 15), eligible, v .. " operation edition gate")
  if not eligible then unchanged(s, before, v .. " unsupported save not mutated") end
  for _, size in ipairs({ { 720, 1400 }, { 1280, 720 } }) do
    for _, which in ipairs({ "trainer", "wallet" }) do
      before = snapshot(s)
      local row = panel(s, which, size[1], size[2])
      T.eq(row ~= nil, eligible, v .. " " .. which .. " row eligibility at " .. size[1])
      unchanged(s, before, v .. " drawing does not mutate save/history")
      if row then
        T.eq(row.title, "Volcanic Ash", which .. " currency label")
        T.eq(row.value, amount(s.save), which .. " reads canonical ash")
        T.eq(row.limits.lo, 0, which .. " minimum")
        T.eq(row.limits.hi, 9999, which .. " original-game maximum")
        T.check(row.limits.help:find("Soot Sack", 1, true), which .. " explains currency")
        T.eq(row.apply(2345), true, which .. " control applies edits")
        T.eq(amount(s.save), 2345, which .. " callback writes ash")
      end
    end
  end
end
Touch.value = realValue

-- Public adapter contract: edition routing must not depend on active cart;
-- older port saves can lack vars, and serialized numeric keys may be strings.
T.check(type(Gen.hasVolcanicAsh) == "function", "Gen.hasVolcanicAsh exists")
T.check(type(Gen.volcanicAsh) == "function", "Gen.volcanicAsh exists")
T.check(type(Gen.setVolcanicAsh) == "function", "Gen.setVolcanicAsh exists")
if Gen.hasVolcanicAsh and Gen.volcanicAsh and Gen.setVolcanicAsh then
  for _, v in ipairs({ "ruby", "sapphire", "emerald" }) do
    Version.set("firered")
    local save = { version = v, generation = 3, vars = { [tostring(ASH)] = 21, [ASH + 1] = 100 } }
    T.eq(Gen.volcanicAsh(save), 21, v .. " reads string-key ash with another cart active")
    T.eq(Gen.setVolcanicAsh(save, 42), true, v .. " routes by save edition")
    T.eq(save.vars[ASH], 42, v .. " canonical numeric key")
    T.eq(save.vars[tostring(ASH)], nil, v .. " stale string alias removed")
    T.eq(save.vars[ASH + 1], 100, v .. " unrelated var preserved")
    save = { generation = 3 }
    T.eq(Gen.volcanicAsh(save, v), 0, v .. " missing vars default zero")
    T.eq(Gen.setVolcanicAsh(save, 10, v), true, v .. " initializes missing vars with edition argument")
    T.eq(save.vars[ASH], 10, v .. " missing vars now canonical")
    local prior = Serializer.encode(save)
    T.eq(Gen.setVolcanicAsh(save, 10000, v), false, v .. " direct setter enforces cap")
    T.eq(Serializer.encode(save), prior, v .. " invalid direct setter leaves save alone")
    local s = state({ generation = 3 }, v)
    local before = snapshot(s)
    T.eq(Ops.setTrainerProperty(s, "volcanicAsh", 0), true, v .. " absent ash zero edit is a no-op")
    unchanged(s, before, v .. " zero no-op does not create vars or history")
    T.eq(Ops.setTrainerProperty(s, "volcanicAsh", 9999), true, v .. " Ops initializes missing vars")
    T.eq(s.save.vars[ASH], 9999, v .. " Ops initializes canonical ash")
    T.eq(#s.undoStack, 1, v .. " missing-vars edit records history")
    T.eq(History.undo(s), true, v .. " missing-vars edit undoes")
    T.eq(s.save.vars, nil, v .. " undo restores absent vars")
    s = state({ version = v, generation = 3, vars = "malformed" }, v)
    before = snapshot(s)
    T.eq(Ops.setTrainerProperty(s, "volcanicAsh", 0), false, v .. " malformed vars rejected even for zero")
    unchanged(s, before, v .. " malformed vars remain untouched")
  end
end
local f = assert(io.open("tests/quick.list", "r"))
local quick = f:read("*a"); f:close()
T.check(quick:find("tests/engine/save_editor_volcanic_ash_2752.lua", 1, true), "registered in quick suite")
Version.set("red")
T.finish("save_editor_volcanic_ash_2752")
