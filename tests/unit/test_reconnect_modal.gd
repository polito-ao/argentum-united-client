extends GutTest
## Unit tests for the ReconnectModal scene + ReconnectModalController.
##
## The modal has real Control children (Buttons, Labels, RichTextLabel,
## Timer) so we instantiate the .tscn and let it auto-wire. The
## controller side is exercised with a stub host (anything that accepts
## add_child) and a stub connection.

const PacketIds = preload("res://scripts/network/packet_ids.gd")
const ReconnectModalScene := preload("res://scenes/match/reconnect_modal.tscn")
const ReconnectModalControllerScript = preload("res://scripts/ui/reconnect_modal_controller.gd")

# Mock-clock cursor in unix-epoch seconds. Tests advance this directly
# and the modal's `_seconds_remaining` reads through it.
var _now_seconds: int = 1_700_000_000

# Captured `responded(match_id, accept)` invocations for assertions.
var _signal_log: Array = []

var modal: ReconnectModal


func before_each():
	_now_seconds = 1_700_000_000
	_signal_log = []
	modal = ReconnectModalScene.instantiate()
	add_child_autofree(modal)
	modal.set_clock(_clock)
	modal.responded.connect(func(mid, accept): _signal_log.append({"match_id": mid, "accept": accept}))


# --- show_for displays the modal -------------------------------------------


func test_show_for_makes_modal_visible():
	assert_false(modal.visible, "modal starts hidden")
	modal.show_for("m-1", "Mini LoL", _now_seconds + 30)
	assert_true(modal.visible)
	assert_true(modal.is_open())
	assert_eq(modal.current_match_id(), "m-1")


func test_show_for_renders_title_and_body():
	modal.show_for("m-1", "Mini LoL", _now_seconds + 30)
	var title: Label = modal.get_node("Dimmer/Panel/VBox/TitleLabel")
	var body: RichTextLabel = modal.get_node("Dimmer/Panel/VBox/BodyLabel")
	assert_eq(title.text, "RECONECTAR")
	# match_type is rendered into the body line. We don't pin the exact
	# Spanish copy -- just that it includes the type for context.
	assert_true(body.text.find("Mini LoL") >= 0, "body should mention match_type, got: %s" % body.text)


func test_show_for_with_blank_match_type_omits_type():
	modal.show_for("m-1", "", _now_seconds + 30)
	var body: RichTextLabel = modal.get_node("Dimmer/Panel/VBox/BodyLabel")
	# No bracket clause when match_type is empty.
	assert_eq(body.text.find("["), -1, "blank match_type should not render a parenthesised tag in body")


func test_show_for_with_empty_match_id_is_no_op():
	modal.show_for("", "Mini LoL", _now_seconds + 30)
	assert_false(modal.visible, "blank match_id should not display the modal")


# --- duplicate-prompt dedupe ------------------------------------------------


func test_show_for_same_match_id_refreshes_deadline_only():
	modal.show_for("m-1", "Mini LoL", _now_seconds + 30)
	# Second prompt for the SAME match with a NEW deadline -- should
	# silently replace the deadline, leave visible state alone.
	modal.show_for("m-1", "Mini LoL", _now_seconds + 60)
	assert_eq(modal.current_match_id(), "m-1")
	var countdown: Label = modal.get_node("Dimmer/Panel/VBox/CountdownLabel")
	assert_eq(countdown.text, "(expira en 60s)")


func test_show_for_different_match_id_replaces():
	modal.show_for("m-1", "Mini LoL", _now_seconds + 30)
	modal.show_for("m-2", "Coliseum", _now_seconds + 25)
	assert_eq(modal.current_match_id(), "m-2", "newer match_id replaces older")


# --- Yes / No buttons -------------------------------------------------------


func test_yes_button_emits_responded_with_accept_true():
	modal.show_for("m-77", "Mini LoL", _now_seconds + 30)
	var yes_btn: Button = modal.get_node("Dimmer/Panel/VBox/Buttons/YesButton")
	yes_btn.pressed.emit()
	assert_eq(_signal_log.size(), 1)
	assert_eq(_signal_log[0].match_id, "m-77")
	assert_true(_signal_log[0].accept)
	assert_false(modal.visible, "modal closes after responding")


func test_no_button_emits_responded_with_accept_false():
	modal.show_for("m-77", "Mini LoL", _now_seconds + 30)
	var no_btn: Button = modal.get_node("Dimmer/Panel/VBox/Buttons/NoButton")
	no_btn.pressed.emit()
	assert_eq(_signal_log.size(), 1)
	assert_eq(_signal_log[0].match_id, "m-77")
	assert_false(_signal_log[0].accept)
	assert_false(modal.visible)


# --- countdown ticker -------------------------------------------------------


func test_countdown_decrements_with_clock():
	modal.show_for("m-1", "Mini LoL", _now_seconds + 23)
	var countdown: Label = modal.get_node("Dimmer/Panel/VBox/CountdownLabel")
	assert_eq(countdown.text, "(expira en 23s)")
	# Advance the mock clock 5s. Re-trigger render via set_clock (which
	# the modal calls on visible state).
	_now_seconds += 5
	modal.set_clock(_clock)
	assert_eq(countdown.text, "(expira en 18s)")


func test_countdown_floors_at_zero_when_deadline_passed():
	modal.show_for("m-1", "Mini LoL", _now_seconds + 5)
	_now_seconds += 100
	modal.set_clock(_clock)
	# The render call happens synchronously via set_clock; modal stays
	# visible until _on_tick (timer-driven) closes it. We assert the
	# label here, separate auto-close test below.
	var countdown: Label = modal.get_node("Dimmer/Panel/VBox/CountdownLabel")
	assert_eq(countdown.text, "(expira en 0s)")


func test_tick_auto_closes_when_countdown_hits_zero():
	# Skip the timer; call the private tick handler directly with
	# the clock past the deadline.
	modal.show_for("m-1", "Mini LoL", _now_seconds + 1)
	_now_seconds += 5
	modal._on_tick()
	assert_false(modal.visible, "auto-close fires silently on timeout")
	assert_eq(_signal_log.size(), 0, "auto-close does NOT emit responded -- server already forfeited")


# --- Esc dismiss ------------------------------------------------------------


func test_escape_dismisses_as_no():
	modal.show_for("m-9", "Mini LoL", _now_seconds + 30)
	# Synthesize the Esc keypress the way the modal expects.
	var ev := InputEventKey.new()
	ev.keycode = KEY_ESCAPE
	ev.pressed = true
	ev.echo = false
	modal._unhandled_input(ev)
	assert_eq(_signal_log.size(), 1)
	assert_eq(_signal_log[0].match_id, "m-9")
	assert_false(_signal_log[0].accept, "Esc is treated as decline")
	assert_false(modal.visible)


func test_escape_when_hidden_is_noop():
	# Modal hasn't been shown — Esc should not fire a phantom signal.
	var ev := InputEventKey.new()
	ev.keycode = KEY_ESCAPE
	ev.pressed = true
	ev.echo = false
	modal._unhandled_input(ev)
	assert_eq(_signal_log.size(), 0)


# --- ReconnectModalController integration -----------------------------------


func test_controller_handle_prompt_displays_modal():
	var host := Node.new()
	add_child_autofree(host)
	var conn := _StubConnection.new()
	var ctrl = ReconnectModalControllerScript.new({
		host         = host,
		connection   = conn,
		modal_scene  = ReconnectModalScene,
	})
	ctrl.handle_prompt({
		"match_id":   "m-42",
		"match_type": "Mini LoL Ranked",
		"expires_at": _now_seconds + 30,
	})
	assert_true(ctrl.is_open())
	assert_eq(ctrl.current_match_id(), "m-42")


func test_controller_yes_response_sends_packet():
	var host := Node.new()
	add_child_autofree(host)
	var conn := _StubConnection.new()
	var ctrl = ReconnectModalControllerScript.new({
		host         = host,
		connection   = conn,
		modal_scene  = ReconnectModalScene,
	})
	ctrl.handle_prompt({
		"match_id":   "m-42",
		"match_type": "Mini LoL Ranked",
		"expires_at": _now_seconds + 30,
	})
	# Click Yes via the modal's signal -- bypasses the button so we
	# don't depend on input-event plumbing.
	var modal_node = host.get_child(0)
	modal_node.responded.emit("m-42", true)

	assert_eq(conn.sent.size(), 1)
	assert_eq(conn.sent[0].id, PacketIds.RECONNECT_RESPONSE)
	assert_eq(conn.sent[0].payload.match_id, "m-42")
	assert_true(conn.sent[0].payload.accept)


func test_controller_no_response_sends_packet_with_accept_false():
	var host := Node.new()
	add_child_autofree(host)
	var conn := _StubConnection.new()
	var ctrl = ReconnectModalControllerScript.new({
		host         = host,
		connection   = conn,
		modal_scene  = ReconnectModalScene,
	})
	ctrl.handle_prompt({
		"match_id":   "m-99",
		"match_type": "Coliseum",
		"expires_at": _now_seconds + 30,
	})
	var modal_node = host.get_child(0)
	modal_node.responded.emit("m-99", false)

	assert_eq(conn.sent.size(), 1)
	assert_eq(conn.sent[0].id, PacketIds.RECONNECT_RESPONSE)
	assert_false(conn.sent[0].payload.accept)


func test_controller_blank_match_id_is_no_op():
	var host := Node.new()
	add_child_autofree(host)
	var conn := _StubConnection.new()
	var ctrl = ReconnectModalControllerScript.new({
		host         = host,
		connection   = conn,
		modal_scene  = ReconnectModalScene,
	})
	ctrl.handle_prompt({"match_id": "", "match_type": "x", "expires_at": 0})
	assert_false(ctrl.is_open())
	assert_eq(host.get_child_count(), 0, "controller never instantiated the modal scene")


func test_controller_duplicate_prompt_does_not_create_second_modal():
	var host := Node.new()
	add_child_autofree(host)
	var conn := _StubConnection.new()
	var ctrl = ReconnectModalControllerScript.new({
		host         = host,
		connection   = conn,
		modal_scene  = ReconnectModalScene,
	})
	ctrl.handle_prompt({
		"match_id":   "m-1",
		"match_type": "Mini LoL",
		"expires_at": _now_seconds + 30,
	})
	ctrl.handle_prompt({
		"match_id":   "m-1",
		"match_type": "Mini LoL",
		"expires_at": _now_seconds + 60,
	})
	# Same match_id -- only one modal child instance.
	assert_eq(host.get_child_count(), 1)


# --- packet ID sanity check -------------------------------------------------


func test_packet_ids_are_at_documented_slots():
	# The server contract pins these specific IDs. validate_server_config
	# is the runtime safety net; this test is the static one so a bad
	# rebase that bumps the constants gets caught at unit-test time.
	assert_eq(PacketIds.RECONNECT_PROMPT, 0x008F)
	assert_eq(PacketIds.RECONNECT_RESPONSE, 0x00C0)


# --- helpers ----------------------------------------------------------------


# Mock-clock callable. Returns the integer cursor as a unix-epoch
# float, the same shape `Time.get_unix_time_from_system` returns.
func _clock() -> float:
	return float(_now_seconds)


class _StubConnection extends RefCounted:
	var sent: Array = []
	func send_packet(id, payload = {}):
		sent.append({"id": id, "payload": payload})
