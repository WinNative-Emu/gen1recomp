-- Exercises src/core/WinNativeBridge.lua against a stubbed LOVE filesystem and
-- stubbed engine modules, so the host protocol is proven before any device is
-- involved. Run from the gen1recomp checkout root.

local FS = {}   -- path -> contents
local dirs = {}

love = {
  filesystem = {
    createDirectory = function(p) dirs[p] = true; return true end,
    write = function(p, s) FS[p] = s; return true end,
    read = function(p) return FS[p] end,
    remove = function(p) FS[p] = nil; return true end,
    getInfo = function(p) if FS[p] then return { type = "file", size = #FS[p] } end return nil end,
  },
}

-- ------------------------------------------------------------ engine stubs

local stepped = {}          -- id -> accumulated direction
local activated = {}
local optionValues = { voxel = "ON", tilt = "OFF", speed = "1X" }

package.loaded["src.ui.OptionsMenu"] = {
  buildRows = function()
    return {
      { id = "voxel", label = "VOXEL", value = function() return optionValues.voxel end,
        step = function(_, dir)
          stepped.voxel = (stepped.voxel or 0) + dir
          optionValues.voxel = optionValues.voxel == "ON" and "OFF" or "ON"
        end },
      { id = "tilt", label = "TILT", value = function() return optionValues.tilt end,
        step = function(_, dir) stepped.tilt = (stepped.tilt or 0) + dir end },
      -- An activate-only row, like MODS / CONTROLS in the real menu.
      { id = "mods", label = "MODS", value = function() return "2 INSTALLED" end,
        activate = function() activated.mods = true end },
      -- A label containing a tab, to prove field separators cannot be forged.
      { id = "weird", label = "A\tB", value = function() return "x\ny" end,
        step = function() end },
    }
  end,
}

local activeSlot = "slot1"
local createdSlots = {}
package.loaded["src.core.SaveData"] = {
  listSlots = function() return {
    { id = "slot1", name = "MAIN", summary = "RED 3:14" },
    { id = "slot2", name = "B", summary = "RED 0:02" },
  } end,
  activeSlot = function() return activeSlot end,
  setActiveSlot = function(_, id) activeSlot = id end,
  createSlot = function() local id = "slot3"; createdSlots[#createdSlots + 1] = id; return id end,
  slotSummary = function() return "" end,
}
package.loaded["src.core.GameVersion"] = { get = function() return "red" end }

local saved, loaded, optionsFlushed = 0, 0, 0
local game = {
  save = { options = {} },
  writeSave = function() saved = saved + 1 end,
  load = function() loaded = loaded + 1 end,
  writeOptions = function() optionsFlushed = optionsFlushed + 1 end,
}

-- ------------------------------------------------------------------ helpers

local Bridge = dofile("src/core/WinNativeBridge.lua")

-- The bridge only acts every POLL_FRAMES frames, so a "tick" is a full poll
-- period. Driving it this way also proves the throttle does not skip work.
local function tick()
  for _ = 1, 6 do Bridge.update(game) end
end

local function send(...)
  FS["winnative/cmd.txt"] = table.concat({ ... }, "\n") .. "\n"
end

local function state()
  return FS["winnative/state.txt"] or ""
end

local function rowValue(id)
  for line in state():gmatch("[^\n]+") do
    local f = {}
    for x in line:gmatch("[^\t]+") do f[#f + 1] = x end
    if f[1] == "row" and f[2] == id then return f[4], f[5] end
  end
  return nil
end

local failures = 0
local function check(name, cond, detail)
  if cond then
    print("  ok   " .. name)
  else
    failures = failures + 1
    print("  FAIL " .. name .. (detail and ("  -- " .. detail) or ""))
  end
end

-- -------------------------------------------------------------------- tests

print("state publication")
tick()
check("state file written", state() ~= "")
check("reports booted", state():match("booted\t1") ~= nil)
check("reports version", state():match("version\tred") ~= nil)
check("voxel row value", rowValue("voxel") == "ON", tostring(rowValue("voxel")))
local _, kind = rowValue("mods")
check("activate row marked activate", kind == "activate", tostring(kind))
local _, kind2 = rowValue("voxel")
check("step row marked step", kind2 == "step", tostring(kind2))
check("tabs stripped from labels", state():match("row\tweird\tA B\tx y\t") ~= nil)
check("slots listed", state():match("save\tslot1\tMAIN\tRED 3:14\t1") ~= nil)
check("inactive slot flagged", state():match("save\tslot2\tB\tRED 0:02\t0") ~= nil)

print("stepping a row")
local seqBefore = tonumber(state():match("seq\t(%d+)"))
send("step\tvoxel\t1")
tick()
check("command file consumed", FS["winnative/cmd.txt"] == nil)
check("step ran", stepped.voxel == 1, tostring(stepped.voxel))
check("value updated in state", rowValue("voxel") == "OFF", tostring(rowValue("voxel")))
check("options flushed", optionsFlushed == 1, tostring(optionsFlushed))
check("seq advanced", tonumber(state():match("seq\t(%d+)")) > seqBefore)

print("negative direction")
send("step\ttilt\t-1")
tick()
check("negative step ran", stepped.tilt == -1, tostring(stepped.tilt))

print("activate")
send("activate\tmods")
tick()
check("activate ran", activated.mods == true)

print("save / load / reset")
send("save")
tick()
check("writeSave called", saved == 1, tostring(saved))
send("loadslot\tslot2")
tick()
check("active slot switched", activeSlot == "slot2", activeSlot)
check("game reloaded", loaded == 1, tostring(loaded))
check("state shows new active slot", state():match("save\tslot2\tB\tRED 0:02\t1") ~= nil)
send("reset")
tick()
check("reset reloads", loaded == 2, tostring(loaded))
send("newslot")
tick()
check("slot created", #createdSlots == 1)

print("batching and robustness")
stepped.tilt = 0
send("step\ttilt\t1", "step\ttilt\t1", "step\ttilt\t1")
tick()
check("all three applied in one batch", stepped.tilt == 3, tostring(stepped.tilt))
send("bogus\tcommand", "step\tnosuchrow\t1", "step")
tick()
check("unknown commands survive", true)
check("state still valid after junk", state():match("booted\t1") ~= nil)

print("idle does not rewrite")
local before = state()
tick(); tick()
check("unchanged state not rewritten", state() == before)

print("pre-boot")
local seqPre = state()
local nilGame = nil
Bridge.update(nilGame)
check("nil game does not throw", true)

print("")
if failures == 0 then
  print("ALL PASS")
else
  print(failures .. " FAILURE(S)")
  os.exit(1)
end
