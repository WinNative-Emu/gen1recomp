# Black/White battle sprites

Select IMPORTERS > Pokemon Black / White and import your own unzipped,
untrimmed 256 MiB .nds dump. The engine writes
`asset_packs/gen5_bw/battle_sprites`. Distribute code only, never ROMs or packs.
Black IRBO was tested; White, other regions and alternate forms are unverified.
Black 2/White 2 are unsupported. Headset timing is unmeasured. An intermittent
desktop JIT-off export crash also occurs on pre-change code.

The pack covers dex 1-649 base forms, front/back, normal/shiny and female
variants. Identical gender graphics share atlases. Exporter 1.1.0 adds independent
part tracks for complete idle loops; reimport older packs to obtain them.
Tested Black had zero native fallbacks across 5,192 entries. Scheduling uses a
soft 6 ms frame budget. Same-source/version reimport is not transactional.

## Renderer contract

Declare `optional_assets` with importer `gen5_bw`, pack `battle_sprites`,
version `>=1.0.0`. Access it through `mod.packs`. IDs include
`normal/025/front`, `shiny/025/back` and `/female` variants.

Atlas metadata records dimensions, columns, integer tick durations,
`tickRate=60`, and zero-based `loopStartFrame`. Play the intro once, then loop
the suffix. Never loop a `cycleCapped` atlas: use its `partsEntry` and
`partsPalette`, or native art. Part metadata holds palettes, pieces,
per-record intro/period/runs/states and canvas bounds. Compose priority 3 to 0,
records last to first, clipped to the current canvas union.

The example exposes API 2 through `mod.find("GEN5_PRIVATE_SPRITES").exports`.
Call `frame({dex,side,shiny,gender,form,battleId,battlerId,mon})`; nil means native
art. Frames return `{image,width,height,groundOffset,frame,entryId}` at original
resolution up to 256x256. `groundOffset=height/2`; consumers choose display scale.
Importing or enabling the provider alone does not change battle rendering.

The clock advances through `input.step`; do not also call `update(dt)`.
Both eyes share timing and cached frames. Session ending releases graphics.
Only base forms are supported; consumers exclude substitutes, ghosts and
personality-dependent forms. Invalid assets fall back per entry.

Run `luajit tests/run_gen5.lua` for ROM-free checks.
Retain [AnimaEngine provenance](../src/import/gen5/PROVENANCE.md) and its
[MIT notice](../src/import/gen5/ANIMAENGINE_LICENSE).
