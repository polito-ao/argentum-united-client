extends GutTest
## Unit tests for MusicDirector. The pure resolution function +
## day/night helper carry the test surface; the stateful crossfade /
## scene-tree behavior is covered by integration use rather than unit
## tests (no good way to assert on the active stream in headless mode).

# --- resolve_track --------------------------------------------------------

func test_resolve_login_picks_clasica_ao():
	assert_eq(
		MusicDirector.resolve_track("login", 0, 12),
		"clasica-ao.ogg"
	)


func test_resolve_character_select_picks_clasica_ao():
	assert_eq(
		MusicDirector.resolve_track("character_select", 0, 12),
		"clasica-ao.ogg"
	)


func test_resolve_world_with_curated_music_id_picks_curated_track():
	# music_id 7 = Ullathorpe per CURATED_BY_MUSIC_ID. Daylight hour --
	# the curated mapping should still win.
	assert_eq(
		MusicDirector.resolve_track("world", 7, 12),
		"ulla.ogg"
	)


func test_resolve_world_with_curated_music_id_overrides_night():
	# Curated mapping trumps time-of-day, even at 22:00.
	assert_eq(
		MusicDirector.resolve_track("world", 7, 22),
		"ulla.ogg"
	)


func test_resolve_world_unknown_music_id_day_falls_back_to_open_world_day():
	assert_eq(
		MusicDirector.resolve_track("world", 999, 12),
		"open-world-day.mp3"
	)


func test_resolve_world_unknown_music_id_night_falls_back_to_open_world_night():
	assert_eq(
		MusicDirector.resolve_track("world", 999, 22),
		"open-world-night.mp3"
	)


func test_resolve_world_early_morning_is_night():
	# 04:00 is well within the 19:00 -> 05:30 night window.
	assert_eq(
		MusicDirector.resolve_track("world", 999, 4),
		"open-world-night.mp3"
	)


func test_resolve_world_post_dawn_is_day():
	# 06:00 is after the 05:30 day boundary.
	assert_eq(
		MusicDirector.resolve_track("world", 999, 6),
		"open-world-day.mp3"
	)


func test_resolve_world_19_is_night_start():
	# 19:00 flips to night.
	assert_eq(
		MusicDirector.resolve_track("world", 999, 19),
		"open-world-night.mp3"
	)


func test_resolve_world_zero_music_id_falls_through_to_time_of_day():
	# 0 is the documented "no map music" sentinel -- resolution must fall
	# through to the day/night branch, not return silence.
	assert_eq(
		MusicDirector.resolve_track("world", 0, 12),
		"open-world-day.mp3"
	)


func test_resolve_unknown_scene_returns_silence():
	# Future scenes that haven't been wired yet should produce "" and the
	# director will fade out rather than crash.
	assert_eq(
		MusicDirector.resolve_track("siege", 0, 12),
		""
	)


# --- is_night boundary cases ---------------------------------------------

func test_is_night_at_0():
	assert_true(MusicDirector.is_night(0), "00:00 should be night")


func test_is_night_at_4():
	assert_true(MusicDirector.is_night(4), "04:00 should be night")


func test_is_night_at_5_default_minute_is_night():
	# is_night(5) is is_night_at(5, 0) -- 05:00 is still in the night band.
	assert_true(MusicDirector.is_night(5), "05:00 should be night")


func test_is_night_at_5_30_is_day():
	assert_false(MusicDirector.is_night_at(5, 30), "05:30 should be day")


func test_is_night_at_5_29_is_night():
	assert_true(MusicDirector.is_night_at(5, 29), "05:29 should be night")


func test_is_night_at_6():
	assert_false(MusicDirector.is_night(6), "06:00 should be day")


func test_is_night_at_12():
	assert_false(MusicDirector.is_night(12), "12:00 should be day")


func test_is_night_at_18():
	assert_false(MusicDirector.is_night(18), "18:00 should be day")


func test_is_night_at_19():
	assert_true(MusicDirector.is_night(19), "19:00 should be night")


func test_is_night_at_22():
	assert_true(MusicDirector.is_night(22), "22:00 should be night")


func test_is_night_at_23():
	assert_true(MusicDirector.is_night(23), "23:00 should be night")


# --- curated map sanity ---------------------------------------------------

func test_curated_map_contains_ullathorpe():
	# Ullathorpe is the only city with a track in the initial PR; this
	# guards against accidental table edits.
	assert_true(MusicDirector.CURATED_BY_MUSIC_ID.has(7))
	assert_eq(MusicDirector.CURATED_BY_MUSIC_ID[7], "ulla.ogg")
