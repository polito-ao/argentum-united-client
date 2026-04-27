extends GutTest
## Unit tests for ChatController.format_broadcast_bbcode — pure-function
## BBCode formatter for BROADCAST_MESSAGE payloads. No scene tree, no
## RichTextLabel — we assert directly on the BBCode source string the
## formatter emits, then a smaller end-to-end test confirms the rendered
## output flows into the RichTextLabel.

# --- Level → color ---

func test_info_level_uses_cream_color():
	var bb := ChatController.format_broadcast_bbcode({
		"category": "system",
		"level": "info",
		"message": "Server iniciado.",
	})
	assert_string_contains(bb, ChatController.BROADCAST_INFO_COLOR)
	assert_string_contains(bb, "Server iniciado.")

func test_warning_level_uses_amber_color():
	var bb := ChatController.format_broadcast_bbcode({
		"category": "siege",
		"level": "warning",
		"message": "Castle Siege starts in 15 minutes!",
	})
	assert_string_contains(bb, ChatController.BROADCAST_WARNING_COLOR)
	assert_string_contains(bb, "Castle Siege")

func test_critical_level_uses_alarm_red():
	var bb := ChatController.format_broadcast_bbcode({
		"category": "world",
		"level": "critical",
		"message": "El Eucatastrophe es inminente.",
	})
	assert_string_contains(bb, ChatController.BROADCAST_CRITICAL_COLOR)

func test_unknown_level_falls_back_to_info():
	var bb := ChatController.format_broadcast_bbcode({
		"level": "spaghetti",
		"message": "what",
	})
	assert_string_contains(bb, ChatController.BROADCAST_INFO_COLOR)
	# And not the warning/critical colors.
	assert_eq(bb.find(ChatController.BROADCAST_WARNING_COLOR), -1)
	assert_eq(bb.find(ChatController.BROADCAST_CRITICAL_COLOR), -1)

# --- Category badge ---

func test_category_renders_as_bracketed_prefix():
	var bb := ChatController.format_broadcast_bbcode({
		"category": "siege",
		"level": "warning",
		"message": "Castle Siege starts in 15 minutes!",
	})
	# BBCode contains "[siege]" inside a [color=...] tag for the badge.
	assert_string_contains(bb, "[siege]")
	# Category appears before the message body.
	var idx_cat := bb.find("[siege]")
	var idx_msg := bb.find("Castle Siege")
	assert_gt(idx_msg, idx_cat)

func test_missing_category_omits_prefix():
	var bb := ChatController.format_broadcast_bbcode({
		"level": "info",
		"message": "Hello world",
	})
	# No badge color tag pair before the body — only the body color.
	# We assert no "[color=#9ba0a8]" badge appears.
	assert_eq(bb.find("[color=" + ChatController.BROADCAST_BADGE_COLOR + "]"), -1)
	assert_string_contains(bb, "Hello world")

func test_empty_category_omits_prefix():
	var bb := ChatController.format_broadcast_bbcode({
		"category": "",
		"level": "info",
		"message": "Hello",
	})
	assert_eq(bb.find("[color=" + ChatController.BROADCAST_BADGE_COLOR + "]"), -1)

# --- Sender name ---

func test_sender_name_renders_after_category():
	var bb := ChatController.format_broadcast_bbcode({
		"category": "siege",
		"level": "warning",
		"message": "Castle Siege starts in 15 minutes!",
		"sender_name": "Gobernador",
	})
	var idx_cat   := bb.find("[siege]")
	var idx_send  := bb.find("[Gobernador]")
	var idx_body  := bb.find("Castle Siege")
	assert_gt(idx_send, idx_cat, "sender follows category")
	assert_gt(idx_body, idx_send, "body follows sender")

func test_sender_only_no_category():
	var bb := ChatController.format_broadcast_bbcode({
		"level": "info",
		"message": "Hi",
		"sender_name": "Ana",
	})
	assert_string_contains(bb, "[Ana]")
	assert_string_contains(bb, "Hi")

func test_empty_sender_name_omits_badge():
	var bb := ChatController.format_broadcast_bbcode({
		"level": "info",
		"message": "Hi",
		"sender_name": "",
	})
	# No badge color tag pair appears.
	assert_eq(bb.find("[color=" + ChatController.BROADCAST_BADGE_COLOR + "]"), -1)

# --- Link wrapping ---

func test_link_wraps_body_in_url_tag():
	var bb := ChatController.format_broadcast_bbcode({
		"category": "siege",
		"level": "warning",
		"message": "Click to find castle",
		"link": {"kind": "map_jump", "params": {"map_id": 1, "x": 50, "y": 50}},
	})
	assert_string_contains(bb, "[url=")
	assert_string_contains(bb, "\"kind\":\"map_jump\"")
	assert_string_contains(bb, "Click to find castle")
	assert_string_contains(bb, "[/url]")

func test_link_missing_does_not_wrap():
	var bb := ChatController.format_broadcast_bbcode({
		"level": "info",
		"message": "Plain message",
	})
	assert_eq(bb.find("[url="), -1)

func test_malformed_link_renders_plain_no_url():
	# link present but has no `kind` — render plain, do not wrap in [url].
	var bb := ChatController.format_broadcast_bbcode({
		"level": "info",
		"message": "still readable",
		"link": {"params": {"x": 1}},
	})
	assert_eq(bb.find("[url="), -1)
	assert_string_contains(bb, "still readable")

func test_empty_link_kind_does_not_wrap():
	var bb := ChatController.format_broadcast_bbcode({
		"level": "info",
		"message": "just text",
		"link": {"kind": "", "params": {}},
	})
	assert_eq(bb.find("[url="), -1)

# --- Bracket escaping ---

func test_message_with_brackets_does_not_break_parser():
	var bb := ChatController.format_broadcast_bbcode({
		"category": "system",
		"level": "info",
		"message": "Note: [important] payload",
	})
	# "[" in user input gets escaped to "[lb]" — bbcode-literal-bracket.
	assert_string_contains(bb, "[lb]important]")
	# "[important]" must NOT appear unescaped (would be parsed as a tag).
	assert_eq(bb.find(": [important]"), -1)

# --- End-to-end through append_broadcast_message ---

func test_append_broadcast_message_writes_to_richtextlabel():
	var display := RichTextLabel.new()
	display.bbcode_enabled = true
	add_child_autofree(display)
	var input_box := LineEdit.new()
	add_child_autofree(input_box)
	var conn := _StubConnection.new()
	var chat := ChatController.new({
		chat_display = display,
		chat_input   = input_box,
		connection   = conn,
	})
	chat.append_broadcast_message({
		"category": "siege",
		"level": "warning",
		"message": "Castle Siege starts in 15 minutes!",
	})
	# RichTextLabel parsed the BBCode — visible text drops the tags.
	var visible := display.get_parsed_text()
	assert_string_contains(visible, "[siege]")
	assert_string_contains(visible, "Castle Siege starts in 15 minutes!")

# --- helpers ---

class _StubConnection extends RefCounted:
	var sent: Array = []
	func send_packet(id, payload = {}):
		sent.append({"id": id, "payload": payload})
