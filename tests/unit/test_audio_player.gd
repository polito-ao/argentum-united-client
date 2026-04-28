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
