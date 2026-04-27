extends GutTest
## Tests SpriteCatalog.item_icon() lookup. Item icons are keyed by GRH id
## (the wire identity in GROUND_ITEM_SPAWN.item_data.icon_grh_id) and
## resolve to a single-frame entry { id, source, file, region }. The
## catalog is data-driven by tools/parse_cucsi_graphics.py, so missing
## ids must return null instead of raising.

func before_all():
	if not SpriteCatalog.is_loaded():
		SpriteCatalog.load_catalogs()


# Cucsi obj.dat OBJ12 = "Monedas de Oro" -> GrhIndex 511. Always present
# unless the parser is broken or the upscaled atlas is missing entirely.
const GOLD_GRH_ID := 511

# OBJ2 = "Espada Larga" -> GrhIndex 504. Pairs with the chest icon (503)
# and various potions/items in the ~500s as a sanity sample.
const ESPADA_LARGA_GRH_ID := 504


func test_gold_icon_present_with_expected_shape():
	var entry = SpriteCatalog.item_icon(GOLD_GRH_ID)
	assert_typeof(entry, TYPE_DICTIONARY, "gold icon should resolve")
	assert_eq(int(entry.get("id", -1)), GOLD_GRH_ID, "id field matches the GRH id")
	assert_true(entry.has("source"), "has source provenance")
	assert_true(entry.has("file"), "has atlas file ref")
	assert_true(entry.has("region"), "has region")


func test_item_icon_region_shape():
	var entry = SpriteCatalog.item_icon(GOLD_GRH_ID)
	var region = entry["region"]
	assert_typeof(region, TYPE_DICTIONARY)
	for key in ["x", "y", "w", "h"]:
		assert_true(region.has(key), "region.%s present" % key)
	# Pixel coords are pre-doubled by the parser (x2 ESRGAN scale). Width
	# and height must be positive.
	assert_gt(int(region["w"]), 0, "region width positive")
	assert_gt(int(region["h"]), 0, "region height positive")


func test_item_icon_file_is_png_in_upscaled_layout():
	var entry = SpriteCatalog.item_icon(GOLD_GRH_ID)
	var file_name: String = String(entry["file"])
	assert_true(file_name.ends_with(".png"),
		"file should be a .png in assets/upscaled_2x/, got %s" % file_name)


func test_espada_larga_icon_present():
	# Paired sanity: Cucsi's iconic starter weapon should resolve too.
	var entry = SpriteCatalog.item_icon(ESPADA_LARGA_GRH_ID)
	assert_typeof(entry, TYPE_DICTIONARY,
		"item_icon(504) should resolve (Cucsi Espada Larga)")
	assert_eq(int(entry.get("id", -1)), ESPADA_LARGA_GRH_ID)


func test_unknown_item_icon_id_returns_null():
	# Defensive contract: world.gd relies on null-on-miss to dispatch the
	# yellow-rect fallback.
	assert_null(SpriteCatalog.item_icon(999999))
	assert_null(SpriteCatalog.item_icon(-1))
	assert_null(SpriteCatalog.item_icon(0))
