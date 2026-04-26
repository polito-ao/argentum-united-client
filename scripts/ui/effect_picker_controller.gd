class_name EffectPickerController
extends RefCounted

## Settings-overlay picker for the player's chosen meditation aura.
##
## Today only one category exists ("meditation"); the controller is written
## so adding more (blessings, VIP halos, status overlays) is a matter of
## extending CATEGORY and reusing the same wire shape. The wire side is
## SETTINGS_SAVE with an `effect_choices` Dictionary — server merges it into
## the persisted state and broadcasts the next aura with the new id.
##
## Pure logic + Control widget refs — testable headless. Construct in
## setup() per the controller-lifecycle memory: we need `connection` to send
## packets.
##
## Responsibilities:
##   - Render one button per effect_id in `available`
##   - Highlight the currently-chosen id and update a "Actual: <name>" label
##   - On click: send SETTINGS_SAVE { effect_choices: { meditation: id } }
##     and update local state optimistically (server is authoritative — if
##     it rejects via filter_valid_choices, the next CHARACTER_SELECT will
##     reset us)
##
## Defensive fallbacks:
##   - Empty `available` -> render nothing, keep "Actual: -" label.
##   - Server PR not yet shipped -> world.gd defaults to [1] / 1 before
##     calling set_options so the section still renders coherently.

const PacketIds = preload("res://scripts/network/packet_ids.gd")

# The category key on the wire. The server PR uses string keys like
# "meditation" -- keep this matching. If more categories land we will
# parameterise the controller per-category instead of stringly-coding.
const CATEGORY_MEDITATION := "meditation"

var _connection
var _hud  # HUDController, optional -- used to confirm the change in messages
var _container: Control            # the whole "Aura de meditacion" section
var _current_label: Label          # "Actual: <id>"
var _options_grid: Container       # grid/HBox where one Button per option goes

var _available: Array = []         # ints
var _chosen: int = -1
var _buttons: Array = []           # parallel to _available


func _init(refs: Dictionary) -> void:
	_connection    = refs.get("connection", null)
	_hud           = refs.get("hud", null)
	_container     = refs.get("container", null)
	_current_label = refs.get("current_label", null)
	_options_grid  = refs.get("options_grid", null)

	if _connection == null:
		push_error("EffectPickerController: null connection -- wiring bug")


# Apply the server-shipped state for this character. Called every time the
# settings overlay opens (so a freshly-CHARACTER_SELECTed value is reflected)
# and once on initial wiring.
func set_options(available, chosen) -> void:
	# Coerce: msgpack may yield Float/String here.
	_available = []
	for v in available:
		_available.append(int(v))
	_chosen = int(chosen)
	# If the chosen id is not in the available list (server-side data drift,
	# or the choice was demoted), anchor to the first available and let the
	# server reconcile on the next save.
	if not _available.is_empty() and not _available.has(_chosen):
		_chosen = _available[0]
	_rebuild_buttons()
	_refresh_label()


func current_chosen() -> int:
	return _chosen


func available() -> Array:
	return _available.duplicate()


# Public so tests / button signals can drive the same code path.
func select(effect_id: int) -> void:
	if not _available.has(effect_id):
		# Refuse silently -- the option is not owned. UI never offers it, so
		# this only fires from synthetic test paths.
		return
	if effect_id == _chosen:
		# No-op: double-click on the active option.
		return
	_chosen = effect_id
	_send_choice()
	_refresh_label()
	_refresh_button_states()


# --- private ---------------------------------------------------------------

func _send_choice() -> void:
	if _connection == null:
		return
	var payload := {
		"effect_choices": {
			CATEGORY_MEDITATION: _chosen,
		}
	}
	_connection.send_packet(PacketIds.SETTINGS_SAVE, payload)
	if _hud != null:
		_hud.add_message("Aura de meditacion: %d" % _chosen)


func _rebuild_buttons() -> void:
	if _options_grid == null:
		return
	for child in _options_grid.get_children():
		child.queue_free()
	_buttons = []
	for effect_id in _available:
		var btn := Button.new()
		btn.text = _label_for(effect_id)
		btn.focus_mode = Control.FOCUS_NONE
		btn.toggle_mode = true
		btn.button_pressed = (effect_id == _chosen)
		btn.pressed.connect(select.bind(effect_id))
		_options_grid.add_child(btn)
		_buttons.append({"id": effect_id, "button": btn})


func _refresh_button_states() -> void:
	for entry in _buttons:
		var btn: Button = entry["button"]
		btn.button_pressed = (int(entry["id"]) == _chosen)


func _refresh_label() -> void:
	if _current_label == null:
		return
	if _available.is_empty():
		_current_label.text = "Actual: -"
	else:
		_current_label.text = "Actual: %s" % _label_for(_chosen)


# Display label for an effect_id. Cucsi-rooted names mirror Protocol.bas
# MeditarToggle -- players who know the original game will recognise them.
const _LABELS := {
	1: "Chico",
	2: "Mediano",
	3: "Grande",
}


func _label_for(effect_id: int) -> String:
	return _LABELS.get(effect_id, "Aura %d" % effect_id)
