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
	status_label.text = "TCP connected. Fetching config..."
	connection.send_packet(PacketIds.CONFIG_REQUEST)

func _on_disconnected():
	status_label.text = "Disconnected"
	login_button.disabled = false

var _char_select_scene = preload("res://scenes/character/character_select.tscn")
var _world_scene = preload("res://scenes/world/world.tscn")
var _select_payload: Dictionary = {}
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

func _on_character_selected(select_payload: Dictionary):
	print("[login] Character selected: ", select_payload)
	_select_payload = select_payload

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
		world.setup(conn, _select_payload, payload)

		# Remove self (login control)
		queue_free()

func _on_packet_received(packet_id: int, payload: Dictionary):
	match packet_id:
		PacketIds.CONFIG_RESPONSE:
			_handle_config(payload)
		PacketIds.AUTH_RESPONSE:
			if payload.get("success", false):
				_show_character_select()
			else:
				status_label.text = "Auth failed: %s" % payload.get("error", "unknown")
				login_button.disabled = false
		_:
			push_error("DRIFT or MALICIOUS: unknown packet_id 0x%04x" % packet_id)

func _handle_config(payload: Dictionary):
	var server_ids = payload.get("packet_ids", {})
	var mismatches = PacketIds.validate_server_config(server_ids)
	if mismatches.size() > 0:
		push_error("PROTOCOL DRIFT — client/server packet IDs mismatch: %s" % mismatches)
		status_label.text = "Protocol mismatch! Update client."
		return

	PacketIds.load_game_config(payload)
	print("[login] Config OK (%d classes, %d races)" % [PacketIds.classes.size(), PacketIds.races.size()])

	status_label.text = "Authenticating..."
	connection.send_packet(PacketIds.DEV_LOGIN, {"account_id": account_input.text})
