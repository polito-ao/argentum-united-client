extends GutTest
## Unit tests for AudioCatalog.sfx_curated -- the string-keyed lookup
## that resolves curated SFX (assets/audio/sfx_curated/) by `wav_name`
## with auto-extension probing.
##
## Unlike test_audio_catalog.gd (which exercises the missing-asset
## defensive path because the auto-generated sfx/ tree isn't checked
## in), this suite asserts against the REAL files committed in
## assets/audio/sfx_curated/. If those files move, this test moves
## with them.

const REAL_SFX_NAME := "drop_item"           # ships as drop_item.mp3
const REAL_SFX_EXTENSION := ".mp3"
const REAL_SFX_PATH := "res://assets/audio/sfx_curated/drop_item.mp3"
const MISSING_SFX_NAME := "this_sfx_does_not_exist_anywhere"


func before_each():
	AudioCatalog._reset_for_tests()


# --- happy path -----------------------------------------------------------

func test_sfx_curated_resolves_real_asset_to_audio_stream():
	# The committed sfx_curated/ folder ships drop_item.mp3 -- verify the
	# end-to-end load path returns a non-null AudioStream.
	var stream = AudioCatalog.sfx_curated(REAL_SFX_NAME)
	assert_not_null(stream, "expected drop_item to resolve via auto-extension probe")
	assert_true(stream is AudioStream)


func test_sfx_curated_auto_extension_finds_mp3():
	# drop_item ships as .mp3, not .wav. Auto-extension probing must walk
	# past the failing .wav probe and resolve the .mp3.
	var stream = AudioCatalog.sfx_curated(REAL_SFX_NAME)
	var direct = load(REAL_SFX_PATH)
	assert_eq(stream, direct, "auto-extension probe should resolve the same resource as direct load")


# --- caching -------------------------------------------------------------

func test_sfx_curated_caches_on_repeated_call():
	# Second call should return the SAME AudioStream object reference --
	# load() is not invoked twice. We can't peek at the cache directly so
	# this is the strongest behavioral assertion available.
	var first = AudioCatalog.sfx_curated(REAL_SFX_NAME)
	var second = AudioCatalog.sfx_curated(REAL_SFX_NAME)
	assert_not_null(first)
	assert_eq(first, second, "repeated curated lookups must return the cached stream")


# --- defensive paths -----------------------------------------------------

func test_sfx_curated_missing_name_returns_null():
	# Wired up but not yet shipped: missing -> null + warn-once. Mirror of
	# test_audio_catalog.gd's missing-id contract.
	var stream = AudioCatalog.sfx_curated(MISSING_SFX_NAME)
	assert_null(stream)


func test_sfx_curated_empty_name_returns_null_silently():
	# Empty string is the sentinel for "no curated name set; fall back to
	# wav_id". The catalog must NOT warn here -- the caller is using the
	# empty string deliberately.
	var stream = AudioCatalog.sfx_curated("")
	assert_null(stream)


func test_sfx_curated_missing_caches_negative_result():
	# After the first miss, a repeat call should hit the cache (return
	# the same null) without re-walking the four extensions on disk. We
	# can't observe disk activity from GUT, so we settle for "null both
	# times and no crash".
	var first = AudioCatalog.sfx_curated(MISSING_SFX_NAME)
	var second = AudioCatalog.sfx_curated(MISSING_SFX_NAME)
	assert_null(first)
	assert_null(second)
