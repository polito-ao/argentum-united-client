extends Control

signal character_selected(character: Dictionary)

@onready var char_list: VBoxContainer = $Panel/VBoxContainer/CharacterList
@onready var create_panel: VBoxContainer = $Panel/VBoxContainer/CreatePanel
@onready var name_input: LineEdit = $Panel/VBoxContainer/CreatePanel/NameInput
@onready var class_selector: OptionButton = $Panel/VBoxContainer/CreatePanel/ClassSelector
@onready var race_selector: OptionButton = $Panel/VBoxContainer/CreatePanel/RaceSelector
@onready var dice_label: Label = $Panel/VBoxContainer/CreatePanel/DiceLabel
@onready var throw_selector: OptionButton = $Panel/VBoxContainer/CreatePanel/ThrowSelector
@onready var create_button: Button = $Panel/VBoxContainer/CreatePanel/CreateButton
@onready var status_label: Label = $Panel/VBoxContainer/StatusLabel
@onready var title_label: Label = $Panel/VBoxContainer/TitleLabel

var connection: ServerConnection
var _characters: Array = []
var _dice_throws: Array = []

var CLASSES: Array = []
var RACES: Array = []

func setup(conn: ServerConnection):
	connection = conn
	connection.packet_received.connect(_on_packet_received)

	CLASSES = PacketIds.classes
	RACES = PacketIds.races

	class_selector.clear()
	for c in CLASSES:
		class_selector.add_item(c.capitalize())

	race_selector.clear()
	for r in RACES:
		race_selector.add_item(r.capitalize())

	create_button.pressed.connect(_on_create_pressed)

	# Request character list
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

func _handle_character_list(payload: Dictionary):
	_characters = payload.get("characters", [])
	_dice_throws = payload.get("dice_throws", [])

	# Clear previous buttons
	for child in char_list.get_children():
		child.queue_free()

	if _characters.size() > 0:
		title_label.text = "Select Character"
		create_panel.visible = _characters.size() < 3

		for character in _characters:
			var btn = Button.new()
			btn.text = "%s — %s %s (Lv %d)" % [
				character.get("name", "?"),
				character.get("class", "?"),
				character.get("race", "?"),
				character.get("level", 1)
			]
			var char_id = character.get("id")
			btn.pressed.connect(func(): _select_character(char_id))
			char_list.add_child(btn)

		status_label.text = "%d character(s). Click to select." % _characters.size()
	else:
		title_label.text = "Create Your First Character"
		create_panel.visible = true
		status_label.text = "No characters yet."

	_update_dice_display()

func _update_dice_display():
	if _dice_throws.size() == 0:
		dice_label.text = "No dice throws available"
		return

	throw_selector.clear()
	for i in _dice_throws.size():
		var throw = _dice_throws[i]
		var total = 0
		var parts = []
		for key in throw:
			total += throw[key]
			if throw[key] > 0:
				parts.append("%s:+%d" % [key, throw[key]])
		throw_selector.add_item("Throw %d (total +%d): %s" % [i + 1, total, ", ".join(parts)])

	dice_label.text = "Choose your blessing from the Shrine of Fortune:"

func _select_character(char_id: int):
	status_label.text = "Selecting..."
	connection.send_packet(PacketIds.CHARACTER_SELECT, {"character_id": char_id})

func _on_create_pressed():
	var char_name = name_input.text.strip_edges()
	if char_name.is_empty():
		status_label.text = "Enter a name!"
		return

	var class_type = CLASSES[class_selector.selected]
	var race = RACES[race_selector.selected]
	var throw_index = throw_selector.selected

	if throw_index < 0:
		status_label.text = "Choose a dice throw!"
		return

	status_label.text = "Creating %s..." % char_name
	create_button.disabled = true

	connection.send_packet(PacketIds.CHARACTER_CREATE, {
		"name": char_name,
		"class": class_type,
		"race": race,
		"throw_index": throw_index
	})

func _handle_create_response(payload: Dictionary):
	create_button.disabled = false

	if payload.get("success", false):
		status_label.text = "Created! Loading characters..."
		name_input.text = ""
		connection.send_packet(PacketIds.CHARACTER_LIST_REQUEST)
	else:
		status_label.text = "Failed: %s" % payload.get("error", "unknown")

func _handle_select_response(payload: Dictionary):
	if payload.get("success", false):
		# Pass the full payload so world can read state (hp, mana, attrs, alive)
		character_selected.emit(payload)
	else:
		status_label.text = "Select failed: %s" % payload.get("error", "unknown")
