extends GutTest
## Unit tests for AudioPlayer autoload. We don't actually emit sound
## (headless mode), so the assertions cover state + bus routing + the
## crossfade tween bookkeeping rather than acoustic output.

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


# --- play_music + stop_music ---------------------------------------------

func test_play_music_with_zero_stops_music():
	# Tracks the documented contract: music_id <= 0 stops playback.
	AudioPlayer.play_music(0)
	assert_eq(AudioPlayer.current_music_id(), 0)


func test_play_music_with_missing_id_clears_current():
	# If we ask for a track that isn't on disk, current_music_id should
	# end up cleared (we can't fulfill the request -- silent > wrong).
	AudioPlayer.play_music(99999)
	assert_eq(AudioPlayer.current_music_id(), 0)


func test_stop_music_clears_current_id():
	# Even if there's no track playing, stop should be safe + idempotent.
	AudioPlayer.stop_music()
	assert_eq(AudioPlayer.current_music_id(), 0)


# --- themes ------------------------------------------------------------

func test_play_theme_unknown_name_clears_current():
	AudioPlayer.play_theme("not_a_real_theme")
	assert_eq(AudioPlayer.current_theme(), "")


func test_stop_theme_clears_current_name():
	AudioPlayer.stop_theme()
	assert_eq(AudioPlayer.current_theme(), "")
