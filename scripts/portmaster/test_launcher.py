#!/usr/bin/env python3
"""Exercise launcher ordering, paths with spaces, exit status and cleanup."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

SOURCE = Path(__file__).with_name("Gen1Recomp.sh")
with tempfile.TemporaryDirectory(prefix="portmaster launcher ") as tmp:
    root = Path(tmp)
    control = root / "PortMaster"
    runtime = control / "runtimes/love_11.5"
    runtime.mkdir(parents=True)
    port = root / "ports/gen1recomp"
    (port / "lovegame").mkdir(parents=True)
    trace = root / "trace"
    (control / "control.txt").write_text('''CFW_NAME=test
DEVICE_ARCH=aarch64
get_controls() { echo controls >> "$TRACE"; sdl_controllerconfig=testpad; }
pm_platform_helper() { echo helper >> "$TRACE"; }
pm_finish() { echo finish >> "$TRACE"; }
GPTOKEYB=true
''')
    (control / "mod_test.txt").write_text('echo cfw >> "$TRACE"\n')
    binary = runtime / "love.aarch64"
    binary.write_text('''#!/bin/bash
[ "$POKEPORT_PORTMASTER_MANAGED" = 1 ] || exit 90
[ "$SDL_GAMECONTROLLERCONFIG" = testpad ] || exit 91
[ -d "$1" ] || exit 92
echo game >> "$TRACE"
exit 7
''')
    binary.chmod(0o755)
    # Real LOVE_RUN is a shell word list; use a space-free command with quoted
    # execution inside the fake runtime function to test the GAME directory.
    (runtime / "love.txt").write_text('''LOVE_BINARY="$RUNTIME_BINARY"
LOVE_GPTK=love.aarch64
run_love() { "$LOVE_BINARY" "$@"; }
LOVE_RUN=run_love
''')
    launcher = root / "ports/Gen1Recomp.sh"
    shutil.copy2(SOURCE, launcher)
    env = dict(os.environ, XDG_DATA_HOME=str(root), TRACE=str(trace),
               RUNTIME_BINARY=str(binary))
    result = subprocess.run(["bash", str(launcher)], env=env)
    assert result.returncode == 7, result.returncode
    assert trace.read_text().splitlines() == ["cfw", "controls", "helper", "game", "finish"]
    print("PASS launcher: CFW/controls order, spaced game path, managed updates, exit status, cleanup")
