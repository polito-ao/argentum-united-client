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


# --- Issue #22: dormant catalog entries (server does not emit yet) ----------
# Effects 4-7 ride the same shape as 1-3. Server never sends EFFECT_START with
# these ids today; the catalog scaffolding lets the wiring land in one shot
# whenever the server side is ready.

const _DORMANT_EFFECTS := [
	{ "id": 4, "source": "Fxs.ini[9]" },   # blessing_real (Bendicion de Sortilego)
	{ "id": 5, "source": "Fxs.ini[13]" },  # blessing_caos (Apocalipsis placeholder)
	{ "id": 6, "source": "Fxs.ini[8]" },   # status_paralysis (Paralizar)
	{ "id": 7, "source": "Fxs.ini[3]" },   # status_poison (Envenenar)
]


func test_dormant_effects_present_with_expected_shape():
	for spec in _DORMANT_EFFECTS:
		var eid: int = int(spec["id"])
		var entry = SpriteCatalog.effect(eid)
		assert_typeof(entry, TYPE_DICTIONARY,
			"effect_id=%d should resolve to a Dictionary" % eid)
		assert_eq(int(entry.get("id", -1)), eid,
			"effect_id=%d id field mismatch" % eid)
		assert_eq(entry.get("source"), spec["source"],
			"effect_id=%d source provenance mismatch" % eid)
		assert_true(entry.has("offset"), "effect %d has offset" % eid)
		assert_true(entry.has("animation"), "effect %d has animation" % eid)


func test_dormant_effects_animation_round_trips():
	for spec in _DORMANT_EFFECTS:
		var eid: int = int(spec["id"])
		var entry = SpriteCatalog.effect(eid)
		var anim = entry["animation"]
		assert_typeof(anim, TYPE_DICTIONARY,
			"effect %d animation block missing" % eid)
		var frames: Array = anim["frames"]
		assert_gt(frames.size(), 0,
			"effect %d should have at least one frame" % eid)
		assert_gt(int(anim.get("speed_ms", 0)), 0,
			"effect %d speed_ms must be positive" % eid)
		assert_true(anim.get("loop", false),
			"effect %d should loop" % eid)
		# Spot-check the first frame: file ref + complete region.
		var first = frames[0]
		assert_true(first.has("file"), "effect %d frame[0] has file" % eid)
		var region = first["region"]
		for key in ["x", "y", "w", "h"]:
			assert_true(region.has(key),
				"effect %d frame[0].region.%s present" % [eid, key])
		assert_gt(int(region["w"]), 0,
			"effect %d frame[0] width must be positive" % eid)
		assert_gt(int(region["h"]), 0,
			"effect %d frame[0] height must be positive" % eid)


func test_dormant_effects_resolve_to_existing_assets():
	# Every frame's `file` must exist under res://assets/upscaled_2x/. The
	# parser already enforces this at build time, but a Godot-side sanity
	# check protects against dirty merges where the YAML was edited by hand.
	# NOTE: assets/upscaled_2x/ is gitignored (Google Drive-hosted); skip the
	# asset-existence assertion in environments without the upscaled bundle.
	var sample := "res://assets/upscaled_2x/3069.png"
	if not FileAccess.file_exists(sample):
		pending("upscaled_2x assets not present in this checkout — skipping path check")
		return
	for spec in _DORMANT_EFFECTS:
		var eid: int = int(spec["id"])
		var entry = SpriteCatalog.effect(eid)
		for frame in entry["animation"]["frames"]:
			var path := "res://assets/upscaled_2x/%s" % frame["file"]
			assert_true(FileAccess.file_exists(path),
				"effect %d references missing asset: %s" % [eid, path])
