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
	status_label.text = "Connected! Authenticating..."
	connection.send_packet(PacketIds.DEV_LOGIN, {
		"account_id": account_input.text
	})

func _on_disconnected():
	status_label.text = "Disconnected"
	login_button.disabled = false

func _on_packet_received(packet_id: int, payload: Dictionary):
	match packet_id:
		PacketIds.AUTH_RESPONSE:
			if payload.get("success", false):
				status_label.text = "Authenticated! Loading characters..."
				# TODO: transition to character select scene
			else:
				status_label.text = "Auth failed: %s" % payload.get("error", "unknown")
				login_button.disabled = false
