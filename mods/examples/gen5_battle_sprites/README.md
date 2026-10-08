# Gen 5 battle sprite provider

Import your own Black/White dump through the launcher. This code-only example
reads the optional `gen5_bw/battle_sprites` pack. A compatible renderer displays
the sprites; missing or invalid data uses native art. Never distribute artwork,
packs or ROMs.

API 2 returns original pixels, variable dimensions up to 256x256, and
`groundOffset=height/2`. Exporter 1.1 packs need no reimport; older packs need
reimport for complete loops. See the
[renderer contract](../../../docs/gen5-battle-sprite-importer.md).

Checks:

```sh
python3 tools/modkit.py validate mods/examples/gen5_battle_sprites --base fixture
python3 tools/modkit.py lint mods/examples/gen5_battle_sprites
luajit tests/run_gen5.lua
```

Retain the [AnimaEngine provenance](../../../src/import/gen5/PROVENANCE.md) and
[MIT notice](../../../src/import/gen5/ANIMAENGINE_LICENSE).
