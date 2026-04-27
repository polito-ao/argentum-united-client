extends Control

signal character_selected(character: Dictionary)

const CharacterCardScript = preload("res://scripts/ui/character_card.gd")
const CharacterCreateToggleScript = preload("res://scripts/ui/character_create_toggle.gd")
const RaceBaseAttrsScript = preload("res://scripts/ui/race_base_attrs.gd")
const ReconnectModalControllerScript = preload("res://scripts/ui/reconnect_modal_controller.gd")
const ReconnectModalScene := preload("res://scenes/match/reconnect_modal.tscn")

# How many characters can a player keep on one account.
const MAX_CHARACTERS := 3

@onready var char_list: VBoxContainer = $Panel/OuterHBox/LeftColumn/CharacterList
@onready var new_character_button: Button = $Panel/OuterHBox/LeftColumn/NewCharacterButton
@onready var create_panel: VBoxContainer = $Panel/OuterHBox/LeftColumn/CreatePanel
@onready var name_input: LineEdit = $Panel/OuterHBox/LeftColumn/CreatePanel/NameInput
@onready var class_selector: OptionButton = $Panel/OuterHBox/LeftColumn/CreatePanel/ClassSelector
@onready var race_selector: OptionButton = $Panel/OuterHBox/LeftColumn/CreatePanel/RaceSelector
@onready var create_button: Button = $Panel/OuterHBox/LeftColumn/CreatePanel/CreateButtonRow/CreateButton
@onready var cancel_button: Button = $Panel/OuterHBox/LeftColumn/CreatePanel/CreateButtonRow/CancelButton
@onready var status_label: Label = $Panel/OuterHBox/LeftColumn/StatusLabel
@onready var title_label: Label = $Panel/OuterHBox/LeftColumn/TitleLabel
@onready var logout_button: Button = $Panel/OuterHBox/LeftColumn/LogoutButton
@onready var logout_confirm: ConfirmationDialog = $LogoutConfirm
@onready var head_picker_label: Label = $Panel/OuterHBox/LeftColumn/CreatePanel/HeadPickerLabel
@onready var head_picker: HBoxContainer = $Panel/OuterHBox/LeftColumn/CreatePanel/HeadPicker
@onready var head_prev_button: Button = $Panel/OuterHBox/LeftColumn/CreatePanel/HeadPicker/HeadPrev
@onready var head_next_button: Button = $Panel/OuterHBox/LeftColumn/CreatePanel/HeadPicker/HeadNext
@onready var head_preview: Control = $Panel/OuterHBox/LeftColumn/CreatePanel/HeadPicker/HeadPreview
@onready var head_body_sprite: Sprite2D = $Panel/OuterHBox/LeftColumn/CreatePanel/HeadPicker/HeadPreview/BodySprite
@onready var head_head_sprite: Sprite2D = $Panel/OuterHBox/LeftColumn/CreatePanel/HeadPicker/HeadPreview/HeadSprite
@onready var head_loading_label: Label = $Panel/OuterHBox/LeftColumn/CreatePanel/HeadPicker/HeadPreview/HeadLoading
@onready var head_index_label: Label = $Panel/OuterHBox/LeftColumn/CreatePanel/HeadIndexLabel
@onready var head_random_button: Button = $Panel/OuterHBox/LeftColumn/CreatePanel/HeadRandomButton
@onready var preview_panel: VBoxContainer = $Panel/OuterHBox/PreviewPanel
@onready var preview_card_slot: VBoxContainer = $Panel/OuterHBox/PreviewPanel/PreviewCardSlot
@onready var background: TextureRect = $Background

var connection: ServerConnection
var head_picker_controller: HeadPickerController
var create_toggle: CharacterCreateToggle
var reconnect_modal_controller: ReconnectModalController
var preview_card # CharacterCard, lazily built
var _characters: Array = []
var _pending_select_payload: Dictionary = {}

var CLASSES: Array = []
var RACES: Array = []

func _ready() -> void:
	_apply_time_of_day_background()
	# Crossfade from the login theme into the character_select theme.
	# AudioPlayer is a global autoload; if the MP3 is missing on disk
	# the call silently no-ops.
	AudioPlayer.play_theme("character_select")


func _apply_time_of_day_background() -> void:
	var now := Time.get_time_dict_from_system()
	var hour := int(now.get("hour", 0))
	var minute := int(now.get("minute", 0))
	var path := "res://assets/cosmetics/background_character_select_%s_with_logo.PNG" % ("night" if _is_night(hour, minute) else "day")
	var tex := load(path)
	if tex != null and is_instance_valid(background):
		background.texture = tex


# Day/night boundary helper. Pure function -- safe to call from tests without
# instantiating the scene.
#
#   Night: 19:00 (inclusive) through 05:30 (exclusive)
#   Day:   05:30 (inclusive) through 19:00 (exclusive)
static func _is_night(hour: int, minute: int) -> bool:
	if hour >= 19:
		return true
	if hour < 5:
		return true
	if hour == 5 and minute < 30:
		return true
	return false


func setup(conn: ServerConnection):
	connection = conn
	connection.packet_received.connect(_on_packet_received)
	if not connection.disconnected.is_connected(_on_connection_lost):
		connection.disconnected.connect(_on_connection_lost)

	CLASSES = PacketIds.classes
	RACES = PacketIds.races

	class_selector.clear()
	for c in CLASSES:
		class_selector.add_item(c.capitalize())

	race_selector.clear()
	for r in RACES:
		race_selector.add_item(r.capitalize())

	create_button.pressed.connect(_on_create_pressed)
	logout_button.pressed.connect(func(): logout_confirm.popup_centered())
	logout_confirm.confirmed.connect(_on_logout_confirmed)

	# Visibility toggle for the creation form. Starts hidden; the
	# "+ Crear nuevo personaje" button reveals it, "Cancelar" hides again.
	create_toggle = CharacterCreateToggleScript.new({
		create_panel  = create_panel,
		preview_panel = preview_panel,
		new_button    = new_character_button,
		cancel_button = cancel_button,
	})

	# Live-preview FIFA card -- mirrors the form values in real time.
	# Visibility is owned by create_toggle; we only feed it data.
	preview_card = CharacterCardScript.new()
	preview_card_slot.add_child(preview_card)
	_refresh_preview_card()

	# Form -> preview wiring.
	name_input.text_changed.connect(func(_t): _refresh_preview_card())
	class_selector.item_selected.connect(func(_i): _refresh_preview_card())
	race_selector.item_selected.connect(_on_race_changed)

	# Head picker (controller-lifecycle: needs `connection`).
	head_picker_controller = HeadPickerController.new({
		connection    = connection,
		body_sprite   = head_body_sprite,
		head_sprite   = head_head_sprite,
		label         = head_index_label,
		prev_button   = head_prev_button,
		next_button   = head_next_button,
		container     = head_picker,
		loading_label = head_loading_label,
	})
	head_random_button.pressed.connect(func(): head_picker_controller.pick_random())
	if RACES.size() > 0:
		head_picker_controller.set_race(RACES[race_selector.selected])

	# Reconnect-prompt modal: the server may fire RECONNECT_PROMPT during
	# this scene if the player is mid-match. The controller lazy-builds
	# the modal on first prompt and routes the user's Si/No back over
	# `connection` as a RECONNECT_RESPONSE packet.
	reconnect_modal_controller = ReconnectModalControllerScript.new({
		host         = self,
		connection   = connection,
		modal_scene  = ReconnectModalScene,
	})

	connection.send_packet(PacketIds.CHARACTER_LIST_REQUEST)
	status_label.text = "Loading characters..."

func _on_packet_received(packet_id: int, payload: Dictionary):
	match packet_id:
		PacketIds.CHARACTER_LIST_RESPONSE:
			_handle_character_list(payload)
		PacketIds.CHARACTER_CREATE_RESPONSE:
			_handle_create_response(payload)
		PacketIds.CHARACTER_SELECT_RESPONSE:
			_handle_select_response(payload)
		PacketIds.MAP_LOAD:
			_enter_world(payload)
		PacketIds.HEAD_OPTIONS_RESPONSE:
			if head_picker_controller != null:
				head_picker_controller.handle_options_response(payload)
		PacketIds.RECONNECT_PROMPT:
			# Server detected an in-progress match for this character on
			# (re-)login. Show the modal; user's response goes back over
			# `connection` via RECONNECT_RESPONSE.
			if reconnect_modal_controller != null:
				reconnect_modal_controller.handle_prompt(payload)

func _handle_character_list(payload: Dictionary):
	_characters = payload.get("characters", [])

	# Warm the texture cache for each character's last map BEFORE the user
	# picks one -- by the time they click, the world render hits a hot cache.
	for character in _characters:
		MapTextureCache.queue_preload(int(character.get("map_id", 0)))

	# Clear previous cards
	for child in char_list.get_children():
		child.queue_free()

	if _characters.size() > 0:
		title_label.text = "Select Character"
		# Render one FIFA-style card per existing character. Click selects.
		for character in _characters:
			var card = CharacterCardScript.new()
			char_list.add_child(card)
			card.set_data({
				"name": character.get("name", "?"),
				"class": character.get("class", ""),
				"race": character.get("race", ""),
				"level": character.get("level", 1),
				# NOTE: server's Character#to_summary doesn't ship dice_roll
				# yet, so we render +0 for existing characters until that
				# lands. Tracked in PR body.
				"dice_roll": character.get("dice_roll", {}),
				"show_level": true,
				"payload": {"id": character.get("id")},
			})
			var char_id = character.get("id")
			card.pressed.connect(func(_p): _select_character(char_id))

		status_label.text = "%d character(s). Click a card to enter." % _characters.size()
	else:
		title_label.text = "Create Your First Character"
		status_label.text = "No characters yet."

	# Slot-cap policy: hide create button at cap. With 0 characters auto-open
	# the form so the user is never stuck on an empty screen.
	create_toggle.set_can_create(_characters.size() < MAX_CHARACTERS)
	if _characters.size() == 0:
		create_toggle.show()

func _select_character(char_id):
	if char_id == null:
		return
	status_label.text = "Selecting..."
	connection.send_packet(PacketIds.CHARACTER_SELECT, {"character_id": char_id})

func _on_race_changed(idx: int) -> void:
	if idx >= 0 and idx < RACES.size() and head_picker_controller != null:
		head_picker_controller.set_race(RACES[idx])
	_refresh_preview_card()

# Pull the current form values and push them into the preview card. No-ops
# until the card is built.
func _refresh_preview_card() -> void:
	if preview_card == null:
		return

	var class_slug := ""
	if class_selector.selected >= 0 and class_selector.selected < CLASSES.size():
		class_slug = CLASSES[class_selector.selected]

	var race_slug := ""
	if race_selector.selected >= 0 and race_selector.selected < RACES.size():
		race_slug = RACES[race_selector.selected]

	var typed_name := name_input.text.strip_edges()
	if typed_name == "":
		typed_name = "Nuevo personaje"

	# Dice rolls are deferred to the Shrine of Fortune (level 2 unlock).
	# Creation preview always shows +0 -- server persists zeros at create time.
	preview_card.set_data({
		"name": typed_name,
		"class": class_slug,
		"race": race_slug,
		"dice_roll": {},
		"show_level": false,
	})

func _on_create_pressed():
	var char_name = name_input.text.strip_edges()
	if char_name.is_empty():
		status_label.text = "Enter a name!"
		return

	var class_type = CLASSES[class_selector.selected]
	var race = RACES[race_selector.selected]

	status_label.text = "Creating %s..." % char_name
	create_button.disabled = true

	# Dice rolls deferred to the Shrine of Fortune (level 2). Server now
	# ignores throw_index and persists all-zero dice at creation, so we
	# stop sending it.
	connection.send_packet(PacketIds.CHARACTER_CREATE, {
		"name": char_name,
		"class": class_type,
		"race": race,
		"head_id": head_picker_controller.selected_head_id() if head_picker_controller != null else 1,
	})

func _handle_create_response(payload: Dictionary):
	create_button.disabled = false

	if payload.get("success", false):
		status_label.text = "Created! Loading characters..."
		name_input.text = ""
		# Tuck the form away once creation succeeds so the user lands back
		# on the card list.
		create_toggle.cancel()
		connection.send_packet(PacketIds.CHARACTER_LIST_REQUEST)
	else:
		status_label.text = "Failed: %s" % payload.get("error", "unknown")

func _handle_select_response(payload: Dictionary):
	if payload.get("success", false):
		_pending_select_payload = payload
		character_selected.emit(payload)
	else:
		status_label.text = "Select failed: %s" % payload.get("error", "unknown")

# MAP_LOAD arrives right after a successful select. When we own the
# connection (post-/salir re-entry) we swap into world ourselves; on first
# login, login.gd has already orchestrated the swap and we are queue_freed.
func _enter_world(map_payload: Dictionary):
	if not is_instance_valid(self) or _pending_select_payload.is_empty():
		return

	connection.packet_received.disconnect(_on_packet_received)
	if connection.disconnected.is_connected(_on_connection_lost):
		connection.disconnected.disconnect(_on_connection_lost)

	# Stop the menu theme; the world's MUSIC_CHANGE packet (if any) will
	# crossfade into the city/zone music after spawn.
	AudioPlayer.stop_theme()

	var world_scene: PackedScene = load("res://scenes/world/world.tscn")
	var world = world_scene.instantiate()
	get_parent().add_child(world)
	get_tree().current_scene = world
	world.setup(connection, _pending_select_payload, map_payload)
	queue_free()

func _on_logout_confirmed():
	connection.packet_received.disconnect(_on_packet_received)
	if connection.disconnected.is_connected(_on_connection_lost):
		connection.disconnected.disconnect(_on_connection_lost)
	if is_instance_valid(connection):
		connection.disconnect_from_server()
		connection.queue_free()
	# Stop the character_select theme; login._ready() will start the
	# login theme back up when the new scene mounts.
	AudioPlayer.stop_theme()
	_return_to_login()

func _on_connection_lost():
	_return_to_login()

func _return_to_login():
	var login_scene: PackedScene = load("res://scenes/login/login.tscn")
	var login = login_scene.instantiate()
	get_parent().add_child(login)
	get_tree().current_scene = login
	queue_free()
