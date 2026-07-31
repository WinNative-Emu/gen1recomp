-- A control channel between this engine and the host application.
--
-- WinNative hosts this engine the way it hosts Dolphin: the engine runs inside
-- the host's own process and the host owns the menus, the settings UI and the
-- on-screen controls.  For that to work the host needs to do more than press
-- keys at us -- it has to be able to READ what a setting currently is, or every
-- switch it draws is a guess.  Key injection cannot do that, and driving the
-- engine's menus by synthesising keystrokes also meant the host had to know the
-- shape of menus it does not own.
--
-- So this module exposes the engine's own option rows, and its save slots, as
-- data.  Two files inside the save directory:
--
--   winnative/cmd.txt     host -> engine.  One command per line, TAB separated.
--                         Consumed and deleted as a unit.
--   winnative/state.txt   engine -> host.  Rewritten whenever it changes.
--
-- The rows are the ones the engine's own OPTIONS menu builds, which is what
-- makes this correct rather than a parallel implementation: a mod that splices
-- rows in (the voxel mod registers its pipeline rows exactly this way) shows up
-- here for free, and stepping a row runs the engine's own step function with
-- all of its side effects.  The engine stays the single owner of its settings;
-- the host only renders them and asks for changes.
--
-- Everything here is defensive.  This module runs on every frame of a normal
-- play session, so a fault in it must never take the game down with it: each
-- entry point is wrapped, and a failure degrades to "the host menu does not
-- update" rather than a crash.

local WinNativeBridge = {}

local DIR = "winnative"
local CMD_PATH = DIR .. "/cmd.txt"
local STATE_PATH = DIR .. "/state.txt"
local STATE_TMP = DIR .. "/state.tmp"

-- Frames between polls of the command file.  The host writes one only when the
-- player touches the menu, so this is a cheap stat() the vast majority of the
-- time; 6 frames keeps a menu tap feeling immediate without polling every frame.
local POLL_FRAMES = 6

local frame = 0
local seq = 0
local lastState = nil
local lastMenuState = nil
local enabled = nil

-- Host-owned run state. The engine has no notion of either: pausing is the
-- host holding the game still, and fast-forward is the host driving the
-- engine's own speed setting, so both live here rather than in save.options.
-- Neither is persisted -- a game should not come back paused.
local paused = false
local ffPrevSpeed = nil   -- the speed to restore when fast-forward turns off

-- What fast-forward runs at. GameSpeed.LEVELS goes far higher, but those
-- levels exist for the automated route-running bots; 4x is the "hold to skip
-- this text" speed a player actually wants, and matches what fast-forward
-- does on the libretro path.
local FF_LEVEL = 4

-- On by default, deliberately.  The obvious design is to have the host switch
-- this on, but the host has no way to tell this runtime anything at startup
-- except argv: the process environment is not readable from here (verified --
-- os.getenv returns nil even for variables the host set successfully), and
-- argv is limited to the two boot flags, because adding a third made LOVE exit
-- silently right after SDL_main.  This fork is only ever hosted by WinNative,
-- which is the same reasoning that defaults the engine's touch overlay off, so
-- "always on" is the honest default rather than a workaround.
--
-- WINNATIVE_BRIDGE=0 still turns it off where the environment does work, which
-- is desktop development.
local function isEnabled()
  if enabled == nil then
    enabled = os.getenv("WINNATIVE_BRIDGE") ~= "0"
  end
  return enabled
end

function WinNativeBridge.setEnabled(value)
  enabled = value and true or false
end

-- TAB separates fields and newline separates records, so neither may survive
-- inside a value.  Labels come from Strings() and mod manifests, so this is
-- about robustness rather than an expected case.
local function clean(value)
  local text = tostring(value == nil and "" or value)
  text = text:gsub("[\t\r\n]", " ")
  return text
end

-- ---------------------------------------------------------------- option rows

-- The engine's OPTIONS rows, including any a mod spliced in.  buildRows is a
-- local in OptionsMenu; scripts/winnative_bridge.sh publishes it, and this
-- degrades to an empty list if that patch ever fails to apply, so a partially
-- patched engine shows an empty settings pane instead of crashing.
local function optionRows(game)
  local ok, OptionsMenu = pcall(require, "src.ui.OptionsMenu")
  if not ok or type(OptionsMenu) ~= "table" then return {} end
  local builder = OptionsMenu.buildRows
  if type(builder) ~= "function" then return {} end
  local built
  ok, built = pcall(builder, game)
  if not ok or type(built) ~= "table" then return {} end
  return built
end

local function rowById(game, id)
  for _, row in ipairs(optionRows(game)) do
    if row.id == id then return row end
  end
  return nil
end

-- ---------------------------------------------------------------- save slots

local function saveData()
  local ok, SaveData = pcall(require, "src.core.SaveData")
  if not ok then return nil end
  return SaveData
end

local function gameVersion()
  local ok, GameVersion = pcall(require, "src.core.GameVersion")
  if not ok then return nil end
  local got
  ok, got = pcall(GameVersion.get)
  if ok then return got end
  return nil
end

-- ---------------------------------------------------------------- state file

local function buildState(game, importer)
  local out = {}
  out[#out + 1] = "seq\t" .. seq

  local version = gameVersion()
  if version then out[#out + 1] = "version\t" .. clean(version) end

  -- Tells the host whether a game is actually running.  While the engine is
  -- still importing a ROM there are no rows and no slots, and the host should
  -- show that rather than an empty menu that looks broken.
  out[#out + 1] = "booted\t" .. ((game and game.save) and "1" or "0")

  -- Run state the host owns but cannot see from its side, so its menu can
  -- show Pause and Fast Forward in the right position instead of guessing.
  out[#out + 1] = "paused\t" .. (paused and "1" or "0")
  out[#out + 1] = "ff\t" .. ((ffPrevSpeed ~= nil) and "1" or "0")

  -- First-boot ROM import. The host covers the screen with its own loading
  -- screen while this runs, so it needs the stage text and how far along it is;
  -- without them it could only show a spinner and hope. Absent entirely once
  -- the import is done, which is how the host knows to take its screen down.
  if importer then
    local status = importer.status
    local progress = tonumber(importer.progress) or 0
    if progress < 0 then progress = 0 elseif progress > 1 then progress = 1 end
    out[#out + 1] = table.concat({
      "import", clean(status or "Importing"),
      tostring(math.floor(progress * 1000)),
    }, "\t")
  end

  -- The engine's own frame rate. The host's performance overlay counts frames
  -- it is told about, and nothing on the Java side sees this engine present --
  -- SDL swaps buffers on its own thread -- so the rate has to come from here or
  -- the overlay reads a flat zero.
  if love.timer and love.timer.getFPS then
    local okFps, fps = pcall(love.timer.getFPS)
    if okFps then out[#out + 1] = "fps\t" .. tostring(math.floor(tonumber(fps) or 0)) end
  end

  for _, row in ipairs(optionRows(game)) do
    if row.id then
      local value = ""
      if type(row.value) == "function" then
        local ok, got = pcall(row.value, game)
        if ok and got ~= nil then value = got end
      end
      local kind = type(row.step) == "function" and "step" or "activate"
      out[#out + 1] = table.concat({
        "row", clean(row.id), clean(row.label), clean(value), kind,
      }, "\t")
    end
  end

  -- Which mods loaded, and why one did not. The host shows this on its own
  -- menu, so a mod that is present but rejected -- wrong game version,
  -- refused permission, a Lua error in its entry point -- says so, instead of
  -- silently not being there and looking like the host failed to install it.
  local status = game and game.modStatus
  if type(status) == "table" then
    for _, mod in ipairs(status.available or {}) do
      if mod.id then
        out[#out + 1] = table.concat({
          "mod", clean(mod.id), clean(mod.name or mod.id),
          clean(mod.version), clean(mod.state), clean(mod.error),
        }, "\t")
      end
    end
    -- Loader-level failures, which have no mod entry to hang off: a manifest
    -- that would not parse never becomes a mod at all.
    for _, err in ipairs(status.errors or {}) do
      out[#out + 1] = table.concat({
        "moderror", clean(type(err) == "table" and (err.id or err.path or "?") or "?"),
        clean(type(err) == "table" and (err.message or err.error) or err),
      }, "\t")
    end
  end

  local SaveData = saveData()
  if SaveData and version then
    local ok, slots = pcall(SaveData.listSlots, version)
    local activeOk, active = pcall(SaveData.activeSlot, version)
    if not activeOk then active = nil end
    -- activeSlot returns the slot record on some paths and a bare id on
    -- others; the host only ever needs the id.
    if type(active) == "table" then active = active.id end
    if ok and type(slots) == "table" then
      for _, slot in ipairs(slots) do
        local id = slot.id or slot.slotId
        if id then
          -- listSlots reports three different things and they are easy to
          -- confuse: `label` is the custom name the player gave the slot,
          -- `name` is the player character's name read out of the save, and
          -- `meta` is the summary line (badges, play time). The host shows the
          -- label when there is one and falls back to the character name, so a
          -- slot always has something to identify it by.
          -- meta is a table of parts (badges, play time, Pokedex count), not a
          -- sentence. They are sent as separate fields so the host can phrase
          -- and translate the summary itself, the way it does for every other
          -- system, rather than the engine baking English into a string.
          local meta = type(slot.meta) == "table" and slot.meta or {}
          out[#out + 1] = table.concat({
            "save", clean(id),
            clean(slot.label or slot.name or id),
            clean(meta.timeText),
            tostring(tonumber(meta.badges) or 0),
            tostring(tonumber(meta.dexCount) or 0),
            (tostring(id) == tostring(active)) and "1" or "0",
            slot.exists and "1" or "0",
          }, "\t")
        end
      end
    end
  end

  return table.concat(out, "\n") .. "\n"
end

-- Written through a temporary file and renamed, so the host can never read a
-- half-written state -- it polls this file on its own schedule and there is no
-- lock between the two processes.
local function writeState(game, importer)
  local ok, text = pcall(buildState, game, importer)
  if not ok then return end
  -- Two kinds of change, deliberately treated differently.
  --
  -- The frame rate moves every poll, and the sequence number is what tells the
  -- host its menu is stale. If the rate counted as a change the host would
  -- rebuild its menu ten times a second for a number that is not even on the
  -- menu. So the comparison ignores both the sequence number and the frame
  -- rate: the file is still rewritten so the rate stays fresh, but the sequence
  -- only moves when something the menu actually shows has changed.
  local body = text:gsub("^seq\t%d+\n", "")
  -- The import line moves constantly for the few seconds it exists, and the
  -- host's loading screen reads it directly rather than through the menu, so it
  -- is excluded from staleness for the same reason the frame rate is.
  local menuBody = body:gsub("fps\t%-?%d+\n", ""):gsub("import\t[^\n]*\n", "")
  if body == lastState then return end
  local menuChanged = menuBody ~= lastMenuState
  lastState = body
  lastMenuState = menuBody
  if menuChanged then seq = seq + 1 end
  text = "seq\t" .. seq .. "\n" .. body
  pcall(love.filesystem.createDirectory, DIR)
  local wrote = select(1, pcall(love.filesystem.write, STATE_TMP, text))
  if not wrote then return end
  -- love.filesystem has no rename, and a remove+write leaves a window where
  -- the file is absent; the host treats a missing file as "not ready yet" and
  -- retries, which is why that window is safe.
  pcall(love.filesystem.remove, STATE_PATH)
  pcall(love.filesystem.write, STATE_PATH, text)
  pcall(love.filesystem.remove, STATE_TMP)
end

-- -------------------------------------------------------------- command file

local function applyCommand(game, parts)
  local verb = parts[1]

  if verb == "step" then
    local row = rowById(game, parts[2])
    if row and type(row.step) == "function" then
      local dir = tonumber(parts[3]) or 1
      pcall(row.step, game, dir >= 0 and 1 or -1)
      -- The engine persists options when its own menu closes; the host menu
      -- never opens that screen, so flush here or a change is lost on exit.
      if game and type(game.writeOptions) == "function" then
        pcall(game.writeOptions, game)
      end
    end
    return
  end

  if verb == "activate" then
    local row = rowById(game, parts[2])
    if row and type(row.activate) == "function" then
      pcall(row.activate, game)
    end
    return
  end

  if verb == "save" then
    if game and type(game.writeSave) == "function" then
      pcall(game.writeSave, game)
    end
    return
  end

  -- Save INTO a chosen slot, the way the games themselves work: pick the slot,
  -- then write. Distinct from "save", which writes wherever the player already
  -- is without asking.
  if verb == "saveslot" then
    local SaveData, version = saveData(), gameVersion()
    if SaveData and version and parts[2] then
      pcall(SaveData.setActiveSlot, version, parts[2])
    end
    if game and type(game.writeSave) == "function" then
      pcall(game.writeSave, game)
    end
    return
  end

  if verb == "loadslot" then
    local SaveData, version = saveData(), gameVersion()
    if SaveData and version and parts[2] then
      pcall(SaveData.setActiveSlot, version, parts[2])
    end
    -- Game:load re-reads the active slot, which is exactly what booting into
    -- that slot does, so switching slots and reloading share one path.
    if game and type(game.load) == "function" then
      pcall(game.load, game)
    end
    return
  end

  if verb == "pause" then
    paused = parts[2] == "1"
    return
  end

  if verb == "ff" then
    local want = parts[2] == "1"
    local opts = game and game.save and game.save.options
    if not opts then return end
    local ok, GameSpeed = pcall(require, "src.core.GameSpeed")
    if not ok then return end
    if want then
      -- Remembered so turning fast-forward off restores whatever the player
      -- had chosen on the Performance pane, rather than snapping to 1x.
      if ffPrevSpeed == nil then ffPrevSpeed = opts.speed or GameSpeed.DEFAULT end
      opts.speed = FF_LEVEL
    elseif ffPrevSpeed ~= nil then
      opts.speed = ffPrevSpeed
      ffPrevSpeed = nil
    end
    return
  end

  if verb == "renameslot" then
    local SaveData, version = saveData(), gameVersion()
    -- parts[4..] rejoined: a slot name may contain spaces, and only tabs and
    -- newlines are excluded by the wire format.
    local name = parts[3]
    for i = 4, #parts do name = name .. "\t" .. parts[i] end
    if SaveData and version and parts[2] and name and name ~= "" then
      pcall(SaveData.renameSlot, version, parts[2], name)
    end
    return
  end

  if verb == "newslot" then
    local SaveData, version = saveData(), gameVersion()
    if SaveData and version then
      local ok, id = pcall(SaveData.createSlot, version)
      if ok and id then
        if type(id) == "table" then id = id.id end
        pcall(SaveData.setActiveSlot, version, id)
        if game and type(game.load) == "function" then
          pcall(game.load, game)
        end
      end
    end
    return
  end

  if verb == "reset" then
    if game and type(game.load) == "function" then
      pcall(game.load, game)
    end
    return
  end

  -- "refresh" and anything unrecognised fall through: the state file is
  -- rewritten after every batch regardless, which is all refresh asks for.
end

local function consumeCommands(game)
  local info = love.filesystem.getInfo(CMD_PATH)
  if not info then return false end
  local text = love.filesystem.read(CMD_PATH)
  -- Removed before the commands run, not after.  A command that throws would
  -- otherwise leave the file in place and be retried on every poll forever.
  pcall(love.filesystem.remove, CMD_PATH)
  if not text or text == "" then return false end

  for line in text:gmatch("[^\r\n]+") do
    local parts = {}
    for field in line:gmatch("[^\t]+") do parts[#parts + 1] = field end
    if parts[1] then pcall(applyCommand, game, parts) end
  end
  return true
end

-- ---------------------------------------------------------------- entry point

-- Called once per frame from love.update, before the game steps.
--
-- Returns true when the host has paused the game, which is the caller's signal
-- to skip the rest of love.update. Only the game's own stepping stops: this
-- function keeps polling, or there would be no way to receive the command that
-- unpauses, and love.draw keeps running so the frozen frame stays on screen.
function WinNativeBridge.update(game, importer)
  if not isEnabled() then return false end
  frame = frame + 1
  if frame % POLL_FRAMES == 0 then
    pcall(consumeCommands, game)
    pcall(writeState, game, importer)
  end
  return paused
end

return WinNativeBridge
