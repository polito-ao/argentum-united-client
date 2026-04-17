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

func _show_character_select():
	print("[login] Auth success — transitioning to character select")

	# Hide login UI
	$VBoxContainer.visible = false

	# Reparent the connection so it survives scene changes
	var conn = connection
	connection.packet_received.disconnect(_on_packet_received)

	# Instantiate character select as sibling
	var char_select = _char_select_scene.instantiate()
	get_parent().add_child(char_select)
	char_select.setup(conn)
	char_select.character_selected.connect(_on_character_selected)

	print("[login] Character select scene added")

func _on_character_selected(character: Dictionary):
	print("[login] Character selected: ", character)
	# TODO: transition to world scene

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
