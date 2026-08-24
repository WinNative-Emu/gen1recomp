#!/usr/bin/env bash
# Asserts the engine still honours everything WinNative drives it through.
#
# WHY THIS EXISTS, AND WHY IT IS NOT THE SAME AS THE PATCH SCRIPTS.
#
# The three winnative_*.sh patch scripts already fail loudly when upstream
# moves what they anchor on, so a half-patched engine cannot ship. But they
# only guard the four places we EDIT. The bridge also CALLS a couple of dozen
# engine functions and reads a dozen module tables, and none of that is
# patched -- it is just called at runtime.
#
# Every one of those calls is wrapped in pcall, deliberately: this module runs
# on every frame of a play session and a fault in it must never take the game
# down. The cost of that is silence. If upstream renames Tilt.ANGLE_LABELS the
# TILT dropdown quietly becomes a pair of arrows; if it renames
# Game:restoreSave, Load quietly stops loading; if it renames
# SaveData.loadOptions, a slot rename quietly reverts. The engine builds, the
# menu opens, and nothing says a word -- which is exactly how Load shipped
# broken once already.
#
# So this checks the contract itself. It is deliberately STATIC: it reads the
# source rather than loading it, because loading these modules needs a real
# LOVE runtime with a window and a GPU, which CI does not have. Static checking
# catches the failure that actually happens on an upstream sync -- a symbol
# being renamed, moved or deleted -- without needing any of that.
#
# Run after the patch scripts. A failure here means an upstream change has
# broken something WinNative depends on, and the message names what breaks so
# it can be fixed rather than rediscovered on a device.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

python3 - "$@" <<'PY'
import re, sys, pathlib

fails = []
oks = 0

def check(path, pattern, what, breaks):
    """Assert `pattern` (a regex) appears in `path`."""
    global oks
    p = pathlib.Path(path)
    if not p.is_file():
        fails.append((f"{path} is missing", breaks))
        return
    if re.search(pattern, p.read_text(), re.M):
        oks += 1
        print(f"  ok   {what}")
    else:
        fails.append((f"{what}  [{path}]", breaks))

# ---------------------------------------------------------------- the patches
# Cheap re-assertion that the build-time patches are in place. The scripts
# check this too; repeating it here means one command can answer "is this tree
# fit for WinNative to drive".
check("main.lua", r"WINNATIVE_BOOT_ARGS", "main.lua takes the ROM on argv",
      "the host cannot tell the engine which ROM to import")
check("main.lua", r"WINNATIVE_BRIDGE_UPDATE", "main.lua drives the bridge",
      "the entire Retro menu goes dead: no settings, no save slots, no pause")
check("src/ui/OptionsMenu.lua", r"WINNATIVE_BUILD_ROWS", "OptionsMenu publishes buildRows",
      "the settings panes show nothing at all")
check("src/core/TouchControls.lua", r"WINNATIVE_TOUCH_ARG", "engine touch overlay suppressed",
      "two sets of on-screen controls stack on top of each other")

# ------------------------------------------------------------- engine methods
# Called on the Game object by the bridge. A rename here is silent: the bridge
# type-checks before calling, so a missing method is simply never invoked.
for name, what, breaks in [
    ("writeSave",    "Game:writeSave",    "Save, and Save-to-slot, stop writing anything"),
    ("writeOptions", "Game:writeOptions", "settings changed from the menu are lost on exit"),
    ("load",         "Game:load",         "the reset fallback has nothing to call"),
    ("restoreSave",  "Game:restoreSave",  "Load stops loading and silently starts a new game"),
    ("returnToTitle","Game:returnToTitle","Reset re-runs the whole boot instead of power-cycling"),
]:
    check("src/core/Game.lua", rf"^function Game:{name}\b", what, breaks)

# ---------------------------------------------------------------- SaveData API
for name, breaks in [
    ("listSlots",     "the save-slot list is empty"),
    ("activeSlot",    "no slot is ever marked active"),
    ("setActiveSlot", "choosing a slot to save into or load from does nothing"),
    ("createSlot",    "New Save Slot does nothing"),
    ("renameSlot",    "renaming a slot does nothing"),
    ("load",          "Load cannot read the slot it was asked for"),
    ("loadOptions",   "the slot registry is not resynced, so a slot switch or rename silently reverts"),
]:
    check("src/core/SaveData.lua", rf"^function SaveData\.{name}\b", f"SaveData.{name}", breaks)

# ------------------------------------------------------------- the value ladders
# Each dropdown in the Retro menu is built from one of these. Losing one does
# not break the row -- it downgrades it to the arrows the dropdowns replaced,
# which is a regression a player would notice long before CI did.
LADDERS = [
    ("src/render/Tilt.lua",         r"^Tilt\.ANGLE_LABELS\s*=",      "Tilt.ANGLE_LABELS",      "TILT"),
    ("src/render/PaletteFX.lua",    r"^PaletteFX\.MODES\s*=",        "PaletteFX.MODES",        "COLORS"),
    ("src/render/PaletteFX.lua",    r"^function PaletteFX\.modeLabel", "PaletteFX.modeLabel",  "COLORS"),
    ("src/render/TileRenderer.lua", r"^TileRenderer\.VOID_FILLS\s*=", "TileRenderer.VOID_FILLS","VOID FILL"),
    ("src/render/TileRenderer.lua", r"^function TileRenderer\.voidFillLabel", "TileRenderer.voidFillLabel", "VOID FILL"),
    ("src/render/Zoom.lua",         r"^function Zoom\.offsetRange",  "Zoom.offsetRange",       "ZOOM"),
    ("src/render/Zoom.lua",         r"^function Zoom\.offsetLabel",  "Zoom.offsetLabel",       "ZOOM"),
    ("src/core/VideoMode.lua",      r"^VideoMode\.MODES\s*=",        "VideoMode.MODES",        "the Fullscreen button"),
    ("src/core/VideoMode.lua",      r"^function VideoMode\.normalize","VideoMode.normalize",   "the Fullscreen button"),
    ("src/core/FrameCap.lua",       r"^FrameCap\.STEPS\s*=",         "FrameCap.STEPS",         "MAX FPS"),
    ("src/core/FrameCap.lua",       r"^function FrameCap\.normalize", "FrameCap.normalize",    "MAX FPS"),
    ("src/core/GameSpeed.lua",      r"^GameSpeed\.LEVELS\s*=",       "GameSpeed.LEVELS",       "GAME SPEED, and fast-forward"),
    ("src/core/GameSpeed.lua",      r"^function GameSpeed\.clamp",   "GameSpeed.clamp",        "GAME SPEED"),
    ("src/core/GameSpeed.lua",      r"^function GameSpeed\.levelLabel","GameSpeed.levelLabel", "GAME SPEED"),
    ("src/render/Pipelines.lua",    r"^function Pipelines\.levelLabels", "Pipelines.levelLabels", "the VOXEL and T-SHIFT dropdowns"),
    ("src/render/Pipelines.lua",    r"^function Pipelines\.level\b", "Pipelines.level",        "the VOXEL and T-SHIFT dropdowns"),
    ("src/render/Renderer.lua",     r"function Renderer:fitScale",   "Renderer:fitScale",      "ZOOM"),
]
for path, pattern, what, row in LADDERS:
    check(path, pattern, what, f"the {row} dropdown degrades to arrows")

# The speed rows are the one ladder the bridge does not name: there is one row
# per category and their ids come from GameSpeed.optionKey, so the bridge reads
# these two to find its own rows. Losing either costs more than a dropdown --
# nothing matches the speed rows any more, so they degrade to arrows AND the
# host's fast-forward button writes nothing at all.
check("src/core/GameSpeed.lua", r"^GameSpeed\.CATEGORIES\s*=", "GameSpeed.CATEGORIES",
      "the speed dropdowns degrade to arrows and fast-forward stops working")
check("src/core/GameSpeed.lua", r"^function GameSpeed\.optionKey", "GameSpeed.optionKey",
      "the speed dropdowns degrade to arrows and fast-forward stops working")

# ------------------------------------------------------------------- the rows
# The host sorts rows onto panes by id. An id that disappears is not fatal --
# unknown ids fall through to System on purpose -- but a RENAMED id lands on
# the wrong pane silently, so they are worth pinning.
rows = pathlib.Path("src/ui/OptionsMenu.lua").read_text()
for rid, pane in [
    ("musicVol", "Sound"), ("sfxVol", "Sound"), ("musicFilter", "Sound"),
    ("colors", "Display"), ("tilt", "Display"), ("zoom", "Display"),
    ("voidFill", "Display"), ("videoMode", "Display"), ("animations", "Display"),
    # SHADER FX replaced GBC FX upstream. Both slots are activate rows that open
    # the engine's own preset picker, so there is no ladder to pin -- only that
    # the rows are still called this, or they land on the wrong pane.
    ("shaderfx", "Display"), ("shaderfx2", "Display"),
    ("fpsCap", "Performance"),
    # One speed row per GameSpeed category, replacing the single "speed" row.
    ("speedOverworld", "Performance"), ("speedBattle", "Performance"),
    ("speedMenu", "Performance"),
    ("textSpeed", "System"), ("battleStyle", "System"), ("battleLayout", "System"),
    ("ruleset", "System"), ("mods", "System"), ("controls", "Controls"),
]:
    if re.search(rf'id = "{rid}"', rows):
        oks += 1
        print(f"  ok   row id {rid}")
    else:
        fails.append((f'row id "{rid}" is gone', f"it disappears from the {pane} pane"))

# ------------------------------------------------------------------- the bridge
check("src/core/WinNativeBridge.lua", r"^local WinNativeBridge", "the bridge module is present",
      "there is no host bridge at all")

print()
if fails:
    print(f"\033[1;31m{len(fails)} CONTRACT FAILURE(S)\033[0m -- upstream moved something WinNative drives:\n")
    for what, breaks in fails:
        print(f"  \033[1;31mFAIL\033[0m {what}")
        print(f"       -> {breaks}")
    print("\nFix the bridge (src/core/WinNativeBridge.lua) or the patch scripts to match")
    print("the new upstream layout. Do not publish until this passes: the engine will")
    print("build and run, and WinNative's menu will be quietly broken.")
    sys.exit(1)

print(f"\033[1;32mCONTRACT OK\033[0m -- {oks} checks passed")
PY
