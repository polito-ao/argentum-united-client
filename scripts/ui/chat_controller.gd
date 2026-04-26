class_name ChatController
extends RefCounted

## Chat log + input + send. Owns:
##   - chat_display (RichTextLabel) — the rolling chat log
##   - chat_input   (LineEdit)      — message entry
##   - the CHAT_SEND wire to the server
##
## NOT owned: chat bubbles over player sprites. Those are tightly coupled
## to the player-sprite node tree and timer-based auto-free, so they stay
## in world.gd until a separate pass.
##
## Lifecycle: needs `connection` to send → construct in world.gd's setup(),
## not _ready(). See feedback_godot_controller_lifecycle memory.

var _display: RichTextLabel
var _input: LineEdit
var _connection

func _init(refs: Dictionary) -> void:
	_display    = refs.chat_display
	_input      = refs.chat_input
	_connection = refs.connection
	if _connection == null:
		push_error("ChatController: null connection at construction — wiring bug")
	_input.text_submitted.connect(_on_submitted)

# --- Incoming ---

# CHAT_BROADCAST handler. from_name=null → "?" placeholder (matches prior
# inline behaviour for messages whose sender we couldn't resolve).
func append_broadcast(from_name, msg: String) -> void:
	var name_str = from_name if from_name != null else "?"
	_display.append_text("[%s]: %s\n" % [name_str, msg])

# --- Outgoing ---

# Sends CHAT_SEND. Empty/whitespace-only messages still send (server uses
# them to clear the local chat bubble). Always clears the input afterwards.
func submit(text: String) -> bool:
	if _connection == null:
		_input.text = ""
		_input.release_focus()
		return false
	var payload = {"message": text if not text.strip_edges().is_empty() else ""}
	_connection.send_packet(PacketIds.CHAT_SEND, payload)
	_input.text = ""
	_input.release_focus()
	return true

# --- Focus (for "chat_toggle" key + input-gating checks in world.gd) ---

func focus() -> void:
	_input.grab_focus()
	_input.text = ""

func has_focus() -> bool:
	return _input.has_focus()

func _on_submitted(text: String) -> void:
	submit(text)
