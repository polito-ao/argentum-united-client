# Argentum United — Godot Client

## What this is

2D MMORPG client for Argentum United, built in Godot 4.6 with GDScript. Connects to the Ruby server via TCP + MessagePack.

**GitHub**: polito-ao/argentum-united-client
**Server repo**: polito-ao/argentum-united-server
**Project board**: argentum-united

## Last verified state (2026-04-27)

- **Tests**: 257 GUT tests, all passing. Run with:
  ```
  godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit/ -gexit
  ```
- **Last commit**: `fd465e8` (ground items: render Cucsi icon sprites instead of yellow rect)
- **M2**: feature-complete on visual axis. Layered character pipeline (body + head + equipment + effect aura) live for player / other players / NPCs; race-distinct bodies; equipment overlay updates live on equip; meditation aura with picker; FIFA-card character select; cosmetic login + char-select scenes; ground items render Cucsi icon sprites. Remaining: spells hotbar, sound/music, more content.
- **Editor cache nuke if needed**: if you see "class not registered" / unresolved `%UniqueName` errors on first open, run `rm .godot/global_script_class_cache.cfg .godot/uid_cache.bin && godot --headless --path . --import` then reopen.

## Tech stack

- **Engine**: Godot 4.6 (GL Compatibility renderer for broad GPU support)
- **Language**: GDScript
- **Tests**: GUT 9.4 (vendored at `addons/gut/`); see `tests/README.md`
- **Protocol**: TCP + length-prefixed framing: `[uint16 length][uint16 packet_id][MessagePack payload]`
- **Assets**: Cucsi sprites upscaled 2× via ESRGAN (`assets/upscaled_2x/`, ~4700 files). Not committed; grab from Drive or re-run server's pipeline.

## Architecture

```
scenes/
  login/          login screen (dev auth via DEV_LOGIN packet)
  character/      character select + create (FIFA-style dice)
  world/          world.gd + world.tscn — main game scene
                  (~1300 lines; controllers extracted, see below)

scripts/
  network/        connection, framing, packet_ids
  ui/             extracted controllers (RefCounted; testable without scene tree)
                    hud_controller.gd          read-update HUD widgets
                    inventory_controller.gd    grid + drop dialog + use/equip
                    chat_controller.gd         log + input + send
                    bank_controller.gd         two-pane overlay + amount prompt
                    dev_controller.gd          F2 search-and-spawn (items, creatures, chests)
                    head_picker_controller.gd  arrow-scroll head picker on character creation
                    effect_picker_controller.gd  meditation-aura decal selector in settings
                    character_create_toggle.gd   gates the creation form behind a button
                    character_card.gd          FIFA-style card (6 attrs + class/race playstyle hint)
                    race_base_attrs.gd         static race → base attr table + OVR formula
                    class_race_hints.gd        35-cell class+race playstyle hint matrix
  game/           map_texture_cache (autoload), parsed-JSON helpers
                    sprite_catalog.gd (autoload)        loads bodies/heads/helmets/weapons/shields/effects/items YAML
                    sprite_frames_builder.gd            id → cached SpriteFrames resource
                    layered_character.gd                Node2D with 5 AnimatedSprite2D layers + EffectSprite
                    meditation_aura.gd                  effect aura node (real Cucsi sprite + placeholder fallback)
                    character_direction.gd              delta → cardinal direction

tests/
  unit/           GUT unit tests, one per controller + smoke
```

### Controller pattern

Each interactive subsystem lives in `scripts/ui/<controller>.gd` as a `RefCounted` class. World.gd constructs them in `setup()` (or `_ready()` for HUDController) with a Dictionary of widget refs. This keeps controllers **testable without a scene tree** — pass real Controls + stub Connection/HUD/Inventory.

**Controller lifecycle rule** (memory: `feedback_godot_controller_lifecycle`):
- Build in `_ready()` if the controller only needs `@onready` widgets (HUDController)
- Build in `setup()` if it needs `connection` (sends packets) — Inventory / Chat / Bank / Dev. The connection only gets assigned in `setup()`; building earlier captures a null reference and silently no-ops every send.

### `%UniqueName` everywhere

`world.gd` references HUD widgets via `%NodeName` (Godot 4 unique-name syntax) instead of `$Path/To/Node`. Survives parent renames + scene-tree reshuffles without code changes. ~40 nodes are flagged `unique_name_in_owner = true` in `world.tscn`.

## M2 progress

### Done
- [x] Login (dev auth via DEV_LOGIN packet)
- [x] Character list + select + create (FIFA-style dice roller)
- [x] In-world: 2 maps + tile transitions (server-driven via `mapaN.json`)
- [x] Smooth player movement: tween sprite + camera-locked over MOVE_INTERVAL (AO-style)
- [x] HUD: HP / MP / XP bars, level / name / city header, STR / CELE / Gold, equipment row, FPS / position, messages feed
- [x] Chat: send + broadcast log + bubbles over player sprites (in world.gd) + log in panel (ChatController)
- [x] Inventory: 30-slot grid, click-to-focus, U/E/D actions, drop dialog with amount prompt, INVENTORY_RESPONSE / INVENTORY_UPDATE handlers
- [x] Bank (V key): two-pane overlay (bank left + inventory mirror right), double-click amount prompt, right-click whole stack, BANK_OPEN/CONTENTS/DEPOSIT/WITHDRAW packets
- [x] Dev tools (F2): search-and-spawn for items + creatures (server-gated on DEV_AUTH)
- [x] Settings overlay (S button): rebindable keys, persisted via SETTINGS_SAVE
- [x] Combat: melee (Ctrl), spell cast (LANZAR + tile click), HP/MP potions (R/B), meditate (M), hide (O)
- [x] NPC rendering: spawn / move (tweened over 380ms server cadence) / death broadcasts
- [x] Death + ghost flow: CHAR_DEATH visual, respawn via SPACE, ghost passes through players
- [x] Smooth-walk for own player + NPCs (tween over MOVE_INTERVAL / 380ms). Other players still snap on PLAYER_MOVE — see Pending below.
- [x] Mini-map (`%Minimap` control + `_MinimapDrawer` redrawn periodically)

### Done since 2026-04-25 (this session)
- [x] **Layered character pipeline** — `LayeredCharacter` with body / head / helmet / weapon / shield AnimatedSprite2D layers + EffectSprite. Player, other players, and NPCs all use it. Equipment changes re-apply layers live.
- [x] **Walk animations** — 4-direction walk cycles driven by movement delta. Player at 5 tiles/sec (Cucsi-exact), NPCs at 380ms (Cucsi TimerAI cadence).
- [x] **Race-distinct visuals** — Cucsi-derived body/head defaults per race (humano body 21/head 1, gnomo 222/401, etc.).
- [x] **Head picker** — arrow-scroll picker on character creation with live body+head preview.
- [x] **Equipment overlay** — equip a weapon/helmet/shield/armor and see it on the character live; broadcast to other players.
- [x] **Meditation aura** — real Cucsi `FxMeditar.CHICO` sprite (with MEDIANO/GRANDE mined for level-gated upgrades), pulsing on top of the character. Decal picker in settings overlay reads `available_effects.meditation` from server.
- [x] **Chests** — render with Cucsi icon, F-key interaction, F2 dev-spawn from `cofre_pequeno` / `cofre_grande` templates.
- [x] **FIFA character cards** — name + class + race + portrait + 6 attrs (base + dice) + OVR + class/race playstyle hint. Creation gated behind "Crear nuevo personaje" button.
- [x] **Cosmetic login + char-select** — painted backgrounds, Cinzel-rendered "Argentum United" wordmark, time-conditional day/night char-select bg (night = 19:00 → 05:30).
- [x] **Ground item icons** — Cucsi item sprites driven by `icon_grh_id` from server, with yellow ColorRect fallback for missing refs.
- [x] **Other-players smoothing** — fell out for free from layered character work; PLAYER_MOVE no longer snaps.

### Pending / not started
- [ ] Spells hotbar — spell list in tab works, no quick-cast bar yet
- [ ] Sound / music (whole pass deferred)
- [ ] Clan / citizenship UI (M4)
- [ ] Settings panel: keybind UI doesn't show new actions automatically (e.g. `bank: KEY_V` is in `DEFAULT_BINDINGS` but the rebinder UI may need a refresh — verify when touched)
- [ ] **Shrine of Fortune mechanic** — dice rolls deferred to level 2 unlock; data path is ready (`Character.dice_roll` JSONB, `to_summary` ships it), only the mechanic + UI are missing.
- [ ] **Gender axis on Character** — schema column + dice roller + creation UI; Cucsi `_M_` female head arrays are already emitted in `race_heads.yml`, just unused.
- [ ] **Effect catalog expansion** — only meditation auras live today (CHICO/MEDIANO/GRANDE). Mine remaining Cucsi auras (blessings, VIP indicators, status effect visuals).
- [ ] **More maps** — only 3 maps loaded; Cucsi has 624 maps and the parser is in place.

## Tech debt (before M3)

- **CONFIG_REQUEST (0x0000)**: client should request packet IDs, classes, races from server on connect. Only hardcode 0x0000 itself. Server is single source of truth.
- **TLS**: wrap TCP in TLS before deploying to a real server. Godot: StreamPeerTLS. Server: OpenSSL via async. Localhost dev doesn't need it.

## Map rendering perf

Done this milestone: single `_MapDrawer` Node2D + parallel PNG loads + autoload `MapTextureCache` + background neighbor preload via `tile_exits`. Cold load ~500ms, steady-state map transitions ~140-180ms (down from 814ms).

Open follow-ups (not urgent):
- **LRU eviction on `MapTextureCache`** — current cache grows monotonically. Fine for 40 usable maps with high atlas overlap, may matter once the world expands.
- **Profile login → CHARS_LIST → SELECT chain** — server round-trip dominated; needs server-side timing too.
- **`Character#to_summary` must keep shipping `map_id`** — character-select map preload depends on it.

## Conventions

- **Code in English, game content in Spanish** (item names, spell names, city names, action labels in DEFAULT_BINDINGS)
- **Slugs are the human-readable layer** for any config that crosses the wire by name (item slugs, creature slugs). Numeric IDs are the wire identity.
- **F2** opens the dev menu (DEV_AUTH-gated server-side; overlay just stays empty in production)
- **V** opens the bank
- **Esc cascade**: amount prompts close first, then their parent overlay
