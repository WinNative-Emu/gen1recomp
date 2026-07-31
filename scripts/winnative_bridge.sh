#!/usr/bin/env bash
# Wires src/core/WinNativeBridge.lua into the engine.
#
# The bridge module itself is a normal committed file -- upstream does not have
# it, so a daily sync can never conflict over it. Only the two touch points in
# files upstream DOES own are patched here, at build time, for the same reason
# the SDL rename and the boot flags are: a merge conflict in main.lua every time
# upstream edits near the update loop would break the daily sync.
#
# Two touch points:
#
#   1. OptionsMenu.buildRows -- buildRows is a local. The bridge reports the
#      engine's own option rows rather than reimplementing them, so that the
#      host's settings menu shows real values and stepping a row runs the
#      engine's own side effects. Publishing the existing local is the smallest
#      change that allows it.
#
#   2. love.update -- one call, before Game:update, so a command the host wrote
#      takes effect on the same frame it is read.
#
# Idempotent, and each patch is guarded separately: an upstream sync can restore
# one of these files without the other.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MAIN="$ROOT/main.lua"
OPTIONS="$ROOT/src/ui/OptionsMenu.lua"
BRIDGE="$ROOT/src/core/WinNativeBridge.lua"

say() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }

[ -f "$BRIDGE" ] || { echo "error: $BRIDGE is missing; the bridge module should be committed" >&2; exit 1; }
[ -f "$MAIN" ] || { echo "error: $MAIN not found" >&2; exit 1; }
[ -f "$OPTIONS" ] || { echo "error: $OPTIONS not found" >&2; exit 1; }

# ---------------------------------------------------------------- buildRows

if grep -q 'WINNATIVE_BUILD_ROWS' "$OPTIONS"; then
  say "OptionsMenu already publishes buildRows"
else
  python3 - "$OPTIONS" <<'PY'
import pathlib, sys

path = pathlib.Path(sys.argv[1])
src = path.read_text()

# Anchor on the constructor, which is the first thing that uses buildRows --
# so the assignment is placed where the local is certainly in scope, and the
# anchor fails loudly if upstream renames either.
anchor = "function OptionsMenu.new(game, opts)"
if anchor not in src:
    raise SystemExit("OptionsMenu.new not found; upstream layout changed")
if "local function buildRows(game)" not in src:
    raise SystemExit("buildRows not found; upstream layout changed")

patch = """-- WINNATIVE_BUILD_ROWS: publish the row builder so the host bridge can report
-- the engine's own options instead of maintaining a second copy of the list.
-- Read-only from the bridge's side: it calls this to describe rows, and calls
-- each row's own step/activate to change one.
OptionsMenu.buildRows = buildRows

function OptionsMenu.new(game, opts)"""

path.write_text(src.replace(anchor, patch, 1))
PY
  say "OptionsMenu now publishes buildRows"
fi

# ---------------------------------------------------------------- love.update

if grep -q 'WINNATIVE_BRIDGE_UPDATE' "$MAIN"; then
  say "main.lua already drives the host bridge"
else
  python3 - "$MAIN" <<'PY'
import pathlib, sys

path = pathlib.Path(sys.argv[1])
src = path.read_text()

anchor = "function love.update(dt)\n"
if anchor not in src:
    raise SystemExit("love.update not found in main.lua; upstream layout changed")

patch = """function love.update(dt)
  -- WINNATIVE_BRIDGE_UPDATE: let the host read the engine's settings and ask
  -- for changes. Placed at the very top so it also runs while the importer is
  -- still on screen -- the host's menu needs to know a game has not booted yet,
  -- and the early returns below would otherwise hide that. Game is nil until
  -- bootGame runs, which the bridge handles. Importer is passed too: it only
  -- exists during a first-boot ROM import, and it is the only thing that knows
  -- how far along that import is -- the host draws its own loading screen from
  -- it, so the player sees WinNative rather than the engine's own splash.
  -- Returns true while the host has the game paused, which stops the game
  -- stepping without stopping the poll below it -- otherwise there would be no
  -- way to receive the command that unpauses. love.draw still runs, so the
  -- paused frame stays on screen.
  if require("src.core.WinNativeBridge").update(Game, Importer) then return end

"""

path.write_text(src.replace(anchor, patch, 1))
PY
  say "main.lua now drives the host bridge"
fi

# A half-applied patch set is the failure that costs the most time to diagnose,
# because the engine still builds and still runs -- it just silently ignores the
# host. Fail the build instead.
for marker in "WINNATIVE_BUILD_ROWS:$OPTIONS" "WINNATIVE_BRIDGE_UPDATE:$MAIN"; do
  name="${marker%%:*}"
  file="${marker#*:}"
  grep -q "$name" "$file" || { echo "error: $name did not apply to $file" >&2; exit 1; }
done

say "host bridge wired"
