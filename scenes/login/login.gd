extends Control

@onready var account_input: LineEdit = $FormPanel/VBoxContainer/AccountInput
@onready var login_button: Button = $FormPanel/VBoxContainer/LoginButton
@onready var status_label: Label = $FormPanel/VBoxContainer/StatusLabel
@onready var connection: ServerConnection = $ServerConnection

func _ready():
	login_button.pressed.connect(_on_login_pressed)
	connection.connected.connect(_on_connected)
	connection.disconnected.connect(_on_disconnected)
	connection.packet_received.connect(_on_packet_received)

	account_input.text = "dev|player1"
	status_label.text = "Not connected"

	# Kick off the login theme. AudioPlayer is a global autoload; if the
	# theme's MP3 isn't on disk it silently no-ops.
	AudioPlayer.play_theme("login")

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

func _show_character_select():
	print("[login] Auth success — swapping to character_select")
	connection.packet_received.disconnect(_on_packet_received)
	connection.connected.disconnect(_on_connected)
	connection.disconnected.disconnect(_on_disconnected)

	# Reparent connection out of login (which is about to free) so it survives.
	var conn = connection
	remove_child(conn)
	get_parent().add_child(conn)

	# character_select handles its own MAP_LOAD → world instantiation now.
	var cs_scene: PackedScene = load("res://scenes/character/character_select.tscn")
	var cs = cs_scene.instantiate()
	get_parent().add_child(cs)
	get_tree().current_scene = cs
	cs.setup(conn)

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
