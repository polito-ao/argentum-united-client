# Curated sound effects

Hand-authored / hand-edited SFX. **Tracked in git** (small enough that
versioning beats the regen workflow used for `assets/audio/sfx/`).

The server may reference these by `wav_name` (string, in `PLAY_SFX`
packets) instead of by numeric `wav_id`. The client tries each of
`.wav`, `.mp3`, `.flac`, `.ogg` in order until one resolves, so
recordings can ship in whatever format the source asset happens to be
in -- no transcoding step required.

If both `wav_name` and `wav_id` are present in a `PLAY_SFX` payload,
`wav_name` wins (server can phase IDs out gradually). If neither is
set, the client silently skips -- no error log.

## Inventory

| File | Format | Use |
|---|---|---|
| `drop_item.mp3` | MP3 | Inventory drop -- player tossing an item to the ground (server: inventory_handler.rb). |
| `pickup_item.wav` | WAV | Inventory pickup -- player picks an item off the ground. Renamed from `pick_up_item.wav` for snake_case consistency. |
| `death_npc_mammal.wav` | WAV | Generic mammal NPC death cry. Default fallback for rata, murcielago, lobo, oso, etc. when a creature lacks a specific death SFX. (Filename typo `mamal` -> `mammal` fixed on import.) |
| `entering_gate.wav` | WAV | Gate dungeon entry sting. **Dormant** -- waits for Gates feature (M5) to ship. |
| `gates_dragon_boss_appears.wav` | WAV | Dragon boss spawn roar inside a Gate. Dormant. (Filename typo `apears` -> `appears` fixed on import.) |
| `gates_dragon_boss_dies.flac` | FLAC | Dragon boss death cry. Dormant. |
| `gates_monster_appears.wav` | WAV | Generic Gate monster spawn cue. Dormant. (Filename typo `apears` -> `appears` fixed on import.) |
| `npc_large_footstep.wav` | WAV | Heavy footstep for large NPCs (giants, ogres, dragons, golems). **Dormant** until per-creature footstep wiring lands (paired with the doppler / Y-pitch shift PR). |
| `npc_monster_roar.mp3` | MP3 | Generic monster ambient roar. Dormant -- waits for AmbientAudioDirector. |

## Wiring status

Files marked **Dormant** sit in this folder ready for their feature.
The server is the source of truth for which `wav_name` fires when --
the client just resolves whatever name the server sends.

Currently the only live emit hooks (in the paired server PR) are
`drop_item` and `pickup_item` from inventory_handler. The remaining
files ride along so they're available the moment their feature wires
up, with no client-side change required.
