extends Control

@onready var account_input: LineEdit = $VBoxContainer/AccountInput
@onready var login_button: Button = $VBoxContainer/LoginButton
@onready var status_label: Label = $VBoxContainer/StatusLabel
@onready var connection: ServerConnection = $ServerConnection

func _ready():
	login_button.pressed.connect(_on_login_pressed)
	connection.connected.connect(_on_connected)
	connection.disconnected.connect(_on_disconnected)
	connection.packet_received.connect(_on_packet_received)

	account_input.text = "dev|player1"
	status_label.text = "Not connected"

func _on_login_pressed():
	status_label.text = "Connecting..."
	login_button.disabled = true

	var err = connection.connect_to_server()
	if err != OK:
		status_label.text = "Connection failed"
		login_button.disabled = false

func _on_connected():
	status_label.text = "TCP connected. Sending auth..."
	connection.send_packet(PacketIds.DEV_LOGIN, {
		"account_id": account_input.text
	})
	# If this text changes, we know _on_connected fires
	await get_tree().create_timer(0.5).timeout
	status_label.text = status_label.text + " (waiting for response...)"

func _on_disconnected():
	status_label.text = "Disconnected"
	login_button.disabled = false

var _char_select_scene = preload("res://scenes/character/character_select.tscn")
var _world_scene = preload("res://scenes/world/world.tscn")
var _selected_character: Dictionary = {}
var _char_select_instance: Control = null

func _show_character_select():
	print("[login] Auth success — transitioning to character select")
	$VBoxContainer.visible = false

	var conn = connection
	connection.packet_received.disconnect(_on_packet_received)

	_char_select_instance = _char_select_scene.instantiate()
	add_child(_char_select_instance)
	_char_select_instance.setup(conn)
	_char_select_instance.character_selected.connect(_on_character_selected)

	# Also listen for MAP_LOAD which comes right after character select
	conn.packet_received.connect(_on_world_packet)

func _on_character_selected(character: Dictionary):
	print("[login] Character selected: ", character)
	_selected_character = character

func _on_world_packet(packet_id: int, payload: Dictionary):
	if packet_id == PacketIds.MAP_LOAD:
		print("[login] MAP_LOAD received — entering world")
		connection.packet_received.disconnect(_on_world_packet)

		# Reparent connection to root before destroying login
		var conn = connection
		remove_child(conn)
		get_parent().add_child(conn)

		# Remove character select
		if _char_select_instance:
			_char_select_instance.queue_free()

		# Create world scene
		var world = _world_scene.instantiate()
		get_parent().add_child(world)
		world.setup(conn, _selected_character, payload)

		# Remove self (login control)
		queue_free()

func _on_packet_received(packet_id: int, payload: Dictionary):
	print("[login] Packet received: 0x%04x payload: %s" % [packet_id, payload])
	match packet_id:
		PacketIds.AUTH_RESPONSE:
			print("[login] Auth response success=%s" % payload.get("success", false))
			if payload.get("success", false):
				_show_character_select()
			else:
				status_label.text = "Auth failed: %s" % payload.get("error", "unknown")
				login_button.disabled = false
