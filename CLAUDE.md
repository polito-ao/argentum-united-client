# Argentum United — Godot Client

## What this is

2D MMORPG client for Argentum United, built in Godot 4.x with GDScript. Connects to the Ruby server via TCP + MessagePack.

**GitHub**: polito-ao/argentum-united-client
**Server repo**: polito-ao/argentum-united-server
**Project board**: argentum-united

## Tech stack

- **Engine**: Godot 4.x (2D)
- **Language**: GDScript
- **Protocol**: TCP with length-prefixed framing: `[uint16 length][uint16 packet_id][MessagePack payload]`
- **Assets**: placeholder sprites for M2, AI-upscaled sprites later

## Architecture

```
scenes/
  login/          — login screen (dev auth for now)
  character/      — character select + create
  world/          — main game scene (map, players, NPCs, UI)
  ui/             — reusable UI components

scripts/
  network/        — TCP connection, framing, packet router
  game/           — game state, player, NPC, inventory
  ui/             — HUD, chat, inventory overlay

assets/
  sprites/        — character, NPC, item sprites
  tiles/          — map tile graphics
  ui/             — UI textures, fonts
```

## Protocol

Same as server — `[uint16 length][uint16 packet_id][MessagePack payload]`.
MessagePack decoded in GDScript (lightweight addon or custom decoder).

## M2 Scope

- Login screen (text input + button, dev auth)
- Character select (list, create with dice, select)
- In-world: 2 test maps with tile transition
- Player movement (arrow keys), facing indicator
- NPC rendering, attack (Ctrl when facing)
- HP/MP bars
- Chat (text input + display)
- Inventory overlay (I key)
- Settings overlay with key mapping (stored in server DB via JSONB)
- Sprite PoC: one character, one armor, 4 directions

## Tech debt (before M3)

- **CONFIG_REQUEST (0x0000)**: client should request packet IDs, classes, races from server on connect. Only hardcode 0x0000 itself. Server is single source of truth.
- **TLS**: wrap TCP in TLS before deploying to a real server. Godot: StreamPeerTLS. Server: OpenSSL via async. Localhost dev doesn't need it.

## Performance follow-ups (not urgent)

The map-render perf refactor landed this session: single `_MapDrawer` Node2D + parallel PNG loads + autoload texture/JSON cache + background neighbor preload via `tile_exits`. Cold load ~500ms, steady-state map transitions ~140-180ms (down from 814ms). Open follow-ups:

- **LRU eviction on `MapTextureCache`** — current cache grows monotonically. Fine for 40 usable maps with high atlas overlap, may matter once the world expands. Evict by atlas-key keyed on map-distance from current.
- **Profile the login → CHARS_LIST → SELECT chain** — server round-trips, not client render. Different problem space; needs server-side timing too.
- **Character-select preload depends on server `to_summary` shipping `map_id`** — already wired. If a future server refactor touches `Character#to_summary`, keep the field.

## What to skip in M2

- Auth0 integration (M3)
- Spells hotbar
- Mini-map
- Clan/citizenship UI
- Stats panel detail
- Sound/music
