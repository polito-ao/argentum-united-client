extends Node2D

# Base tile size in the Cucsi .map files; the real render uses `_tile_size`
# below, which is driven by the per-map JSON (64 for the 2x-upscaled pipeline,
# falls back to this constant if the JSON is missing the field).
const FALLBACK_TILE_SIZE := 32

# Map rendering — mirrors the dev ulla_preview scene. The JSON produced by
# scripts/parse_map_binary.py + scripts/apply_floor_catalog.py drives everything:
#   tile_size, graficos_root, floors_root, per-grh lookup entries (atlas region
#   for L2-4 or {floor:true, file} for individualised L1 floor tiles).
# Map layer rendering split:
#   GROUND_LAYERS (1, 2, 3) → drawn under `_MapDrawer` on $Ground (z=0).
#   OVERHEAD_LAYER (4)      → drawn under a separate `_MapDrawer` on $Overhead
#     (z=10), which is ABOVE the player + NPCs (z=5). Layer 4 is Cucsi's
#     "above-player" layer (trees, roof corners, hanging signs); rendering it
#     overhead gives AO-style occlusion — the player walks behind trees.
# DRAW_LAYERS preserved for any caller still asking for "all map layers".
const GROUND_LAYERS := [1, 2, 3]
const OVERHEAD_LAYER := 4
const DRAW_LAYERS := [1, 2, 3, 4]
const BLACK_KEY_THRESHOLD_255 := 16
var _tile_size: int = FALLBACK_TILE_SIZE
var _graficos_root: String = ""
var _floors_root: String = ""
# Texture cache lives on the MapTextureCache autoload — survives across
# world scene lifetimes (salir → entrar no longer wipes loaded atlases).
var _black_key_max: float = float(BLACK_KEY_THRESHOLD_255) / 255.0
# Perf counters — reset per _render_ground call, printed on completion.
var _perf_load_image_ms: int = 0
var _perf_color_key_ms: int = 0
var _perf_load_image_calls: int = 0
var _perf_color_key_calls: int = 0

# Camera follows the player but offsets so the player sits in the visual
# CENTER of the game-area rectangle (viewport minus HUD). Right panel is
# 260px wide and top chat is ~120px tall, both fixed pixels regardless of
# viewport size. Game-area center vs screen-center differs by exactly half
# the HUD widths in each axis: (260/2 right, 120/2 down). Camera shifts
# the OPPOSITE direction so the player visually moves up-and-left into the
# game-area center. Math is independent of viewport (1024, 1280, 1600...).
const HUD_RIGHT_WIDTH := 260
const HUD_TOP_HEIGHT := 184
const CAMERA_WORLD_OFFSET := Vector2(HUD_RIGHT_WIDTH / 2.0, -HUD_TOP_HEIGHT / 2.0)

var connection: ServerConnection
var my_pos: Vector2i = Vector2i(50, 50)
var my_heading: String = "south"
var map_id: int = 1
var map_size: Vector2i = Vector2i(100, 100)
var my_level: int = 1
# Server's connection.id for this client — used to tell own HIDE_STATE_CHANGED
# events apart from those broadcast for other players.
var _self_id: int = -1

var players: Dictionary = {}       # id -> { pos: Vector2i, name: String, node: Node2D }
var npcs: Dictionary = {}          # id -> { pos: Vector2i, name: String, hp: int, max_hp: int, node: Node2D }
var ground_items: Dictionary = {}  # ground_id -> { pos: Vector2i, node: Node2D, item_data: Dictionary, amount: int }
var chests: Dictionary = {}        # chest_id -> { pos: Vector2i, state: String, node: Node2D }

# Set of icon_grh_ids we have already logged a missing-catalog warning for.
# Prevents log spam when the same item type spawns repeatedly.
var _warned_missing_item_icons: Dictionary = {}

# One-shot guard: if a PLAY_SFX payload arrives with BOTH wav_name and
# wav_id set, we prefer wav_name (the new field wins) and warn once so
# the server team knows to drop the legacy field. Repeated payloads
# don't re-warn.
var _warned_play_sfx_both: bool = false

# === World scene nodes ===
@onready var camera: Camera2D                = $Camera
@onready var entities_layer: Node2D          = $Entities
@onready var ground_items_layer: Node2D      = $GroundItems
@onready var chests_layer: Node2D             = $Chests
@onready var ground_layer: Node2D            = $Ground
@onready var overhead_layer: Node2D          = $Overhead
@onready var player_sprite: Node2D           = $PlayerSprite

# === HUD widgets ===
# Widgets passed BY PATH to HUDController in _ready (HP/MP/XP bars, stat
# labels, equipment row, etc.) are not declared here — they're resolved
# inline at construction. Only widgets world.gd reads/writes directly
# live below. See feedback_godot_controller_lifecycle memory.

# -- Chat + minimap
@onready var chat_display: RichTextLabel     = %ChatDisplay
@onready var chat_input: LineEdit            = %ChatInput
@onready var chat_jump_button: Button        = %JumpToPresentButton
@onready var minimap: Control                = %Minimap

# -- Top-bar buttons
@onready var help_button: Button             = %HelpButton
@onready var settings_button: Button         = %SettingsButton

# -- Inventory + spells tab
@onready var inventory_grid: GridContainer   = %Inventario
@onready var lanzar_button: Button           = %LanzarButton
@onready var spell_list: ItemList            = %SpellList

# -- Stats tab
@onready var quests_button: Button           = %QuestsButton

# -- Drop-amount dialog (state owned by InventoryController)
@onready var drop_amount_input: LineEdit     = %AmountInput
@onready var drop_amount_overlay: Control    = %DropAmountOverlay
@onready var drop_cancel_button: Button      = %DropCancelButton
@onready var drop_confirm_button: Button     = %ConfirmButton

# -- Settings overlay (hidden by default)
@onready var bindings_grid: GridContainer    = %BindingsGrid
@onready var cancel_settings_button: Button  = %SettingsCancelButton
@onready var defaults_button: Button         = %DefaultsButton
@onready var save_settings_button: Button    = %SaveButton
@onready var settings_overlay: Control       = %SettingsOverlay
@onready var meditation_aura_section: VBoxContainer = %MeditationAuraSection
@onready var meditation_aura_options: HBoxContainer = %MeditationAuraOptions
@onready var meditation_aura_label: Label    = %MeditationAuraCurrentLabel
@onready var audio_section: GridContainer    = %AudioSection
@onready var master_slider: HSlider          = %MasterSlider
@onready var music_slider: HSlider           = %MusicSlider
@onready var sfx_slider: HSlider             = %SFXSlider
@onready var master_value_label: Label       = %MasterValueLabel
@onready var music_value_label: Label        = %MusicValueLabel
@onready var sfx_value_label: Label          = %SFXValueLabel

# === Controllers (extracted state machines — see scripts/ui/) ===
var audio_settings: AudioSettingsController
var bank: BankController
var chat: ChatController
var dev: DevController
var effect_picker: EffectPickerController
var hud: HUDController
var inventory: InventoryController
var reconnect_modal_controller: ReconnectModalController

var _minimap_drawer: _MinimapDrawer
var _is_dead: bool = false

# Layered character node for the local player. Created on first
# _apply_self_sprite_layers and reused; hidden when the legacy body_sprite_ref
# path is used instead.
var _self_layered: LayeredCharacter = null

# Spellbook for this character — populated from server config in setup() based on
# class + level. Empty for non-caster classes or levels below the lowest learn_level.
var _my_spells: Array = []
# Server-shipped meditation aura state — refreshed when settings overlay
# opens. Picker reads these to render its option buttons.
var _meditation_available: Array = []
var _meditation_chosen: int = 1
# Click-to-cast: after pressing LANZAR with a spell selected, the NEXT click on the
# game viewport sends CAST_SPELL with the tile coords. Escape or another LANZAR cancels.
var _casting_armed: bool = false

# Action name → default keycode. Order here also drives the row order in the settings UI.
const DEFAULT_BINDINGS = {
	"move_up": KEY_UP,
	"move_down": KEY_DOWN,
	"move_left": KEY_LEFT,
	"move_right": KEY_RIGHT,
	"attack": KEY_CTRL,
	"hp_potion": KEY_R,
	"mana_potion": KEY_B,
	"chat_toggle": KEY_T,
	"inventory": KEY_I,
	"respawn": KEY_SPACE,
	"meditate": KEY_M,
	"use_item": KEY_U,
	"equip_item": KEY_E,
	"drop_item": KEY_D,
	"pickup_item": KEY_A,
	"exit_to_select": KEY_F1,
	"hide": KEY_O,
	"bank": KEY_V,
	"open_chest": KEY_F,
}

const ACTION_LABELS = {
	"move_up": "Arriba",
	"move_down": "Abajo",
	"move_left": "Izquierda",
	"move_right": "Derecha",
	"attack": "Atacar",
	"hp_potion": "Poción HP",
	"mana_potion": "Poción Maná",
	"chat_toggle": "Hablar",
	"inventory": "Inventario",
	"respawn": "Resucitar",
	"meditate": "Meditar",
	"use_item": "Usar",
	"equip_item": "Equipar",
	"drop_item": "Tirar",
	"pickup_item": "Agarrar",
	"exit_to_select": "Salir",
	"hide": "Ocultar",
	"bank": "Bóveda",
	"open_chest": "Abrir cofre",
}

var bindings: Dictionary = DEFAULT_BINDINGS.duplicate()
var _pending_bindings: Dictionary = {}
var _capturing_action: String = ""
var _capturing_button: Button = null

func setup(conn: ServerConnection, select_payload: Dictionary, map_data: Dictionary):
	connection = conn
	connection.packet_received.connect(_on_packet_received)

	# Controllers that need `connection` (send_packet) are built here, not in
	# _ready(), because connection only gets assigned above. Building earlier
	# would capture the null and silently no-op all sends.
	inventory = InventoryController.new({
		inventory_grid = inventory_grid,
		drop_overlay   = drop_amount_overlay,
		drop_input     = drop_amount_input,
		connection     = connection,
		hud            = hud,
	})
	inventory.build_slots()
	drop_confirm_button.pressed.connect(inventory.confirm_drop)
	drop_cancel_button.pressed.connect(inventory.hide_drop_dialog)
	drop_amount_input.text_submitted.connect(func(_t): inventory.confirm_drop())

	chat = ChatController.new({
		chat_display = chat_display,
		chat_input   = chat_input,
		connection   = connection,
		world        = self,
		jump_button  = chat_jump_button,
	})
	# `MessagesLabel` is gone; system messages now flow through the chat
	# console. HUD was built in _ready() before chat existed, so wire the
	# sink now and flush any buffered messages.
	hud.set_chat_sink(chat)

	bank = BankController.new({
		bank_grid       = %BankGrid,
		inv_grid        = %BankInvMirror,
		bank_overlay    = %BankOverlay,
		amount_overlay  = %BankAmountOverlay,
		amount_input    = %BankAmountInput,
		connection      = connection,
		hud             = hud,
		inventory       = inventory,
	})
	%BankCloseButton.pressed.connect(bank.close)
	%BankAmountConfirmButton.pressed.connect(bank.confirm_amount)
	%BankAmountCancelButton.pressed.connect(bank.cancel_amount)
	%BankAmountInput.text_submitted.connect(func(_t): bank.confirm_amount())

	dev = DevController.new({
		overlay        = %DevOverlay,
		amount_overlay = %DevAmountOverlay,
		query_input    = %DevQueryInput,
		amount_input   = %DevAmountInput,
		results        = %DevResultsList,
		item_tab       = %DevItemTab,
		creature_tab   = %DevCreatureTab,
		chest_tab      = %DevChestTab,
		connection     = connection,
		hud            = hud,
	})
	%DevCloseButton.pressed.connect(dev.close)
	%DevAmountConfirmButton.pressed.connect(dev.confirm_amount)
	%DevAmountCancelButton.pressed.connect(dev.cancel_amount)
	%DevAmountInput.text_submitted.connect(func(_t): dev.confirm_amount())
	%DevQueryInput.text_submitted.connect(func(_t): dev._request_list())

	# Reconnect-prompt modal: also handled in character_select, but the
	# server's RECONNECT_PROMPT can land in either scene depending on
	# timing -- we wire both. The controller lazy-builds the modal as
	# a child of `self` (the world Node2D) on first prompt; visually it
	# overlays the entire game viewport because the modal scene is a
	# full-rect Control.
	reconnect_modal_controller = ReconnectModalController.new({
		host         = self,
		connection   = connection,
		modal_scene  = preload("res://scenes/match/reconnect_modal.tscn"),
	})

	# Two ways out of the world scene:
	#   - Willful /salir → EXITED_TO_SELECT packet (handled in _on_packet_received)
	#   - Unexpected drop → connection.disconnected signal
	# Both end at the login scene; the log messages differ.
	if not connection.disconnected.is_connected(_on_connection_lost):
		connection.disconnected.connect(_on_connection_lost)

	map_id = map_data.get("map_id", 1)
	my_pos = Vector2i(map_data.get("x", 50), map_data.get("y", 50))
	map_size = Vector2i(map_data.get("width", 100), map_data.get("height", 100))

	var character = select_payload.get("character", {})
	var state = select_payload.get("state", {})
	my_level = int(character.get("level", 1))
	_self_id = int(state.get("self_id", -1))

	# Header
	hud.update_character_header(character.get("name", "?"), my_level, character.get("city", null))

	$PlayerSprite/NameLabel.text = character.get("name", "You")

	# Spellbook — from server config, filtered to spells this character can actually cast.
	_my_spells = PacketIds.spells_for(character.get("class", ""), my_level)
	_populate_spell_list()

	# Bars
	hud.update_hp(int(state.get("hp", 100)), int(state.get("max_hp", 100)))
	hud.update_mp(int(state.get("mana", 0)), int(state.get("max_mana", 100)))
	_update_xp_bar(int(state.get("xp_in_level", 0)))

	# Stats + gold
	var attrs = state.get("attrs", {})
	hud.update_stats(int(attrs.get("str", 0)), int(attrs.get("agi", 0)), int(state.get("gold", 0)))

	# Equipment
	hud.update_equipment(state.get("equipment", {}))

	# Inventory — populate from state (slots already built in _ready)
	inventory.set_inventory(state.get("inventory", []))

	# Restore persisted key bindings (server-side JSONB state)
	_apply_saved_bindings(state.get("key_bindings", {}))

	# Cache server-shipped meditation-aura options. Server contract: the
	# character payload carries `available_effects` (Hash) + `effect_choices`
	# (Hash) keyed by category. If the in-flight server PR has not landed
	# yet, both fields are absent and we fall back to the seeded defaults
	# (single Chico aura, id 1) so the picker still renders coherently.
	var avail_dict = character.get("available_effects", {"meditation": [1]})
	var choices_dict = character.get("effect_choices", {"meditation": 1})
	_meditation_available = []
	var avail_list = avail_dict.get("meditation", [1]) if avail_dict is Dictionary else [1]
	for v in avail_list:
		_meditation_available.append(int(v))
	_meditation_chosen = int(choices_dict.get("meditation", 1)) if choices_dict is Dictionary else 1

	effect_picker = EffectPickerController.new({
		connection    = connection,
		hud           = hud,
		container     = meditation_aura_section,
		current_label = meditation_aura_label,
		options_grid  = meditation_aura_options,
	})
	effect_picker.set_options(_meditation_available, _meditation_chosen)

	# Audio sliders. Uses the same SETTINGS_SAVE channel; the wire shape is
	# `audio: { master, music, sfx }` (mirrors `effect_choices` /
	# `key_bindings`). On open we re-push from server state so a fresh
	# CHARACTER_SELECT is reflected; the persisted shape lives on
	# `character.audio` (default-empty -> AudioSettingsController.DEFAULTS).
	audio_settings = AudioSettingsController.new({
		connection     = connection,
		master_slider  = master_slider,
		music_slider   = music_slider,
		sfx_slider     = sfx_slider,
		master_label   = master_value_label,
		music_label    = music_value_label,
		sfx_label      = sfx_value_label,
	})
	audio_settings.set_values(character.get("audio", {}))

	if not state.get("alive", true):
		_is_dead = true
		hud.add_message("You are a ghost. Press SPACE to respawn.")

	# _render_ground must run FIRST — it reads tile_size + graficos_root from
	# the JSON. Otherwise _update_player_position uses the fallback tile size
	# AND _apply_self_body_sprite can't resolve its atlas (graficos_root is
	# still empty at this point, so _get_map_texture returns null).
	_render_ground()
	# Prefer the new sprite_layers contract; fall back to legacy body_sprite_ref
	# until both PRs (server + client) are merged.
	var sprite_layers = character.get("sprite_layers", null)
	if sprite_layers is Dictionary:
		_apply_self_sprite_layers(sprite_layers)
	else:
		_apply_self_body_sprite(character.get("body_sprite_ref", null))
	_update_player_position()
	_setup_minimap()

func _ready():
	# Hand music control to the director. It resolves the open-world
	# day/night fallback immediately; a subsequent MUSIC_CHANGE packet
	# (set_music_id) overrides with city/zone music if applicable.
	MusicDirector.set_scene("world")

	hud = HUDController.new({
		hp_bar         = %HPBar,
		hp_text        = %HPText,
		mp_bar         = %MPBar,
		mp_text        = %MPText,
		xp_bar         = %XPBar,
		xp_label       = %XPLabel,
		level_label    = %LevelLabel,
		name_label     = %PlayerNameLabel,
		city_label     = %CityLabel,
		str_label      = %StrLabel,
		cele_label     = %CeleLabel,
		gold_label     = %GoldLabel,
		eq_helm        = %HelmValue,
		eq_armor       = %ArmorValue,
		eq_weapon      = %WeaponValue,
		eq_shield      = %ShieldValue,
		eq_magres      = %MagResValue,
		position_label = %PositionLabel,
		fps_label      = %FPSLabel,
	})

	help_button.pressed.connect(func(): hud.add_message("Help — coming soon"))
	settings_button.pressed.connect(_show_settings)
	quests_button.pressed.connect(func(): hud.add_message("Quests — coming soon"))
	lanzar_button.pressed.connect(_on_lanzar_pressed)
	defaults_button.pressed.connect(func(): hud.add_message("Defaults — coming soon"))
	cancel_settings_button.pressed.connect(_hide_settings)
	save_settings_button.pressed.connect(_on_save_settings)
	_populate_spell_list()
	# Arrow keys drive movement; they must never be consumed by UI focus navigation.
	# TabContainer's internal TabBar has its own focus_mode that ignores ours — strip it here.
	%InvTabs.get_tab_bar().focus_mode = Control.FOCUS_NONE
	%StatsTabs.get_tab_bar().focus_mode = Control.FOCUS_NONE
	get_viewport().gui_release_focus()

# --- Key bindings + settings overlay ---

func _apply_saved_bindings(saved: Dictionary):
	for action in DEFAULT_BINDINGS:
		if saved.has(action):
			bindings[action] = int(saved[action])
		else:
			bindings[action] = DEFAULT_BINDINGS[action]

func _show_settings():
	_pending_bindings = bindings.duplicate()
	_capturing_action = ""
	_capturing_button = null
	_build_bindings_ui()
	if effect_picker != null:
		effect_picker.set_options(_meditation_available, _meditation_chosen)
	# Audio sliders are already in their last applied state; nothing
	# to refresh here (set_values() ran in setup() with server state,
	# and slider drags push live). If the player opens the overlay
	# repeatedly we just keep showing whatever they last set.
	settings_overlay.visible = true

func _hide_settings():
	_capturing_action = ""
	_capturing_button = null
	settings_overlay.visible = false

func _on_save_settings():
	bindings = _pending_bindings.duplicate()
	# Server persists as-is; keys are Godot keycodes, opaque to the server.
	# We also bundle the current audio slider values so the "Guardar y salir"
	# path is one round-trip even if the player only touched bindings.
	# Slider value_changed already saved on the fly, so this is mostly a
	# safety net for the case where the player closes via Save without
	# moving sliders -- payload is small either way.
	var payload := {"key_bindings": bindings}
	if audio_settings != null:
		payload["audio"] = audio_settings.current_values()
	connection.send_packet(PacketIds.SETTINGS_SAVE, payload)
	hud.add_message("Settings saved")
	_hide_settings()

func _build_bindings_ui():
	for child in bindings_grid.get_children():
		child.queue_free()
	# Iterate DEFAULT_BINDINGS for stable row order (Dictionary iteration follows insert order).
	for action in DEFAULT_BINDINGS:
		var lbl = Label.new()
		lbl.text = ACTION_LABELS.get(action, action)
		bindings_grid.add_child(lbl)
		var btn = Button.new()
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(140, 0)
		btn.text = OS.get_keycode_string(_pending_bindings[action])
		btn.pressed.connect(_start_capturing.bind(action, btn))
		bindings_grid.add_child(btn)

func _start_capturing(action: String, btn: Button):
	# If another capture is active, cancel it visually first
	if _capturing_button and is_instance_valid(_capturing_button):
		_capturing_button.text = OS.get_keycode_string(_pending_bindings[_capturing_action])
	_capturing_action = action
	_capturing_button = btn
	btn.text = "..."

func _finish_capturing(keycode: int):
	_pending_bindings[_capturing_action] = keycode
	_capturing_button.text = OS.get_keycode_string(keycode)
	_capturing_action = ""
	_capturing_button = null

func _cancel_capturing():
	if _capturing_button and is_instance_valid(_capturing_button):
		_capturing_button.text = OS.get_keycode_string(_pending_bindings[_capturing_action])
	_capturing_action = ""
	_capturing_button = null

func _action_for_keycode(keycode: int) -> String:
	for action in bindings:
		if bindings[action] == keycode:
			return action
	return ""

func _handle_exit_confirmed():
	# Willful /salir — server rewound the connection to :character_select and kept
	# the socket open. Swap to the character_select scene without dropping connection.
	print("[world] /salir confirmed — returning to character select")
	_swap_to_character_select()

func _on_connection_lost():
	# Socket dropped unexpectedly — genuinely logged out. Back to login.
	print("[world] connection dropped — returning to login")
	_return_to_login()

var _leaving_world: bool = false

func _swap_to_character_select():
	if _leaving_world:
		return
	_leaving_world = true
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)

	# Detach our packet handlers before swapping — otherwise we'd briefly receive
	# character_select's packets while queue_free runs deferred.
	if is_instance_valid(connection):
		if connection.packet_received.is_connected(_on_packet_received):
			connection.packet_received.disconnect(_on_packet_received)
		if connection.disconnected.is_connected(_on_connection_lost):
			connection.disconnected.disconnect(_on_connection_lost)

	# load() not preload() — character_select.gd may well end up preloading world
	# later; avoiding the cycle preemptively.
	var cs_scene: PackedScene = load("res://scenes/character/character_select.tscn")
	var cs = cs_scene.instantiate()
	get_parent().add_child(cs)
	get_tree().current_scene = cs
	cs.setup(connection)

	queue_free()

func _return_to_login():
	if _leaving_world:
		return
	_leaving_world = true
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)

	var login_scene: PackedScene = load("res://scenes/login/login.tscn")
	var login = login_scene.instantiate()
	get_parent().add_child(login)
	get_tree().current_scene = login

	if is_instance_valid(connection):
		connection.queue_free()
	queue_free()

func _populate_spell_list():
	spell_list.clear()
	if _my_spells.is_empty():
		spell_list.add_item("(no spells at this level)")
		return
	for spell in _my_spells:
		spell_list.add_item("%s  (%d MP)" % [spell.get("name", "?"), int(spell.get("mana_cost", 0))])

func _on_lanzar_pressed():
	if _my_spells.is_empty():
		hud.add_message("No spells available")
		return
	var selected = spell_list.get_selected_items()
	if selected.is_empty():
		hud.add_message("Select a spell first")
		return
	_casting_armed = true
	Input.set_default_cursor_shape(Input.CURSOR_CROSS)
	var spell_name = _my_spells[selected[0]].get("name", "?")
	hud.add_message("Click target for %s (Esc to cancel)" % spell_name)

func _unhandled_input(event):
	# Two left-click flows in the world viewport (clicks NOT absorbed by HUD
	# Controls — buttons, tabs, chat). Casting wins when armed; otherwise
	# fall through to the inspect-tile reporter.
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return

	var world_pos = get_global_mouse_position()
	var tile = Vector2i(int(world_pos.x / _tile_size), int(world_pos.y / _tile_size))

	if _casting_armed:
		var selected = spell_list.get_selected_items()
		if selected.is_empty():
			_casting_armed = false
			return
		var spell = _my_spells[selected[0]]
		connection.send_packet(PacketIds.CAST_SPELL, {
			"spell_id": int(spell.get("id", 0)),
			"x": tile.x,
			"y": tile.y,
		})
		hud.add_message("Casting %s at (%d, %d)" % [spell.get("name", "?"), tile.x, tile.y])
		_casting_armed = false
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
		get_viewport().set_input_as_handled()
		return

	# Inspect-tile fallback: report everything currently on the clicked tile
	# to the chat console. Pure client-side feature — all state already lives
	# in `players` / `npcs` / `ground_items` / `chests` from the existing
	# spawn packets. Out-of-bounds clicks silently no-op.
	if tile.x < 0 or tile.y < 0 or tile.x >= map_size.x or tile.y >= map_size.y:
		return
	var report := format_inspect_report(
		tile,
		my_pos,
		hud.current_hp(),
		hud.current_max_hp(),
		players,
		npcs,
		ground_items,
		chests
	)
	if report != "":
		chat.append_system(report)
	get_viewport().set_input_as_handled()


# --- Inspect-tile formatting ---

# Pure-function helper: given click position + current world state,
# return the formatted multi-line system message describing what's on
# the tile. Static so unit tests can exercise it without a live world
# instance. Returns "" only when the client has nothing to say
# (currently never; empty tiles return "No hay nada aquí.").
static func format_inspect_report(
	tile: Vector2i,
	self_pos: Vector2i,
	self_hp: int,
	self_max_hp: int,
	players_dict: Dictionary,
	npcs_dict: Dictionary,
	ground_items_dict: Dictionary,
	chests_dict: Dictionary
) -> String:
	var lines: Array = []

	if tile == self_pos:
		if self_max_hp > 0:
			lines.append("Tú (HP %d/%d)" % [self_hp, self_max_hp])
		else:
			lines.append("Tú")

	for id in players_dict:
		var p = players_dict[id]
		if p.get("pos", Vector2i.ZERO) == tile:
			lines.append("Jugador: %s" % p.get("name", "?"))

	for id in npcs_dict:
		var n = npcs_dict[id]
		if n.get("pos", Vector2i.ZERO) == tile:
			var nm = n.get("name", "NPC")
			var hp = int(n.get("hp", 0))
			var mhp = int(n.get("max_hp", 0))
			if mhp > 0:
				lines.append("NPC: %s (HP %d/%d)" % [nm, hp, mhp])
			else:
				lines.append("NPC: %s" % nm)

	for id in ground_items_dict:
		var g = ground_items_dict[id]
		if g.get("pos", Vector2i.ZERO) == tile:
			lines.append("Item: %s" % _format_ground_item(g))

	for id in chests_dict:
		var c = chests_dict[id]
		if c.get("pos", Vector2i.ZERO) == tile:
			var state = String(c.get("state", "closed"))
			var label = "(abierto)" if state == "opened" else "(cerrado)"
			lines.append("Cofre %s" % label)

	if lines.is_empty():
		return "No hay nada aquí."
	if lines.size() == 1:
		return "Aquí: %s" % lines[0]
	var out := "Hay aquí:"
	for line in lines:
		out += "\n  • " + line
	return out

static func _format_ground_item(entry: Dictionary) -> String:
	var item_data = entry.get("item_data", {})
	var amount := int(entry.get("amount", 1))
	var nm := "?"
	if item_data is Dictionary:
		nm = String(item_data.get("name", "?"))
	if amount > 1:
		return "%s x%d" % [nm, amount]
	return nm

func _cancel_armed_cast():
	if not _casting_armed:
		return
	_casting_armed = false
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	hud.add_message("Cast cancelled")

# Per-map palette for procedural ground (placeholder until real tiles)
const MAP_PALETTE = {
	1: { "a": Color(0.25, 0.45, 0.20), "b": Color(0.20, 0.40, 0.18) }, # map 1 = green
	2: { "a": Color(0.55, 0.45, 0.25), "b": Color(0.50, 0.40, 0.22) }, # map 2 = sandy
}

func _render_ground():
	# Read the per-map JSON, build a flat draw plan for layers 1-4 and hand it
	# to a single _MapDrawer (one Node2D, one _draw). Falls back to the
	# procedural checker if the JSON isn't found.
	var _t_total := Time.get_ticks_msec()
	for child in ground_layer.get_children():
		child.queue_free()
	# Layer 4 lives on $Overhead so it renders above the player; clear that too.
	for child in overhead_layer.get_children():
		child.queue_free()
	# Persistent texture/missing caches across renders: the ImageTextures don't
	# change between maps, so re-entry to a previously-loaded map skips disk I/O
	# entirely. Memory cost is small (atlases are PNG-sized in RAM).

	var _t_json := Time.get_ticks_msec()
	var data := MapTextureCache.get_map_json(map_id)
	var dt_json := Time.get_ticks_msec() - _t_json
	if data.is_empty():
		push_warning("[world] map JSON not found for map_id=%d — falling back to checker" % map_id)
		_render_checker_fallback()
		return

	# Pick up tile_size + roots from the JSON.
	_tile_size = int(data.get("tile_size", FALLBACK_TILE_SIZE))
	_graficos_root = String(data.get("graficos_root", ""))
	_floors_root = String(data.get("floors_root", ""))
	map_size = Vector2i(int(data.get("width", 100)), int(data.get("height", 100)))

	var grh_lookup: Dictionary = data.get("grh_lookup", {})
	var tiles: Array = data.get("tiles", [])

	# --- Phase 1: collect unique image files this map needs that aren't cached.
	var _t_collect := Time.get_ticks_msec()
	var to_load: Dictionary = {}  # cache_key -> absolute path
	for layer_num in DRAW_LAYERS:
		for tile in tiles:
			var grh_id: int = int(tile["layer%d" % layer_num])
			if grh_id == 0:
				continue
			var info = grh_lookup.get(str(grh_id))
			if info == null:
				continue
			var file_name := String(info["file"])
			var is_floor: bool = bool(info.get("floor", false))
			var cache_key := ("floor:" + file_name) if is_floor else file_name
			if MapTextureCache.has_either(cache_key) or to_load.has(cache_key):
				continue
			var root: String = _floors_root if is_floor and _floors_root != "" else _graficos_root
			if root == "":
				MapTextureCache.mark_missing(cache_key)
				continue
			to_load[cache_key] = "%s/%s" % [root, file_name]
	var dt_collect := Time.get_ticks_msec() - _t_collect

	# --- Phase 2: load all needed PNGs in parallel via WorkerThreadPool.
	# Image.load_from_file is the dominant cost (~4ms per file × 100+ files).
	# Decoding is CPU-bound and fully thread-safe; ImageTexture creation must
	# happen on the main thread, so we split the work in two.
	var _t_load := Time.get_ticks_msec()
	_perf_load_image_calls = to_load.size()
	var failures := 0
	if not to_load.is_empty():
		var keys := to_load.keys()
		var paths := to_load.values()
		var results: Array = []
		results.resize(keys.size())
		# Lambda captures `paths` and `results` directly. Avoids Callable.bind,
		# which interacted poorly with add_group_task (every task returned null
		# instantly with the bind variant).
		var loader := func(idx: int) -> void:
			results[idx] = Image.load_from_file(paths[idx])
		var group_id := WorkerThreadPool.add_group_task(
			loader, keys.size(), -1, false, "world_image_load"
		)
		WorkerThreadPool.wait_for_group_task_completion(group_id)
		for i in keys.size():
			var img: Image = results[i]
			if img == null:
				MapTextureCache.mark_missing(keys[i])
				failures += 1
				if failures <= 3:
					push_warning("[world] image load failed: %s" % paths[i])
			else:
				MapTextureCache.set_cached(keys[i], ImageTexture.create_from_image(img))
	_perf_load_image_ms = Time.get_ticks_msec() - _t_load
	_perf_color_key_ms = 0
	_perf_color_key_calls = 0

	# --- Phase 3: build the draw plan (every texture is now cached).
	# Two plans now: one for layers 1-3 (ground / below player), one for
	# layer 4 (overhead — trees, roof corners). They render to separate
	# Node2D parents at different z values so the player walks BEHIND
	# layer 4. See world.tscn for the z-stack reference.
	var _t_tiles := Time.get_ticks_msec()
	var ground_plan: Array = []
	var overhead_plan: Array = []
	var drawn := 0
	for layer_num in DRAW_LAYERS:
		var target_plan: Array = overhead_plan if layer_num == OVERHEAD_LAYER else ground_plan
		for tile in tiles:
			var grh_id: int = int(tile["layer%d" % layer_num])
			if grh_id == 0:
				continue
			var info = grh_lookup.get(str(grh_id))
			if info == null:
				continue
			var texture := _get_map_image_texture(info)
			if texture == null:
				continue
			var sprite_w: int = int(info["w"])
			var sprite_h: int = int(info["h"])
			var dest := Rect2(
				(tile["x"] - 1) * _tile_size - (sprite_w - _tile_size) / 2.0,
				(tile["y"] - 1) * _tile_size - (sprite_h - _tile_size),
				sprite_w, sprite_h
			)
			var src := Rect2(int(info["sx"]), int(info["sy"]), sprite_w, sprite_h)
			target_plan.append({"texture": texture, "dest": dest, "src": src})
			drawn += 1
	var drawer := _MapDrawer.new()
	drawer.draw_plan = ground_plan
	ground_layer.add_child(drawer)
	drawer.queue_redraw()
	# Overhead drawer runs even when its plan is empty — keeps the scene
	# tree shape stable for tests + future-map JSONs that lack layer 4.
	var overhead_drawer := _MapDrawer.new()
	overhead_drawer.draw_plan = overhead_plan
	overhead_layer.add_child(overhead_drawer)
	overhead_drawer.queue_redraw()
	var dt_tiles := Time.get_ticks_msec() - _t_tiles
	var dt_total := Time.get_ticks_msec() - _t_total
	print("[world] map %d: %d tiles drawn (%d ground, %d overhead), tile_size=%d, cache=%d" % [map_id, drawn, ground_plan.size(), overhead_plan.size(), _tile_size, MapTextureCache.count()])
	print("  perf: total=%dms json=%dms collect=%dms tile_loop=%dms" % [dt_total, dt_json, dt_collect, dt_tiles])
	print("  perf: image_load %d files / %dms (parallel, %d failed)" % [_perf_load_image_calls, _perf_load_image_ms, failures])

	# Background-preload the maps the player can transition INTO from here.
	# By the time they walk to an exit tile, those atlases are already decoded.
	MapTextureCache.mark_already_loaded(map_id)
	var unique_dests: Dictionary = {}
	for exit in data.get("tile_exits", []):
		unique_dests[int(exit.get("dest_map_id", 0))] = true
	for dest_id in unique_dests:
		MapTextureCache.queue_preload(dest_id)


func _render_checker_fallback():
	_tile_size = FALLBACK_TILE_SIZE
	var drawer = _CheckerDrawer.new()
	drawer.map_size = map_size
	drawer.palette = MAP_PALETTE.get(map_id, { "a": Color.DARK_GRAY, "b": Color.GRAY })
	ground_layer.add_child(drawer)


class _CheckerDrawer extends Node2D:
	var map_size: Vector2i
	var palette: Dictionary

	func _draw():
		const TILE = 32
		for y in map_size.y:
			for x in map_size.x:
				var color = palette["a"] if (x + y) % 2 == 0 else palette["b"]
				draw_rect(Rect2(x * TILE, y * TILE, TILE, TILE), color)


class _MapDrawer extends Node2D:
	# Single Node2D that draws the entire ground in one _draw call. Replaces
	# the per-tile Sprite2D fan-out (10k+ nodes on mapa1) — node creation
	# was dominating map-load time.
	var draw_plan: Array = []

	func _ready():
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	func _draw():
		for entry in draw_plan:
			draw_texture_rect_region(entry["texture"], entry["dest"], entry["src"])


func _get_map_image_texture(info: Dictionary) -> Texture2D:
	# Returns the raw whole-file ImageTexture (no AtlasTexture wrap). The
	# _MapDrawer takes a src Rect2 directly, so wrapping is wasted work.
	# Alpha is BAKED into every PNG under upscaled_2x/ via
	# scripts/bake_alpha_channel.py — runtime color-keying is gone.
	# Cache lives on MapTextureCache (autoload) so it survives world re-creates.
	var file_name := String(info["file"])
	var is_floor: bool = bool(info.get("floor", false))
	var cache_key := ("floor:" + file_name) if is_floor else file_name
	if MapTextureCache.is_missing(cache_key):
		return null
	var cached := MapTextureCache.get_cached(cache_key)
	if cached != null:
		return cached
	# Lazy-load fallback. _render_ground prefetches all map atlases in
	# parallel up front, so this path is mostly hit by entity sprites
	# (NPCs, players, own body) that aren't part of the prefetch set.
	var root: String
	if is_floor and _floors_root != "":
		root = _floors_root
	else:
		root = _graficos_root
	if root == "":
		MapTextureCache.mark_missing(cache_key)
		return null
	var img_path := "%s/%s" % [root, file_name]
	var t_img := Time.get_ticks_msec()
	var img := Image.load_from_file(img_path)
	_perf_load_image_ms += Time.get_ticks_msec() - t_img
	_perf_load_image_calls += 1
	if img == null:
		MapTextureCache.mark_missing(cache_key)
		return null
	var tex := ImageTexture.create_from_image(img)
	MapTextureCache.set_cached(cache_key, tex)
	return tex


func _get_map_texture(info: Dictionary) -> Texture2D:
	# AtlasTexture wrapper — used by entity Sprite2Ds (NPCs, players, own
	# body). _MapDrawer skips this and uses _get_map_image_texture directly.
	var raw := _get_map_image_texture(info)
	if raw == null:
		return null
	var atlas := AtlasTexture.new()
	atlas.atlas = raw
	atlas.region = Rect2(
		int(info["sx"]), int(info["sy"]),
		int(info["w"]),  int(info["h"])
	)
	return atlas


func _color_key_near_black(img: Image):
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	var thresh := _black_key_max
	for y in range(h):
		for x in range(w):
			var c := img.get_pixel(x, y)
			if c.r <= thresh and c.g <= thresh and c.b <= thresh:
				img.set_pixel(x, y, Color(0, 0, 0, 0))

# --- Minimap ---

func _setup_minimap():
	if _minimap_drawer:
		_minimap_drawer.queue_free()
	_minimap_drawer = _MinimapDrawer.new()
	_minimap_drawer.host = self
	_minimap_drawer.anchor_right = 1.0
	_minimap_drawer.anchor_bottom = 1.0
	minimap.add_child(_minimap_drawer)

class _MinimapDrawer extends Control:
	var host = null
	# Optional pulsing marker (e.g. broadcast link `map_jump`). Active for
	# PULSE_DURATION_S then auto-clears. Pulse is on whichever map_id was
	# requested; we still render the dot on the current minimap because
	# the player might be on the same map. If the destination is a
	# different map, the dot is rendered with a "(elsewhere)" hint via
	# the bg ring color, but the position is still the destination tile.
	var _pulse_pos: Vector2i = Vector2i.ZERO
	var _pulse_active: bool = false
	var _pulse_t: float = 0.0
	var _pulse_dest_map_id: int = 0
	const PULSE_DURATION_S: float = 4.0
	const PULSE_RATE_HZ: float = 2.0

	func _ready():
		set_process(true)

	func _process(delta: float) -> void:
		if not _pulse_active:
			return
		_pulse_t += delta
		if _pulse_t >= PULSE_DURATION_S:
			_pulse_active = false
		queue_redraw()

	func start_pulse(map_id: int, pos: Vector2i) -> void:
		_pulse_dest_map_id = map_id
		_pulse_pos = pos
		_pulse_active = true
		_pulse_t = 0.0
		queue_redraw()

	func _draw():
		var sz = size
		draw_rect(Rect2(Vector2.ZERO, sz), Color(0.05, 0.05, 0.08), true)
		draw_rect(Rect2(Vector2.ZERO, sz), Color(0.4, 0.4, 0.5), false, 1.0)
		if host == null or host.map_size.x <= 0 or host.map_size.y <= 0:
			return

		# Ground items first (lowest priority visual)
		for id in host.ground_items:
			var p = host.ground_items[id].pos
			_dot(p, sz, Color(1, 0.85, 0.2), 1.5)

		# NPCs — red
		for id in host.npcs:
			var p = host.npcs[id].pos
			_dot(p, sz, Color(1, 0.3, 0.2), 2.0)

		# Other players — cyan
		for id in host.players:
			var p = host.players[id].pos
			_dot(p, sz, Color(0.3, 0.85, 1), 2.0)

		# Self — bright red, largest, drawn last (on top)
		_dot(host.my_pos, sz, Color(1, 0.2, 0.2), 3.0)

		# Broadcast link pulse marker — drawn last, on top of everything.
		# Yellow if on the current map (actionable), pale gold if on
		# another map (informational only — player chooses to travel).
		if _pulse_active:
			var phase = sin(_pulse_t * PULSE_RATE_HZ * TAU) * 0.5 + 0.5
			var radius = 4.0 + phase * 4.0
			var same_map = (host.map_id == _pulse_dest_map_id)
			var color = Color(1, 0.95, 0.3, 0.85) if same_map else Color(0.85, 0.75, 0.45, 0.65)
			_dot(_pulse_pos, sz, color, radius)

	func _dot(world_pos: Vector2i, sz: Vector2, color: Color, radius: float):
		var px = (float(world_pos.x) / host.map_size.x) * sz.x
		var py = (float(world_pos.y) / host.map_size.y) * sz.y
		draw_circle(Vector2(px, py), radius, color)

# Public API for BroadcastLinkDispatcher.map_jump. Pulses a marker on the
# minimap at the destination tile. We deliberately do NOT teleport — the
# player's free-will travel is preserved. If the destination is on a
# different map, the marker is still drawn (on the current minimap) with
# a dimmer color so the player knows where to head.
func pulse_minimap_marker(dest_map_id: int, x: int, y: int) -> void:
	if _minimap_drawer == null:
		return
	# Make sure the minimap is visible — broadcast clicks should not be
	# silent if the player has the panel collapsed.
	if minimap != null:
		minimap.visible = true
	_minimap_drawer.start_pulse(dest_map_id, Vector2i(x, y))

# --- XP bar (thin wrapper — resolves the level threshold then delegates) ---

func _update_xp_bar(xp_in_level: int):
	hud.update_xp(xp_in_level, PacketIds.xp_for_level(my_level))

# --- Movement / player sprite ---

# Pure tile -> world-pixel conversion. Lifted out of _update_player_position so
# unit tests can exercise the math without spinning up a scene tree, and so
# every caller that needs sprite-pixel coords goes through one definition.
static func tile_to_world(tile_x: int, tile_y: int, tile_size: int) -> Vector2:
	return Vector2(tile_x * tile_size, tile_y * tile_size)

func _update_player_position():
	# This is the SNAP path — initial spawn, MAP_TRANSITION, MOVE_REJECTED.
	# Any in-flight smooth-walk tween from the prior tile (or prior MAP) must
	# be killed here, otherwise it keeps tweening to its old target and
	# overrides the snap a frame later. That was the visible "I'm at far-east
	# of map 1 even though server says X=14" bug on edge-tile transitions:
	# the player would render at the prior map's east edge until the next
	# step kicked off a fresh tween. Symmetric across all 4 edges (N/S/E/W);
	# any tile-exit transition routes through here.
	if _move_tween and _move_tween.is_valid():
		_move_tween.kill()
	# Killing the tween short-circuits the on-tween-end callback that sets
	# walking=false on the LayeredCharacter. Reset it explicitly here so the
	# walk animation doesn't persist after a snap (was: sprite stuck cycling
	# walk frames after a map transition).
	if _self_layered != null:
		_self_layered.set_walking(false)
	player_sprite.position = tile_to_world(my_pos.x, my_pos.y, _tile_size)
	camera.position = player_sprite.position + CAMERA_WORLD_OFFSET
	hud.set_position_label(map_id, my_pos.x, my_pos.y)
	# Spatial-audio listener follows the player tile (not the camera) so
	# Y-pitch shift uses the player's vertical position even if the
	# camera is offset. Snap path -- initial spawn / map transition.
	AudioPlayer.set_listener_position(float(my_pos.x), float(my_pos.y))
	if _minimap_drawer:
		_minimap_drawer.queue_redraw()

# Glides the player sprite + camera from their current world-position to the
# my_pos tile over MOVE_INTERVAL. AO-style: camera stays rigidly locked to
# the sprite, the smoothness comes from interpolating the sprite itself.
# Used by _send_move on a successful step. Other callers of
# _update_player_position (initial spawn, map change, server corrections)
# still snap, which is correct — those are jumps, not walks.
var _move_tween: Tween

func _tween_player_step() -> void:
	var target_sprite = tile_to_world(my_pos.x, my_pos.y, _tile_size)
	var target_camera = target_sprite + CAMERA_WORLD_OFFSET
	if _move_tween and _move_tween.is_valid():
		_move_tween.kill()
	_move_tween = create_tween().set_parallel(true)
	_move_tween.tween_property(player_sprite, "position", target_sprite, MOVE_INTERVAL)
	_move_tween.tween_property(camera, "position", target_camera, MOVE_INTERVAL)
	# Animation drive — only when the new layered path is mounted. The legacy
	# single-Sprite2D path keeps rendering a static body, which is fine: the
	# fallback is meant to disappear once both server + client PRs land.
	if _self_layered != null:
		_self_layered.set_direction(my_heading)
		_self_layered.set_walking(true)
		_move_tween.finished.connect(_on_self_step_finished, CONNECT_ONE_SHOT)
	hud.set_position_label(map_id, my_pos.x, my_pos.y)
	# Update the spatial-audio listener on every smooth-walk step so
	# Y-pitch shift on incoming SFX tracks the player's tile, not the
	# stale value from before this step. Cheap (no allocations).
	AudioPlayer.set_listener_position(float(my_pos.x), float(my_pos.y))
	if _minimap_drawer:
		_minimap_drawer.queue_redraw()


func _on_self_step_finished() -> void:
	if _self_layered != null:
		_self_layered.set_walking(false)

var _move_cooldown: float = 0.0
var _fps_cooldown: float = 0.0
var _minimap_cooldown: float = 0.0
const MOVE_INTERVAL: float = 0.20 # 5 tiles/sec — matches Cucsi's measured walk speed
const FPS_REFRESH: float = 0.5
const MINIMAP_REFRESH: float = 0.2 # 5Hz — cheap, catches NPC/player/ground item changes

func _process(delta):
	if _move_cooldown > 0:
		_move_cooldown -= delta

	_fps_cooldown -= delta
	if _fps_cooldown <= 0 and hud:
		hud.set_fps(Engine.get_frames_per_second())
		_fps_cooldown = FPS_REFRESH

	_minimap_cooldown -= delta
	if _minimap_cooldown <= 0 and _minimap_drawer:
		_minimap_drawer.queue_redraw()
		_minimap_cooldown = MINIMAP_REFRESH

	# Safety net: when no modal is open, only chat_input may hold focus.
	# Inside a modal (settings, drop dialog) the modal's own controls legitimately need it.
	var any_modal_open = (
		settings_overlay.visible
		or inventory.is_drop_dialog_open()
		or bank.is_open()
		or dev.is_open()
	)
	if not any_modal_open:
		var focused = get_viewport().gui_get_focus_owner()
		if focused != null and focused != chat_input:
			get_viewport().gui_release_focus()

	if chat.has_focus() or any_modal_open:
		# Tick the dev controller's query debounce while its overlay is open.
		if dev.is_open():
			dev.process(int(delta * 1000))
		return

	if _move_cooldown <= 0:
		if Input.is_key_pressed(bindings["move_up"]):
			my_heading = "north"
			_send_move(0, -1)
			_move_cooldown = MOVE_INTERVAL
		elif Input.is_key_pressed(bindings["move_down"]):
			my_heading = "south"
			_send_move(0, 1)
			_move_cooldown = MOVE_INTERVAL
		elif Input.is_key_pressed(bindings["move_right"]):
			my_heading = "east"
			_send_move(1, 0)
			_move_cooldown = MOVE_INTERVAL
		elif Input.is_key_pressed(bindings["move_left"]):
			my_heading = "west"
			_send_move(-1, 0)
			_move_cooldown = MOVE_INTERVAL

func _input(event):
	if not (event is InputEventKey) or not event.pressed:
		return

	# Rebinding: intercept the next non-echo keypress and assign it to the action.
	# Escape cancels. All keystrokes are consumed so nothing else reacts.
	if _capturing_action != "":
		if not event.echo:
			if event.keycode == KEY_ESCAPE:
				_cancel_capturing()
			else:
				_finish_capturing(event.keycode)
		get_viewport().set_input_as_handled()
		return

	# Drop-amount dialog open — only handle Escape here; LineEdit captures other keys.
	if inventory.is_drop_dialog_open():
		if event.keycode == KEY_ESCAPE and not event.echo:
			inventory.hide_drop_dialog()
			get_viewport().set_input_as_handled()
		return

	# Settings overlay open — ignore world input (Escape closes).
	if settings_overlay.visible:
		if event.keycode == KEY_ESCAPE and not event.echo:
			_hide_settings()
			get_viewport().set_input_as_handled()
		return

	# Bank amount prompt open — Esc cancels; LineEdit captures other keys.
	if bank.is_amount_prompt_open():
		if event.keycode == KEY_ESCAPE and not event.echo:
			bank.cancel_amount()
			get_viewport().set_input_as_handled()
		return

	# Bank overlay open — ignore world input (Escape closes).
	if bank.is_open():
		if event.keycode == KEY_ESCAPE and not event.echo:
			bank.close()
			get_viewport().set_input_as_handled()
		return

	# Dev amount prompt open — Esc cancels; LineEdit captures other keys.
	if dev.is_amount_prompt_open():
		if event.keycode == KEY_ESCAPE and not event.echo:
			dev.cancel_amount()
			get_viewport().set_input_as_handled()
		return

	# Dev overlay open — ignore world input (Escape closes).
	if dev.is_open():
		if event.keycode == KEY_ESCAPE and not event.echo:
			dev.close()
			get_viewport().set_input_as_handled()
		return

	# F2 toggles the dev overlay (dev-only — server gates response on
	# ENV["DEV_AUTH"]; in production the overlay opens but stays empty).
	if event.keycode == KEY_F2 and not event.echo:
		dev.toggle()
		get_viewport().set_input_as_handled()
		return

	# Escape cancels an armed cast.
	if _casting_armed and event.keycode == KEY_ESCAPE and not event.echo:
		_cancel_armed_cast()
		get_viewport().set_input_as_handled()
		return

	# Typing in chat: let LineEdit have everything.
	if chat.has_focus():
		return

	var action = _action_for_keycode(event.keycode)

	# Consume any game-bound key so Godot's GUI focus nav never steals arrow movement
	# (TabContainer/ItemList can ignore focus_mode = 0 — belt and braces).
	if action != "":
		get_viewport().set_input_as_handled()

	if event.echo:
		return

	match action:
		"attack":
			_attack_facing()
		"hp_potion":
			connection.send_packet(PacketIds.USE_POTION, {"hp": 150})
			hud.add_message("HP potion!")
		"mana_potion":
			connection.send_packet(PacketIds.USE_POTION, {"mana": 300})
			hud.add_message("Mana potion!")
		"chat_toggle":
			chat.focus()
		"inventory":
			connection.send_packet(PacketIds.INVENTORY_REQUEST)
		"respawn":
			if _is_dead:
				connection.send_packet(PacketIds.RESPAWN)
				hud.add_message("Respawning...")
		"meditate":
			connection.send_packet(PacketIds.MEDITATE_TOGGLE)
			hud.add_message("Meditar (toggle)")
		"use_item":
			inventory.use_focused()
		"equip_item":
			inventory.equip_focused()
		"drop_item":
			inventory.start_drop()
		"pickup_item":
			connection.send_packet(PacketIds.PICKUP_ITEM)
		"exit_to_select":
			connection.send_packet(PacketIds.EXIT_TO_SELECT)
		"hide":
			connection.send_packet(PacketIds.HIDE_TOGGLE)
		"bank":
			bank.toggle()
		"open_chest":
			_try_open_adjacent_chest()

func _send_move(dx: int, dy: int):
	# Always update facing on a directional input — even if the move ends up
	# blocked by an edge, NPC, or player. AO convention: pressing a direction
	# rotates the character so they can interact (attack, talk) with whatever
	# is in front of them, regardless of whether stepping forward is possible.
	if _self_layered != null:
		_self_layered.set_direction(my_heading)

	var new_x = my_pos.x + dx
	var new_y = my_pos.y + dy

	if new_x < 0 or new_y < 0 or new_x >= map_size.x or new_y >= map_size.y:
		return

	for npc_id in npcs:
		if npcs[npc_id].pos == Vector2i(new_x, new_y):
			return

	for player_id in players:
		if players[player_id].pos == Vector2i(new_x, new_y):
			return

	connection.send_packet(PacketIds.PLAYER_MOVE, {"x": new_x, "y": new_y})
	my_pos = Vector2i(new_x, new_y)
	_tween_player_step()

func _attack_facing():
	var facing = _facing_offset()
	var target_pos = my_pos + facing

	for npc_id in npcs:
		var npc = npcs[npc_id]
		if npc.pos == target_pos:
			connection.send_packet(PacketIds.ATTACK_NPC, {"npc_id": npc_id})
			hud.add_message("Attacking %s!" % npc.name)
			return

	for player_id in players:
		var player = players[player_id]
		if player.pos == target_pos:
			connection.send_packet(PacketIds.ATTACK, {"target_id": player_id})
			hud.add_message("Attacking %s!" % player.name)
			return

	hud.add_message("Nothing to attack")

func _facing_offset() -> Vector2i:
	match my_heading:
		"north": return Vector2i(0, -1)
		"south": return Vector2i(0, 1)
		"east":  return Vector2i(1, 0)
		"west":  return Vector2i(-1, 0)
	return Vector2i(0, 1)

func _on_packet_received(packet_id: int, payload: Dictionary):
	match packet_id:
		PacketIds.PLAYER_SPAWN:
			_handle_player_spawn(payload)
		PacketIds.PLAYER_MOVED:
			_handle_player_moved(payload)
		PacketIds.PLAYER_DESPAWN:
			_handle_player_despawn(payload)
		PacketIds.NPC_SPAWN, PacketIds.NPC_RESPAWN:
			_handle_npc_spawn(payload)
		PacketIds.NPC_MOVED:
			_handle_npc_moved(payload)
		PacketIds.NPC_DEATH:
			_handle_npc_death(payload)
		PacketIds.NPC_ATTACK:
			var npc_name = npcs.get(payload.get("npc_id", 0), {}).get("name", "NPC")
			var npc_damage = int(payload.get("damage", 0))
			hud.add_message("%s hits you for %d!" % [npc_name, npc_damage])
			if npc_damage > 0:
				_spawn_floating(player_sprite, "-%d" % npc_damage, Color(1, 0.35, 0.35))
		PacketIds.MAP_TRANSITION:
			_handle_map_transition(payload)
		PacketIds.MOVE_REJECTED:
			my_pos = Vector2i(payload.get("x", my_pos.x), payload.get("y", my_pos.y))
			_update_player_position()
		PacketIds.DAMAGE_NUMBER:
			_handle_damage(payload)
		PacketIds.MISS:
			hud.add_message("MISS!")
		PacketIds.UPDATE_HP:
			var hp = int(payload.get("hp", 0))
			hud.update_hp(hp, int(payload.get("max_hp", 1)))
			if hp > 0 and _is_dead:
				_is_dead = false
				hud.add_message("You have respawned!")
		PacketIds.UPDATE_MANA:
			hud.update_mp(int(payload.get("mana", 0)), int(payload.get("max_mana", 1)))
		PacketIds.UPDATE_GOLD:
			hud.set_gold(int(payload.get("gold", 0)))
		PacketIds.UPDATE_XP:
			var new_level = int(payload.get("level", my_level))
			if new_level != my_level:
				my_level = new_level
				hud.set_level(my_level)
			# Use the server's authoritative xp-for-level if provided, falling back to the local exp_table.
			var xp_in = int(payload.get("xp_in_level", 0))
			var xp_for = int(payload.get("xp_for_level", PacketIds.xp_for_level(my_level)))
			hud.update_xp(xp_in, xp_for)
		PacketIds.CHAR_DEATH:
			hud.add_message("YOU DIED! Press SPACE to respawn")
			_is_dead = true
			# Auto-stop any active effect on the local player (e.g. meditation
			# aura) — server stops the effect server-side too, but the dying
			# player needs the visual cleared whether or not an EFFECT_STOP
			# follows. Other-player deaths (CHAR_DEATH for someone else) will
			# arrive via a future per-target packet; for now we only clear self.
			if _self_layered != null:
				_self_layered.clear_effects()
		PacketIds.SYSTEM_MESSAGE:
			hud.add_message(payload.get("text", ""))
		PacketIds.EXITED_TO_SELECT:
			_handle_exit_confirmed()
		PacketIds.CHAT_BROADCAST:
			var msg = payload.get("message", "")
			chat.append_broadcast(payload.get("from_name", null), msg)
			_show_chat_bubble(payload.get("from_id", null), msg)
		PacketIds.CHAT_CLEAR:
			# Server tells us to drop the bubble over the given player (empty message).
			_clear_chat_bubble(payload.get("id", 0))
		PacketIds.INVENTORY_RESPONSE:
			inventory.render_only(payload.get("items", []))
		PacketIds.INVENTORY_UPDATE:
			inventory.set_inventory(payload.get("inventory", []))
			hud.update_equipment(payload.get("equipment", {}))
			bank.refresh_inventory_mirror() # mirror tracks live inventory while bank is open
			# Server's `equipment-layers-and-meditation-effect` PR adds a
			# refreshed sprite_layers field reflecting the post-equip state.
			# Old servers don't ship the field — ignore silently in that case.
			var sl = payload.get("sprite_layers", null)
			if sl is Dictionary:
				_apply_self_sprite_layers(sl)
		PacketIds.PLAYER_LAYERS_UPDATE:
			# Broadcast: another player's sprite_layers changed (or our own,
			# for forward-compat). Look the player up and re-apply on their
			# LayeredCharacter. Drop silently if the target isn't on-map.
			_handle_player_layers_update(payload)
		PacketIds.EFFECT_START:
			_handle_effect_start(payload)
		PacketIds.EFFECT_STOP:
			_handle_effect_stop(payload)
		PacketIds.BANK_CONTENTS:
			bank.handle_contents(payload)
		PacketIds.DEV_LIST_RESPONSE:
			dev.handle_list_response(payload)
		PacketIds.GROUND_ITEM_SPAWN:
			_handle_ground_item_spawn(payload)
		PacketIds.GROUND_ITEM_DESPAWN:
			_handle_ground_item_despawn(payload)
		PacketIds.CHEST_SPAWN:
			_handle_chest_spawn(payload)
		PacketIds.CHEST_OPENED:
			_handle_chest_opened(payload)
		PacketIds.CHEST_DESPAWN:
			_handle_chest_despawn(payload)
		PacketIds.HIDE_STATE_CHANGED:
			_handle_hide_state_changed(payload)
		PacketIds.PLAY_SFX:
			# Spatial SFX from the server. payload = { wav_id?, wav_name?, x, y }.
			# 0/0 = non-spatial UI sound (still routed through SFX bus).
			# Dispatch rules:
			#   wav_name set                       -> curated SFX (string lookup)
			#   wav_name unset, wav_id set         -> legacy numeric SFX
			#   both set                           -> wav_name wins, warn once
			#   neither set                        -> silent no-op
			var wav_name = payload.get("wav_name", "")
			var wav_id = int(payload.get("wav_id", 0))
			var sfx_x = int(payload.get("x", 0))
			var sfx_y = int(payload.get("y", 0))
			if wav_name != "":
				if wav_id > 0 and not _warned_play_sfx_both:
					_warned_play_sfx_both = true
					push_warning("PLAY_SFX: payload has both wav_name='%s' and wav_id=%d; using wav_name (server should drop wav_id once curated routing is canonical)" % [wav_name, wav_id])
				AudioPlayer.play_sfx_curated(String(wav_name), sfx_x, sfx_y)
			elif wav_id > 0:
				AudioPlayer.play_sfx(wav_id, sfx_x, sfx_y)
			# else: neither set -- silent, intentional
		PacketIds.MUSIC_CHANGE:
			# music_id may be null/0; MusicDirector falls through to the
			# day/night open-world fallback in either case.
			var raw = payload.get("music_id", 0)
			MusicDirector.set_music_id(0 if raw == null else int(raw))
		PacketIds.DISCOVERY_UNLOCKED:
			# Server fires this once per (character, category, slug) on first
			# unlock. Show a system line in chat — no other UI yet.
			var name = payload.get("name", payload.get("slug", "?"))
			chat.append_system("Has descubierto: %s" % name)
		PacketIds.BROADCAST_MESSAGE:
			# Server-wide / city-scoped broadcasts (siege, governor bounty,
			# discoveries, system events). Renderer + click-link dispatcher
			# handles the full payload — see ChatController.
			if chat != null:
				chat.append_broadcast_message(payload)
		PacketIds.RECONNECT_PROMPT:
			# Defensive timing path: server is supposed to fire this on
			# the post-auth flow (character_select handles it there), but
			# if the client has already entered the world by the time the
			# packet arrives, we still want to show the prompt rather
			# than push_error on it. Same modal, same response packet.
			if reconnect_modal_controller != null:
				reconnect_modal_controller.handle_prompt(payload)
		_:
			push_error("DRIFT or MALICIOUS: unknown packet_id 0x%04x" % packet_id)

func _handle_player_spawn(payload: Dictionary):
	var id = payload.get("id", 0)
	var pos = Vector2i(payload.get("x", 0), payload.get("y", 0))
	var character_payload = payload.get("character", {})
	var char_name = character_payload.get("name", "?")
	# Prefer the new sprite_layers contract; fall back to the legacy
	# body_sprite_ref (single-Sprite2D atlas tile) until the server PR lands.
	var sprite_layers = character_payload.get("sprite_layers", null)
	var sprite_ref = character_payload.get("body_sprite_ref", null)

	var node: Node2D
	var layered: LayeredCharacter = null
	if sprite_layers is Dictionary:
		node = _create_layered_player_node(char_name, sprite_layers)
		# The LayeredCharacter is the first child we added — find it for animation drive.
		for child in node.get_children():
			if child is LayeredCharacter:
				layered = child
				break
	else:
		node = _create_entity_node(char_name, Color.CYAN, sprite_ref)
	node.position = Vector2(pos.x * _tile_size, pos.y * _tile_size)
	entities_layer.add_child(node)

	players[id] = {"pos": pos, "name": char_name, "node": node, "layered": layered}
	hud.add_message("%s appeared" % char_name)

func _handle_player_moved(payload: Dictionary):
	var id = payload.get("id", 0)
	if not (id in players):
		return
	var new_pos = Vector2i(payload.get("x", 0), payload.get("y", 0))
	var prev_pos: Vector2i = players[id].pos
	players[id].pos = new_pos
	var node = players[id].node
	if node == null:
		return
	var target = Vector2(new_pos.x * _tile_size, new_pos.y * _tile_size)
	# Smooth-walk the other player's sprite over MOVE_INTERVAL — same cadence
	# as our own player. Drives the LayeredCharacter walk animation in lockstep.
	# (Implicitly fixes the parked "other players snap" follow-up.)
	var layered: LayeredCharacter = players[id].get("layered", null)
	var dx: int = new_pos.x - prev_pos.x
	var dy: int = new_pos.y - prev_pos.y
	if layered != null:
		layered.set_direction(CharacterDirection.from_delta(dx, dy))
		layered.set_walking(true)
	var tween := create_tween()
	tween.tween_property(node, "position", target, MOVE_INTERVAL)
	if layered != null:
		var stop_walking := func():
			if is_instance_valid(layered):
				layered.set_walking(false)
		tween.finished.connect(stop_walking, CONNECT_ONE_SHOT)

func _handle_player_despawn(payload: Dictionary):
	var id = payload.get("id", 0)
	if id in players:
		hud.add_message("%s left" % players[id].name)
		players[id].node.queue_free()
		players.erase(id)

func _handle_npc_spawn(payload: Dictionary):
	var id = payload.get("npc_id", 0)
	var pos = Vector2i(payload.get("x", 0), payload.get("y", 0))
	var npc_name = payload.get("name", "NPC")
	var hp = payload.get("hp", 0)
	var max_hp = payload.get("max_hp", 0)
	# Prefer the new sprite_layers contract (body_id + nullable head_id); fall
	# back to the legacy single-Sprite2D sprite_ref while the server PR is
	# unmerged. Once both PRs land the legacy path can be removed.
	var sprite_layers = payload.get("sprite_layers", null)
	var sprite_ref = payload.get("sprite_ref", null)

	if id in npcs and npcs[id].has("node"):
		npcs[id].node.queue_free()

	var node: Node2D
	var layered: LayeredCharacter = null
	if sprite_layers is Dictionary:
		node = _create_layered_npc_node(npc_name, sprite_layers)
		for child in node.get_children():
			if child is LayeredCharacter:
				layered = child
				break
	else:
		node = _create_entity_node(npc_name, Color.RED, sprite_ref)
	node.position = Vector2(pos.x * _tile_size, pos.y * _tile_size)
	entities_layer.add_child(node)

	npcs[id] = {"pos": pos, "name": npc_name, "hp": hp, "max_hp": max_hp, "node": node, "layered": layered}

func _handle_npc_moved(payload: Dictionary):
	var id = int(payload.get("npc_id", 0))
	if not (id in npcs):
		return
	var prev_pos: Vector2i = npcs[id].pos
	var pos = Vector2i(int(payload.get("x", 0)), int(payload.get("y", 0)))
	npcs[id].pos = pos
	# Glide the sprite over the server's NPC_MOVE_INTERVAL_MS (~380ms) for the
	# same AO-style smooth-walk feel as the player. Snap if no node yet.
	var node = npcs[id].get("node")
	if node == null:
		return
	var target = Vector2(pos.x * _tile_size, pos.y * _tile_size)
	# Drive walk animation on the LayeredCharacter (when present) in lockstep
	# with the position tween — direction from delta, walking=true while the
	# tween runs, stop on the last facing direction's frame 0 at end.
	var layered: LayeredCharacter = npcs[id].get("layered", null)
	var dx: int = pos.x - prev_pos.x
	var dy: int = pos.y - prev_pos.y
	if layered != null:
		layered.set_direction(CharacterDirection.from_delta(dx, dy))
		layered.set_walking(true)
	var tween = create_tween()
	tween.tween_property(node, "position", target, 0.38)
	if layered != null:
		var stop_walking := func():
			if is_instance_valid(layered):
				layered.set_walking(false)
		tween.finished.connect(stop_walking, CONNECT_ONE_SHOT)

func _handle_npc_death(payload: Dictionary):
	var id = payload.get("npc_id", 0)
	if id in npcs:
		hud.add_message("%s died!" % npcs[id].name)
		npcs[id].node.queue_free()
		npcs.erase(id)

func _handle_map_transition(payload: Dictionary):
	map_id = payload.get("map_id", 1)
	my_pos = Vector2i(payload.get("x", 50), payload.get("y", 50))
	map_size = Vector2i(payload.get("width", 100), payload.get("height", 100))

	for id in players:
		players[id].node.queue_free()
	players.clear()
	for id in npcs:
		npcs[id].node.queue_free()
	npcs.clear()
	for id in ground_items:
		ground_items[id].node.queue_free()
	ground_items.clear()
	for id in chests:
		chests[id].node.queue_free()
	chests.clear()

	# Same ordering constraint as on initial world-entry.
	_render_ground()
	_update_player_position()
	hud.add_message("Map %d (%dx%d)" % [map_id, map_size.x, map_size.y])

func _handle_damage(payload: Dictionary):
	var dmg = int(payload.get("damage", 0))
	var type = payload.get("type", "")
	var xp = int(payload.get("xp", 0))
	var gold = int(payload.get("gold", 0))
	var target_id = int(payload.get("target_id", 0))

	if type == "gold":
		hud.add_message("+%d gold" % gold)
	elif dmg < 0:
		hud.add_message("Healed %d HP" % (-dmg))
	else:
		var msg = "%d %s damage" % [dmg, type]
		if xp > 0:
			msg += " [+%d XP]" % xp
		hud.add_message(msg)

	# Floating number above the target.
	var target_node = _resolve_damage_target(target_id)
	if target_node == null:
		return
	if type == "gold":
		_spawn_floating(target_node, "+%d gold" % gold, Color(1, 0.85, 0.2))
	elif dmg < 0:
		_spawn_floating(target_node, "+%d" % (-dmg), Color(0.3, 1, 0.3))
	elif dmg > 0:
		var color = Color(1, 0.35, 0.35) if type == "physical" else Color(0.5, 0.7, 1)
		_spawn_floating(target_node, "-%d" % dmg, color)

func _resolve_damage_target(target_id: int) -> Node2D:
	if target_id in npcs:
		return npcs[target_id].node
	if target_id in players:
		return players[target_id].node
	return null

func _spawn_floating(target_node: Node2D, text: String, color: Color):
	var label = Label.new()
	label.text = text
	label.position = Vector2(4, -6)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", 14)
	label.z_index = 50 # above sprites
	target_node.add_child(label)

	var tween = create_tween().set_parallel(true)
	tween.tween_property(label, "position:y", -38, 1.0)
	tween.tween_property(label, "modulate:a", 0.0, 1.0).set_delay(0.3)
	# Don't chain a tween_callback — capturing `label` in a lambda blows up if the
	# target_node is freed mid-tween. An async await on self survives that.
	_free_after(label, 1.1)

func _free_after(node: Node, secs: float):
	await get_tree().create_timer(secs).timeout
	if is_instance_valid(node):
		node.queue_free()

func _clear_chat_bubble(from_id):
	var target: Node2D = null
	if from_id is int or from_id is float:
		if int(from_id) in players:
			target = players[int(from_id)].node
	if target == null:
		target = player_sprite # ourselves
	var existing = target.get_node_or_null("ChatBubble")
	if existing:
		existing.queue_free()

func _show_chat_bubble(from_id, msg: String):
	var target_node: Node2D = null

	if from_id == null:
		return

	if from_id is int or from_id is float:
		if int(from_id) in players:
			target_node = players[int(from_id)].node

	if target_node == null:
		target_node = player_sprite

	var existing = target_node.get_node_or_null("ChatBubble")
	if existing:
		existing.queue_free()

	var bubble = Label.new()
	bubble.name = "ChatBubble"
	bubble.text = msg
	bubble.position = Vector2(0, -32)
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bubble.add_theme_font_size_override("font_size", 10)
	bubble.add_theme_color_override("font_color", Color.WHITE)
	target_node.add_child(bubble)

	_free_after(bubble, 3.0)

func _handle_ground_item_spawn(payload: Dictionary):
	var id = int(payload.get("ground_id", 0))
	var pos = Vector2i(int(payload.get("x", 0)), int(payload.get("y", 0)))
	var item_data = payload.get("item_data", {})
	var amount = int(payload.get("amount", 1))

	# Replace if already present (map re-entry, etc.)
	if id in ground_items and ground_items[id].has("node"):
		ground_items[id].node.queue_free()

	# Stack badge: small "xN" overlay on the corner. Empty when amount == 1
	# so the icon is not cluttered with a redundant "x1".
	var amount_text := "" if amount <= 1 else "x%d" % amount

	# Server-side ground-item-icons PR ships icon_grh_id in item_data.
	# When present and the catalog resolves, render the actual Cucsi
	# sprite. Otherwise fall back to the legacy yellow-rect placeholder
	# (server pre-PR, or item type without an icon mapping).
	var icon_grh_id := ground_item_icon_grh_id(item_data)
	var node: Node2D = null
	if icon_grh_id > 0:
		node = _create_ground_item_sprite_node(icon_grh_id, amount_text)
	if node == null:
		var nm: String = item_data.get("name", "?")
		var label_text = nm.substr(0, min(4, nm.length()))
		if amount_text != "":
			label_text = "%s\n%s" % [label_text, amount_text]
		node = _create_ground_item_node(label_text)

	node.position = Vector2(pos.x * _tile_size, pos.y * _tile_size)
	ground_items_layer.add_child(node)

	ground_items[id] = {"pos": pos, "node": node, "item_data": item_data, "amount": amount}

func _handle_hide_state_changed(payload: Dictionary):
	var id = int(payload.get("id", 0))
	var hidden = bool(payload.get("hidden", false))
	if id == _self_id:
		_apply_self_hidden(hidden)
	elif id in players:
		_apply_other_hidden(id, hidden)

func _apply_self_hidden(hidden: bool):
	var name_label = $PlayerSprite/NameLabel
	if hidden:
		# Green + 20% opacity (see-through to self; reinforces "oculto" state).
		player_sprite.modulate = Color(1, 1, 1, 0.2)
		name_label.add_theme_color_override("font_color", Color(1, 1, 0.2, 1)) # yellow
	else:
		player_sprite.modulate = Color(1, 1, 1, 1)
		name_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))

func _apply_other_hidden(id: int, hidden: bool):
	var node = players[id].node
	node.modulate = Color(1, 1, 1, 0.2) if hidden else Color(1, 1, 1, 1)

func _handle_ground_item_despawn(payload: Dictionary):
	var id = int(payload.get("ground_id", 0))
	if id in ground_items:
		ground_items[id].node.queue_free()
		ground_items.erase(id)

# --- Ground item dispatch helper ---

# Pure-data decision: given the GROUND_ITEM_SPAWN payload's `item_data`,
# return the icon GRH id we should try to render (>0 means "build a
# sprite-based node"; 0 means "fall back to the yellow-rect placeholder").
# Static so the dispatch logic is testable without standing up the world
# scene tree. The render path itself (catalog lookup, AtlasTexture
# construction) lives in _create_ground_item_sprite_node and is exercised
# at runtime against the real catalog.
static func ground_item_icon_grh_id(item_data) -> int:
	if not (item_data is Dictionary):
		return 0
	var raw = item_data.get("icon_grh_id", 0)
	var iid := int(raw)
	return iid if iid > 0 else 0


# --- Chests ---

# Cardinal-adjacency check (Manhattan distance == 1). Mirrors the server's
# Npc#in_attack_range? rule for chest interaction. Static so unit tests can
# exercise the helper without a live world instance.
static func find_adjacent_chest(player_pos: Vector2i, chest_dict: Dictionary) -> int:
	for chest_id in chest_dict:
		var entry = chest_dict[chest_id]
		var pos: Vector2i = entry.get("pos", Vector2i.ZERO)
		# Closed chests only — opened ones are visually present but already looted.
		if entry.get("state", "closed") != "closed":
			continue
		var dx: int = abs(pos.x - player_pos.x)
		var dy: int = abs(pos.y - player_pos.y)
		if dx + dy == 1:
			return int(chest_id)
	return -1

func _try_open_adjacent_chest():
	var chest_id := find_adjacent_chest(my_pos, chests)
	if chest_id == -1:
		hud.add_message("No hay cofre adyacente")
		return
	connection.send_packet(PacketIds.CHEST_OPEN, {"chest_id": chest_id})

func _handle_chest_spawn(payload: Dictionary):
	var id = int(payload.get("chest_id", 0))
	var pos = Vector2i(int(payload.get("x", 0)), int(payload.get("y", 0)))
	var state = String(payload.get("state", "closed"))
	var sprite_ref = payload.get("sprite_ref", null)

	if id in chests and chests[id].has("node"):
		chests[id].node.queue_free()

	var node = _create_chest_node(state, sprite_ref)
	node.position = Vector2(pos.x * _tile_size, pos.y * _tile_size)
	chests_layer.add_child(node)

	chests[id] = {"pos": pos, "state": state, "node": node}

func _handle_chest_opened(payload: Dictionary):
	var id = int(payload.get("chest_id", 0))
	if not (id in chests):
		return
	chests[id].state = "opened"
	# Visual swap: tint the placeholder, or recolor the open marker. The
	# closed/opened distinction is mostly state — loot ground-spawns via
	# GROUND_ITEM_SPAWN, which is already wired.
	var node = chests[id].node
	if node != null and is_instance_valid(node):
		var rect = node.get_node_or_null("Rect")
		if rect != null and rect is ColorRect:
			(rect as ColorRect).color = Color(0.45, 0.30, 0.10) # darker, "opened lid"
		var label = node.get_node_or_null("Label")
		if label != null and label is Label:
			(label as Label).text = "cofre*"

func _handle_chest_despawn(payload: Dictionary):
	var id = int(payload.get("chest_id", 0))
	if id in chests:
		chests[id].node.queue_free()
		chests.erase(id)

func _create_chest_node(state: String, sprite_ref) -> Node2D:
	# Server may ship a sprite_ref atlas region; fall back to a brown
	# ColorRect placeholder. Wiring is the goal; art polish lands later.
	var node = Node2D.new()

	var sprite := _make_entity_sprite(sprite_ref)
	if sprite != null:
		node.add_child(sprite)
	else:
		var rect = ColorRect.new()
		rect.name = "Rect"
		rect.size = Vector2(_tile_size - 8, _tile_size - 8)
		rect.position = Vector2(4, 4)
		# closed = warm brown; opened gets darkened by _handle_chest_opened
		rect.color = Color(0.65, 0.42, 0.18) if state == "closed" else Color(0.45, 0.30, 0.10)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		node.add_child(rect)

		var label = Label.new()
		label.name = "Label"
		label.text = "cofre" if state == "closed" else "cofre*"
		label.position = Vector2(-8, -16)
		label.size = Vector2(_tile_size + 16, 14)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_font_size_override("font_size", 9)
		label.add_theme_color_override("font_color", Color(1, 0.92, 0.7, 1))
		node.add_child(label)

	return node

func _create_ground_item_node(text: String) -> Node2D:
	var node = Node2D.new()

	var rect = ColorRect.new()
	rect.size = Vector2(_tile_size - 10, _tile_size - 10)
	rect.position = Vector2(5, 5)
	rect.color = Color(0.9, 0.8, 0.3)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.add_child(rect)

	var label = Label.new()
	label.text = text
	label.position = Vector2(-8, -18)
	label.size = Vector2(48, 16)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 8)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	node.add_child(label)

	return node


# Resolve a Cucsi GRH id through SpriteCatalog and build a Sprite2D that
# crops the upscaled atlas via AtlasTexture. Returns null on missing
# catalog entry, missing PNG, or any other resolve failure: caller is
# expected to fall back to the placeholder. Each missing icon_grh_id is
# logged exactly once via _warned_missing_item_icons to keep the console
# usable when many of the same item drop.
func _create_ground_item_sprite_node(icon_grh_id: int, amount_text: String) -> Node2D:
	var entry = SpriteCatalog.item_icon(icon_grh_id)
	if not (entry is Dictionary):
		if not _warned_missing_item_icons.has(icon_grh_id):
			_warned_missing_item_icons[icon_grh_id] = true
			push_warning("[ground_items] no sprite_catalog entry for icon_grh_id=%d (re-run tools/parse_cucsi_graphics.py?)" % icon_grh_id)
		return null

	var file_name: String = String(entry.get("file", ""))
	if file_name == "":
		return null
	var atlas_path := "res://assets/upscaled_2x/" + file_name
	if not ResourceLoader.exists(atlas_path):
		if not _warned_missing_item_icons.has(icon_grh_id):
			_warned_missing_item_icons[icon_grh_id] = true
			push_warning("[ground_items] icon_grh_id=%d resolved to missing file %s" % [icon_grh_id, atlas_path])
		return null
	var base_tex: Texture2D = load(atlas_path)
	if base_tex == null:
		return null

	var region_data = entry.get("region", {})
	if not (region_data is Dictionary):
		return null
	var atlas := AtlasTexture.new()
	atlas.atlas = base_tex
	atlas.region = Rect2(
		float(region_data.get("x", 0)),
		float(region_data.get("y", 0)),
		float(region_data.get("w", 0)),
		float(region_data.get("h", 0)),
	)
	atlas.filter_clip = true

	var node := Node2D.new()
	var sprite := Sprite2D.new()
	sprite.texture = atlas
	sprite.centered = false
	# Center the icon over the tile. Cucsi icons are typically 32x32 in
	# source (64x64 after the parser doubling). Fit it inside one tile
	# and center it horizontally + vertically.
	var iw := float(region_data.get("w", _tile_size))
	var ih := float(region_data.get("h", _tile_size))
	var scale := 1.0
	var max_dim: float = max(iw, ih)
	if max_dim > 0.0 and max_dim > float(_tile_size):
		scale = float(_tile_size) / max_dim
	sprite.scale = Vector2(scale, scale)
	sprite.position = Vector2(
		(float(_tile_size) - iw * scale) * 0.5,
		(float(_tile_size) - ih * scale) * 0.5,
	)
	node.add_child(sprite)

	if amount_text != "":
		var label := Label.new()
		label.text = amount_text
		# Bottom-right corner of the tile.
		label.position = Vector2(_tile_size - 22, _tile_size - 16)
		label.size = Vector2(20, 14)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_font_size_override("font_size", 9)
		label.add_theme_color_override("font_color", Color(1, 1, 0.4, 1))
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
		label.add_theme_constant_override("outline_size", 2)
		node.add_child(label)

	return node

func _create_layered_player_node(entity_name: String, sprite_layers: Dictionary) -> Node2D:
	# Other-player rendering: a Node2D that owns a LayeredCharacter (5
	# AnimatedSprite2D children) plus a name label. Mirrors what the local
	# player gets under $PlayerSprite, just constructed programmatically.
	var node := Node2D.new()
	var layered := LayeredCharacter.new()
	layered.set_tile_size(_tile_size)
	layered.apply_layers(sprite_layers)
	node.add_child(layered)

	var label = Label.new()
	label.text = entity_name
	label.position = Vector2(-30, _tile_size + 2)
	label.size = Vector2(92, 16)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 10)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.add_child(label)

	return node


func _create_layered_npc_node(entity_name: String, sprite_layers: Dictionary) -> Node2D:
	# NPC rendering: same layered pipeline as players, but head_id may be null
	# (non-humanoid NPCs — animals, golems, etc.) and helmet/weapon/shield are
	# never sent for NPCs. LayeredCharacter handles all of that internally.
	var node := Node2D.new()
	var layered := LayeredCharacter.new()
	layered.set_tile_size(_tile_size)
	layered.apply_layers(sprite_layers)
	node.add_child(layered)

	var label = Label.new()
	label.text = entity_name
	label.position = Vector2(-30, _tile_size + 2)
	label.size = Vector2(92, 16)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 10)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color", Color(1, 0.6, 0.6))
	node.add_child(label)

	return node


func _create_entity_node(entity_name: String, color: Color, sprite_ref = null) -> Node2D:
	var node = Node2D.new()

	# Prefer a real sprite when the server sends one (NPCs + players with
	# body_sprite_ref). Fall back to the legacy colored square if the ref is
	# missing or the atlas file can't be resolved — keeps the old rendering
	# path alive for entities that haven't been art-wired yet.
	var sprite := _make_entity_sprite(sprite_ref)
	if sprite != null:
		node.add_child(sprite)
	else:
		var rect = ColorRect.new()
		rect.size = Vector2(_tile_size - 2, _tile_size - 2)
		rect.position = Vector2(1, 1)
		rect.color = color
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		node.add_child(rect)

	var label = Label.new()
	label.text = entity_name
	label.position = Vector2(-30, _tile_size + 2)
	label.size = Vector2(92, 16)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 10)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.add_child(label)

	return node


func _apply_self_body_sprite(sprite_ref):
	# Own player renders via the $PlayerSprite node (scene-authored, not
	# server-spawned like other entities). If the server shipped a
	# body_sprite_ref, hide the placeholder ColorRect and mount a Sprite2D
	# in its place so we match how NPCs / other players are drawn.
	var sprite := _make_entity_sprite(sprite_ref)
	if sprite == null:
		return
	$PlayerSprite/Rect.hide()
	# Remove any previously-added body sprite (in case this gets called
	# twice, e.g. on map transition).
	for existing in $PlayerSprite.get_children():
		if existing is Sprite2D and existing.name == "BodySprite":
			existing.queue_free()
	sprite.name = "BodySprite"
	$PlayerSprite.add_child(sprite)


func _handle_player_layers_update(payload: Dictionary) -> void:
	# Self update — server may use this packet for both self and others; the
	# self path also fires on INVENTORY_UPDATE (which has more useful side
	# effects than just layers), but mirroring it here keeps both code paths
	# resilient to either packet arriving alone.
	var id = int(payload.get("id", -1))
	var sprite_layers = payload.get("sprite_layers", null)
	if not (sprite_layers is Dictionary):
		return
	if id == _self_id:
		_apply_self_sprite_layers(sprite_layers)
		return
	if not (id in players):
		# Edge case: target not on-map (off-screen broadcast, just-despawned).
		# Drop silently.
		return
	var layered: LayeredCharacter = players[id].get("layered", null)
	if layered == null:
		# Legacy single-Sprite2D path — nothing to update at the layer level.
		return
	layered.apply_layers(sprite_layers)


func _handle_effect_start(payload: Dictionary) -> void:
	var target_id = int(payload.get("target_id", -1))
	var effect_id = int(payload.get("effect_id", -1))
	if effect_id < 0:
		push_warning("[world] EFFECT_START missing effect_id, payload=%s" % payload)
		return
	var layered := _resolve_layered(target_id)
	if layered == null:
		# Target off-map / unknown id — silently drop, server will resync if
		# they re-enter our visibility radius.
		return
	layered.start_effect(effect_id)


func _handle_effect_stop(payload: Dictionary) -> void:
	var target_id = int(payload.get("target_id", -1))
	var effect_id = int(payload.get("effect_id", -1))
	if effect_id < 0:
		push_warning("[world] EFFECT_STOP missing effect_id, payload=%s" % payload)
		return
	var layered := _resolve_layered(target_id)
	if layered == null:
		return
	layered.stop_effect(effect_id)


func _resolve_layered(entity_id: int) -> LayeredCharacter:
	# Effects can target the local player, other players, or NPCs. NPCs not
	# wired today — server doesn't broadcast effects on creatures yet — but
	# the lookup is symmetric so future packets just work.
	if entity_id == _self_id:
		return _self_layered
	if entity_id in players:
		return players[entity_id].get("layered", null)
	if entity_id in npcs:
		return npcs[entity_id].get("layered", null)
	return null


func _apply_self_sprite_layers(sprite_layers: Dictionary) -> void:
	# New rendering path: 5-layer LayeredCharacter mounted under PlayerSprite.
	# Layers we render in lockstep — body and head always; helmet/weapon/shield
	# only when the server names them.
	$PlayerSprite/Rect.hide()
	# Tear down legacy single-Sprite2D path if it had been mounted.
	for existing in $PlayerSprite.get_children():
		if existing is Sprite2D and existing.name == "BodySprite":
			existing.queue_free()
	var first_mount := false
	if _self_layered == null:
		_self_layered = LayeredCharacter.new()
		_self_layered.name = "LayeredCharacter"
		_self_layered.set_tile_size(_tile_size)
		$PlayerSprite.add_child(_self_layered)
		first_mount = true
	else:
		_self_layered.set_tile_size(_tile_size)
	# Only seed direction + idle on the very first mount; later re-applies
	# (e.g. equip mid-walk) preserve whatever direction/walking state the
	# LayeredCharacter is already driving so the cycle doesn't snap.
	if first_mount:
		_self_layered.set_direction(my_heading)
		_self_layered.set_walking(false)
	_self_layered.apply_layers(sprite_layers)


func _make_entity_sprite(sprite_ref) -> Sprite2D:
	# sprite_ref is a Dictionary from MessagePack: {file, sx, sy, w, h}. nil
	# or missing fields -> return null and let caller use the fallback square.
	if sprite_ref == null or not (sprite_ref is Dictionary):
		return null
	if not sprite_ref.has("file"):
		return null
	# Anchor sprite to the tile's bottom-center (Cucsi convention) so tall
	# bodies overflow upward and read naturally against the grid.
	var texture := _get_map_texture(sprite_ref)
	if texture == null:
		return null
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.centered = false
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var w: int = int(sprite_ref.get("w", _tile_size))
	var h: int = int(sprite_ref.get("h", _tile_size))
	sprite.position = Vector2(-(w - _tile_size) / 2.0, -(h - _tile_size))
	return sprite
