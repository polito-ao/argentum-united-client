extends GutTest
## Unit tests for ChatController's meta_clicked → BroadcastLinkDispatcher
## bridge. Simulates clicking a [url=...] meta with valid / invalid JSON
## and verifies the dispatcher is (or isn't) invoked.

var chat: ChatController
var display: RichTextLabel
var input_box: LineEdit
var conn: _StubConnection
var world: _StubWorld

func before_each():
	display = RichTextLabel.new()
	display.bbcode_enabled = true
	add_child_autofree(display)
	input_box = LineEdit.new()
	add_child_autofree(input_box)
	conn = _StubConnection.new()
	world = _StubWorld.new()
	chat = ChatController.new({
		chat_display = display,
		chat_input   = input_box,
		connection   = conn,
		world        = world,
	})

# --- valid JSON dispatches ---

func test_meta_click_with_valid_link_dispatches_to_world():
	var meta := JSON.stringify({"kind": "map_jump", "params": {"map_id": 2, "x": 10, "y": 20}})
	display.meta_clicked.emit(meta)
	assert_eq(world.pulse_calls.size(), 1)
	assert_eq(world.pulse_calls[0].map_id, 2)
	assert_eq(world.pulse_calls[0].x, 10)
	assert_eq(world.pulse_calls[0].y, 20)

func test_meta_click_unknown_kind_does_not_crash():
	var meta := JSON.stringify({"kind": "highlight_entity", "params": {"id": 7}})
	display.meta_clicked.emit(meta)
	# Unknown kind logs warning, no pulse.
	assert_eq(world.pulse_calls.size(), 0)

# --- invalid JSON ---

func test_meta_click_with_garbage_string_does_not_crash():
	display.meta_clicked.emit("this is not json")
	assert_eq(world.pulse_calls.size(), 0)

func test_meta_click_with_empty_string_does_not_crash():
	display.meta_clicked.emit("")
	assert_eq(world.pulse_calls.size(), 0)

# --- end-to-end via append_broadcast_message ---

func test_append_then_simulate_click_round_trip():
	# Format a broadcast through the static formatter, yank the meta back
	# out of the bbcode, simulate meta_clicked, and verify the dispatcher
	# fires. This proves the format → click → dispatch pipeline.
	var payload := {
		"category": "siege",
		"level": "warning",
		"message": "Defend the castle!",
		"link": {"kind": "map_jump", "params": {"map_id": 5, "x": 99, "y": 1}},
	}
	chat.append_broadcast_message(payload)
	var bb := ChatController.format_broadcast_bbcode(payload)
	var i := bb.find("[url=")
	assert_gt(i, -1)
	var j := bb.find("]", i)
	var meta := bb.substr(i + 5, j - (i + 5))
	display.meta_clicked.emit(meta)
	assert_eq(world.pulse_calls.size(), 1)
	assert_eq(world.pulse_calls[0].map_id, 5)

# --- helpers ---

class _StubConnection extends RefCounted:
	var sent: Array = []
	func send_packet(id, payload = {}):
		sent.append({"id": id, "payload": payload})

class _StubWorld extends RefCounted:
	var pulse_calls: Array = []
	func pulse_minimap_marker(map_id: int, x: int, y: int) -> void:
		pulse_calls.append({"map_id": map_id, "x": x, "y": y})
