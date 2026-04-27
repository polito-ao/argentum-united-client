class_name ChatController
extends RefCounted

const _BroadcastLinkDispatcher = preload("res://scripts/ui/broadcast_link_dispatcher.gd")

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

var _display: RichTextLabel
var _input: LineEdit
var _connection
var _world = null

func _init(refs: Dictionary) -> void:
	_display    = refs.chat_display
	_input      = refs.chat_input
	_connection = refs.connection
	# Optional — only callers that want broadcast link clicks dispatched
	# need to provide the world ref. Tests pass null and broadcast clicks
	# fall through to a no-op warning.
	_world      = refs.get("world", null)
	if _connection == null:
		push_error("ChatController: null connection at construction — wiring bug")
	_input.text_submitted.connect(_on_submitted)
	# RichTextLabel emits meta_clicked when a [url=...] is clicked. We
	# JSON-encode the link Dictionary into the meta string and parse it
	# back here.
	if not _display.meta_clicked.is_connected(_on_meta_clicked):
		_display.meta_clicked.connect(_on_meta_clicked)

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
	_display.append_text("[%s]: %s\n" % [name_str, msg])

# BROADCAST_MESSAGE handler. Renders a single chat line of the form:
#   [category] [sender_name] message
# in the level-appropriate color. `category` and `sender_name` are
# optional; if both are missing the line is just the colored body. If
# `link` is provided, the message body is wrapped in [url=<json>]...[/url]
# so it's clickable; meta_clicked then JSON-decodes and dispatches.
func append_broadcast_message(payload: Dictionary) -> void:
	_display.append_text(format_broadcast_bbcode(payload) + "\n")

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
	_display.append_text("[color=%s]%s[/color]\n" % [SYSTEM_COLOR, safe])

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
