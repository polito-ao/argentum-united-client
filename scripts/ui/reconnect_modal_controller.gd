class_name ReconnectModalController
extends RefCounted

## Bridge between an active scene's packet stream and the ReconnectModal.
##
## RECONNECT_PROMPT (0x008F) can arrive during character_select OR right
## after entering the world (defensive timing -- the server fires it on
## the post-auth flow but we don't want to drop the packet if it lands
## a frame late). Both scenes instantiate one of these controllers and
## hand it the modal scene's packed reference + their connection. When
## a prompt arrives, the controller:
##
##   1. Lazy-instantiates the modal scene as a child of `host` (the
##      character_select / world Control), so it overlays the active
##      view at the top of the scene tree's z-order.
##   2. Calls show_for(match_id, match_type, expires_at).
##   3. Listens for `responded(match_id, accept)` and translates that
##      into a RECONNECT_RESPONSE packet over `connection`.
##
## Duplicate-prompt policy: if a modal is already visible for the SAME
## match_id, we no-op (server jitter / re-send). For a DIFFERENT
## match_id, we replace -- the new prompt is more authoritative, the
## previous one is stale.
##
## RefCounted (no scene-tree presence of its own); fully testable by
## passing fake `host` and stub `connection`.

# What we send back when the user clicks Si / No.
const RECONNECT_RESPONSE_PACKET := PacketIds.RECONNECT_RESPONSE

var _host: Node                    # parent for the modal scene
var _connection                    # ServerConnection (duck-typed for tests)
var _modal_scene: PackedScene      # res://scenes/match/reconnect_modal.tscn
var _modal: Control = null         # lazy; instantiated on first prompt


func _init(refs: Dictionary) -> void:
	_host = refs.get("host", null)
	_connection = refs.get("connection", null)
	_modal_scene = refs.get("modal_scene", null)

	if _host == null:
		push_error("ReconnectModalController: missing host ref")
	if _connection == null:
		push_error("ReconnectModalController: missing connection ref")
	if _modal_scene == null:
		push_error("ReconnectModalController: missing modal_scene ref")


# Call from the host scene's `_on_packet_received` for the
# RECONNECT_PROMPT packet. Idempotent for duplicate prompts; replaces
# the on-screen modal if a different match_id arrives.
func handle_prompt(payload: Dictionary) -> void:
	var match_id = str(payload.get("match_id", ""))
	if match_id == "":
		# Server contract guarantees a non-empty id; if it ever ships an
		# empty string we couldn't round-trip the response anyway.
		return

	var match_type = str(payload.get("match_type", ""))
	var expires_at = int(payload.get("expires_at", 0))

	_ensure_modal()
	if _modal == null:
		# Instantiation failed; nothing else to do.
		return

	_modal.show_for(match_id, match_type, expires_at)


# Tear down the modal explicitly. Useful when the host scene is freed
# and we want to make sure no signals fire post-hoc.
func close() -> void:
	if _modal != null and is_instance_valid(_modal):
		# `_close()` is private on the modal; emulate via hide + reset
		# state through the public API (responded won't fire because we
		# don't go through the button paths).
		_modal.visible = false


# True iff the modal is currently visible to the user.
func is_open() -> bool:
	return _modal != null and is_instance_valid(_modal) and _modal.is_open()


# Returns the match_id currently displayed, or "" if no modal is up.
# Useful for tests + duplicate-prompt assertions from outside.
func current_match_id() -> String:
	if _modal == null or not is_instance_valid(_modal):
		return ""
	return _modal.current_match_id()


# --- internal ---------------------------------------------------------------


func _ensure_modal() -> void:
	if _modal != null and is_instance_valid(_modal):
		return
	if _modal_scene == null or _host == null:
		return
	_modal = _modal_scene.instantiate()
	if _modal == null:
		push_error("ReconnectModalController: modal_scene.instantiate() returned null")
		return
	_host.add_child(_modal)
	_modal.responded.connect(_on_responded)


func _on_responded(match_id: String, accept: bool) -> void:
	if _connection == null:
		return
	# Server expects { match_id, accept }. Extra fields ignored.
	_connection.send_packet(RECONNECT_RESPONSE_PACKET, {
		"match_id": match_id,
		"accept": accept,
	})
