extends GutTest
## Tests SpriteFramesBuilder autoload. Builds for body_1 / head_1 (always
## present in the parsed Cucsi data) and verifies the resulting SpriteFrames
## resource has the expected animations, frame counts, and gets cached.

func before_all():
	if not SpriteCatalog.is_loaded():
		SpriteCatalog.load_catalogs()
	SpriteFramesBuilder.clear_cache()

# --- body --------------------------------------------------------------------

func test_for_body_1_returns_sprite_frames_with_four_animations():
	var sf := SpriteFramesBuilder.for_body(1)
	assert_not_null(sf, "body_1 should build")
	for anim_name in ["walk_south", "walk_north", "walk_east", "walk_west"]:
		assert_true(sf.has_animation(anim_name), "missing %s" % anim_name)
		assert_gt(sf.get_frame_count(anim_name), 0, "%s should have frames" % anim_name)

func test_for_body_frame_count_matches_catalog():
	var entry = SpriteCatalog.body(1)
	var sf := SpriteFramesBuilder.for_body(1)
	for dir_name in ["walk_south", "walk_north", "walk_east", "walk_west"]:
		var expected: int = entry["animations"][dir_name]["frames"].size()
		assert_eq(sf.get_frame_count(dir_name), expected,
			"%s frame count should match catalog" % dir_name)

func test_for_body_is_cached_on_second_call():
	var sf1 := SpriteFramesBuilder.for_body(1)
	var sf2 := SpriteFramesBuilder.for_body(1)
	assert_same(sf1, sf2, "second call should return the same instance")

func test_for_body_unknown_id_returns_null():
	assert_null(SpriteFramesBuilder.for_body(999999))

# --- head --------------------------------------------------------------------

func test_for_head_1_returns_sprite_frames():
	var sf := SpriteFramesBuilder.for_head(1)
	assert_not_null(sf)
	for anim_name in ["walk_south", "walk_north", "walk_east", "walk_west"]:
		assert_true(sf.has_animation(anim_name))

func test_for_head_is_cached():
	var sf1 := SpriteFramesBuilder.for_head(1)
	var sf2 := SpriteFramesBuilder.for_head(1)
	assert_same(sf1, sf2)

# --- weapon / shield: smoke ---------------------------------------------------

func test_for_weapon_1_builds():
	var sf := SpriteFramesBuilder.for_weapon(1)
	assert_not_null(sf)

func test_for_shield_1_builds():
	var sf := SpriteFramesBuilder.for_shield(1)
	assert_not_null(sf)

# --- speed clamp --------------------------------------------------------------

func test_animation_speed_is_at_least_one():
	# A static (single-frame) animation should still report >= 1 FPS so play()
	# is well-defined.
	var sf := SpriteFramesBuilder.for_body(1)
	for anim_name in ["walk_south", "walk_north", "walk_east", "walk_west"]:
		assert_gte(sf.get_animation_speed(anim_name), 1.0)
