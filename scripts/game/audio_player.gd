extends Node

## AudioPlayer — autoload that owns:
##   - a pool of AudioStreamPlayer2D nodes for spatial SFX
##   - bus volume helpers used by the settings overlay
##
## Music is owned by MusicDirector (also an autoload) which resolves
## tracks based on scene + music_id + time of day. AudioPlayer used to
## play music + themes too, but that responsibility moved out in the
## music-director-service PR.
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

# When the bus is sitting at "max volume" we render it at this dB. Going
# all the way to 0 dB clips on some hardware; -3 dB at slider=100 keeps
# headroom and lines up with the Cucsi Master.
# Note: this is the dB at slider value 1.0 (100%). Slider 0 mutes via
# linear_to_db -- handled in set_bus_volume_linear().
const BUS_MAX_DB := 0.0

var _sfx_pool: Array = []   # Array[AudioStreamPlayer2D]
var _next_sfx_index: int = 0


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
	_play_via_pool(stream, world_x, world_y)


# Spatial SFX by curated wav_name. Same routing + pool semantics as
# play_sfx; the only difference is the source catalog. Used for
# hand-authored SFX (assets/audio/sfx_curated/) addressed by string
# rather than the numeric Cucsi id.
func play_sfx_curated(wav_name: String, world_x: int = 0, world_y: int = 0) -> void:
	if wav_name.is_empty():
		return
	var stream: AudioStream = AudioCatalog.sfx_curated(wav_name)
	if stream == null:
		return  # AudioCatalog already warned -- silent no-op for caller
	_play_via_pool(stream, world_x, world_y)


func _play_via_pool(stream: AudioStream, world_x: int, world_y: int) -> void:
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

# Tests run sequentially in the same process; this is a no-op today
# (we only own the SFX pool, no per-test mutable state) but kept as a
# stable hook in case future SFX state needs cleanup.
func _reset_for_tests() -> void:
	pass


func sfx_pool_size() -> int:
	return _sfx_pool.size()
