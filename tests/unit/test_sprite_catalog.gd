extends GutTest
## Tests SpriteCatalog autoload. Assumes tools/parse_cucsi_graphics.py has
## already been run (the YAML/JSON files are committed). Doesn't re-parse;
## just verifies the in-memory catalog answers basic lookups correctly.

func before_all():
	# Force a load in case the autoload's _ready hasn't run yet for some
	# reason (running tests headless still fires autoloads, but be safe).
	if not SpriteCatalog.is_loaded():
		SpriteCatalog.load_catalogs()

# --- All five catalogs loaded -------------------------------------------------

func test_body_1_present_with_expected_shape():
	var entry = SpriteCatalog.body(1)
	assert_typeof(entry, TYPE_DICTIONARY, "body_1 should be a Dictionary")
	assert_true(entry.has("head_offset"), "body has head_offset")
	assert_true(entry.has("animations"), "body has animations")
	var anims = entry["animations"]
	for dir_name in ["walk_south", "walk_north", "walk_east", "walk_west"]:
		assert_true(anims.has(dir_name), "body has %s" % dir_name)
		var anim = anims[dir_name]
		assert_true(anim.has("frames"), "%s has frames" % dir_name)
		assert_gt(anim["frames"].size(), 0, "%s has at least one frame" % dir_name)

func test_head_1_present_with_expected_shape():
	var entry = SpriteCatalog.head(1)
	assert_typeof(entry, TYPE_DICTIONARY)
	assert_true(entry.has("animations"))
	# Heads have NO head_offset (only bodies do).
	assert_false(entry.has("head_offset"), "head should not carry its own head_offset")

func test_helmet_catalog_has_some_entries():
	# Just smoke-test: a known-present id (1) returns a Dictionary.
	# If parser yield drops dramatically this will flag it.
	var entry = SpriteCatalog.helmet(1)
	if entry == null:
		# Some helmets may legitimately be skipped; try a couple known low ids.
		var found := false
		for id in [1, 3, 5, 10]:
			if SpriteCatalog.helmet(id) != null:
				found = true
				break
		assert_true(found, "expected at least one of helmet 1/3/5/10 to be in the catalog")
	else:
		assert_true(entry.has("animations"))

func test_weapon_catalog_known_id():
	# Arma1 (Espada Normal) is universally present in Cucsi installs.
	var entry = SpriteCatalog.weapon(1)
	assert_typeof(entry, TYPE_DICTIONARY)
	assert_true(entry.has("animations"))

func test_shield_catalog_known_id():
	var entry = SpriteCatalog.shield(1)
	assert_typeof(entry, TYPE_DICTIONARY)
	assert_true(entry.has("animations"))

# --- Unknown ids return null --------------------------------------------------

func test_body_unknown_id_returns_null():
	assert_null(SpriteCatalog.body(999999))

func test_head_unknown_id_returns_null():
	assert_null(SpriteCatalog.head(999999))

func test_helmet_unknown_id_returns_null():
	assert_null(SpriteCatalog.helmet(999999))

func test_weapon_unknown_id_returns_null():
	assert_null(SpriteCatalog.weapon(999999))

func test_shield_unknown_id_returns_null():
	assert_null(SpriteCatalog.shield(999999))
