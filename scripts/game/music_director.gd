extends Node

## MusicDirector — autoload that picks the right music track based on:
##   - the current scene ("login" / "character_select" / "world")
##   - the server-emitted music_id (cities and special maps)
##   - the local time of day (day/night fallback for open-world maps)
##
## The director owns ONE AudioStreamPlayer wired to the "Music" bus and
## crossfades between resolved tracks. Tracks live in
## `assets/audio/music_curated/` and are committed (small, original works).
##
## Continuous music across scene transitions: if the resolution doesn't
## change (e.g. login -> character_select both pick "clasica-ao.ogg"), the
## director keeps the existing playback going without restarting it.
##
## Architecture notes:
##   - resolve_track() and is_night() are pure static functions, fully
##     testable without the scene tree.
##   - The mutable side (crossfade, scene tracking, periodic refresh) is
##     intentionally kept thin and is exercised by integration use.
##   - Future contexts (siege, match lobby, combat) plug in by adding new
##     scene names + matching branches to resolve_track().

const MUSIC_DIR := "res://assets/audio/music_curated/"

# Crossfade duration when the resolved track changes. 800 ms is slightly
# longer than the legacy AudioPlayer's 500 ms -- the curated tracks are
# longer / more atmospheric, and the longer fade feels less jarring.
const CROSSFADE_SECONDS := 0.8

# Periodic re-evaluation cadence for time-of-day flips. Every minute is
# plenty: the only boundary that matters is 19:00 and 05:30, and we don't
# need sub-minute precision on either.
const REFRESH_INTERVAL_SECONDS := 60.0

# Curated overrides keyed by the server's music_id (mirrors Cucsi's
# MapaN.dat MusicNum). These trump the time-of-day fallback.
const CURATED_BY_MUSIC_ID := {
	7: "ulla.ogg",  # Ullathorpe
	# Add more cities here as their tracks ship.
}

const TRACK_LOGIN := "clasica-ao.ogg"
const TRACK_CHAR_SELECT := "clasica-ao.ogg"
const TRACK_OPEN_WORLD_DAY := "open-world-day.mp3"
const TRACK_OPEN_WORLD_NIGHT := "open-world-night.mp3"

# Day/night boundary helper. Mirrors character_select.gd's _is_night so the
# bg switch and the music switch flip at the same moment. Pure function.
#
#   Night: 19:00 (inclusive) through 05:30 (exclusive)
#   Day:   05:30 (inclusive) through 19:00 (exclusive)
#
# Tests pass minute=0 by default; the 05:30 boundary case exercises the
# minute branch via is_night_at(hour, minute).
static func is_night(hour: int) -> bool:
	return is_night_at(hour, 0)


static func is_night_at(hour: int, minute: int) -> bool:
	if hour >= 19:
		return true
	if hour < 5:
		return true
	if hour == 5 and minute < 30:
		return true
	return false


# Pure resolution function -- given the current scene, the latest
# server-emitted music_id, and the local hour, pick a track filename
# (relative to MUSIC_DIR) or return "" for silence.
#
# music_id <= 0 means "no map music" -- fall through to the time-of-day
# fallback. Same for unknown ids.
static func resolve_track(scene: String, music_id: int, hour: int) -> String:
	match scene:
		"login":
			return TRACK_LOGIN
		"character_select":
			return TRACK_CHAR_SELECT
		"world":
			if music_id > 0 and CURATED_BY_MUSIC_ID.has(music_id):
				return String(CURATED_BY_MUSIC_ID[music_id])
			return TRACK_OPEN_WORLD_NIGHT if is_night(hour) else TRACK_OPEN_WORLD_DAY
		_:
			return ""


# --- mutable runtime state ------------------------------------------------

var _scene: String = ""
var _music_id: int = 0
var _current_track: String = ""

var _player: AudioStreamPlayer
var _stream_cache: Dictionary = {}  # filename -> AudioStream
var _warned_missing: Dictionary = {}
var _crossfade_tween: Tween = null
var _refresh_timer: Timer


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.name = "MusicDirectorPlayer"
	_player.bus = "Music"
	add_child(_player)

	_refresh_timer = Timer.new()
	_refresh_timer.name = "RefreshTimer"
	_refresh_timer.wait_time = REFRESH_INTERVAL_SECONDS
	_refresh_timer.one_shot = false
	_refresh_timer.autostart = true
	_refresh_timer.timeout.connect(refresh)
	add_child(_refresh_timer)


# --- public API -----------------------------------------------------------

# Called by scene scripts in their _ready() to declare the active scene.
# Triggers re-resolution; crossfades only if the resolved track changed.
func set_scene(scene_name: String) -> void:
	_scene = scene_name
	# Leaving the world means any cached map music_id no longer applies.
	if scene_name != "world":
		_music_id = 0
	_apply()


# Called when MUSIC_CHANGE arrives in world. 0 / null are tolerated and
# fall through to the time-of-day path.
func set_music_id(music_id: int) -> void:
	_music_id = max(0, music_id)
	_apply()


# Re-evaluate without changing scene/music_id. Used by the periodic timer
# so a 19:00 day->night flip swaps the open-world track.
func refresh() -> void:
	_apply()


func current_track() -> String:
	return _current_track


# --- test helpers ---------------------------------------------------------

# Resets the director's runtime state. Tests run sequentially in the same
# process; without this they'd inherit each other's _current_track.
func _reset_for_tests() -> void:
	if _crossfade_tween != null and _crossfade_tween.is_valid():
		_crossfade_tween.kill()
	_crossfade_tween = null
	_scene = ""
	_music_id = 0
	_current_track = ""
	_stream_cache.clear()
	_warned_missing.clear()
	if _player != null:
		_player.stop()
		_player.stream = null
		_player.volume_db = 0.0


# --- private --------------------------------------------------------------

func _apply() -> void:
	var hour := _current_hour()
	var resolved := resolve_track(_scene, _music_id, hour)

	if resolved == _current_track:
		return  # same filename -- keep playing without restart

	if resolved == "":
		_fade_out_and_stop()
		_current_track = ""
		return

	var stream: AudioStream = _load_stream(resolved)
	if stream == null:
		# File missing on disk -- silent fallback. Stop whatever's playing
		# so we don't bleed the previous scene's track.
		_fade_out_and_stop()
		_current_track = ""
		return

	_current_track = resolved
	_swap_to(stream)


func _current_hour() -> int:
	var now := Time.get_time_dict_from_system()
	return int(now.get("hour", 0))


func _load_stream(filename: String) -> AudioStream:
	if _stream_cache.has(filename):
		return _stream_cache[filename]

	var path := MUSIC_DIR + filename
	if not ResourceLoader.exists(path):
		_warn_once(path, "MusicDirector: missing track %s" % path)
		_stream_cache[filename] = null
		return null

	var stream: Resource = load(path)
	if stream == null or not (stream is AudioStream):
		_warn_once(path, "MusicDirector: %s did not load as AudioStream" % path)
		_stream_cache[filename] = null
		return null

	# Loop streams seamlessly. OGGs in music_curated/ are crafted to loop
	# (last sample -> first sample); MP3s rely on encoder padding and may
	# have a small audible gap -- noted in the PR body.
	if stream is AudioStreamOggVorbis:
		stream.loop = true
	elif stream is AudioStreamMP3:
		stream.loop = true

	_stream_cache[filename] = stream
	return stream


func _swap_to(stream: AudioStream) -> void:
	if _crossfade_tween != null and _crossfade_tween.is_valid():
		_crossfade_tween.kill()
	var was_playing := _player.playing
	if was_playing:
		_crossfade_tween = create_tween()
		_crossfade_tween.tween_property(_player, "volume_db", -40.0, CROSSFADE_SECONDS)
		var swap_in := func():
			_player.stream = stream
			_player.volume_db = -40.0
			_player.play()
		_crossfade_tween.tween_callback(swap_in)
		_crossfade_tween.tween_property(_player, "volume_db", 0.0, CROSSFADE_SECONDS)
	else:
		_player.stream = stream
		_player.volume_db = -40.0
		_player.play()
		_crossfade_tween = create_tween()
		_crossfade_tween.tween_property(_player, "volume_db", 0.0, CROSSFADE_SECONDS)


func _fade_out_and_stop() -> void:
	if not _player.playing:
		return
	if _crossfade_tween != null and _crossfade_tween.is_valid():
		_crossfade_tween.kill()
	_crossfade_tween = create_tween()
	_crossfade_tween.tween_property(_player, "volume_db", -40.0, CROSSFADE_SECONDS)
	var stop_it := func():
		_player.stop()
		_player.volume_db = 0.0
	_crossfade_tween.tween_callback(stop_it)


func _warn_once(key: String, msg: String) -> void:
	if _warned_missing.has(key):
		return
	_warned_missing[key] = true
	push_warning(msg)
