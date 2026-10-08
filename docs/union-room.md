# Cross-generation Union Room

Gen 1, 2 and 3 players meet in one Union Room over the relay, battle and
trade. Cross-generation battles and trades are a feature of this app, not of
the original games.

## Setting

Launcher Options -> Union Room (default ON; a missing preference counts as
ON, an explicit OFF is kept). OFF restores the original Gen 1 and Gen 2
Pokemon Centers: no stairs, no 2F additions, the Gen 1 cable club desk back on
1F. Gen 3 Union Rooms always work. Map changes are applied to a fresh copy of
the map data at load, so toggling never accumulates edits.

## Saves

A save written anywhere the original game has no such cell (Gen 1 2F, any
added Union Room, Gen 2 2F added columns, the Ruby/Sapphire added door and
room, the FireRed/LeafGreen/Emerald 40-player room) records the player in
front of the origin Pokemon Center's 1F nurse desk, facing up. Loading such a
save from an older build moves the player there too, with the setting ON or
OFF. Cart-format exports never contain an added map or cell.

## Imports

- Entering the room, battling and trading need only the game being played.
- Another player's real sprite needs their game family imported (Gen 1: Red,
  Blue or Yellow; Gen 2 male: Gold, Silver or Crystal; Gen 2 female: Crystal;
  FireRed/LeafGreen classes: FireRed or LeafGreen; Emerald classes: Emerald;
  Ruby/Sapphire player: Ruby, Sapphire or Emerald). Otherwise they appear as an
  ordinary trainer from your own game, chosen the same way every time, with
  their generation badge; talking to them names the import that shows their
  real look.

## Battles

- Same generation (Gen 1 vs Gen 1, Gen 2 vs Gen 2, Gen 3 vs Gen 3): the
  existing link battle for that generation.
- Cross-generation: ruleset `g3u`. Gen 3 battle mechanics, run on every
  client from one move and species-type table taken from the lower-generation
  player's own game (Gen 1 table against any Gen 2/3 player, Gen 2 table
  against a Gen 3 player) and sent once at battle start (numbers only).
  Species and moves are limited to that table (151/165 with a Gen 1 player,
  251/251 with Gen 2). With a Gen 1/2 player present: abilities and held items
  off, natures neutral. Both clients run the same lockstep core
  (`src/battle/g3u/`) and compare a state hash every turn.
- Preparation (temporary, never written to the save): rules, team problems,
  substitutes from your party and PC, rentals, move fixes, team size,
  confirm. Any change after confirming clears both confirmations. The
  opponent's team is never shown.

Source of truth: `src/online/xgen/Policy.lua` (`Policy.BATTLE`, `Policy.TRADE`
field tables, constants).

## Identity

- Species: national dex number. Gen 1/2 caches give it as `dex` on each
  `pokemon.lua` row; Gen 3 via `national.lua` (`toSpecies[national]` is the
  internal species id).
- Moves: canonical move number. Gen 1/2 rows carry `index`; Gen 3 ids are
  already canonical (1..354). Gen 1 = 1..165, Gen 2 = 1..251.
- Names are normalized (upper case, ♀/♂ -> F/M, é -> E, only A-Z0-9 kept)
  and `Identity.agree(a, b)` asserts that every shared species and move id
  has the same normalized name in both caches (a truncated name that is a
  subsequence of the other also counts as the same). Checked over all 55
  pairs of the 11 local caches: zero mismatches.
- Types: canonical names NORMAL..DARK plus MYSTERY. Gen 1/2 `PSYCHIC_TYPE`
  -> PSYCHIC, `CURSE_TYPE` -> MYSTERY. Gen 3 type ids map through the pret
  `TYPE_*` constants; the cache's truncated display names (ELECTR, PSYCHC) are
  checked as subsequences.
- Items: canonical key = normalized display name. Gen 1 has no held items.
- Category (for move suggestions only): status if power 0, else physical for
  types below MYSTERY, special above (Gen 3 `IS_TYPE_PHYSICAL`).

## Learnability (owner's own game data)

`Datasets.learnSources(data, national, level)` unions over the species and
every pre-evolution: level-up moves at or below the level (level 1 moves
included), TM/HM, tutor (Crystal `tutorMoves`; Emerald/FRLG tutor bitfield;
FRLG Cape Brink for the Kanto starters), egg moves (Gen 2/3). Both Gen 2
cache layouts (`levelMoves`/`eggMoves`/`tmhm`/`tutorMoves` and
`learnset`/`level1Moves`) are read.

## Battle projection (g3u, temporary, never written)

| field | rule |
|---|---|
| species | national dex kept; must be <= ruleset dexMax (`species_not_in_ruleset` otherwise) |
| level | kept |
| ivs | Gen 3 kept. Gen 1/2: IV = 2*DV+1 for Atk/Def/Spe; HP IV = 2*HPDV+1 where HPDV is derived from the four DV low bits; SpA = SpD = 2*Special+1 |
| evs | Gen 3 kept. Gen 1/2: EV = min(255, floor(sqrt(StatExp))); Special Stat Exp feeds both SpA and SpD; 510 total cap applied in HP, Atk, Def, Spe, SpA, SpD order |
| base stats | owner's own game; Gen 1 base Special used for SpA and SpD |
| stats | Gen 3 formula (`CalculateMonStats`, Shedinja HP 1) from the above and nature |
| nature | neutral (0) when a Gen 1/2 player is present; Gen 3 nature only when not |
| ability, item | 0 when a Gen 1/2 player is present |
| types | not in the record: typing comes from the match table (owner decision 2) |
| moves | each must be id <= moveMax, not in the match table's unsupported list, and learnable per the owner's data. Codes: `move_not_in_ruleset`, `move_unsupported`, `move_not_legal`. Player picks a legal replacement or empties the slot; order of the remaining moves kept; at least one move (`no_legal_moves`) |
| pp | owner's base PP + PP Ups * floor(base/5), full |
| gender | Gen 2 DV rule, Gen 3 personality rule, none for Gen 1 |
| shiny | Gen 1/2 DV rule, Gen 3 personality rule |
| hp / status | full / clear |

Record shape: `{national, species, nickname, level, hp, maxHp, atk, def,
spAtk, spDef, speed, moves={{id,pp,ppUps}}, ability, item, ivs, evs, nature,
gender, shiny, unownLetter, sourceGen, rental}`. Output never aliases input.

Team size: default min(roster sizes) (or a smaller size both agree); a larger
roster gets `choose_sit_out` with the number to bench and is never trimmed
automatically. Replacement candidates (party then PC order): shares a type,
then same primary type, then level closeness, then source order; only
species in the ruleset with at least one legal move. Move suggestions: same
type, then same category and power band (0, 1-40, 41-70, 71-100, 101+), then
name.

## Permanent trade conversion (TradeConvert, policy v1)

Deterministic, no rerolls. Move legality policy: a kept move must exist in
the destination and be learnable by the species in the destination game OR
in the source game (so a legally learned Gen 2 egg move or a FRLG tutor move
survives). Staged replacements must be learnable in the destination game.

| field | rule |
|---|---|
| species | national kept; `species_missing` if the destination lacks it |
| level | kept |
| exp | kept, clamped into the destination curve's range for that level |
| Gen 1/2 -> Gen 3 IVs/EVs | as in the battle projection |
| Gen 3 -> Gen 1/2 DVs | target floor(IV/2) for Atk/Def/Spe and Special from SpA; the nearest DV set (L1 distance, first in attack-major scan order on ties) that keeps shininess, Gen 2 gender and the Unown letter; HP DV derived; HP IV lost. Unown !/? refused (`traits_unrepresentable`) |
| Gen 3 -> Gen 1/2 Stat Exp | min(65535, EV^2); Special from SpA EV; SpD EV lost when it differs |
| personality (Gen 1/2 -> Gen 3) | seed = FNV-1a of canonical {national, OT ID, DVs, exp, level}; high half starts at seed % 65536 and walks upward; for each high half the low halves are scanned for a personality with pid % 25 == 0 (Hardy), even (ability slot 0), the Gen 2 DV gender under the destination gender ratio, the DV Unown letter, and shiny iff the DVs are shiny with Secret ID 0 |
| nature | from personality |
| ability | Gen 1/2 -> 3: slot 0; Gen 3 -> 3: kept; Gen 3 -> 1/2: lost |
| moves / pp | see legality above; PP at destination max with the same PP Ups |
| nickname | kept when the destination charset encodes it within 10 characters, else refused; a nickname equal to the species name becomes the destination default |
| OT | name (7) and ID (0..65535) kept when encodable, else refused |
| item | Gen 2/3 by canonical name, else refused until removed. Mail refused. Gen 2 -> Gen 1 stored as the catch-rate byte; Gen 1 -> Gen 2 from the catch rate (Time Capsule); Gen 3 item -> Gen 1 refused; Gen 1 catch rate -> Gen 3 lost |
| friendship | kept Gen 2 <-> 3; Gen 1 -> Gen 2 is 70; Gen 1 -> Gen 3 is the species base; lost into Gen 1 |
| pokerus | kept Gen 2 <-> 3; lost into Gen 1 |
| origin | Gen 3 target from Gen 1/2: met location 0xFE (in a trade), met level = level, Poke Ball, destination game id, English, OT gender from Crystal caught gender else 0, no markings/ribbons/contest; Mew gets the modern fateful flag so it obeys. Gen 2 target from another gen: caught data 0 (Time Capsule). Same-gen: kept |
| ribbons / contest / markings / met data | kept Gen 3 -> 3, lost otherwise |
| eggs | refused |
| hp / status | full / clear |
| mod `extra` | kept same-gen, lost cross-gen |
| evolution | not run here |

Every top-level field of the source record is classified as carried,
changed, derived or lost (`report.accounting`); every changed field has a
`kind='change'` row and every lost field a `kind='loss'` row in `changes`.
Unknown fields default to lost.

`TradeConvert.canonical(rec)` is a sorted-key JSON-like serialization
(integers as `%.0f`); `TradeConvert.digest(rec)` is two FNV-1a 32 words over it.

## Rentals v1

Per ruleset one rental per ordinary type (g3u-gen1: 15, g3u-gen2/3: 17),
level 50, IVs 20, EVs 0, personality 150 (Hardy, not shiny). Species and
moves were chosen so they are learnable at level 50 in every local cache of
that ruleset's generation and above (all 11 for g3u-gen1). `Rentals.build`
validates each against the providing game's data and excludes and reports
any that fail.

## Trades: transaction

- Each offer carries the sender's source record (its game's own link
  encoding), the destination game and the converted preview. The receiver
  re-converts the source record itself and refuses any mismatch.
- Agreed digest = digest over both offer revisions, both source records,
  both converted records and the policy version. It is the readiness digest
  and the `trade_confirm` digest; the relay refuses any confirm with another
  digest, so changing either offer invalidates both approvals.
- Before confirming, each client rechecks its outgoing record at its slot and
  writes a journal entry (`<save>_xtrade.lua`, atomic) holding the outgoing
  and incoming records. On the relay's `trade_commit` it applies the swap in
  place, runs the destination game's own trade evolution, saves atomically
  and drops the journal. `trade_abort` drops the journal; both originals stay.
- Recovery: at boot, committed entries apply without the network; confirming
  entries ask `GET /trade/outcome` and apply, drop or wait. Applying is keyed
  by room, round and digest and guarded by an applied marker (Gen 1/2) and the
  record identity check (all gens), so a commit applies exactly once. No copy
  of a traded-away Pokemon is kept for the sender.

## What the relay verifies

Room membership, seat, revision freshness, capability shapes, team size
bounds, message size caps, that only the lower-generation seat sends the
battle table, digest equality for trades, the commit barrier and the outcome
ledger. It holds no game data: a matching digest proves both players agreed
on the same exchange, not that a Pokemon is legally owned or legal. Battle
tables and parties are bounds-checked by the receiving client.

## Deployment order

Relay first (additive, relay protocol stays 3; older clients keep their own
rooms). Then clients. A new Gen 1/2 client on an old relay is refused at join
and shows an update message; a new Gen 3 client on an old relay detects the
missing generation field and shows the same message.
