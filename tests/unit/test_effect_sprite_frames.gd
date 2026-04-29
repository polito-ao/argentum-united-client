extends GutTest
## Tests SpriteFramesBuilder.for_effect(). The meditation effect (id=1) is
## a single-animation SpriteFrames keyed under "default" — distinct from the
## 4-direction shape body / head / etc. resources use.

func before_all():
	if not SpriteCatalog.is_loaded():
		SpriteCatalog.load_catalogs()
	SpriteFramesBuilder.clear_cache()


func test_for_effect_meditation_returns_sprite_frames():
	var sf := SpriteFramesBuilder.for_effect(1)
	assert_not_null(sf, "meditation effect should build")
	assert_true(sf.has_animation("default"), "single 'default' animation")
	assert_gt(sf.get_frame_count("default"), 0, "default animation has frames")


func test_for_effect_meditation_frame_count_matches_catalog():
	var entry = SpriteCatalog.effect(1)
	var expected: int = entry["animation"]["frames"].size()
	var sf := SpriteFramesBuilder.for_effect(1)
	assert_eq(sf.get_frame_count("default"), expected,
		"frame count should match catalog")


func test_for_effect_loops_by_default():
	var sf := SpriteFramesBuilder.for_effect(1)
	assert_true(sf.get_animation_loop("default"),
		"meditation animation should loop")


func test_for_effect_speed_at_least_one_fps():
	var sf := SpriteFramesBuilder.for_effect(1)
	assert_gte(sf.get_animation_speed("default"), 1.0)


func test_for_effect_is_cached_on_second_call():
	var sf1 := SpriteFramesBuilder.for_effect(1)
	var sf2 := SpriteFramesBuilder.for_effect(1)
	assert_same(sf1, sf2, "second call returns cached instance")


func test_for_effect_unknown_id_returns_null():
	assert_null(SpriteFramesBuilder.for_effect(999999))
	assert_null(SpriteFramesBuilder.for_effect(0))


# --- Issue #22: dormant effects (4-7) build the same as the wired ones ------
# When the server eventually emits EFFECT_START for blessings / status visuals
# the resource pipeline must already cope. We don't try to *play* them here —
# just confirm SpriteFramesBuilder produces a non-empty SpriteFrames.

func test_for_effect_dormant_ids_build():
	# Skip when the upscaled_2x bundle is absent (gitignored in CI clones).
	if not FileAccess.file_exists("res://assets/upscaled_2x/3069.png"):
		pending("upscaled_2x assets not present — skipping dormant build check")
		return
	for eid in [4, 5, 6, 7]:
		var sf := SpriteFramesBuilder.for_effect(eid)
		assert_not_null(sf, "dormant effect %d should build" % eid)
		assert_true(sf.has_animation("default"),
			"dormant effect %d animation is keyed under 'default'" % eid)
		assert_gt(sf.get_frame_count("default"), 0,
			"dormant effect %d animation has frames" % eid)
		assert_true(sf.get_animation_loop("default"),
			"dormant effect %d should loop" % eid)
		assert_gte(sf.get_animation_speed("default"), 1.0,
			"dormant effect %d speed must be >= 1 fps" % eid)
