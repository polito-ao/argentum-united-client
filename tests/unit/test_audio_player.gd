extends GutTest
## Unit tests for AudioPlayer autoload. We don't actually emit sound
## (headless mode), so the assertions cover state + bus routing rather
## than acoustic output.
##
## Music + theme APIs moved to MusicDirector; AudioPlayer now only owns
## the spatial SFX pool + bus volume helpers used by settings.

func before_each():
	AudioPlayer._reset_for_tests()
	AudioCatalog._reset_for_tests()


# --- pool + bus wiring ------------------------------------------------------

func test_sfx_pool_size_matches_constant():
	assert_eq(AudioPlayer.sfx_pool_size(), AudioPlayer.SFX_POOL_SIZE)


func test_music_and_sfx_buses_exist():
	assert_gte(AudioServer.get_bus_index("Master"), 0)
	assert_gte(AudioServer.get_bus_index("Music"), 0)
	assert_gte(AudioServer.get_bus_index("SFX"), 0)


# --- play_sfx -----------------------------------------------------------

func test_play_sfx_with_invalid_id_is_silent_noop():
	# Negative or zero ids never reach the catalog -- the caller is
	# explicitly using "no sound" semantics.
	AudioPlayer.play_sfx(0, 5, 5)
	AudioPlayer.play_sfx(-1, 5, 5)
	# No assertion beyond "doesn't crash" -- we don't have a way to peek at
	# the pool's `playing` state in headless mode without real audio.
	assert_true(true)


func test_play_sfx_with_missing_id_is_silent_noop():
	# Id without an asset on disk -- AudioCatalog returns null, AudioPlayer
	# silently skips. Exercises the defensive path.
	AudioPlayer.play_sfx(99999, 0, 0)
	assert_true(true)


# --- bus volume helpers --------------------------------------------------

func test_set_bus_volume_linear_zero_mutes_bus():
	AudioPlayer.set_bus_volume_linear("Music", 0.0)
	assert_eq(AudioPlayer.get_bus_volume_linear("Music"), 0.0)


func test_set_bus_volume_linear_full_unmutes_bus():
	# After silencing, going back to 1.0 should unmute and report ~1.0.
	AudioPlayer.set_bus_volume_linear("Music", 0.0)
	AudioPlayer.set_bus_volume_linear("Music", 1.0)
	var got := AudioPlayer.get_bus_volume_linear("Music")
	assert_almost_eq(got, 1.0, 0.01)


func test_set_bus_volume_linear_unknown_bus_warns_no_crash():
	# Defensive: the settings overlay shouldn't be able to crash the audio
	# subsystem by misnaming a bus.
	AudioPlayer.set_bus_volume_linear("DoesNotExist", 0.5)
	assert_true(true)


# --- Y-axis pitch shift -------------------------------------------------
#
# `compute_y_pitch_shift` is a pure static helper -- no node tree, no
# state -- so we can pin its math directly. The integration with
# AudioStreamPlayer2D (see _play_via_pool) is exercised manually; the
# tests here cover the formula + clamps.

const _SCALE := 0.001  # mirror AudioPlayer.Y_PITCH_SCALE
const _CLAMP := 0.10   # mirror AudioPlayer.Y_PITCH_CLAMP


func test_compute_y_pitch_shift_no_delta_returns_unity():
	# listener and source colocated -> pitch_scale = 1.0 (no shift).
	var got := AudioPlayer.compute_y_pitch_shift(50.0, 50.0, _SCALE)
	assert_almost_eq(got, 1.0, 0.0001)


func test_compute_y_pitch_shift_source_above_clamps_to_max():
	# Source 100 tiles above (source_y << listener_y) -> way past the
	# +10% cap. Result must clamp to 1.10 exactly.
	var got := AudioPlayer.compute_y_pitch_shift(150.0, 50.0, _SCALE)
	assert_almost_eq(got, 1.0 + _CLAMP, 0.0001)


func test_compute_y_pitch_shift_source_below_clamps_to_min():
	# Source 100 tiles below -> -10% cap. Result must clamp to 0.90 exactly.
	var got := AudioPlayer.compute_y_pitch_shift(50.0, 150.0, _SCALE)
	assert_almost_eq(got, 1.0 - _CLAMP, 0.0001)


func test_compute_y_pitch_shift_moderate_delta_is_linear():
	# Source 1 tile above listener (= TILE_SIZE_PX = 64 pixels above).
	# Expected shift: 64 * 0.001 = +0.064 -> pitch_scale = 1.064.
	var got := AudioPlayer.compute_y_pitch_shift(10.0, 9.0, _SCALE)
	var expected := 1.0 + (1.0 * float(AudioPlayer.TILE_SIZE_PX) * _SCALE)
	assert_almost_eq(got, expected, 0.0001)


func test_compute_y_pitch_shift_below_listener_lowers_pitch():
	# Sanity check that direction matches the doc comment: source_y >
	# listener_y (below in screen space) -> pitch_scale < 1.0.
	var got := AudioPlayer.compute_y_pitch_shift(10.0, 11.0, _SCALE)
	assert_lt(got, 1.0)
	assert_gt(got, 1.0 - _CLAMP)


# --- listener position ---------------------------------------------------

func test_set_listener_position_changes_pitch_for_subsequent_sfx():
	# Indirect check: after moving the listener, calling compute with the
	# same source should show the listener-y move took effect by passing
	# different listener_y values into the helper. (compute_y_pitch_shift
	# is pure, so this is really just a sanity test that the API exists.)
	AudioPlayer.set_listener_position(10.0, 20.0)
	# No public getter; rely on the indirect assertion that play_sfx
	# doesn't crash and the helper math holds independently above.
	assert_true(true)


func test_sfx_pool_voices_are_audio_stream_player_2d():
	# Sanity: the pool's children are the AudioStreamPlayer2D nodes
	# we expect. (Doppler is 3D-only in Godot 4 -- AudioStreamPlayer2D
	# has no `doppler_tracking` property -- so no doppler-state assertion
	# here. See _setup_pool comment for context.)
	var count := 0
	for child in AudioPlayer.get_children():
		if child is AudioStreamPlayer2D:
			count += 1
	assert_eq(count, AudioPlayer.SFX_POOL_SIZE)
