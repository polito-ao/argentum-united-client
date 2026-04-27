extends GutTest
## Unit tests for AudioSettingsController. Real HSlider / Label widgets
## are constructed without the scene tree -- the controller wires
## value_changed signals + reads/writes their .value.

const PacketIds = preload("res://scripts/network/packet_ids.gd")
const AudioSettingsControllerScript = preload("res://scripts/ui/audio_settings_controller.gd")

var ctrl
var conn: _StubConnection
var master_slider: HSlider
var music_slider: HSlider
var sfx_slider: HSlider
var master_label: Label
var music_label: Label
var sfx_label: Label


func before_each():
	conn = _StubConnection.new()
	master_slider = HSlider.new()
	music_slider = HSlider.new()
	sfx_slider = HSlider.new()
	master_label = Label.new()
	music_label = Label.new()
	sfx_label = Label.new()
	add_child_autofree(master_slider)
	add_child_autofree(music_slider)
	add_child_autofree(sfx_slider)
	add_child_autofree(master_label)
	add_child_autofree(music_label)
	add_child_autofree(sfx_label)

	ctrl = AudioSettingsControllerScript.new({
		connection     = conn,
		master_slider  = master_slider,
		music_slider   = music_slider,
		sfx_slider     = sfx_slider,
		master_label   = master_label,
		music_label    = music_label,
		sfx_label      = sfx_label,
	})


# --- defaults ---------------------------------------------------------------

func test_defaults_apply_when_no_saved_values():
	ctrl.set_values({})
	assert_almost_eq(master_slider.value, 0.80, 0.001)
	assert_almost_eq(music_slider.value, 0.70, 0.001)
	assert_almost_eq(sfx_slider.value, 0.90, 0.001)


func test_defaults_render_percentage_label():
	ctrl.set_values({})
	assert_eq(master_label.text, "80%")
	assert_eq(music_label.text, "70%")
	assert_eq(sfx_label.text, "90%")


# --- saved values --------------------------------------------------------

func test_set_values_pushes_each_axis_into_its_slider():
	ctrl.set_values({"master": 0.5, "music": 0.25, "sfx": 1.0})
	assert_almost_eq(master_slider.value, 0.5, 0.001)
	assert_almost_eq(music_slider.value, 0.25, 0.001)
	assert_almost_eq(sfx_slider.value, 1.0, 0.001)


func test_set_values_does_not_emit_save_packet():
	# Loading saved state must not bounce a SETTINGS_SAVE back to the server,
	# otherwise opening the overlay would always re-save what's already there.
	ctrl.set_values({"master": 0.5, "music": 0.5, "sfx": 0.5})
	assert_eq(conn.sent.size(), 0, "no packets emitted while loading saved state")


func test_set_values_coerces_strings_and_ints():
	# msgpack lax shapes -- we accept "0.5", 0.5, 1, etc.
	ctrl.set_values({"master": "0.5", "music": 1, "sfx": 0.0})
	assert_almost_eq(master_slider.value, 0.5, 0.001)
	assert_almost_eq(music_slider.value, 1.0, 0.001)
	assert_almost_eq(sfx_slider.value, 0.0, 0.001)


func test_set_values_clamps_out_of_range():
	ctrl.set_values({"master": 2.0, "music": -0.5, "sfx": 0.5})
	assert_almost_eq(master_slider.value, 1.0, 0.001)
	assert_almost_eq(music_slider.value, 0.0, 0.001)


# --- live slider -> save -----------------------------------------------------

func test_slider_change_emits_settings_save():
	ctrl.set_values({})  # establish baseline
	master_slider.value = 0.42
	# The signal fires synchronously when value differs from the previous one.
	var pkt = _first_packet(PacketIds.SETTINGS_SAVE)
	assert_not_null(pkt)
	assert_true(pkt.payload.has("audio"))
	assert_almost_eq(pkt.payload.audio.master, 0.42, 0.001)


func test_slider_change_propagates_to_audio_server():
	# Master bus volume should reflect the slider after a drag.
	ctrl.set_values({})
	master_slider.value = 0.1  # quiet
	var idx := AudioServer.get_bus_index("Master")
	# Linear 0.1 -> ~-20 dB, well below 0 dB. Don't pin an exact dB; just
	# assert the bus is below max.
	assert_lt(AudioServer.get_bus_volume_db(idx), 0.0)


func test_slider_zero_mutes_bus():
	ctrl.set_values({})
	music_slider.value = 0.0
	var idx := AudioServer.get_bus_index("Music")
	assert_true(AudioServer.is_bus_mute(idx))
	# Restore a sane non-mute value so other tests aren't poisoned by mute state.
	music_slider.value = 0.7


func test_current_values_returns_wire_shape():
	ctrl.set_values({"master": 0.4, "music": 0.6, "sfx": 0.8})
	var v = ctrl.current_values()
	assert_almost_eq(v.master, 0.4, 0.001)
	assert_almost_eq(v.music, 0.6, 0.001)
	assert_almost_eq(v.sfx, 0.8, 0.001)


# --- helpers ----------------------------------------------------------------

func _first_packet(id: int):
	var matches = conn.sent.filter(func(p): return p.id == id)
	return matches.front() if matches.size() > 0 else null


class _StubConnection extends RefCounted:
	var sent: Array = []
	func send_packet(id, payload = {}):
		sent.append({"id": id, "payload": payload})
