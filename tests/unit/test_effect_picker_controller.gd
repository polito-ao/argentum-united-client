extends GutTest
## Unit tests for EffectPickerController. Real Button/Label/Container widgets
## are constructed without entering the scene tree -- the controller only
## reads their properties and connects pressed signals.

const PacketIds = preload("res://scripts/network/packet_ids.gd")

var picker: EffectPickerController
var conn: _StubConnection
var hud: _StubHud
var container: Control
var current_label: Label
var options_grid: HBoxContainer

func before_each():
	conn = _StubConnection.new()
	hud = _StubHud.new()
	container = Control.new()
	current_label = Label.new()
	options_grid = HBoxContainer.new()
	add_child_autofree(container)
	add_child_autofree(current_label)
	add_child_autofree(options_grid)

	picker = EffectPickerController.new({
		connection    = conn,
		hud           = hud,
		container     = container,
		current_label = current_label,
		options_grid  = options_grid,
	})

# --- set_options renders buttons --------------------------------------------

func test_set_options_creates_one_button_per_available_effect():
	picker.set_options([1, 2], 1)
	await wait_physics_frames(1)  # queue_free in _rebuild_buttons clears prior children
	assert_eq(options_grid.get_child_count(), 2)

func test_set_options_marks_chosen_button_pressed():
	picker.set_options([1, 2, 3], 2)
	await wait_physics_frames(1)
	var chosen_btn: Button = null
	for child in options_grid.get_children():
		if (child as Button).button_pressed:
			chosen_btn = child
	assert_not_null(chosen_btn)
	assert_string_contains(chosen_btn.text, "Mediano")

func test_set_options_with_chosen_not_in_available_anchors_to_first():
	picker.set_options([1, 2], 99)
	assert_eq(picker.current_chosen(), 1)

func test_set_options_updates_current_label():
	picker.set_options([1, 2], 2)
	assert_eq(current_label.text, "Actual: Mediano")

func test_set_options_with_empty_available_shows_dash():
	picker.set_options([], 1)
	await wait_physics_frames(1)
	assert_eq(current_label.text, "Actual: -")
	assert_eq(options_grid.get_child_count(), 0)

# --- selecting an option fires the right packet -----------------------------

func test_select_sends_settings_save_with_effect_choices():
	picker.set_options([1, 2], 1)
	picker.select(2)
	var pkt = _first_packet(PacketIds.SETTINGS_SAVE)
	assert_not_null(pkt)
	assert_eq(pkt.payload, {"effect_choices": {"meditation": 2}})

func test_select_updates_current_chosen():
	picker.set_options([1, 2], 1)
	picker.select(2)
	assert_eq(picker.current_chosen(), 2)

func test_select_updates_label():
	picker.set_options([1, 2, 3], 1)
	picker.select(3)
	assert_eq(current_label.text, "Actual: Grande")

func test_select_unowned_id_is_silent_noop():
	picker.set_options([1, 2], 1)
	picker.select(99)
	assert_eq(picker.current_chosen(), 1, "chosen unchanged")
	assert_eq(conn.sent.size(), 0, "no packet emitted")

func test_select_same_id_does_not_resend_packet():
	picker.set_options([1, 2], 2)
	picker.select(2)
	assert_eq(conn.sent.size(), 0)

func test_select_via_button_press_signal():
	picker.set_options([1, 2], 1)
	await wait_physics_frames(1)
	# Find the "Mediano" button and emit pressed.
	var mediano_btn: Button = null
	for child in options_grid.get_children():
		if (child as Button).text.find("Mediano") != -1:
			mediano_btn = child
	assert_not_null(mediano_btn)
	mediano_btn.pressed.emit()
	assert_eq(picker.current_chosen(), 2)
	var pkt = _first_packet(PacketIds.SETTINGS_SAVE)
	assert_not_null(pkt)
	assert_eq(pkt.payload.effect_choices.meditation, 2)

# --- coercion + getters ------------------------------------------------------

func test_set_options_coerces_numeric_strings_to_ints():
	# msgpack can deliver String/Float in lax cases.
	picker.set_options(["1", 2.0], "2")
	assert_eq(picker.available(), [1, 2])
	assert_eq(picker.current_chosen(), 2)

func test_available_returns_a_copy():
	picker.set_options([1, 2], 1)
	var copy = picker.available()
	copy.append(99)
	assert_eq(picker.available(), [1, 2], "internal state unchanged")

# --- helpers ---------------------------------------------------------------

func _first_packet(id: int):
	var matches = conn.sent.filter(func(p): return p.id == id)
	return matches.front() if matches.size() > 0 else null

class _StubConnection extends RefCounted:
	var sent: Array = []
	func send_packet(id, payload = {}):
		sent.append({"id": id, "payload": payload})

class _StubHud extends RefCounted:
	var messages: Array = []
	func add_message(text: String):
		messages.append(text)
