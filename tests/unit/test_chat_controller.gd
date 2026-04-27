extends GutTest
## Unit tests for ChatController. RichTextLabel + LineEdit are real
## (and attached to the test scene tree so grab_focus / release_focus
## don't log "is_inside_tree()" errors). Connection is a stub that
## records every send_packet call.

const PacketIds = preload("res://scripts/network/packet_ids.gd")

var chat: ChatController
var display: RichTextLabel
var input_box: LineEdit
var conn: _StubConnection

func before_each():
	display = RichTextLabel.new()
	display.bbcode_enabled = true
	add_child_autofree(display)
	input_box = LineEdit.new()
	add_child_autofree(input_box)
	conn = _StubConnection.new()
	chat = ChatController.new({
		chat_display = display,
		chat_input   = input_box,
		connection   = conn,
	})

# --- append_broadcast ---

func test_append_broadcast_writes_formatted_line():
	chat.append_broadcast("Ana", "hola")
	assert_string_contains(display.get_parsed_text(), "[Ana]: hola")

func test_append_broadcast_uses_question_mark_for_null_sender():
	chat.append_broadcast(null, "hola")
	assert_string_contains(display.get_parsed_text(), "[?]: hola")

func test_append_broadcast_appends_in_order():
	chat.append_broadcast("Ana", "first")
	chat.append_broadcast("Bob", "second")
	var idx_first = display.get_parsed_text().find("first")
	var idx_second = display.get_parsed_text().find("second")
	assert_gt(idx_first, -1)
	assert_gt(idx_second, idx_first)

# --- append_system ---

func test_append_system_writes_visible_text():
	chat.append_system("Settings saved")
	assert_string_contains(display.get_parsed_text(), "Settings saved")

func test_append_system_color_tag_is_consumed_by_parser():
	chat.append_system("MISS!")
	# A successful bbcode parse leaves no "[color" residue in the parsed
	# (visible) text. Both visible content + clean parse confirm the
	# distinct-from-broadcast styling is in effect.
	var visible = display.get_parsed_text()
	assert_string_contains(visible, "MISS!")
	assert_eq(visible.find("[color"), -1, "color bbcode should be consumed by parser")

func test_append_system_constant_uses_soft_gray():
	# Compile-time guard: the chosen color is the documented soft gray.
	# A redesign that bumps this should also update CLAUDE.md / hud-layout.md.
	assert_eq(ChatController.SYSTEM_COLOR, "#9ba0a8")

func test_append_system_ignores_empty_message():
	chat.append_system("")
	assert_eq(display.get_parsed_text(), "")

func test_append_system_escapes_bracket_payload():
	# A literal "[NPC]" in the message must not be parsed as a bbcode tag,
	# or subsequent text gets eaten. The controller swaps "[" → "[lb]"
	# (bbcode literal-bracket).
	chat.append_system("Aquí: [NPC] Lobo")
	# After parsing, "[lb]" renders as "[" — visible text contains "[NPC]".
	assert_string_contains(display.get_parsed_text(), "[NPC]")

# --- submit ---

func test_submit_non_empty_sends_message():
	assert_true(chat.submit("hello world"))
	assert_eq(conn.sent.size(), 1)
	assert_eq(conn.sent[0].id, PacketIds.CHAT_SEND)
	assert_eq(conn.sent[0].payload.message, "hello world")

func test_submit_clears_input_after_send():
	input_box.text = "typed"
	chat.submit("typed")
	assert_eq(input_box.text, "")

func test_submit_whitespace_normalises_to_empty_message():
	# Empty/whitespace messages still send — the server uses them to clear
	# the chat bubble over the player.
	chat.submit("   ")
	assert_eq(conn.sent[0].payload.message, "")

func test_submit_with_null_connection_no_op_clears_input():
	var orphan = ChatController.new({
		chat_display = display,
		chat_input   = input_box,
		connection   = null,
	})
	input_box.text = "typed"
	assert_false(orphan.submit("typed"))
	assert_eq(input_box.text, "")
	assert_eq(conn.sent.size(), 0)

# --- focus / has_focus ---

func test_focus_grabs_input_and_clears_text():
	input_box.text = "stale"
	chat.focus()
	assert_eq(input_box.text, "")
	assert_true(input_box.has_focus())

func test_has_focus_reflects_input_state():
	assert_false(chat.has_focus())
	input_box.grab_focus()
	assert_true(chat.has_focus())

# --- text_submitted signal hook ---

func test_signal_emit_triggers_send():
	# Wired by _init via _input.text_submitted.connect(_on_submitted)
	input_box.text_submitted.emit("from-signal")
	assert_eq(conn.sent.size(), 1)
	assert_eq(conn.sent[0].payload.message, "from-signal")

# --- helpers ---

class _StubConnection extends RefCounted:
	var sent: Array = []
	func send_packet(id, payload = {}):
		sent.append({"id": id, "payload": payload})
