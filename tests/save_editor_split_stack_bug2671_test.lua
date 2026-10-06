package.path = package.path .. ";./?.lua;./?/init.lua;./tools/save-editor/?.lua"
  .. ";./tools/save-editor/panels/?.lua"

love = require("tests.love_stub")

local passed, failed = 0, 0

local function check(cond, msg)
  if cond then
    passed = passed + 1
  else
    failed = failed + 1
    print("FAIL: " .. msg)
  end
end

local function eq(a, b, msg)
  check(a == b, msg .. string.format(" (got %s, want %s)", tostring(a), tostring(b)))
end

print("== save editor / .sav split stack tests (#2671) ==")

require("src.core.GameVersion").set("red")
local Ops = require("Ops")
local State = require("State")
local Catalog = require("Catalog")
local Bag = require("src.inventory.Bag")
local SaveData = require("src.core.SaveData")
local GenSave = require("src.save_convert.GenSave")

local Data = require("src.core.Data")
Data:load()
GenSave.setCharmap(loadfile("src/save_convert/data/charmap.lua")())

local function red()
  local S = State.new()
  S.data = Data
  S.cat = Catalog.build(Data)
  S.save = SaveData.newGame()
  S.save.inventory, S.save.bagOrder, S.save.pcItems, S.save.pcOrder = {}, nil, {}, nil
  return S
end

local function split(S)
  Bag.add(S.save, "X_ACCURACY", 99, S.data)
  Bag.add(S.save, "POTION", 3, S.data)
  Bag.add(S.save, "X_ACCURACY", 2, S.data)
end

local function counts(rows)
  local out = {}
  for _, r in ipairs(rows) do out[#out + 1] = tostring(r.id) .. "x" .. tostring(r.count) end
  return table.concat(out, ",")
end

do
  local S = red()
  split(S)
  eq(S.save.inventory.X_ACCURACY, 101, "fixture: 99 + 2 X ACCURACY totals 101")
  eq(table.concat(S.save.bagOrder, ","), "X_ACCURACY,POTION,X_ACCURACY", "fixture: two cart slots")
  eq(counts(Ops.stackRows(S, false)), "X_ACCURACYx99,POTIONx3,X_ACCURACYx2", "editor rows carry each slot's own count")
  local legal = true
  for _, r in ipairs(Ops.stackRows(S, false)) do
    if not require("Legality").integer(r.count, 1, Ops.itemMax(S, r.id, false)) then legal = false end
  end
  check(legal, "a split stack is legal per row")
end

do
  local S = red()
  split(S)
  check(Ops.bagCanMax(S, "X_ACCURACY"), "the part-filled overflow slot can be maxed")
  check(Ops.bagMax(S, "X_ACCURACY") == true, "Max fills the overflow slot")
  eq(S.save.inventory.X_ACCURACY, 198, "Max fills both slots to 99")
  eq(counts(Ops.stackRows(S, false)), "X_ACCURACYx99,POTIONx3,X_ACCURACYx99", "both rows read x99")
end

do
  local S = red()
  split(S)
  S.dirty = false
  check(Ops.bagDrop(S, "X_ACCURACY", 2) == true, "Drop on the overflow row succeeds")
  eq(S.save.inventory.X_ACCURACY, 99, "Drop on the overflow row removes only that slot")
  eq(table.concat(S.save.bagOrder, ","), "X_ACCURACY,POTION", "the overflow slot leaves bagOrder")
end

do
  local S = red()
  Bag.add(S.save, "X_ACCURACY", 99, S.data)
  check(Ops.bagAdjust(S, "X_ACCURACY", 1) == true, "+1 on a full slot opens a new slot")
  eq(S.save.inventory.X_ACCURACY, 100, "the bag now holds 100")
  eq(counts(Ops.stackRows(S, false)), "X_ACCURACYx99,X_ACCURACYx1", "the new slot reads x1")
  check(Ops.bagAdjust(S, "X_ACCURACY", -1, 2) == true, "-1 on the new slot")
  eq(table.concat(S.save.bagOrder, ","), "X_ACCURACY", "emptying the new slot drops it")
end

do
  local S = red()
  Bag.add(S.save, "X_ACCURACY", 99, S.data)
  local n = 1
  for _, id in ipairs(S.cat.items) do
    if n >= Bag.capacity(S.data) then break end
    if not Ops.isBadgeId(id) and id ~= "X_ACCURACY" and Bag.add(S.save, id, 1, S.data) then n = n + 1 end
  end
  eq(Bag.slots(S.save, S.data), 20, "fixture: a 20-slot bag")
  S.dirty = false
  check(Ops.bagAdjust(S, "X_ACCURACY", 1) == false, "a full bag refuses the overflow slot")
  eq(S.save.inventory.X_ACCURACY, 99, "the refusal changes nothing")
  check(S.dirty == false, "the refusal does not dirty")
end

do
  local S = red()
  S.save.pcItems.POTION = 150
  eq(table.concat(Ops.pcOrder(S), ","), "POTION,POTION", "a 150 PC stack lists two box slots")
  eq(counts(Ops.stackRows(S, true)), "POTIONx99,POTIONx51", "PC rows carry each slot's own count")
  check(Ops.pcDrop(S, "POTION", 2) == true, "Drop on the PC overflow row")
  eq(S.save.pcItems.POTION, 99, "only the overflow slot leaves the PC")
  check(Ops.pcAdjust(S, "POTION", 1) == true, "+1 on a full PC slot opens a new slot")
  eq(S.save.pcItems.POTION, 100, "the PC now holds 100")
end

do
  local S = red()
  split(S)
  check(Ops.bagAdjust(S, "X_ACCURACY", -5, 1) == true, "-5 on the first bag slot")
  eq(counts(Ops.stackRows(S, false)), "X_ACCURACYx94,POTIONx3,X_ACCURACYx2",
    "editor rows keep 94 and 2 after a first-slot decrease")
  eq(table.concat(S.save.bagStacks.X_ACCURACY, ","), "94,2", "the per-slot counts ride save.bagStacks")
  S.save.pcItems.POTION = 150
  check(Ops.pcAdjust(S, "POTION", -1, 1) == true, "-1 on the first PC slot")
  eq(counts(Ops.stackRows(S, true)), "POTIONx98,POTIONx51", "PC rows keep 98 and 51")
end

do
  local Kit = require("Kit")
  local App = require("App")
  local oldDim = love.graphics.getDimensions
  love.graphics.getDimensions = function() return 1280, 720 end
  local path = os.tmpname() .. "-bug2671.lua"
  local seed = SaveData.newGame()
  seed.inventory = { X_ACCURACY = 101, POTION = 3 }
  seed.bagOrder = { "X_ACCURACY", "POTION", "X_ACCURACY" }
  local f = assert(io.open(path, "wb")); f:write(SaveData.encode(seed)); f:close()
  App.load(path, { version = "red" })
  local S = App.getState()
  S.tab = "items"
  local labels, invalid = {}, {}
  local real = Kit.button
  Kit.button = function(x, y, w, h, label, opts)
    if type(label) == "string" and label:find("×", 1, true) then
      labels[#labels + 1] = label
      if opts and opts.invalid then invalid[#invalid + 1] = label end
    end
    return real(x, y, w, h, label, opts)
  end
  App.draw()
  Kit.button = real
  eq(table.concat(labels, "|"), "X ACCURACY ×99|POTION ×3|X ACCURACY ×2", "panel: one row per cart slot with its own count")
  eq(#invalid, 0, "panel: no row is flagged as an illegal stack")
  App.unload()
  os.remove(path)
  love.graphics.getDimensions = oldDim
end

do
  local O = GenSave.OFFSETS
  local idx = GenSave.crosswalks(Data).itemsIndex
  local save = SaveData.newGame()
  save.inventory = { X_ACCURACY = 101, POTION = 3 }
  save.bagOrder = { "X_ACCURACY", "POTION", "X_ACCURACY" }
  save.cartBag = nil
  save.pcItems = { POTION = 150, ANTIDOTE = 1 }
  save.pcOrder = { "POTION", "ANTIDOTE", "POTION" }
  save.cartPc = nil
  local ok, bytes = pcall(GenSave.encode, save, Data)
  check(ok and type(bytes) == "string", ".sav encode runs: " .. tostring(bytes))
  if ok and type(bytes) == "string" then
    eq(bytes:byte(O.numBagItems + 1), 3, ".sav: wNumBagItems counts both X ACCURACY slots")
    local function slots(off, n)
      local out = {}
      for i = 0, n - 1 do
        out[#out + 1] = bytes:byte(off + i * 2 + 1) .. ":" .. bytes:byte(off + i * 2 + 2)
      end
      out[#out + 1] = tostring(bytes:byte(off + n * 2 + 1))
      return table.concat(out, ",")
    end
    eq(slots(O.bagItems, 3), ("%d:99,%d:3,%d:2,255"):format(idx.X_ACCURACY, idx.POTION, idx.X_ACCURACY),
      ".sav: wBagItems keeps each slot where bagOrder put it")
    eq(bytes:byte(O.numPcItems + 1), 3, ".sav: wNumBoxItems counts both POTION slots")
    eq(slots(O.pcItems, 3), ("%d:99,%d:1,%d:51,255"):format(idx.POTION, idx.ANTIDOTE, idx.POTION),
      ".sav: wBoxItems keeps each slot where pcOrder put it")
    local okD, dec = pcall(GenSave.decode, bytes, Data)
    check(okD and type(dec) == "table", ".sav decode runs: " .. tostring(dec))
    if okD and type(dec) == "table" then
      local back = dec.save or dec
      eq(back.inventory.X_ACCURACY, 101, ".sav round trip: total 101")
      eq(table.concat(back.bagOrder or {}, ","), "X_ACCURACY,POTION,X_ACCURACY", ".sav round trip: two bagOrder occurrences")
      eq(back.cartBag, nil, ".sav round trip: the modelled rows need no raw carrier")
      eq(back.pcItems.POTION, 150, ".sav round trip: PC total 150")
      eq(table.concat(back.pcOrder or {}, ","), "POTION,ANTIDOTE,POTION", ".sav round trip: two pcOrder occurrences")
    end
  end
end

do
  local O = GenSave.OFFSETS
  local idx = GenSave.crosswalks(Data).itemsIndex
  local save = SaveData.newGame()
  save.inventory = { X_ACCURACY = 96, POTION = 3 }
  save.bagOrder = { "X_ACCURACY", "POTION", "X_ACCURACY" }
  save.bagStacks = { X_ACCURACY = { 94, 2 } }
  save.cartBag = nil
  save.pcItems = { POTION = 149, ANTIDOTE = 1 }
  save.pcOrder = { "POTION", "ANTIDOTE", "POTION" }
  save.pcStacks = { POTION = { 98, 51 } }
  save.cartPc = nil
  local ok, bytes = pcall(GenSave.encode, save, Data)
  check(ok and type(bytes) == "string", ".sav encode of per-slot counts runs: " .. tostring(bytes))
  if ok and type(bytes) == "string" then
    local function slots(off, n)
      local out = {}
      for i = 0, n - 1 do
        out[#out + 1] = bytes:byte(off + i * 2 + 1) .. ":" .. bytes:byte(off + i * 2 + 2)
      end
      out[#out + 1] = tostring(bytes:byte(off + n * 2 + 1))
      return table.concat(out, ",")
    end
    eq(slots(O.bagItems, 3), ("%d:94,%d:3,%d:2,255"):format(idx.X_ACCURACY, idx.POTION, idx.X_ACCURACY),
      ".sav: wBagItems writes each slot's own count")
    eq(slots(O.pcItems, 3), ("%d:98,%d:1,%d:51,255"):format(idx.POTION, idx.ANTIDOTE, idx.POTION),
      ".sav: wBoxItems writes each slot's own count")
    local okD, dec = pcall(GenSave.decode, bytes, Data)
    check(okD and type(dec) == "table", ".sav decode of per-slot counts runs: " .. tostring(dec))
    if okD and type(dec) == "table" then
      local back = dec.save or dec
      eq(back.inventory.X_ACCURACY, 96, ".sav round trip: total 96")
      eq(table.concat(back.bagStacks and back.bagStacks.X_ACCURACY or {}, ","), "94,2",
        ".sav round trip: 94/2 comes back as per-slot counts")
      eq(back.cartBag, nil, ".sav round trip: per-slot counts need no raw carrier")
      eq(table.concat(back.pcStacks and back.pcStacks.POTION or {}, ","), "98,51",
        ".sav round trip: PC 98/51 comes back as per-slot counts")
      eq(back.cartPc, nil, ".sav round trip: PC per-slot counts need no raw carrier")
    end
  end
end

print(string.format("save editor split stack tests: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
