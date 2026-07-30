#!/usr/bin/env bash
# Moves this build's SDL Java glue from org.libsdl.app to org.love2d.sdl.
#
# WinNative hosts this engine in the same APK as ARMSX2, which ships its own
# copy of org.libsdl.app from a different SDL version -- its SDLActivity
# declares `native void nativeSetupJNI()` where SDL2 here declares
# `native int nativeSetupJNI()`. Two classes with one name cannot both survive
# the dex merge, so whichever loses takes its native library down with it:
# liblove.so aborts at startup with
#   JNI DETECTED ERROR ... no static or non-static method
#   "Lorg/libsdl/app/SDLActivity;.nativeSetupJNI()I"
# A separate :process does not help, because processes share the APK classpath.
#
# Renaming ARMSX2's copy instead would disturb PS2 emulation, so the engine
# moves. This runs as a build step rather than as committed edits to the
# vendored trees, so a daily upstream sync never conflicts with it.
#
# Idempotent: re-running on an already-renamed tree is a no-op.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDL_ROOT="$ROOT/mobile/android/love/src/jni/SDL2"
SDL_JAVA="$SDL_ROOT/android-project/app/src/main/java"
LOVE_JAVA="$ROOT/mobile/android/love/src/main/java/org/love2d/android/GameActivity.java"

OLD_DIR="$SDL_JAVA/org/libsdl/app"
NEW_DIR="$SDL_JAVA/org/love2d/sdl"

say() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }

[ -d "$SDL_JAVA" ] || { echo "error: $SDL_JAVA not found" >&2; exit 1; }

# Each step below is separately idempotent, so a partly-renamed tree (an
# interrupted run, or an upstream sync that restored only some files) still
# converges instead of being skipped as already done.
if [ -d "$OLD_DIR" ]; then
  say "moving SDL Java glue to org.love2d.sdl"
  mkdir -p "$(dirname "$NEW_DIR")"
  if [ -d "$NEW_DIR" ]; then
    mv "$OLD_DIR"/*.java "$NEW_DIR"/ && rm -rf "$OLD_DIR"
  else
    git -C "$ROOT" mv "$OLD_DIR" "$NEW_DIR" 2>/dev/null || mv "$OLD_DIR" "$NEW_DIR"
  fi
  rmdir "$SDL_JAVA/org/libsdl" 2>/dev/null || true
fi

# Package declarations, plus the USB permission action -- that string is a
# broadcast name, so leaving it would have both SDL copies listening on the
# same action inside one app.
find "$NEW_DIR" -name '*.java' -print0 2>/dev/null | xargs -0 -r sed -i \
  -e 's/^package org\.libsdl\.app;/package org.love2d.sdl;/' \
  -e 's/org\.libsdl\.app\.USB_PERMISSION/org.love2d.sdl.USB_PERMISSION/g'

# The native side names these classes two different ways: through the macro
# that builds the JNI symbol names, and as literal paths handed to FindClass.
# Both have to move together or the symbols stop matching the Java side.
#
# The prefix is defined in more than one translation unit -- SDL_android.c for
# the core, hid.cpp for the HID manager -- and missing one is invisible until
# that subsystem is first touched at runtime, so rewrite every file that names
# the package rather than a hardcoded list.
mapfile -t natives < <(grep -rl -E '#define SDL_JAVA_PREFIX|"org/libsdl/app' "$SDL_ROOT/src" 2>/dev/null || true)
for f in "${natives[@]}"; do
  sed -i \
    -e 's/\(#define SDL_JAVA_PREFIX  *\)org_libsdl_app$/\1org_love2d_sdl/' \
    -e 's#"org/libsdl/app/#"org/love2d/sdl/#g' \
    "$f"
  say "rewrote $(basename "$f")"
done

# love-android's own activity extends SDLActivity by name.
[ -f "$LOVE_JAVA" ] && sed -i 's/^import org\.libsdl\.app\.SDLActivity;/import org.love2d.sdl.SDLActivity;/' "$LOVE_JAVA"

# Fail loudly rather than shipping a half-renamed tree that only breaks at
# runtime, which is exactly the failure this script exists to prevent.
leftover=$(grep -rl -E 'org[/.]libsdl[/.]app' "$SDL_JAVA" "$SDL_ROOT/src" "$LOVE_JAVA" 2>/dev/null || true)
if [ -n "$leftover" ]; then
  echo "error: org.libsdl.app still referenced in:" >&2
  echo "$leftover" >&2
  exit 1
fi

say "SDL namespace is now org.love2d.sdl"
