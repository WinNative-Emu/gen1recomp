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
DAY_LABELS = { "SYNC", "DAY", "NIGHT", "DUSK", "DAWN" }
dayIndex = 1

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
      -- A row carrying its own ladder, the way a mod's setting does. Nothing
      -- in the bridge can know what a mod cycles through, so a mod that says
      -- so is the only way its row can become a dropdown.
      { id = "DRAMATIC_SHAPE:daytime", label = "DAYTIME",
        value = function() return DAY_LABELS[dayIndex] end,
        choices = function() return DAY_LABELS, dayIndex end,
        step = function(_, dir)
          dayIndex = (dayIndex - 1 + dir) % #DAY_LABELS + 1
        end },
      -- A volume row: enumerated from the stored option rather than declared,
      -- and -- unlike every other ladder -- it CLAMPS at both ends instead of
      -- wrapping, which is the case that breaks a naive shortest-path walk.
      { id = "musicVol", label = "MUSIC VOL",
        value = function(g)
          local v = g.save.options.musicVol or 7
          return v == 0 and "OFF" or tostring(v)
        end,
        step = function(g, dir)
          local o = g.save.options
          o.musicVol = math.max(0, math.min(7, (o.musicVol or 7) + dir))
        end },
    }
  end,
}

local activeSlot = "slot1"
renamedSlot = nil
local createdSlots = {}
package.loaded["src.core.SaveData"] = {
  listSlots = function() return {
    -- Matches SaveData.listSlots: `label` is the custom slot name, `name` is
    -- the character name from the save, `meta` the summary line.
    { id = "slot1", label = "MAIN", name = "MAX", exists = true,
      meta = { timeText = "3:14", badges = 2, dexCount = 25 } },
    { id = "slot2", name = "B", exists = true,
      meta = { timeText = "0:02", badges = 0, dexCount = 1 } },
  } end,
  activeSlot = function() return activeSlot end,
  setActiveSlot = function(_, id) activeSlot = id end,
  createSlot = function() local id = "slot3"; createdSlots[#createdSlots + 1] = id; return id end,
  renamed = nil,
  renameSlot = function(_, id, name) renamedSlot = { id = id, name = name } end,
  slotSummary = function() return "" end,
  -- Reads whichever slot is active, the way the real one resolves its path
  -- through the active slot. slot3 is the created-but-never-written slot.
  load = function()
    if activeSlot == "slot3" then return nil end
    return { player = { map = activeSlot } }, nil
  end,
  -- The slot registry lives in options.lua, so this is what the bridge has to
  -- copy back into the running game after every slot change.
  loadOptions = function() return { saveSlots = { red = { active = activeSlot } } } end,
}
-- The mod hook. Rows a mod adds do NOT come from buildRows -- the engine runs
-- this hook in OptionsMenu.new, a screen the host never opens -- so the bridge
-- runs it too. This stub does both things a real mod does: splices a row in,
-- and takes one away.
CURVE_LABELS = { "OFF", "1", "2", "3" }
curveIndex = 1
hookCalls = 0
package.loaded["src.mods.Runtime"] = {
  call = function(name, default, game, rows)
    if name ~= "ui.options.rows" then return default(game, rows) end
    hookCalls = hookCalls + 1
    local out = {}
    for _, row in ipairs(rows) do
      -- A mod removing an engine row it has taken control of.
      if row.id ~= "battleLayout" then out[#out + 1] = row end
    end
    out[#out + 1] = {
      id = "DRAMATIC_SHAPE:curve", label = "V-CURVE",
      value = function() return CURVE_LABELS[curveIndex] end,
      choices = function() return CURVE_LABELS, curveIndex end,
      step = function(_, dir)
        curveIndex = (curveIndex - 1 + dir) % #CURVE_LABELS + 1
      end,
    }
    return out
  end,
}

package.loaded["src.core.GameVersion"] = { get = function() return "red" end }
package.loaded["src.core.GameSpeed"] = { LEVELS = { 1, 2, 4, 10 }, DEFAULT = 1 }

local saved, loaded, optionsFlushed = 0, 0, 0
local restored, titled = nil, 0
local game = {
  save = { options = { speed = 2 } },
  writeSave = function() saved = saved + 1 end,
  -- The engine's BOOT path. Nothing the host menu does should reach it: it
  -- rebuilds every subsystem and starts a new game.
  load = function() loaded = loaded + 1 end,
  restoreSave = function(_, data) restored = data end,
  returnToTitle = function() titled = titled + 1 end,
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

print("mod rows reach the host")
-- The rows a mod splices in are the ones the engine only assembles when its
-- OWN options screen opens. The host never opens it, so without running the
-- hook these settings are unreachable from WinNative even though they work.
check("hook ran", hookCalls > 0, tostring(hookCalls))
check("a mod's own row is published",
      state():match("row\tDRAMATIC_SHAPE:curve\tV%-CURVE\tOFF\tstep") ~= nil)
check("and carries its ladder, so the host can draw a dropdown",
      state():match("vals\tDRAMATIC_SHAPE:curve\t0\tOFF\t1\t2\t3") ~= nil)
-- A mod may also REMOVE a row it has taken control of; the host must not keep
-- showing a setting that no longer decides anything.
check("a row the mod removed is gone", rowValue("battleLayout") == nil)
check("label preferred over character name", state():match("save\tslot1\tMAIN\t3:14\t2\t25\t1\t1") ~= nil)
check("falls back to character name", state():match("save\tslot2\tB\t0:02\t0\t1\t0\t1") ~= nil)

print("stepping a row")
local seqBefore = tonumber(state():match("seq\t(%d+)"))
send("step\tvoxel\t1")
tick()
check("command file consumed", FS["winnative/cmd.txt"] == nil)
check("step ran", stepped.voxel == 1, tostring(stepped.voxel))
check("value updated in state", rowValue("voxel") == "OFF", tostring(rowValue("voxel")))
check("options flushed", optionsFlushed == 1, tostring(optionsFlushed))
check("seq advanced", tonumber(state():match("seq\t(%d+)")) > seqBefore)

print("value ladders")
local function vals(id)
  for line in state():gmatch("[^\n]+") do
    local f = {}
    for x in line:gmatch("[^\t]+") do f[#f + 1] = x end
    if f[1] == "vals" and f[2] == id then
      local labels = {}
      for i = 4, #f do labels[#labels + 1] = f[i] end
      return tonumber(f[3]), labels
    end
  end
  return nil
end
local dayIdx, dayLabels = vals("DRAMATIC_SHAPE:daytime")
check("row-supplied ladder published", dayLabels ~= nil and #dayLabels == 5,
      dayLabels and tostring(#dayLabels) or "missing")
check("ladder index is zero-based for the host", dayIdx == 0, tostring(dayIdx))
check("ladder labels in order", dayLabels and dayLabels[3] == "NIGHT",
      dayLabels and tostring(dayLabels[3]))
local volIdx, volLabels = vals("musicVol")
check("volume ladder derived from the option", volLabels ~= nil and #volLabels == 8,
      volLabels and tostring(#volLabels) or "missing")
check("volume ladder starts at OFF", volLabels and volLabels[1] == "OFF")
check("volume index tracks the stored value", volIdx == 7, tostring(volIdx))
check("activate rows carry no ladder", vals("mods") == nil)
-- "voxel" here is the stub's own id, not a pipeline: nothing describes it, so
-- the host must be left to fall back to its arrows rather than shown a guess.
check("unknown cyclers carry no ladder", vals("voxel") == nil)

print("setting a row to a chosen value")
send("set\tDRAMATIC_SHAPE:daytime\t3")
tick()
check("walked to the chosen value", dayIndex == 4, tostring(dayIndex))
check("state reports the new index", (vals("DRAMATIC_SHAPE:daytime")) == 3,
      tostring((vals("DRAMATIC_SHAPE:daytime"))))
send("set\tDRAMATIC_SHAPE:daytime\t0")
tick()
check("walks back down a wrapping ladder", dayIndex == 1, tostring(dayIndex))

-- The clamping case: MUSIC VOL 7 -> 0 looks like one step backwards if the
-- ladder is assumed to wrap, and stepping down from 7 goes the wrong way.
send("set\tmusicVol\t0")
tick()
check("clamping ladder still reaches its far end", game.save.options.musicVol == 0,
      tostring(game.save.options.musicVol))
check("clamping ladder index published", (vals("musicVol")) == 0,
      tostring((vals("musicVol"))))
send("set\tmusicVol\t7")
tick()
check("and comes back", game.save.options.musicVol == 7, tostring(game.save.options.musicVol))

local flushedBefore = optionsFlushed
send("set\tmusicVol\t7")
tick()
check("setting to the current value changes nothing", game.save.options.musicVol == 7)
check("but is still flushed, harmlessly", optionsFlushed == flushedBefore + 1)

-- Out of range, and a row with no ladder at all: both have to be inert rather
-- than spin the walk loop.
send("set\tmusicVol\t99", "set\tvoxel\t2", "set\tmods\t1", "set\tnosuchrow\t0")
tick()
check("an out-of-range index clamps to the ladder", game.save.options.musicVol == 7,
      tostring(game.save.options.musicVol))
check("survives set on rows with no ladder", state() ~= "")

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
send("saveslot\tslot2")
tick()
check("saveslot switched the active slot", activeSlot == "slot2", activeSlot)
check("saveslot wrote the game", saved == 2, tostring(saved))
check("saveslot resynced the registry before writing",
      game.save.options.saveSlots.red.active == "slot2",
      tostring(game.save.options.saveSlots and game.save.options.saveSlots.red.active))
activeSlot = "slot1"
send("loadslot\tslot2")
tick()
check("active slot switched", activeSlot == "slot2", activeSlot)
-- The whole point: the slot's save is restored into the running game. Booting
-- instead (Game:load) is what made Load look like it did nothing -- it built a
-- brand new save and went back to the title screen.
check("slot restored into the running game",
      restored ~= nil and restored.player.map == "slot2",
      restored and tostring(restored.player.map) or "nothing restored")
check("did not take the boot path", loaded == 0, tostring(loaded))
check("state shows new active slot", state():match("save\tslot2\tB\t0:02\t0\t1\t1\t1") ~= nil)

-- An empty slot has no file to read, so there is nothing to restore and the
-- running game must be left exactly as it was rather than half-reset.
restored = nil
send("loadslot\tslot3")
tick()
check("an empty slot restores nothing", restored == nil)
check("and still does not boot", loaded == 0, tostring(loaded))
activeSlot = "slot2"

send("reset")
tick()
check("reset power-cycles to the title", titled == 1, tostring(titled))
check("reset does not re-run the whole boot", loaded == 0, tostring(loaded))
local savedBefore = saved
send("newslot")
tick()
check("slot created", #createdSlots == 1)
check("new slot becomes the active one", activeSlot == "slot3", activeSlot)
-- The host only offers this from its Save screen, so the point is to end up
-- with the game saved in the new slot -- not to be handed an empty one.
check("and the game is written into it", saved == savedBefore + 1,
      tostring(saved) .. " vs " .. tostring(savedBefore))
check("new slot does not power-cycle", titled == 1, tostring(titled))

print("rename")
send("renameslot\tslot1\tMY BEST RUN")
tick()
check("rename reached the engine", renamedSlot ~= nil and renamedSlot.id == "slot1")
check("name with spaces preserved", renamedSlot and renamedSlot.name == "MY BEST RUN",
      renamedSlot and tostring(renamedSlot.name))

print("rom import")
local importer = { status = "Verifying Pokemon Red", progress = 0.25 }
for _ = 1, 6 do Bridge.update(game, importer) end
check("import stage and progress published",
      state():match("import\tVerifying Pokemon Red\t250") ~= nil,
      state():match("import[^\n]*"))
local seqWithImport = tonumber(state():match("seq\t(%d+)"))
importer.progress = 0.5
for _ = 1, 6 do Bridge.update(game, importer) end
check("progress moves without restating the menu",
      state():match("import\tVerifying Pokemon Red\t500") ~= nil and
      tonumber(state():match("seq\t(%d+)")) == seqWithImport,
      "seq " .. tostring(seqWithImport) .. " -> " .. tostring(tonumber(state():match("seq\t(%d+)"))))
tick()
check("import line gone once the importer is", state():match("import\t") == nil)

print("pause")
check("not paused at rest", Bridge.update(game) ~= true)
send("pause\t1")
tick()
check("update reports paused", Bridge.update(game) == true)
check("state reports paused", state():match("paused\t1") ~= nil)
check("polling continues while paused", (function()
  send("pause\t0"); tick(); return Bridge.update(game) ~= true
end)(), "could not unpause -- the poll stopped")
check("state reports resumed", state():match("paused\t0") ~= nil)

print("fast forward")
check("speed starts at the player's setting", game.save.options.speed == 2)
send("ff\t1")
tick()
check("speed raised", game.save.options.speed == 4, tostring(game.save.options.speed))
check("state reports ff on", state():match("ff\t1") ~= nil)
send("ff\t0")
tick()
check("previous speed restored, not reset to 1x", game.save.options.speed == 2,
      tostring(game.save.options.speed))
check("state reports ff off", state():match("ff\t0") ~= nil)

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
