class_name AudioSettingsController
extends RefCounted

## Settings-overlay controller for the three audio sliders.
##
## Owns three HSliders (Master / Music / SFX) and propagates value changes
## both to the live AudioServer (so the player hears the change instantly)
## and to the SETTINGS_SAVE packet payload (so the server persists the
## next character-select-merged shape).
##
## Wire shape -- mirrors the `effect_choices` pattern in EffectPickerController:
##
##   SETTINGS_SAVE { audio: { master: 0.0..1.0, music: 0.0..1.0, sfx: 0.0..1.0 } }
##
## On open: set_values() pushes the saved settings into the sliders without
## triggering the save side-effect (we don't want the act of opening the
## overlay to send a packet). On slider change: push to the bus AND to the
## server via SETTINGS_SAVE.
##
## Defaults: master 0.80, music 0.70, sfx 0.90 -- biased high so newcomers
## hear the soundtrack without fiddling. Keep in sync with DEFAULTS below
## AND server-side default state. If they ever drift, the server is
## authoritative on next CHARACTER_SELECT.

const PacketIds = preload("res://scripts/network/packet_ids.gd")

const DEFAULTS := {
	"master": 0.80,
	"music":  0.70,
	"sfx":    0.90,
}

# Bus name on the AudioServer side. Settings dictionary key on the wire
# is the lowercase version below.
const BUS_FOR_KEY := {
	"master": "Master",
	"music":  "Music",
	"sfx":    "SFX",
}

var _connection
var _master_slider: HSlider
var _music_slider: HSlider
var _sfx_slider: HSlider
var _master_label: Label
var _music_label: Label
var _sfx_label: Label

# True while we are programmatically setting slider values from a saved
# state. Slider.value_changed fires unconditionally, so without this guard
# every set_values() would fire 3 SETTINGS_SAVE packets.
var _suppress_save := false


func _init(refs: Dictionary) -> void:
	_connection      = refs.get("connection", null)
	_master_slider   = refs.get("master_slider", null)
	_music_slider    = refs.get("music_slider", null)
	_sfx_slider      = refs.get("sfx_slider", null)
	_master_label    = refs.get("master_label", null)
	_music_label     = refs.get("music_label", null)
	_sfx_label       = refs.get("sfx_label", null)

	if _connection == null:
		push_error("AudioSettingsController: null connection -- wiring bug")

	_wire_slider(_master_slider, "master", _master_label)
	_wire_slider(_music_slider, "music", _music_label)
	_wire_slider(_sfx_slider, "sfx", _sfx_label)


# Apply saved settings (e.g. from CHARACTER_SELECT). Slider values get
# pushed to the AudioServer too. Does NOT trigger a save -- the server
# already has these values.
func set_values(audio_settings: Dictionary) -> void:
	_suppress_save = true
	_apply("master", _read(audio_settings, "master", DEFAULTS["master"]))
	_apply("music",  _read(audio_settings, "music",  DEFAULTS["music"]))
	_apply("sfx",    _read(audio_settings, "sfx",    DEFAULTS["sfx"]))
	_suppress_save = false


# Read current slider values as a wire-shape Dictionary. Used by world.gd
# when building the SETTINGS_SAVE payload that bundles audio with key
# bindings + effect choices.
func current_values() -> Dictionary:
	return {
		"master": _slider_value(_master_slider, DEFAULTS["master"]),
		"music":  _slider_value(_music_slider, DEFAULTS["music"]),
		"sfx":    _slider_value(_sfx_slider, DEFAULTS["sfx"]),
	}


# --- private ---------------------------------------------------------------

func _wire_slider(slider: HSlider, key: String, label: Label) -> void:
	if slider == null:
		return
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = DEFAULTS[key]
	if label != null:
		label.text = _format_pct(DEFAULTS[key])
	slider.value_changed.connect(func(v): _on_slider_changed(key, v))


func _on_slider_changed(key: String, value: float) -> void:
	_apply(key, value)
	if _suppress_save:
		return
	_send_save()


func _apply(key: String, value: float) -> void:
	value = clamp(value, 0.0, 1.0)
	var slider := _slider_for(key)
	if slider != null and not is_equal_approx(slider.value, value):
		slider.value = value
	# Push to the AudioServer so the change is audible immediately.
	# AudioPlayer is a global autoload.
	AudioPlayer.set_bus_volume_linear(BUS_FOR_KEY[key], value)
	var label := _label_for(key)
	if label != null:
		label.text = _format_pct(value)


func _send_save() -> void:
	if _connection == null:
		return
	_connection.send_packet(PacketIds.SETTINGS_SAVE, {"audio": current_values()})


func _slider_for(key: String) -> HSlider:
	match key:
		"master": return _master_slider
		"music":  return _music_slider
		"sfx":    return _sfx_slider
	return null


func _label_for(key: String) -> Label:
	match key:
		"master": return _master_label
		"music":  return _music_label
		"sfx":    return _sfx_label
	return null


func _slider_value(slider: HSlider, fallback: float) -> float:
	if slider == null:
		return fallback
	return clamp(slider.value, 0.0, 1.0)


# Defensive numeric coerce: msgpack may yield Float / Int / String here.
func _read(dict: Dictionary, key: String, fallback: float) -> float:
	if not dict.has(key):
		return fallback
	var v = dict[key]
	if v is float or v is int:
		return clamp(float(v), 0.0, 1.0)
	if v is String and v.is_valid_float():
		return clamp(float(v), 0.0, 1.0)
	return fallback


func _format_pct(v: float) -> String:
	return "%d%%" % int(round(v * 100.0))
