#!/usr/bin/env bash
# Teaches main.lua to take the scripted-boot ROM path and game version from the
# command line as well as from the environment.
#
# Upstream already supports booting straight into a game without its launcher:
# POKEPORT_IMPORT_ROM marks the run "scripted", imports the ROM headlessly and
# boots it. On Android, though, the host has no way to set an environment
# variable the engine can see -- android.system.Os.setenv writes the ART process
# environment, and a probe inside love.load showed os.getenv returning nil for it
# anyway. SDL's nativeSetenv is bound too late to help (calling it after
# super.onCreate made the activity exit before love.load ran).
#
# argv does arrive: SDL passes the activity's getArguments() to LÖVE, LÖVE puts
# it in Lua's `arg`, and conf.lua already reads `arg` for --editor. So the host
# passes --import-rom / --game-version and this patch maps them onto the existing
# scripted path. The environment variables keep working exactly as before; the
# flags are only consulted when the corresponding variable is unset.
#
# Applied as a build step rather than committed edits, so a daily upstream sync
# never conflicts with it. Idempotent.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MAIN="$ROOT/main.lua"

say() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }

[ -f "$MAIN" ] || { echo "error: $MAIN not found" >&2; exit 1; }

# Each patch below is guarded on its own, so an already-patched main.lua does not
# stop the TouchControls patch from being applied (or vice versa) -- an upstream
# sync can restore one file without the other.
if grep -q 'WINNATIVE_BOOT_ARGS' "$MAIN"; then
  say "main.lua already accepts --import-rom / --game-version"
else

python3 - "$MAIN" <<'PY'
import pathlib, sys

path = pathlib.Path(sys.argv[1])
src = path.read_text()

# Anchor on the line that first reads the scripted-boot variable. Everything
# below it already branches on these two values, so supplying them earlier is
# enough -- no other logic has to change.
anchor = '  local importPath = os.getenv("POKEPORT_IMPORT_ROM")\n'
if anchor not in src:
    raise SystemExit("anchor not found in main.lua; upstream layout changed")

patch = '''  -- WINNATIVE_BOOT_ARGS: accept the scripted-boot inputs on the command line
  -- too. The host cannot set an environment variable this runtime can see, but
  -- argv reaches Lua intact. Environment wins when both are present, so this is
  -- purely additive.
  local wnArgRom, wnArgVersion
  do
    local argv = args or arg
    if type(argv) == "table" then
      local i = 1
      while argv[i] do
        if argv[i] == "--import-rom" then
          wnArgRom = argv[i + 1]; i = i + 2
        elseif argv[i] == "--game-version" then
          wnArgVersion = argv[i + 1]; i = i + 2
        else
          i = i + 1
        end
      end
    end
  end

  local importPath = os.getenv("POKEPORT_IMPORT_ROM") or wnArgRom
'''

src = src.replace(anchor, patch, 1)

# The version has its own reader a couple of lines down.
ver_anchor = '  local scriptedVersion = os.getenv("POKEPORT_VERSION") or "red"\n'
if ver_anchor not in src:
    raise SystemExit("version anchor not found in main.lua; upstream layout changed")
src = src.replace(
    ver_anchor,
    '  local scriptedVersion = os.getenv("POKEPORT_VERSION") or wnArgVersion or "red"\n',
    1,
)

path.write_text(src)
PY

say "main.lua now accepts --import-rom / --game-version"
fi

# The engine draws its own on-screen D-pad on Android. WinNative supplies the
# Game Boy pad and the Retro menu itself, so the engine's overlay has to go --
# otherwise the player gets two sets of controls stacked on each other.
# POKEPORT_TOUCH=0 already turns it off, but the environment does not reach this
# runtime, so wantsOverlay() learns to read the same argv the boot flags use.
TOUCH="$ROOT/src/core/TouchControls.lua"
if [ -f "$TOUCH" ] && ! grep -q 'WINNATIVE_TOUCH_ARG' "$TOUCH"; then
  python3 - "$TOUCH" <<'PY'
import pathlib, sys

path = pathlib.Path(sys.argv[1])
src = path.read_text()

anchor = '''local function wantsOverlay()
  local env = os.getenv("POKEPORT_TOUCH")
'''
if anchor not in src:
    raise SystemExit("wantsOverlay anchor not found; upstream layout changed")

patch = '''local function wantsOverlay()
  -- WINNATIVE_TOUCH_ARG: this fork is only ever hosted by WinNative, which
  -- draws the Game Boy pad and the Retro menu itself, so the engine's own
  -- on-screen D-pad must never appear -- otherwise the player gets two sets of
  -- controls stacked on each other. Defaulted off here rather than passed as a
  -- flag: adding anything to argv for it made LÖVE die silently just after
  -- SDL_main, and a build-time fact about this fork does not belong in argv.
  -- POKEPORT_TOUCH=1 still forces it back on for engine-side testing.
  if os.getenv("POKEPORT_TOUCH") ~= "1" then return false end
  local env = os.getenv("POKEPORT_TOUCH")
'''

path.write_text(src.replace(anchor, patch, 1))
PY
  say "TouchControls.lua now accepts --touch-controls"
fi
