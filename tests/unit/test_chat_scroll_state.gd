extends GutTest
## Unit tests for ChatController scroll-respect + jump-to-present behavior.
##
## Two layers of coverage:
##   1. Pure-function `should_auto_scroll(...)` — black-box decision matrix
##      tests, no scene tree, no scrollbar, no controller instance.
##   2. Integration-flavored tests with a real RichTextLabel/LineEdit/Button
##      attached to the test scene tree. These exercise the controller's
##      append → scroll-detection → button-visibility pipeline end-to-end.
##
## We can't drive Godot's RichTextLabel internal viewport from a headless
## test (it doesn't lay out without rendering), so for "user scrolled up"
## scenarios we manipulate the v_scroll_bar's value/max_value/page directly
## and call the controller's _on_scroll_changed handler. That mirrors what
## a real scroll-by-mouse would emit.

const PacketIds = preload("res://scripts/network/packet_ids.gd")

var chat: ChatController
var display: RichTextLabel
var input_box: LineEdit
var jump_button: Button
var conn: _StubConnection

func before_each():
	display = RichTextLabel.new()
	display.bbcode_enabled = true
	add_child_autofree(display)
	input_box = LineEdit.new()
	add_child_autofree(input_box)
	jump_button = Button.new()
	add_child_autofree(jump_button)
	conn = _StubConnection.new()
	chat = ChatController.new({
		chat_display = display,
		chat_input   = input_box,
		connection   = conn,
		jump_button  = jump_button,
	})

# --- Pure-function should_auto_scroll ---

func test_should_auto_scroll_when_no_scrollback():
	# scroll_max == 0 → content fits on screen → always auto-scroll.
	assert_true(ChatController.should_auto_scroll(0.0, 0.0, 100.0, true))
	assert_true(ChatController.should_auto_scroll(0.0, 0.0, 100.0, false))

func test_should_auto_scroll_when_prev_at_bottom():
	# User was tracking the live tail → keep auto-scrolling regardless of
	# the geometry snapshot.
	assert_true(ChatController.should_auto_scroll(50.0, 200.0, 100.0, true))

func test_should_not_auto_scroll_when_user_scrolled_up():
	# User has scrolled up + new content arrived → don't yank the view.
	assert_false(ChatController.should_auto_scroll(0.0, 200.0, 100.0, false))
	assert_false(ChatController.should_auto_scroll(50.0, 200.0, 100.0, false))

func test_should_auto_scroll_when_scroll_value_at_bottom():
	# value >= max - page → at-bottom → auto-scroll, even if prev flag was
	# stale (covers "user scrolled back to bottom right before the
	# message").
	assert_true(ChatController.should_auto_scroll(100.0, 200.0, 100.0, false))
	# small tolerance — fractional pixel rounding shouldn't break it.
	assert_true(ChatController.should_auto_scroll(99.5, 200.0, 100.0, false))

# --- Integration: append while at-bottom auto-scrolls ---

func test_append_at_bottom_keeps_scroll_following_on():
	# Default state at construction: at-bottom, no counter, button hidden.
	chat.append_broadcast("Ana", "hola")
	assert_true(chat.is_user_at_bottom())
	assert_eq(chat.new_messages_since_scroll_away(), 0)
	assert_false(jump_button.visible)
	assert_true(display.scroll_following)

# --- Integration: scroll-up state machine ---

func test_scroll_up_disables_auto_follow_and_keeps_button_hidden():
	# Simulate enough content that the scrollbar has range.
	var sb := display.get_v_scroll_bar()
	sb.max_value = 500.0
	sb.page = 100.0
	sb.value = 50.0  # not at bottom
	chat._on_scroll_changed(sb.value)
	assert_false(chat.is_user_at_bottom())
	assert_false(display.scroll_following)
	# No new messages have arrived since the scroll-away → button stays
	# hidden until something interesting happens.
	assert_false(jump_button.visible)
	assert_eq(chat.new_messages_since_scroll_away(), 0)

func test_new_message_while_scrolled_up_shows_button_with_counter():
	var sb := display.get_v_scroll_bar()
	sb.max_value = 500.0
	sb.page = 100.0
	sb.value = 50.0
	chat._on_scroll_changed(sb.value)

	chat.append_broadcast("Ana", "primero")
	chat.append_broadcast("Bob", "segundo")
	assert_eq(chat.new_messages_since_scroll_away(), 2)
	assert_true(jump_button.visible)
	# Label surfaces the count so the user knows how much they're missing.
	assert_string_contains(jump_button.text, "2")

func test_jump_to_present_resets_counter_and_hides_button():
	var sb := display.get_v_scroll_bar()
	sb.max_value = 500.0
	sb.page = 100.0
	sb.value = 50.0
	chat._on_scroll_changed(sb.value)
	chat.append_broadcast("Ana", "uno")
	chat.append_broadcast("Bob", "dos")
	assert_true(jump_button.visible)

	chat.jump_to_present()
	assert_eq(chat.new_messages_since_scroll_away(), 0)
	assert_false(jump_button.visible)
	assert_true(chat.is_user_at_bottom())
	assert_true(display.scroll_following)

func test_button_press_triggers_jump_to_present():
	var sb := display.get_v_scroll_bar()
	sb.max_value = 500.0
	sb.page = 100.0
	sb.value = 50.0
	chat._on_scroll_changed(sb.value)
	chat.append_broadcast("Ana", "msg")
	assert_true(jump_button.visible)

	# Emitting `pressed` on the button must route through the same path as
	# clicking it — guarantees the wiring in _init() is in place.
	jump_button.pressed.emit()
	assert_false(jump_button.visible)
	assert_eq(chat.new_messages_since_scroll_away(), 0)

func test_scroll_back_to_bottom_manually_resumes_auto_follow():
	var sb := display.get_v_scroll_bar()
	sb.max_value = 500.0
	sb.page = 100.0
	# Scroll up first.
	sb.value = 50.0
	chat._on_scroll_changed(sb.value)
	chat.append_broadcast("Ana", "uno")
	assert_true(jump_button.visible)

	# Now scroll back to the bottom via the scrollbar (real users do this
	# with the mouse wheel; emitting value_changed mirrors that).
	sb.max_value = 500.0
	sb.page = 100.0
	sb.value = 400.0  # value >= max - page → at bottom
	chat._on_scroll_changed(sb.value)

	assert_true(chat.is_user_at_bottom())
	assert_true(display.scroll_following)
	assert_eq(chat.new_messages_since_scroll_away(), 0)
	assert_false(jump_button.visible)

# --- Counter increment + reset edge cases ---

func test_counter_increments_per_appended_line_only():
	var sb := display.get_v_scroll_bar()
	sb.max_value = 500.0
	sb.page = 100.0
	sb.value = 50.0
	chat._on_scroll_changed(sb.value)

	chat.append_broadcast("Ana", "1")
	assert_eq(chat.new_messages_since_scroll_away(), 1)
	chat.append_system("system event")
	assert_eq(chat.new_messages_since_scroll_away(), 2)
	chat.append_broadcast_message({"message": "hola", "level": "info"})
	assert_eq(chat.new_messages_since_scroll_away(), 3)

func test_counter_does_not_increment_when_at_bottom():
	# Fresh state = at-bottom. Append 3 lines. Counter must stay zero.
	chat.append_broadcast("Ana", "1")
	chat.append_broadcast("Ana", "2")
	chat.append_broadcast("Ana", "3")
	assert_eq(chat.new_messages_since_scroll_away(), 0)
	assert_false(jump_button.visible)

# --- Construction without jump_button works (backward-compat) ---

func test_controller_works_without_jump_button():
	# Older callers that don't pass jump_button still get correct scroll
	# behavior — no crash, no orphan signal connection.
	var orphan = ChatController.new({
		chat_display = display,
		chat_input   = input_box,
		connection   = conn,
	})
	orphan.append_broadcast("Ana", "hola")
	assert_eq(orphan.new_messages_since_scroll_away(), 0)

# --- helpers ---

class _StubConnection extends RefCounted:
	var sent: Array = []
	func send_packet(id, payload = {}):
		sent.append({"id": id, "payload": payload})
