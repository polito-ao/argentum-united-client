class_name ReconnectModal
extends Control

## Rocket-League-style "would you like to rejoin your match in progress?" modal.
##
## Server fires RECONNECT_PROMPT on (re-)login when the player has an
## in-progress `Character.in_match_id`. The modal shows match metadata, a
## live countdown computed from `expires_at`, and Si / No buttons. The
## answer fires through the `responded(match_id, accept)` signal; the
## controller above turns that into a RECONNECT_RESPONSE packet.
##
## Pressing Esc is treated as "No" (decline + close). Hitting the
## countdown of 0 closes the modal silently -- the server has already
## auto-forfeited at that point so a Yes click would race the auth
## anyway, and pestering the user with a "you ran out of time" toast is
## noise we can add later if anyone misses it.
##
## The Control covers the full viewport with `mouse_filter = STOP` so it
## blocks clicks to whatever scene is underneath.

signal responded(match_id: String, accept: bool)

# How often the countdown label re-renders. The wall-clock math runs off
# unix-epoch seconds so the cadence is purely cosmetic; 0.5s feels live
# without burning a frame.
const _TICK_INTERVAL_SEC := 0.5

@onready var _title_label: Label    = $Dimmer/Panel/VBox/TitleLabel
@onready var _body_label: RichTextLabel = $Dimmer/Panel/VBox/BodyLabel
@onready var _countdown_label: Label = $Dimmer/Panel/VBox/CountdownLabel
@onready var _yes_button: Button    = $Dimmer/Panel/VBox/Buttons/YesButton
@onready var _no_button: Button     = $Dimmer/Panel/VBox/Buttons/NoButton
@onready var _tick_timer: Timer     = $TickTimer

# Currently-displayed match. Empty string means "modal is idle / hidden".
var _match_id: String = ""
var _match_type: String = ""
var _expires_at: int = 0
# Injected clock for tests. Defaults to real wall-clock unix seconds.
var _clock: Callable = Time.get_unix_time_from_system


func _ready() -> void:
	# Modal default: invisible, but Control still exists in the tree so
	# external code can call show_for() at any time.
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP

	if _yes_button != null:
		_yes_button.pressed.connect(_on_yes_pressed)
	if _no_button != null:
		_no_button.pressed.connect(_on_no_pressed)
	if _tick_timer != null:
		_tick_timer.wait_time = _TICK_INTERVAL_SEC
		_tick_timer.one_shot = false
		if not _tick_timer.timeout.is_connected(_on_tick):
			_tick_timer.timeout.connect(_on_tick)


# --- public API -------------------------------------------------------------


# Display the modal for a freshly-arrived RECONNECT_PROMPT. Replaces any
# already-visible modal whose match_id differs; same-match calls are
# idempotent.
#
# `match_type` is informational (Spanish-rendered match label, e.g.
# "Mini LoL Ranked"). `expires_at` is unix-epoch seconds; everything
# past that is rendered "expira en 0s" and we silently auto-close.
func show_for(match_id: String, match_type: String, expires_at: int) -> void:
	if match_id == "":
		# Defensive: the server contract guarantees a match_id, but if it
		# ever ships an empty string we'd be unable to round-trip the
		# response anyway. Drop on the floor.
		return
	if visible and match_id == _match_id:
		# Server re-sent the same prompt (network jitter, reconnect
		# during reconnect). Refresh the countdown deadline silently --
		# the user's modal stays put.
		_expires_at = expires_at
		_render_countdown()
		return

	_match_id = match_id
	_match_type = match_type
	_expires_at = expires_at

	if _title_label != null:
		_title_label.text = "RECONECTAR"
	if _body_label != null:
		_body_label.bbcode_enabled = true
		_body_label.text = _format_body(match_type)
	_render_countdown()

	visible = true
	if _tick_timer != null:
		_tick_timer.start()
	# Yes is the affirmative default; focus it so Enter accepts. The
	# user's keyboard-first habits matter here -- they probably want to
	# get back into their match without grabbing the mouse.
	if _yes_button != null:
		_yes_button.grab_focus()


# Returns true if the modal is currently visible to the user.
func is_open() -> bool:
	return visible and _match_id != ""


# Returns the match_id the modal is currently displaying, or "" if idle.
func current_match_id() -> String:
	return _match_id if visible else ""


# Override the wall clock for headless tests. The callable must return a
# unix-epoch float (seconds), like Time.get_unix_time_from_system.
func set_clock(clock: Callable) -> void:
	_clock = clock
	# Re-render so a freshly-set clock reflects immediately.
	if visible:
		_render_countdown()


# --- input handling ---------------------------------------------------------


func _unhandled_input(event: InputEvent) -> void:
	# Esc dismisses as "No". We don't want to use ui_cancel directly
	# because settings overlays in world.gd also bind to it; covering
	# Escape via _unhandled_input means the modal eats it before the
	# world scene's _unhandled_key_input ever sees it.
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_on_no_pressed()
			get_viewport().set_input_as_handled()


# --- internal ---------------------------------------------------------------


func _on_yes_pressed() -> void:
	_emit_and_close(true)


func _on_no_pressed() -> void:
	_emit_and_close(false)


func _emit_and_close(accept: bool) -> void:
	var match_id = _match_id
	_close()
	# Emit AFTER closing so listeners see a consistent "modal idle" state
	# if they want to re-trigger another modal (e.g. queue scenarios).
	if match_id != "":
		responded.emit(match_id, accept)


func _close() -> void:
	visible = false
	_match_id = ""
	_match_type = ""
	_expires_at = 0
	if _tick_timer != null and not _tick_timer.is_stopped():
		_tick_timer.stop()


func _on_tick() -> void:
	_render_countdown()
	if _seconds_remaining() <= 0:
		# Server has auto-forfeited by now. Close silently -- no signal
		# fired, the server did its thing.
		_close()


func _render_countdown() -> void:
	if _countdown_label == null:
		return
	var remaining = _seconds_remaining()
	if remaining <= 0:
		_countdown_label.text = "(expira en 0s)"
	else:
		_countdown_label.text = "(expira en %ds)" % remaining


func _seconds_remaining() -> int:
	if _expires_at <= 0:
		return 0
	var now := int(_clock.call())
	return max(0, _expires_at - now)


func _format_body(match_type: String) -> String:
	# Match-type is informational. Spanish content language (per CLAUDE.md).
	# Rendered as a single paragraph; the [b]...[/b] tag is the BBCode
	# emphasis the panel's RichTextLabel can parse.
	if match_type == null or match_type == "":
		return "Parece que dejaste una partida en curso. Quieres reconectarte?"
	return "Parece que dejaste una partida en curso ([b]%s[/b]). Quieres reconectarte?" % match_type
