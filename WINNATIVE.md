# Syncing this fork with upstream

This fork exists to be driven by WinNative. Everything here is arranged so the
daily upstream sync keeps working, and so that when it cannot, it says so
loudly instead of shipping an engine whose menu is quietly broken.

## The rule

**WinNative drives.** When a sync forces a choice, the resolution is whichever
one keeps the host's menus, settings, controls and saves working. Upstream
gameplay changes are always welcome; upstream changes that would take the host
out of the loop are not.

## Why merges do not usually conflict

This fork commits **only files upstream does not have**:

```
src/core/WinNativeBridge.lua              the host control channel
tests/winnative_bridge_test.lua           its protocol tests
scripts/winnative_sdl_namespace.sh        \
scripts/winnative_boot_args.sh             > the build-time patches
scripts/winnative_bridge.sh               /
scripts/winnative_contract.sh             the guard described below
.github/workflows/winnative-engine.yml    the build
WINNATIVE.md                              this file
```

Every change to a file upstream owns -- `main.lua`, `src/ui/OptionsMenu.lua`,
`src/core/TouchControls.lua`, the SDL Java glue -- is applied **at build time**
by the patch scripts and never committed. That is the whole reason a 25-commit
upstream merge lands clean: upstream can rewrite those files freely and there
is nothing of ours in them to collide with.

So `git status` showing those files dirty after a build is correct and
expected. Do not commit them.

## Resolving a conflict

A conflict can only really happen if upstream adds a file at one of the paths
above. Then:

- **Conflict in a file from that list** → keep ours. Taking upstream's version
  removes the bridge, the patches or the build, and the host menu stops
  working. CI does this automatically.
- **Conflict anywhere else** → do not guess. We have no committed change in
  those files, so the conflict is upstream against upstream, and someone who
  knows that code should resolve it. CI leaves the branch untouched and warns.

## The failure that is not a conflict

The dangerous case is not a merge conflict at all. The bridge *calls* about
two dozen engine functions and reads a dozen module tables, none of which are
patched -- and every call is wrapped in `pcall`, deliberately, because this
code runs on every frame and a fault in it must never take the game down.

That safety is what makes an upstream rename silent. Rename
`Tilt.ANGLE_LABELS` and the TILT dropdown quietly becomes a pair of arrows.
Rename `Game:restoreSave` and Load quietly starts a new game instead of
loading. The engine builds, the menu opens, nothing complains. Load shipped
broken exactly once this way.

`scripts/winnative_contract.sh` is the guard. It asserts, statically, that
every symbol the bridge depends on is still there, and names what breaks when
one is not:

```bash
./scripts/winnative_contract.sh
```

CI runs it after the patches and **before** the build, so an engine that has
lost the contract is never published.

## After an upstream sync, by hand

```bash
git fetch upstream && git merge upstream/dev
./scripts/winnative_sdl_namespace.sh
./scripts/winnative_boot_args.sh
./scripts/winnative_bridge.sh
./scripts/winnative_contract.sh          # must pass before publishing
luajit tests/winnative_bridge_test.lua   # the host protocol itself
```

The patch scripts are idempotent, so re-running them on an already-patched tree
is a no-op. Each one fails loudly if upstream moved what it anchors on; the
message names the file and the anchor.

## When the contract does break

Fix the bridge or the patch script to match the new upstream layout -- do not
weaken the check. If upstream drops a feature outright (a settings row, a
render mode), remove it from the contract in the same commit that removes it
from the bridge, so the check always describes what the host actually needs.
