extends GutTest
## Tests SpriteCatalog.effect() lookup. Effects are keyed by human-readable
## name in the YAML (effect_meditation, etc.) but addressed via the wire
## numeric id — the API hides that translation.

func before_all():
	if not SpriteCatalog.is_loaded():
		SpriteCatalog.load_catalogs()


func test_meditation_effect_present_with_expected_shape():
	var entry = SpriteCatalog.effect(1)
	assert_typeof(entry, TYPE_DICTIONARY, "effect_id=1 should be a Dictionary")
	assert_eq(int(entry.get("id", -1)), 1, "id field matches")
	assert_true(entry.has("source"), "has source provenance")
	assert_true(entry.has("offset"), "has offset")
	assert_true(entry.has("animation"), "has animation block")

	var anim = entry["animation"]
	assert_typeof(anim, TYPE_DICTIONARY, "animation is a Dictionary")
	assert_true(anim.has("frames"), "animation has frames")
	assert_gt(anim["frames"].size(), 0, "animation has at least one frame")
	assert_true(anim.has("speed_ms"), "animation has speed_ms")
	assert_true(anim.has("loop"), "animation has loop flag")


func test_meditation_offset_shape():
	var entry = SpriteCatalog.effect(1)
	var off = entry["offset"]
	assert_typeof(off, TYPE_DICTIONARY)
	assert_true(off.has("x"))
	assert_true(off.has("y"))


func test_meditation_frame_shape():
	var entry = SpriteCatalog.effect(1)
	var frame = entry["animation"]["frames"][0]
	assert_typeof(frame, TYPE_DICTIONARY)
	assert_true(frame.has("file"), "frame has file ref")
	assert_true(frame.has("region"), "frame has region")
	var region = frame["region"]
	for key in ["x", "y", "w", "h"]:
		assert_true(region.has(key), "region.%s present" % key)


func test_unknown_effect_id_returns_null():
	assert_null(SpriteCatalog.effect(999999))
	assert_null(SpriteCatalog.effect(-1))
	assert_null(SpriteCatalog.effect(0))


# --- meditation upgrade tiers (effect_id 2 and 3) ---------------------------

func test_meditation_mediano_effect_present():
	var entry = SpriteCatalog.effect(2)
	assert_typeof(entry, TYPE_DICTIONARY, "effect_id=2 should be a Dictionary")
	assert_eq(int(entry.get("id", -1)), 2)
	assert_eq(entry.get("source"), "Fxs.ini[5]")


func test_meditation_grande_effect_present():
	var entry = SpriteCatalog.effect(3)
	assert_typeof(entry, TYPE_DICTIONARY, "effect_id=3 should be a Dictionary")
	assert_eq(int(entry.get("id", -1)), 3)
	assert_eq(entry.get("source"), "Fxs.ini[6]")


func test_all_three_meditation_tiers_have_ten_frames():
	# Cucsi Grh134/145/156 each animate over 10 sub-frames at 555ms.
	for effect_id in [1, 2, 3]:
		var entry = SpriteCatalog.effect(effect_id)
		assert_not_null(entry, "effect %d missing" % effect_id)
		var frames = entry["animation"]["frames"]
		assert_eq(frames.size(), 10, "effect %d should have 10 frames" % effect_id)
		assert_eq(int(entry["animation"]["speed_ms"]), 555,
			"effect %d frame interval mismatch" % effect_id)
