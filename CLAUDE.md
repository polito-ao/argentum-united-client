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

## What to skip in M2

- Auth0 integration (M3)
- Spells hotbar
- Mini-map
- Clan/citizenship UI
- Stats panel detail
- Sound/music
