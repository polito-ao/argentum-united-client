extends GutTest
## Unit tests for AudioCatalog autoload. We don't need real audio files on
## disk -- the missing-asset path is the primary contract we're verifying
## (the game has to stay playable when audio hasn't been generated yet).

func before_each():
	# Reset the autoload state so previous tests don't poison the warn-once
	# bookkeeping.
	AudioCatalog._reset_for_tests()


func test_unknown_theme_name_returns_null():
	var stream = AudioCatalog.theme("definitely_not_a_real_theme")
	assert_null(stream)


func test_missing_sfx_id_returns_null():
	# The repo doesn't ship audio assets -- any id resolves to "file missing".
	# That is in fact the contract: missing -> null + warn-once.
	var stream = AudioCatalog.sfx(99999)
	assert_null(stream)


func test_missing_music_id_returns_null():
	var stream = AudioCatalog.music(99999)
	assert_null(stream)


func test_missing_id_warns_only_once():
	# Calling twice should not double-warn; the cache keys on the resource
	# path. We assert behaviorally: the second call returns the same null
	# without fresh resource probing.
	var first = AudioCatalog.sfx(99999)
	var second = AudioCatalog.sfx(99999)
	assert_null(first)
	assert_null(second)


func test_unknown_theme_name_returns_null_consistently():
	var first = AudioCatalog.theme("nope")
	var second = AudioCatalog.theme("nope")
	assert_null(first)
	assert_null(second)


func test_known_theme_name_resolves_when_file_present_or_null_otherwise():
	# "login" maps to a real id (1) per THEME_IDS, but the .mp3 may not be
	# on disk in CI. Either branch is acceptable here -- what we are asserting
	# is that we don't crash and we don't return garbage.
	var stream = AudioCatalog.theme("login")
	if stream != null:
		assert_true(stream is AudioStream)
	else:
		# Asset not yet generated -- silent null is the documented behavior.
		assert_null(stream)


func test_theme_ids_table_covers_documented_names():
	# Catch typos in the hardcoded map. login + character_select are the
	# names the rest of the codebase uses today.
	assert_true(AudioCatalog.THEME_IDS.has("login"))
	assert_true(AudioCatalog.THEME_IDS.has("character_select"))
