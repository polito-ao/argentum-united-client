extends GutTest
## Unit tests for HeadPickerController. Real Sprite2D + Label + Button
## widgets are constructed without entering the scene tree — the
## controller only reads their properties / connects signals.

const PacketIds = preload("res://scripts/network/packet_ids.gd")

var picker: HeadPickerController
var conn: _StubConnection
var body_sprite: Sprite2D
var head_sprite: Sprite2D
var label: Label
var prev_btn: Button
var next_btn: Button
var container: Control
var loading_label: Label

func before_each():
	conn = _StubConnection.new()
	body_sprite = Sprite2D.new()
	head_sprite = Sprite2D.new()
	label = Label.new()
	prev_btn = Button.new()
	next_btn = Button.new()
	container = Control.new()
	loading_label = Label.new()
	add_child_autofree(body_sprite)
	add_child_autofree(head_sprite)
	add_child_autofree(label)
	add_child_autofree(prev_btn)
	add_child_autofree(next_btn)
	add_child_autofree(container)
	add_child_autofree(loading_label)

	picker = HeadPickerController.new({
		connection    = conn,
		body_sprite   = body_sprite,
		head_sprite   = head_sprite,
		label         = label,
		prev_button   = prev_btn,
		next_button   = next_btn,
		container     = container,
		loading_label = loading_label,
	})

# --- race change triggers HEAD_OPTIONS_REQUEST -------------------------------

func test_set_race_sends_head_options_request():
	picker.set_race("humano")
	var req = _first_packet(PacketIds.HEAD_OPTIONS_REQUEST)
	assert_not_null(req)
	assert_eq(req.payload.race, "humano")

func test_set_race_shows_loading_state():
	picker.set_race("humano")
	assert_true(loading_label.visible)
	assert_true(container.visible)

func test_setting_same_race_twice_after_response_does_not_resend():
	picker.set_race("humano")
	picker.handle_options_response({"race": "humano", "head_ids": [1, 2, 3]})
	conn.sent.clear()
	picker.set_race("humano")
	assert_eq(conn.sent.size(), 0)

func test_changing_race_resends_request():
	picker.set_race("humano")
	picker.handle_options_response({"race": "humano", "head_ids": [1, 2]})
	conn.sent.clear()
	picker.set_race("elfo")
	var req = _first_packet(PacketIds.HEAD_OPTIONS_REQUEST)
	assert_not_null(req)
	assert_eq(req.payload.race, "elfo")

# --- response populates list -------------------------------------------------

func test_response_populates_head_ids_and_resets_index_to_zero():
	picker.set_race("humano")
	picker.handle_options_response({"race": "humano", "head_ids": [10, 11, 12]})
	assert_eq(picker.head_ids(), [10, 11, 12])
	assert_eq(picker.current_index(), 0)
	assert_eq(picker.selected_head_id(), 10)

func test_response_for_stale_race_is_dropped():
	picker.set_race("humano")
	picker.set_race("elfo") # user moved on; humano response is now stale
	picker.handle_options_response({"race": "humano", "head_ids": [1, 2, 3]})
	assert_eq(picker.head_ids(), [], "stale response should not populate list")

func test_response_hides_loading_label():
	picker.set_race("humano")
	picker.handle_options_response({"race": "humano", "head_ids": [1, 2]})
	assert_false(loading_label.visible)

func test_label_shows_one_based_count_after_response():
	picker.set_race("humano")
	picker.handle_options_response({"race": "humano", "head_ids": [10, 11, 12]})
	assert_eq(label.text, "Cabeza 1 / 3")

# --- prev / next navigation --------------------------------------------------

func test_next_advances_index_and_updates_label():
	picker.set_race("humano")
	picker.handle_options_response({"race": "humano", "head_ids": [10, 11, 12]})
	picker.next()
	assert_eq(picker.current_index(), 1)
	assert_eq(picker.selected_head_id(), 11)
	assert_eq(label.text, "Cabeza 2 / 3")

func test_prev_decrements_index():
	picker.set_race("humano")
	picker.handle_options_response({"race": "humano", "head_ids": [10, 11, 12]})
	picker.next()
	picker.prev()
	assert_eq(picker.current_index(), 0)
	assert_eq(picker.selected_head_id(), 10)

func test_next_wraps_at_end():
	picker.set_race("humano")
	picker.handle_options_response({"race": "humano", "head_ids": [10, 11, 12]})
	picker.next(); picker.next(); picker.next() # 0->1->2->0
	assert_eq(picker.current_index(), 0)
	assert_eq(picker.selected_head_id(), 10)

func test_prev_wraps_at_start():
	picker.set_race("humano")
	picker.handle_options_response({"race": "humano", "head_ids": [10, 11, 12]})
	picker.prev() # 0 -> 2 (wrap)
	assert_eq(picker.current_index(), 2)
	assert_eq(picker.selected_head_id(), 12)

func test_navigation_with_one_head_is_a_noop():
	picker.set_race("humano")
	picker.handle_options_response({"race": "humano", "head_ids": [42]})
	picker.next()
	picker.prev()
	assert_eq(picker.current_index(), 0)
	assert_eq(picker.selected_head_id(), 42)

# --- random ------------------------------------------------------------------

func test_pick_random_with_one_head_is_noop():
	picker.set_race("humano")
	picker.handle_options_response({"race": "humano", "head_ids": [7]})
	picker.pick_random()
	assert_eq(picker.current_index(), 0)

func test_pick_random_changes_index():
	# With 3 heads, pick_random must land on a different index every call.
	picker.set_race("humano")
	picker.handle_options_response({"race": "humano", "head_ids": [10, 11, 12]})
	var seen := {0: true}
	for i in 10:
		picker.pick_random()
		seen[picker.current_index()] = true
	assert_gt(seen.size(), 1, "pick_random should explore more than one index")

# --- fallback when response is empty / never arrives -------------------------

func test_selected_head_id_falls_back_to_default_when_list_empty():
	# Never call handle_options_response.
	assert_eq(picker.selected_head_id(), HeadPickerController.FALLBACK_HEAD_ID)

func test_empty_response_falls_back_gracefully():
	picker.set_race("humano")
	picker.handle_options_response({"race": "humano", "head_ids": []})
	assert_eq(picker.selected_head_id(), HeadPickerController.FALLBACK_HEAD_ID)
	# Container stays visible so the layout doesn't jump
	assert_true(container.visible)

func test_missing_head_ids_field_treated_as_empty():
	picker.set_race("humano")
	picker.handle_options_response({"race": "humano"})
	assert_eq(picker.selected_head_id(), HeadPickerController.FALLBACK_HEAD_ID)

# --- button signals are wired to navigation ---------------------------------

func test_prev_button_press_navigates():
	picker.set_race("humano")
	picker.handle_options_response({"race": "humano", "head_ids": [10, 11, 12]})
	prev_btn.pressed.emit()
	assert_eq(picker.current_index(), 2)

func test_next_button_press_navigates():
	picker.set_race("humano")
	picker.handle_options_response({"race": "humano", "head_ids": [10, 11, 12]})
	next_btn.pressed.emit()
	assert_eq(picker.current_index(), 1)

# --- helpers ----------------------------------------------------------------

func _first_packet(id: int):
	var matches = conn.sent.filter(func(p): return p.id == id)
	return matches.front() if matches.size() > 0 else null

class _StubConnection extends RefCounted:
	var sent: Array = []
	func send_packet(id, payload = {}):
		sent.append({"id": id, "payload": payload})
