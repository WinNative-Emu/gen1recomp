# Emerald: Matt missing in Aqua Hideout (#2748)

## Reproduced cause

[Issue #2748](https://github.com/bryanthaboi/gen1recomp/issues/2748) reports
Matt missing and uninteractable in Aqua Hideout B2F on Android v3.60. The
maintainer's comment asks whether Tate and Liza were defeated. No reporter
save is attached, so this is a reproduced cause, not confirmation of the
reporter's exact flag state.

The canonical Emerald scripts have an ordering dependency:

- `MossdeepCity_Gym_EventScript_TateAndLizaDefeated` sets both
  `FLAG_BADGE07_GET` (0x86D) and `FLAG_HIDE_AQUA_HIDEOUT_GRUNTS` (0x39C).
- Aqua Hideout B2F's Matt template (local ID 1, graphics 117, tile 23,19)
  uses that same hide flag. The other hideout grunts share it.
- Matt's trainer battle (trainer 30, continuation type 2) runs
  `AquaHideout_B2F_EventScript_SubmarineEscape` on victory. This removes the
  submarine (local ID 4) and sets
  `FLAG_TEAM_AQUA_ESCAPED_IN_SUBMARINE` (0x70).
- The gym script does not set the escape flag. Completing the gym first
  therefore hides Matt while his escape event is still pending. On the next
  hideout visit, Matt is absent from both `Objects.forDraw()` and
  `Objects.at()`, so field interaction cannot start his battle.

A fresh hideout template with the flag clear is drawable and interactable;
this reproducer did not require broken graphics extraction or an Android
renderer defect. It reproduces a sequence break regardless of how the
player obtained early access to Mossdeep. It does not establish how the
reporter reached that state or attribute it to either previously used mod.

## Recovery boundary

`src/core/game3/profiles/emerald_rules.lua` implements `repairSaveState`
through the existing edition-specific lifecycle:

- `Schema.fromSaveTable` repairs decoded Lua sessions.
- `Flags.loadInto` repairs script-side saved flag stores.
- `Flags.onMapLoad` repairs map-entry/continue stores before objects spawn.

Only when the Mind Badge is earned, the shared hideout hide flag is
synchronized with the submarine-escape flag. If escape is pending, NPCs
remain available; once escape is complete, normal late-story hiding resumes
on map entry/load. Normal story ordering has already completed escape when
the badge is earned, so its hide behavior is unchanged.

The recovery does not award a badge, mark Matt defeated, set the escape
flag, or rewrite imported ROM scripts. A player still needs to fight Matt
and finish his continuation. Without the Mind Badge, explicit hide flags
are left alone. Ruby, Sapphire, FireRed and LeafGreen do not use this rule.

This is not a general recovery for interrupted win continuations, arbitrary
object-removal snapshots, or unrelated mod-written flags.

## Regression

`tests/emerald_matt_2748_test.lua` runs a ROM-free canonical fixture by
default and is registered in `tests/quick.list`. With
`POKEPORT_EMERALD_CACHE` set, it validates the actual imported template and
gym flag writes, then executes the full imported Matt/escape scripts:

```sh
luajit tests/emerald_matt_2748_test.lua
POKEPORT_EMERALD_CACHE=/path/to/emerald luajit tests/emerald_matt_2748_test.lua
```

Coverage includes fresh and early-gym visits, legacy Lua/script-side saves,
object snapshots, A-button interaction through `Field.interact`, win/loss
callbacks, submarine local-ID resolution, all four badge/escape ordering
states, repeated entry, unrelated flags/vars, alternate numeric key
encodings, and other-edition routing.

Messages and battle/movement completion are headless adapters. Tests prove
VM continuation and lifecycle behavior, not battle simulation, actual
sprite pixels, or execution on an Android device. No benchmarks are used.

Canonical sources:

- [B2F template](https://github.com/pret/pokeemerald/blob/master/data/maps/AquaHideout_B2F/map.json)
- [B2F scripts](https://github.com/pret/pokeemerald/blob/master/data/maps/AquaHideout_B2F/scripts.inc)
- [Mossdeep Gym scripts](https://github.com/pret/pokeemerald/blob/master/data/maps/MossdeepCity_Gym/scripts.inc)
