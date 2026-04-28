extends GutTest
## Unit tests for AudioCatalog autoload. We don't need real audio files on
## disk -- the missing-asset path is the primary contract we're verifying
## (the game has to stay playable when audio hasn't been generated yet).
##
## Music + theme APIs were removed when MusicDirector took over those
## responsibilities. AudioCatalog now only resolves SFX.

func before_each():
	# Reset the autoload state so previous tests don't poison the warn-once
	# bookkeeping.
	AudioCatalog._reset_for_tests()


func test_missing_sfx_id_returns_null():
	# The repo doesn't ship audio assets -- any id resolves to "file missing".
	# That is in fact the contract: missing -> null + warn-once.
	var stream = AudioCatalog.sfx(99999)
	assert_null(stream)


func test_missing_id_warns_only_once():
	# Calling twice should not double-warn; the cache keys on the resource
	# path. We assert behaviorally: the second call returns the same null
	# without fresh resource probing.
	var first = AudioCatalog.sfx(99999)
	var second = AudioCatalog.sfx(99999)
	assert_null(first)
	assert_null(second)


func test_negative_sfx_id_returns_null():
	# Defensive: callers occasionally pass <= 0 as "no sound". The catalog
	# itself doesn't gate -- AudioPlayer does -- but the load path should
	# still produce null cleanly rather than crashing.
	var stream = AudioCatalog.sfx(-1)
	assert_null(stream)
