class_name ChatController
extends RefCounted

const _BroadcastLinkDispatcher = preload("res://scripts/ui/broadcast_link_dispatcher.gd")

## Chat log + input + send. Owns:
##   - chat_display (RichTextLabel) — the rolling chat log
##   - chat_input   (LineEdit)      — message entry
##   - the CHAT_SEND wire to the server
##   - jump-to-present button (optional) — shown when the user has scrolled
##     up and new messages arrive while away. Click → snap to bottom + hide.
##
## NOT owned: chat bubbles over player sprites. Those are tightly coupled
## to the player-sprite node tree and timer-based auto-free, so they stay
## in world.gd until a separate pass.
##
## Lifecycle: needs `connection` to send → construct in world.gd's setup(),
## not _ready(). See feedback_godot_controller_lifecycle memory.
##
## Scroll-respect rules:
##   - default behavior: at-bottom + new message → keep auto-scrolling
##     (RichTextLabel.scroll_following stays true).
##   - user scrolls up: scroll_following flipped to false, button stays
##     hidden until a new message arrives.
##   - new message arrives while scrolled-up: button appears with a
##     counter; chat does NOT jump to bottom, the user keeps reading.
##   - user scrolls back to bottom manually: button hides, scroll_following
##     re-enabled, counter reset.
##   - user clicks button: snap to bottom, button hides, counter reset,
##     scroll_following re-enabled.

# System-line color (soft gray) — visually contrasts with normal broadcast
# lines without yelling. Picked over warm cream so it reads as "ambient
# UI feedback" rather than "important game event".
const SYSTEM_COLOR := "#9ba0a8"

# BROADCAST_MESSAGE level → body color. Soft cream for info, amber for
# warning, alarm red for critical. Category badge is rendered in light
# gray regardless of level (it's a label, not the message).
const BROADCAST_INFO_COLOR     := "#c8c2a8"
const BROADCAST_WARNING_COLOR  := "#e0b441"
const BROADCAST_CRITICAL_COLOR := "#d0533a"
const BROADCAST_BADGE_COLOR    := "#9ba0a8"

# Fractional-pixel rounding tolerance when comparing scrollbar position
# to its max. Godot reports value as float; a 0.5px slack avoids
# false-negatives at the literal bottom.
const _AT_BOTTOM_TOLERANCE := 1.0

var _display: RichTextLabel
var _input: LineEdit
var _connection
var _world = null
var _jump_button: Button = null

# Scroll state. When true, new messages auto-scroll. Flipped to false the
# moment the user scrolls away from the bottom; flipped back on jump-to-
# present click or on the user manually scrolling back to bottom.
var _user_at_bottom: bool = true
# Number of new messages received since the user scrolled away. Reset on
# jump-to-present and on returning to bottom manually. Surfaced on the
# button label when > 0.
var _new_messages_since_scroll_away: int = 0
# Re-entrancy guard: while _append_line is mutating the scrollbar
# (scroll_following toggling, value restore via call_deferred), the
# scrollbar may emit `value_changed` signals that DO NOT represent a
# user-driven scroll. We ignore them while this flag is true.
var _suppress_scroll_callback: bool = false

func _init(refs: Dictionary) -> void:
	_display    = refs.chat_display
	_input      = refs.chat_input
	_connection = refs.connection
	# Optional — only callers that want broadcast link clicks dispatched
	# need to provide the world ref. Tests pass null and broadcast clicks
	# fall through to a no-op warning.
	_world      = refs.get("world", null)
	# Optional — when present, we manage its visibility + click handler.
	# Headless tests pass null and the scroll logic still runs (just
	# without the visible button affordance).
	_jump_button = refs.get("jump_button", null)
	if _connection == null:
		push_error("ChatController: null connection at construction — wiring bug")
	_input.text_submitted.connect(_on_submitted)
	# RichTextLabel emits meta_clicked when a [url=...] is clicked. We
	# JSON-encode the link Dictionary into the meta string and parse it
	# back here.
	if not _display.meta_clicked.is_connected(_on_meta_clicked):
		_display.meta_clicked.connect(_on_meta_clicked)

	# Wire scroll detection. The scrollbar's `value_changed` fires on every
	# change (programmatic OR user-driven), so we re-check at-bottom each
	# time and update auto-follow accordingly.
	var sb := _display.get_v_scroll_bar()
	if sb != null and not sb.value_changed.is_connected(_on_scroll_changed):
		sb.value_changed.connect(_on_scroll_changed)

	if _jump_button != null:
		_jump_button.visible = false
		if not _jump_button.pressed.is_connected(_on_jump_pressed):
			_jump_button.pressed.connect(_on_jump_pressed)

# Late-bind the world reference. Useful when ChatController is constructed
# before world.gd's setup() completes wiring (it isn't today, but tests
# can use this without rebuilding the controller).
func set_world(world) -> void:
	_world = world

# --- Incoming ---

# CHAT_BROADCAST handler. from_name=null → "?" placeholder (matches prior
# inline behaviour for messages whose sender we couldn't resolve).
func append_broadcast(from_name, msg: String) -> void:
	var name_str = from_name if from_name != null else "?"
	_append_line("[%s]: %s\n" % [name_str, msg])

# BROADCAST_MESSAGE handler. Renders a single chat line of the form:
#   [category] [sender_name] message
# in the level-appropriate color. `category` and `sender_name` are
# optional; if both are missing the line is just the colored body. If
# `link` is provided, the message body is wrapped in [url=<json>]...[/url]
# so it's clickable; meta_clicked then JSON-decodes and dispatches.
func append_broadcast_message(payload: Dictionary) -> void:
	_append_line(format_broadcast_bbcode(payload) + "\n")

# Pure-function BBCode formatter. Static so tests can assert on the
# output without instantiating a RichTextLabel + scene tree. Render rules:
#   - level → body color (info=cream, warning=amber, critical=alarm-red,
#     unknown→info)
#   - category present + non-empty → "[category]" badge prefix in light gray
#   - sender_name present + non-empty → "[sender_name]" badge after category
#   - link is Dictionary with non-empty `kind` → wrap body in
#     [url=<json>]...[/url], JSON-encoded so meta_clicked round-trips.
#   - link present but malformed (no `kind`) → plain body, warn once.
#   - any literal "[" in user-provided text is escaped to "[lb]" so a
#     stray bracket can't break the bbcode parser for the rest of the log.
static func format_broadcast_bbcode(payload: Dictionary) -> String:
	var level: String = String(payload.get("level", "info"))
	var category = payload.get("category", null)
	var sender_name = payload.get("sender_name", null)
	var raw_message: String = String(payload.get("message", ""))
	var link = payload.get("link", null)

	var body_color := _color_for_level(level)
	var safe_message := _escape_brackets(raw_message)

	var prefix := ""
	if category != null and not String(category).is_empty():
		prefix += "[color=%s][%s][/color] " % [BROADCAST_BADGE_COLOR, _escape_brackets(String(category))]
	if sender_name != null and not String(sender_name).is_empty():
		prefix += "[color=%s][%s][/color] " % [BROADCAST_BADGE_COLOR, _escape_brackets(String(sender_name))]

	var body_inner := safe_message
	if link is Dictionary and not String(link.get("kind", "")).is_empty():
		var meta := JSON.stringify(link)
		body_inner = "[url=%s]%s[/url]" % [meta, safe_message]
	elif link != null:
		push_warning("ChatController: broadcast link malformed, rendering as plain text: %s" % [link])

	var body := "[color=%s]%s[/color]" % [body_color, body_inner]
	return "%s%s" % [prefix, body]

# Maps level to body color. Unknown level falls back to info.
static func _color_for_level(level: String) -> String:
	match level:
		"warning":  return BROADCAST_WARNING_COLOR
		"critical": return BROADCAST_CRITICAL_COLOR
		_:          return BROADCAST_INFO_COLOR

# Same trick as append_system: a stray "[X]" in user-provided text must
# not parse as a bbcode tag. RichTextLabel parses "[lb]" as a literal "[".
static func _escape_brackets(text: String) -> String:
	return text.replace("[", "[lb]")

# RichTextLabel meta_clicked handler. The meta is the JSON-encoded link
# Dictionary we wrote in append_broadcast_message. Parse it and route
# through the dispatcher. Malformed JSON / unknown kind → warn, no-op.
func _on_meta_clicked(meta) -> void:
	var meta_str := String(meta)
	var parsed = JSON.parse_string(meta_str)
	if not (parsed is Dictionary):
		push_warning("ChatController: meta_clicked with non-JSON-Dict payload: %s" % [meta_str])
		return
	_BroadcastLinkDispatcher.dispatch(_world, parsed)

# System-line message: status events, casting hints, server SYSTEM_MESSAGE,
# inspect-tile reports, etc. Single colored line, no "[name]" prefix.
# Multi-line content (e.g. "Hay aquí:\n  • ...") is rendered as a single
# colored block by wrapping the whole text in [color] tags.
func append_system(msg: String) -> void:
	if msg == null or String(msg).is_empty():
		return
	# bbcode_enabled is true on ChatDisplay (see world.tscn). Escape
	# square brackets in the payload so a stray "[X]" doesn't get parsed
	# as a tag and break formatting for the rest of the log.
	var safe := String(msg).replace("[", "[lb]")
	_append_line("[color=%s]%s[/color]\n" % [SYSTEM_COLOR, safe])

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

# --- Scroll-respect ---

# Pure-function helper: should the chat snap to bottom on a new message?
# Inputs are the geometry of the scrollbar at the moment the message
# arrives, plus the previous "user was at bottom" flag.
#   - scroll_max == 0 → no scrollback yet → always auto-scroll
#   - prev_at_bottom true → user is reading the live tail → auto-scroll
#   - otherwise → user has scrolled up to read history → don't auto-scroll
# Static so tests can exercise the decision matrix without a scene tree.
static func should_auto_scroll(scroll_value: float, scroll_max: float, page_size: float, prev_at_bottom: bool) -> bool:
	if scroll_max <= 0.0:
		return true
	return prev_at_bottom or _is_at_bottom(scroll_value, scroll_max, page_size)

# True when the scrollbar's value is within `_AT_BOTTOM_TOLERANCE` pixels
# of the bottom of the scrollable range. Page size accounts for the
# visible viewport — at-bottom means "the last line is on screen".
static func _is_at_bottom(scroll_value: float, scroll_max: float, page_size: float) -> bool:
	if scroll_max <= 0.0:
		return true
	return scroll_value >= (scroll_max - page_size - _AT_BOTTOM_TOLERANCE)

# Append a line to the display, applying scroll-respect:
#   - if the user is at the bottom: keep scroll_following on, append, the
#     RichTextLabel auto-scrolls itself.
#   - if scrolled up: snapshot the scrollbar position before append, write
#     the line, restore the position so we don't yank the user's view, and
#     surface the jump-to-present button with a counter bump.
func _append_line(bbcode_line: String) -> void:
	var sb := _display.get_v_scroll_bar()
	if sb == null:
		# Defensive fallback — RichTextLabel always has a v_scroll_bar in
		# Godot 4, but tests can stub _display with a node missing it.
		_display.append_text(bbcode_line)
		return

	# `_user_at_bottom` is the single source of truth — maintained by
	# `_on_scroll_changed` (user-driven) and reset by `jump_to_present`.
	# We do NOT re-derive it from the scrollbar geometry here, because a
	# freshly-mounted RichTextLabel reports default Range geometry
	# (max=100, value=0, page=0) before any layout has happened, which
	# would falsely classify a brand-new chat as "scrolled up".

	# RichTextLabel + Range may emit `value_changed` while we mutate
	# scroll_following / max_value / value during the append. Suppress
	# our user-scroll detector for the duration of this call so we don't
	# react to our own programmatic changes.
	_suppress_scroll_callback = true

	if _user_at_bottom:
		# Following live feed — RichTextLabel will auto-scroll because
		# scroll_following stays true. Reset the away-counter so subsequent
		# scroll-aways start clean.
		_display.scroll_following = true
		_new_messages_since_scroll_away = 0
		_display.append_text(bbcode_line)
	else:
		# User is reading history — preserve their position. Disable auto-
		# follow before appending so the RichTextLabel doesn't fight us,
		# then restore the scrollbar value after.
		_display.scroll_following = false
		var saved_value: float = sb.value
		_display.append_text(bbcode_line)
		# Defer the restore so the scrollbar's max_value has been
		# recomputed for the new content (Godot updates it after the
		# append settles). One-off node call, no per-frame polling.
		sb.set_deferred("value", saved_value)
		_new_messages_since_scroll_away += 1

	_suppress_scroll_callback = false
	_update_jump_button()

# Scrollbar value_changed handler. Fires on every value change, including
# the programmatic call_deferred from _append_line. We use it to detect
# when the user has manually scrolled back to the bottom and re-enable
# auto-follow.
func _on_scroll_changed(_value: float) -> void:
	if _suppress_scroll_callback:
		return
	var sb := _display.get_v_scroll_bar()
	if sb == null:
		return
	var at_bottom := _is_at_bottom(sb.value, sb.max_value, sb.page)
	if at_bottom and not _user_at_bottom:
		# User just scrolled back to the live tail manually.
		_user_at_bottom = true
		_display.scroll_following = true
		_new_messages_since_scroll_away = 0
		_update_jump_button()
	elif not at_bottom and _user_at_bottom:
		# User just scrolled up, off the live tail.
		_user_at_bottom = false
		_display.scroll_following = false
		# Don't touch the counter — it tracks new messages SINCE this
		# scroll-away, which is by definition zero right now.
		_update_jump_button()

# Jump-to-present button click handler: snap to bottom, hide, reset.
func _on_jump_pressed() -> void:
	jump_to_present()

# Programmatic jump-to-present (also called by the button). Public so
# tests + world.gd can trigger from the keyboard if desired.
func jump_to_present() -> void:
	var sb := _display.get_v_scroll_bar()
	if sb != null:
		sb.value = sb.max_value
	_user_at_bottom = true
	_display.scroll_following = true
	_new_messages_since_scroll_away = 0
	_update_jump_button()

# Visibility + label rule for the jump-to-present button:
#   show when user is scrolled up AND at least one message has arrived
#   since the scroll-away. Counter shown alongside the arrow when > 0.
func _update_jump_button() -> void:
	if _jump_button == null:
		return
	var should_show := (not _user_at_bottom) and _new_messages_since_scroll_away > 0
	_jump_button.visible = should_show
	if should_show:
		# Compact label: just the arrow when there's no count, "↓ N" when
		# there's a count to surface. Keeps the button a fixed width even
		# when the count grows.
		_jump_button.text = "↓ %d" % _new_messages_since_scroll_away

# --- Test hooks ---

# Read-only accessors for tests asserting state without poking privates.
func is_user_at_bottom() -> bool:
	return _user_at_bottom

func new_messages_since_scroll_away() -> int:
	return _new_messages_since_scroll_away
