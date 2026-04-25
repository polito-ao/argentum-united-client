extends Node2D

# Base tile size in the Cucsi .map files; the real render uses `_tile_size`
# below, which is driven by the per-map JSON (64 for the 2x-upscaled pipeline,
# falls back to this constant if the JSON is missing the field).
const FALLBACK_TILE_SIZE := 32
const INVENTORY_SLOTS = 35 # 5 wide × 7 tall grid (capacity is 30; last row is visual padding for now)

# Map rendering — mirrors the dev ulla_preview scene. The JSON produced by
# scripts/parse_map_binary.py + scripts/apply_floor_catalog.py drives everything:
#   tile_size, graficos_root, floors_root, per-grh lookup entries (atlas region
#   for L2-4 or {floor:true, file} for individualised L1 floor tiles).
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
var ground_items: Dictionary = {}  # ground_id -> { pos: Vector2i, node: Node2D }

@onready var camera: Camera2D = $Camera
@onready var ground_layer: Node2D = $Ground
@onready var player_sprite: Node2D = $PlayerSprite
@onready var entities_layer: Node2D = $Entities
@onready var ground_items_layer: Node2D = $GroundItems

# HUD — interactive widgets that stay in world.gd for now.
# Read-update widgets (HP/MP/XP/stats/equipment/level/name/city/messages/fps/position)
# moved to HUDController; constructed in _ready(). Inventory grid, spells tabs,
# settings overlay, and drop dialog are next-pass extractions.
@onready var chat_display: RichTextLabel = $UILayer/HUD/ChatPanel/ChatVBox/ChatDisplay
@onready var chat_input: LineEdit = $UILayer/HUD/ChatPanel/ChatVBox/ChatInput
@onready var minimap: Control = $UILayer/HUD/MinimapPanel/Minimap

@onready var help_button: Button = $UILayer/HUD/RightPanel/VBox/ButtonBar/HelpButton
@onready var settings_button: Button = $UILayer/HUD/RightPanel/VBox/ButtonBar/SettingsButton

@onready var inventory_grid: GridContainer = $UILayer/HUD/RightPanel/VBox/InvTabs/Inventario
@onready var spell_list: ItemList = $UILayer/HUD/RightPanel/VBox/InvTabs/Hechizos/SpellList
@onready var lanzar_button: Button = $UILayer/HUD/RightPanel/VBox/InvTabs/Hechizos/LanzarButton

@onready var quests_button: Button = $UILayer/HUD/RightPanel/VBox/StatsTabs/STATS/SplitRow/LeftCol/QuestsButton

var hud: HUDController

# HUD — drop-amount dialog
@onready var drop_amount_overlay: Control = $UILayer/HUD/DropAmountOverlay
@onready var drop_amount_input: LineEdit = $UILayer/HUD/DropAmountOverlay/Panel/VBox/AmountInput
@onready var drop_confirm_button: Button = $UILayer/HUD/DropAmountOverlay/Panel/VBox/ButtonBar/ConfirmButton
@onready var drop_cancel_button: Button = $UILayer/HUD/DropAmountOverlay/Panel/VBox/ButtonBar/CancelButton

# HUD — settings overlay (hidden by default)
@onready var settings_overlay: Control = $UILayer/HUD/SettingsOverlay
@onready var bindings_grid: GridContainer = $UILayer/HUD/SettingsOverlay/Panel/VBox/BindingsGrid
@onready var defaults_button: Button = $UILayer/HUD/SettingsOverlay/Panel/VBox/ButtonBar/DefaultsButton
@onready var cancel_settings_button: Button = $UILayer/HUD/SettingsOverlay/Panel/VBox/ButtonBar/CancelButton
@onready var save_settings_button: Button = $UILayer/HUD/SettingsOverlay/Panel/VBox/ButtonBar/SaveButton

var _minimap_drawer: _MinimapDrawer
var _is_dead: bool = false

# Spellbook for this character — populated from server config in setup() based on
# class + level. Empty for non-caster classes or levels below the lowest learn_level.
var _my_spells: Array = []
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
}

var bindings: Dictionary = DEFAULT_BINDINGS.duplicate()
var _pending_bindings: Dictionary = {}
var _capturing_action: String = ""
var _capturing_button: Button = null
# Focused inventory slot — target of USE_ITEM / EQUIP_ITEM. -1 means no selection.
var _focused_slot: int = -1
# Local mirror of the server's inventory (same shape as INVENTORY_UPDATE.inventory).
# Needed for UI decisions like "prompt for amount if stack > 1" on drop.
var _inventory: Array = []
# Drop-amount dialog state
var _drop_pending_slot: int = -1
var _drop_pending_max: int = 0

func setup(conn: ServerConnection, select_payload: Dictionary, map_data: Dictionary):
	connection = conn
	connection.packet_received.connect(_on_packet_received)
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

	# Inventory — build the grid once, then populate from state
	_build_inventory_slots()
	_inventory = state.get("inventory", [])
	_render_inventory(_inventory)

	# Restore persisted key bindings (server-side JSONB state)
	_apply_saved_bindings(state.get("key_bindings", {}))

	if not state.get("alive", true):
		_is_dead = true
		hud.add_message("You are a ghost. Press SPACE to respawn.")

	# _render_ground must run FIRST — it reads tile_size + graficos_root from
	# the JSON. Otherwise _update_player_position uses the fallback tile size
	# AND _apply_self_body_sprite can't resolve its atlas (graficos_root is
	# still empty at this point, so _get_map_texture returns null).
	_render_ground()
	_apply_self_body_sprite(character.get("body_sprite_ref", null))
	_update_player_position()
	_setup_minimap()

func _ready():
	hud = HUDController.new({
		hp_bar         = $UILayer/HUD/RightPanel/VBox/StatsTabs/STATS/HPBar,
		hp_text        = $UILayer/HUD/RightPanel/VBox/StatsTabs/STATS/HPBar/HPText,
		mp_bar         = $UILayer/HUD/RightPanel/VBox/StatsTabs/STATS/MPBar,
		mp_text        = $UILayer/HUD/RightPanel/VBox/StatsTabs/STATS/MPBar/MPText,
		xp_bar         = $UILayer/HUD/RightPanel/VBox/XPBar,
		xp_label       = $UILayer/HUD/RightPanel/VBox/XPLabel,
		level_label    = $UILayer/HUD/RightPanel/VBox/HeaderRow/LevelLabel,
		name_label     = $UILayer/HUD/RightPanel/VBox/HeaderRow/HeaderInfo/NameLabel,
		city_label     = $UILayer/HUD/RightPanel/VBox/HeaderRow/HeaderInfo/CityLabel,
		str_label      = $UILayer/HUD/RightPanel/VBox/StatsTabs/STATS/SplitRow/LeftCol/StrLabel,
		cele_label     = $UILayer/HUD/RightPanel/VBox/StatsTabs/STATS/SplitRow/LeftCol/CeleLabel,
		gold_label     = $UILayer/HUD/RightPanel/VBox/StatsTabs/STATS/SplitRow/RightCol/GoldLabel,
		eq_helm        = $UILayer/HUD/RightPanel/VBox/EquipmentRow/Helm/Value,
		eq_armor       = $UILayer/HUD/RightPanel/VBox/EquipmentRow/Armor/Value,
		eq_weapon      = $UILayer/HUD/RightPanel/VBox/EquipmentRow/Weapon/Value,
		eq_shield      = $UILayer/HUD/RightPanel/VBox/EquipmentRow/Shield/Value,
		eq_magres      = $UILayer/HUD/RightPanel/VBox/EquipmentRow/MagRes/Value,
		position_label = $UILayer/HUD/RightPanel/VBox/ButtonBar/PositionLabel,
		fps_label      = $UILayer/HUD/RightPanel/VBox/ButtonBar/FPSLabel,
		messages_label = $UILayer/HUD/MessagesLabel,
	})

	chat_input.text_submitted.connect(_on_chat_submitted)
	help_button.pressed.connect(func(): hud.add_message("Help — coming soon"))
	settings_button.pressed.connect(_show_settings)
	quests_button.pressed.connect(func(): hud.add_message("Quests — coming soon"))
	lanzar_button.pressed.connect(_on_lanzar_pressed)
	defaults_button.pressed.connect(func(): hud.add_message("Defaults — coming soon"))
	cancel_settings_button.pressed.connect(_hide_settings)
	save_settings_button.pressed.connect(_on_save_settings)
	drop_confirm_button.pressed.connect(_on_drop_confirm)
	drop_cancel_button.pressed.connect(_hide_drop_dialog)
	drop_amount_input.text_submitted.connect(func(_t): _on_drop_confirm())
	_populate_spell_list()
	# Arrow keys drive movement; they must never be consumed by UI focus navigation.
	# TabContainer's internal TabBar has its own focus_mode that ignores ours — strip it here.
	$UILayer/HUD/RightPanel/VBox/InvTabs.get_tab_bar().focus_mode = Control.FOCUS_NONE
	$UILayer/HUD/RightPanel/VBox/StatsTabs.get_tab_bar().focus_mode = Control.FOCUS_NONE
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
	settings_overlay.visible = true

func _hide_settings():
	_capturing_action = ""
	_capturing_button = null
	settings_overlay.visible = false

func _on_save_settings():
	bindings = _pending_bindings.duplicate()
	# Server persists as-is; keys are Godot keycodes, opaque to the server.
	connection.send_packet(PacketIds.SETTINGS_SAVE, {"key_bindings": bindings})
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

# --- Drop-amount dialog ---

func _start_drop_from_focused_slot():
	if _focused_slot < 0:
		hud.add_message("Select an inventory slot first")
		return

	var item = _inventory[_focused_slot] if _focused_slot < _inventory.size() else null
	if item == null:
		return

	var amount = int(item.get("amount", 1))
	if amount <= 1:
		connection.send_packet(PacketIds.DROP_ITEM, {"slot": _focused_slot})
		return

	# Stacked — prompt for amount
	_drop_pending_slot = _focused_slot
	_drop_pending_max = amount
	drop_amount_input.text = str(amount)
	drop_amount_overlay.visible = true
	drop_amount_input.grab_focus()
	drop_amount_input.select_all()

func _on_drop_confirm():
	var raw = drop_amount_input.text.strip_edges()
	var amount = int(raw) if raw.is_valid_int() else 0
	amount = clamp(amount, 1, _drop_pending_max)
	connection.send_packet(PacketIds.DROP_ITEM, {"slot": _drop_pending_slot, "amount": amount})
	_hide_drop_dialog()

func _hide_drop_dialog():
	drop_amount_overlay.visible = false
	_drop_pending_slot = -1
	_drop_pending_max = 0
	drop_amount_input.release_focus()

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
	# Click-to-cast: only fires for clicks NOT absorbed by HUD Controls (buttons, tabs, chat).
	if not _casting_armed:
		return
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return

	var world_pos = get_global_mouse_position()
	var tile = Vector2i(int(world_pos.x / _tile_size), int(world_pos.y / _tile_size))
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
	# Outer loop = layer, so the plan is naturally in z-order.
	var _t_tiles := Time.get_ticks_msec()
	var draw_plan: Array = []
	var drawn := 0
	for layer_num in DRAW_LAYERS:
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
			draw_plan.append({"texture": texture, "dest": dest, "src": src})
			drawn += 1
	var drawer := _MapDrawer.new()
	drawer.draw_plan = draw_plan
	ground_layer.add_child(drawer)
	drawer.queue_redraw()
	var dt_tiles := Time.get_ticks_msec() - _t_tiles
	var dt_total := Time.get_ticks_msec() - _t_total
	print("[world] map %d: %d tiles drawn, tile_size=%d, cache=%d" % [map_id, drawn, _tile_size, MapTextureCache.count()])
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

	func _dot(world_pos: Vector2i, sz: Vector2, color: Color, radius: float):
		var px = (float(world_pos.x) / host.map_size.x) * sz.x
		var py = (float(world_pos.y) / host.map_size.y) * sz.y
		draw_circle(Vector2(px, py), radius, color)

# --- Inventory grid ---

func _build_inventory_slots():
	for child in inventory_grid.get_children():
		child.queue_free()
	for i in INVENTORY_SLOTS:
		var slot = _InventorySlot.new()
		slot.slot_index = i
		slot.clicked.connect(_on_inventory_slot_clicked)
		inventory_grid.add_child(slot)

func _render_inventory(items: Array):
	var slots = inventory_grid.get_children()
	for i in slots.size():
		var item = null
		if i < items.size():
			item = items[i]
		slots[i].set_item(item)
		if i == _focused_slot and item == null:
			_focused_slot = -1
	_refresh_focus_highlights()

func _on_inventory_slot_clicked(slot_index: int):
	var slot_node = inventory_grid.get_child(slot_index)
	# Toggle focus off if clicking the same slot, clear on empty slot, else set.
	if not slot_node.has_item:
		_focused_slot = -1
	elif _focused_slot == slot_index:
		_focused_slot = -1
	else:
		_focused_slot = slot_index
	_refresh_focus_highlights()

func _refresh_focus_highlights():
	for i in inventory_grid.get_child_count():
		inventory_grid.get_child(i).set_focused(i == _focused_slot)

class _InventorySlot extends PanelContainer:
	signal clicked(slot_index: int)
	var slot_index: int = -1
	var has_item: bool = false
	var label: Label
	const SLOT_SIZE = 42

	func _init():
		custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
		label = Label.new()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_font_size_override("font_size", 10)
		add_child(label)

	func _ready():
		gui_input.connect(_on_gui_input)

	func _on_gui_input(event):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			clicked.emit(slot_index)

	func set_focused(focused: bool):
		# Yellow tint when this slot is the USE/EQUIP target; full-color otherwise.
		modulate = Color(1.2, 1.2, 0.5, 1) if focused else Color(1, 1, 1, 1)

	func set_item(item):
		has_item = item != null
		if not has_item:
			label.text = ""
			return
		var data = item.get("item_data", {})
		var nm: String = data.get("name", "?")
		var amount = int(item.get("amount", 0))
		var short = nm.substr(0, min(3, nm.length())) if nm else "?"
		if amount > 1:
			label.text = "%s\nx%d" % [short, amount]
		else:
			label.text = short
		var color = Color(0.5, 1, 0.5) if item.get("equipped", false) else Color(1, 1, 1)
		label.add_theme_color_override("font_color", color)

# --- XP bar (thin wrapper — resolves the level threshold then delegates) ---

func _update_xp_bar(xp_in_level: int):
	hud.update_xp(xp_in_level, PacketIds.xp_for_level(my_level))

# --- Movement / player sprite ---

func _update_player_position():
	player_sprite.position = Vector2(my_pos.x * _tile_size, my_pos.y * _tile_size)
	camera.position = player_sprite.position + CAMERA_WORLD_OFFSET
	hud.set_position_label(map_id, my_pos.x, my_pos.y)
	if _minimap_drawer:
		_minimap_drawer.queue_redraw()

var _move_cooldown: float = 0.0
var _fps_cooldown: float = 0.0
var _minimap_cooldown: float = 0.0
const MOVE_INTERVAL: float = 0.15
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
	if not settings_overlay.visible and not drop_amount_overlay.visible:
		var focused = get_viewport().gui_get_focus_owner()
		if focused != null and focused != chat_input:
			get_viewport().gui_release_focus()

	if chat_input.has_focus() or settings_overlay.visible or drop_amount_overlay.visible:
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
	if drop_amount_overlay.visible:
		if event.keycode == KEY_ESCAPE and not event.echo:
			_hide_drop_dialog()
			get_viewport().set_input_as_handled()
		return

	# Settings overlay open — ignore world input (Escape closes).
	if settings_overlay.visible:
		if event.keycode == KEY_ESCAPE and not event.echo:
			_hide_settings()
			get_viewport().set_input_as_handled()
		return

	# Escape cancels an armed cast.
	if _casting_armed and event.keycode == KEY_ESCAPE and not event.echo:
		_cancel_armed_cast()
		get_viewport().set_input_as_handled()
		return

	# Typing in chat: let LineEdit have everything.
	if chat_input.has_focus():
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
			chat_input.grab_focus()
			chat_input.text = ""
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
			if _focused_slot < 0:
				hud.add_message("Select an inventory slot first")
			else:
				connection.send_packet(PacketIds.USE_ITEM, {"slot": _focused_slot})
		"equip_item":
			if _focused_slot < 0:
				hud.add_message("Select an inventory slot first")
			else:
				connection.send_packet(PacketIds.EQUIP_ITEM, {"slot": _focused_slot})
		"drop_item":
			_start_drop_from_focused_slot()
		"pickup_item":
			connection.send_packet(PacketIds.PICKUP_ITEM)
		"exit_to_select":
			connection.send_packet(PacketIds.EXIT_TO_SELECT)
		"hide":
			connection.send_packet(PacketIds.HIDE_TOGGLE)

func _send_move(dx: int, dy: int):
	var new_x = my_pos.x + dx
	var new_y = my_pos.y + dy

	if new_x < 0 or new_y < 0 or new_x >= map_size.x or new_y >= map_size.y:
		_update_player_sprite()
		return

	for npc_id in npcs:
		if npcs[npc_id].pos == Vector2i(new_x, new_y):
			_update_player_sprite()
			return

	for player_id in players:
		if players[player_id].pos == Vector2i(new_x, new_y):
			_update_player_sprite()
			return

	connection.send_packet(PacketIds.PLAYER_MOVE, {"x": new_x, "y": new_y})
	my_pos = Vector2i(new_x, new_y)
	_update_player_position()
	_update_player_sprite()

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

func _update_player_sprite():
	var arrow = {"north": "^", "south": "v", "east": ">", "west": "<"}
	$PlayerSprite/FacingLabel.text = arrow.get(my_heading, "v")

func _on_chat_submitted(text: String):
	if text.strip_edges().is_empty():
		connection.send_packet(PacketIds.CHAT_SEND, {"message": ""})
	else:
		connection.send_packet(PacketIds.CHAT_SEND, {"message": text})
	chat_input.text = ""
	chat_input.release_focus()

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
		PacketIds.SYSTEM_MESSAGE:
			hud.add_message(payload.get("text", ""))
		PacketIds.EXITED_TO_SELECT:
			_handle_exit_confirmed()
		PacketIds.CHAT_BROADCAST:
			var from_name = payload.get("from_name", null)
			var from_id = payload.get("from_id", null)
			var msg = payload.get("message", "")
			if from_name == null:
				from_name = "?"
			chat_display.append_text("[%s]: %s\n" % [from_name, msg])
			_show_chat_bubble(from_id, msg)
		PacketIds.CHAT_CLEAR:
			# Server tells us to drop the bubble over the given player (empty message).
			_clear_chat_bubble(payload.get("id", 0))
		PacketIds.INVENTORY_RESPONSE:
			_render_inventory(payload.get("items", []))
		PacketIds.INVENTORY_UPDATE:
			_inventory = payload.get("inventory", [])
			_render_inventory(_inventory)
			hud.update_equipment(payload.get("equipment", {}))
		PacketIds.GROUND_ITEM_SPAWN:
			_handle_ground_item_spawn(payload)
		PacketIds.GROUND_ITEM_DESPAWN:
			_handle_ground_item_despawn(payload)
		PacketIds.HIDE_STATE_CHANGED:
			_handle_hide_state_changed(payload)
		_:
			push_error("DRIFT or MALICIOUS: unknown packet_id 0x%04x" % packet_id)

func _handle_player_spawn(payload: Dictionary):
	var id = payload.get("id", 0)
	var pos = Vector2i(payload.get("x", 0), payload.get("y", 0))
	var character_payload = payload.get("character", {})
	var char_name = character_payload.get("name", "?")
	# Server stamps body_sprite_ref onto the character summary in bootstrap.rb;
	# nil-default means the old colored-square path still works.
	var sprite_ref = character_payload.get("body_sprite_ref", null)

	var node = _create_entity_node(char_name, Color.CYAN, sprite_ref)
	node.position = Vector2(pos.x * _tile_size, pos.y * _tile_size)
	entities_layer.add_child(node)

	players[id] = {"pos": pos, "name": char_name, "node": node}
	hud.add_message("%s appeared" % char_name)

func _handle_player_moved(payload: Dictionary):
	var id = payload.get("id", 0)
	if id in players:
		var pos = Vector2i(payload.get("x", 0), payload.get("y", 0))
		players[id].pos = pos
		players[id].node.position = Vector2(pos.x * _tile_size, pos.y * _tile_size)

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
	var sprite_ref = payload.get("sprite_ref", null)

	if id in npcs and npcs[id].has("node"):
		npcs[id].node.queue_free()

	var node = _create_entity_node(npc_name, Color.RED, sprite_ref)
	node.position = Vector2(pos.x * _tile_size, pos.y * _tile_size)
	entities_layer.add_child(node)

	npcs[id] = {"pos": pos, "name": npc_name, "hp": hp, "max_hp": max_hp, "node": node}

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

	var nm: String = item_data.get("name", "?")
	var label_text = nm.substr(0, min(4, nm.length()))
	if amount > 1:
		label_text = "%s\nx%d" % [label_text, amount]

	var node = _create_ground_item_node(label_text)
	node.position = Vector2(pos.x * _tile_size, pos.y * _tile_size)
	ground_items_layer.add_child(node)

	ground_items[id] = {"pos": pos, "node": node}

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
