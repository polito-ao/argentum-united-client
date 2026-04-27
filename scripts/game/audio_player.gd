extends Node

## AudioPlayer — autoload that owns:
##   - a pool of AudioStreamPlayer2D nodes for spatial SFX
##   - one AudioStreamPlayer for music with crossfade-on-change
##   - one AudioStreamPlayer for menu/UI themes (login, character_select)
##
## Resolves audio via AudioCatalog (also an autoload). If the catalog returns
## null, the playback request silently no-ops -- the game stays playable
## even with no audio assets on disk.
##
## SFX positioning: world tile coords come over the wire; we convert to
## pixel space using TILE_SIZE_PX so AudioStreamPlayer2D's distance
## attenuation works against the camera. max_distance mirrors Cucsi's
## clsAudio.cls MAX_DISTANCE_TO_SOURCE = 150 (tiles), capped here so
## SFX from across the map don't bleed in.
##
## Pool sizing: 8 simultaneous spatial SFX is plenty for the 1-3 player
## scenarios we have today. Round-robin overwrites the oldest channel
## when exhausted -- simpler than a real priority queue and good enough
## for the M2 audio pass.

const PacketIds = preload("res://scripts/network/packet_ids.gd")

# Cucsi tile cap, in tiles. Beyond this distance from the listener
# (camera), spatial SFX is fully attenuated.
const MAX_DISTANCE_TILES := 150
# World tile size in pixels. Mirrors world.gd's _tile_size for the
# 2x-upscaled pipeline (see CLAUDE.md). Used purely to convert tile
# coords -> pixels for AudioStreamPlayer2D positioning + attenuation.
const TILE_SIZE_PX := 64

const SFX_POOL_SIZE := 8

# Crossfade duration when MUSIC_CHANGE swaps tracks. 500 ms feels right
# for AO-style transitions -- short enough that the player notices the
# music changed, long enough that the cut isn't jarring.
const MUSIC_FADE_SECONDS := 0.5

# When the bus is sitting at "max volume" we render it at this dB. Going
# all the way to 0 dB clips on some hardware; -3 dB at slider=100 keeps
# headroom and lines up with the Cucsi Master.
# Note: this is the dB at slider value 1.0 (100%). Slider 0 mutes via
# linear_to_db -- handled in set_bus_volume_linear().
const BUS_MAX_DB := 0.0

# Track that's currently playing (or 0 if none). MUSIC_CHANGE to the
# same id is a no-op -- prevents restart on duplicate broadcasts.
var _current_music_id: int = 0
# Track the active theme name (login / character_select / "" = none).
var _current_theme: String = ""

var _sfx_pool: Array = []   # Array[AudioStreamPlayer2D]
var _next_sfx_index: int = 0

var _music_player: AudioStreamPlayer
var _theme_player: AudioStreamPlayer

var _crossfade_tween: Tween = null


func _ready() -> void:
	_setup_buses_layer()
	_setup_pool()


func _setup_buses_layer() -> void:
	# default_bus_layout.tres handles the actual bus creation. We just
	# verify the buses exist at boot so a missing resource fails loudly
	# rather than silently routing every sound through Master.
	if AudioServer.get_bus_index("Music") < 0:
		push_warning("AudioPlayer: 'Music' bus missing -- check default_bus_layout.tres")
	if AudioServer.get_bus_index("SFX") < 0:
		push_warning("AudioPlayer: 'SFX' bus missing -- check default_bus_layout.tres")


func _setup_pool() -> void:
	_music_player = AudioStreamPlayer.new()
	_music_player.name = "MusicPlayer"
	_music_player.bus = "Music"
	add_child(_music_player)

	_theme_player = AudioStreamPlayer.new()
	_theme_player.name = "ThemePlayer"
	_theme_player.bus = "Music"
	add_child(_theme_player)

	for i in range(SFX_POOL_SIZE):
		var p := AudioStreamPlayer2D.new()
		p.name = "SFX_%d" % i
		p.bus = "SFX"
		# max_distance + attenuation: linear is the simplest model and
		# matches Cucsi's straight-line falloff. Tune later if needed.
		p.max_distance = float(MAX_DISTANCE_TILES * TILE_SIZE_PX)
		p.attenuation = 1.0
		add_child(p)
		_sfx_pool.append(p)


# --- Public API ---------------------------------------------------------

# Spatial SFX. world_x/world_y are server tile coords. 0/0 means "non-spatial
# UI sound" -- we still play it, just from the listener's position so
# attenuation is a no-op.
func play_sfx(wav_id: int, world_x: int = 0, world_y: int = 0) -> void:
	if wav_id <= 0:
		return
	var stream: AudioStream = AudioCatalog.sfx(wav_id)
	if stream == null:
		return  # AudioCatalog already warned -- silent no-op for caller

	var player: AudioStreamPlayer2D = _sfx_pool[_next_sfx_index]
	_next_sfx_index = (_next_sfx_index + 1) % _sfx_pool.size()

	if world_x == 0 and world_y == 0:
		# Non-spatial: park near origin; treat the listener as colocated
		# for max volume regardless of camera position. Easiest way is
		# to disable distance falloff entirely for this play.
		player.position = Vector2.ZERO
		player.max_distance = 1e9
	else:
		player.position = Vector2(world_x * TILE_SIZE_PX, world_y * TILE_SIZE_PX)
		player.max_distance = float(MAX_DISTANCE_TILES * TILE_SIZE_PX)

	player.stream = stream
	player.play()


# Music change. music_id <= 0 stops the music. Same id as currently playing
# is a no-op. Otherwise crossfades from old to new over MUSIC_FADE_SECONDS.
func play_music(music_id: int) -> void:
	if music_id <= 0:
		stop_music()
		return
	if music_id == _current_music_id and _music_player.playing:
		return  # already on this track

	var stream: AudioStream = AudioCatalog.music(music_id)
	if stream == null:
		# Cancel any existing music, since we've been told to switch but
		# can't fulfill it. Better silent than wrong.
		stop_music()
		return

	_current_music_id = music_id
	_swap_music_stream(_music_player, stream)


func stop_music() -> void:
	_current_music_id = 0
	_fade_and_stop(_music_player)


func play_theme(name: String) -> void:
	if name == _current_theme and _theme_player.playing:
		return
	var stream: AudioStream = AudioCatalog.theme(name)
	if stream == null:
		# Theme not on disk -- stop whatever's running so we don't bleed
		# the previous scene's theme into the new scene.
		stop_theme()
		return
	_current_theme = name
	_swap_music_stream(_theme_player, stream)


func stop_theme() -> void:
	_current_theme = ""
	_fade_and_stop(_theme_player)


# --- Bus volume helpers (for settings sliders) --------------------------

# Set a bus's volume by a 0..1 linear ratio. Slider 0 = silence, slider 1
# = BUS_MAX_DB. The conversion uses Godot's linear_to_db so a slider at
# 0.5 sounds roughly half as loud (true perceptual half) rather than
# halving the dB.
func set_bus_volume_linear(bus_name: String, ratio: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		push_warning("AudioPlayer.set_bus_volume_linear: unknown bus '%s'" % bus_name)
		return
	ratio = clamp(ratio, 0.0, 1.0)
	if ratio <= 0.0:
		AudioServer.set_bus_mute(idx, true)
		return
	AudioServer.set_bus_mute(idx, false)
	# Map slider 1.0 -> BUS_MAX_DB (default 0 dB), slider 0.01 -> roughly -40 dB.
	var db := linear_to_db(ratio) + BUS_MAX_DB
	AudioServer.set_bus_volume_db(idx, db)


func get_bus_volume_linear(bus_name: String) -> float:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return 0.0
	if AudioServer.is_bus_mute(idx):
		return 0.0
	var db := AudioServer.get_bus_volume_db(idx) - BUS_MAX_DB
	return clamp(db_to_linear(db), 0.0, 1.0)


# --- Test helpers -------------------------------------------------------

# Clears any in-flight tween + resets cached state. Tests run sequentially
# in the same process so they need a clean slate.
func _reset_for_tests() -> void:
	if _crossfade_tween != null and _crossfade_tween.is_valid():
		_crossfade_tween.kill()
	_crossfade_tween = null
	_current_music_id = 0
	_current_theme = ""
	if _music_player != null:
		_music_player.stop()
		_music_player.stream = null
		_music_player.volume_db = 0.0
	if _theme_player != null:
		_theme_player.stop()
		_theme_player.stream = null
		_theme_player.volume_db = 0.0


# Test introspection.
func current_music_id() -> int:
	return _current_music_id


func current_theme() -> String:
	return _current_theme


func sfx_pool_size() -> int:
	return _sfx_pool.size()


# --- private ------------------------------------------------------------

# Crossfades `player` from current stream to `new_stream`. If nothing is
# currently playing we just fade in (no fade-out phase).
func _swap_music_stream(player: AudioStreamPlayer, new_stream: AudioStream) -> void:
	if _crossfade_tween != null and _crossfade_tween.is_valid():
		_crossfade_tween.kill()
	var was_playing := player.playing
	if was_playing:
		# Fade out current, then swap and fade in.
		_crossfade_tween = create_tween()
		_crossfade_tween.tween_property(player, "volume_db", -40.0, MUSIC_FADE_SECONDS)
		var swap_in := func():
			player.stream = new_stream
			player.volume_db = -40.0
			player.play()
		_crossfade_tween.tween_callback(swap_in)
		_crossfade_tween.tween_property(player, "volume_db", 0.0, MUSIC_FADE_SECONDS)
	else:
		player.stream = new_stream
		player.volume_db = -40.0
		player.play()
		_crossfade_tween = create_tween()
		_crossfade_tween.tween_property(player, "volume_db", 0.0, MUSIC_FADE_SECONDS)


func _fade_and_stop(player: AudioStreamPlayer) -> void:
	if not player.playing:
		return
	if _crossfade_tween != null and _crossfade_tween.is_valid():
		_crossfade_tween.kill()
	_crossfade_tween = create_tween()
	_crossfade_tween.tween_property(player, "volume_db", -40.0, MUSIC_FADE_SECONDS)
	var stop_it := func():
		player.stop()
		player.volume_db = 0.0
	_crossfade_tween.tween_callback(stop_it)
