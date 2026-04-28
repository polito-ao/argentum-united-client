extends GutTest
## Coverage check: every icon_grh_id the server ships in its items.yml
## MUST resolve via SpriteCatalog.item_icon(). If any id is missing, the
## ground-item renderer falls back to a yellow ColorRect at runtime and
## logs `[ground_items] no sprite_catalog entry for icon_grh_id=...`.
##
## The list mirrors the unique icon_grh_id values currently referenced
## from argentum-united-server/config/items.yml. When a new icon is added
## server-side, add its id here; the test will then enforce that
## tools/parse_cucsi_graphics.py emitted it.
##
## Root cause this catches: a section regex bug in parse_cucsi_graphics.py
## previously rejected obj.dat headers with trailing comments
## (e.g. `[OBJ16] 'CASA RUINAS`), letting the next OBJ's GrhIndex
## clobber the previous OBJ's. Daga's GrhIndex=510 was overwritten with
## 5600 from OBJ16 — silently producing the wrong catalog for ~129 items.

func before_all():
	if not SpriteCatalog.is_loaded():
		SpriteCatalog.load_catalogs()


# Mirror of unique icon_grh_id values in
# argentum-united-server/config/items.yml as of 2026-04-25. Sorted asc.
const SERVER_ICON_GRH_IDS := [
	504,    # Espada Larga / Espada de Entrenamiento
	510,    # Daga (the bug that motivated this test)
	511,    # Monedas de Oro
	526,    # Armadura de Cuero (+newbie variant)
	541,    # Poción Azul (mana)
	542,    # Poción Roja (HP)
	559,    # Casco de Hierro
	588,    # Espada Corta
	712,    # Escudo (Newbie)
	932,    # Vara de Fresno / Bastón de Mago (Newbie)
	1018,   # Sombrero de Mago
	4860,   # Escudo de Hierro
	27132,  # Armadura de Placas Completa
	40111,  # Báculo Rúnico
]


func test_every_server_icon_grh_id_resolves():
	var missing: Array = []
	for grh_id in SERVER_ICON_GRH_IDS:
		var entry = SpriteCatalog.item_icon(grh_id)
		if entry == null:
			missing.append(grh_id)
	assert_eq(missing.size(), 0,
		("Server items.yml references these icon_grh_ids that the client "
		+ "catalog does not contain: %s. "
		+ "Re-run tools/parse_cucsi_graphics.py.") % [missing])


func test_resolved_entries_have_full_shape():
	# Defensive: id/source/file/region must all be present and well-formed.
	for grh_id in SERVER_ICON_GRH_IDS:
		var entry = SpriteCatalog.item_icon(grh_id)
		if entry == null:
			continue  # already reported by the previous test
		assert_eq(int(entry.get("id", -1)), grh_id,
			"id field matches grh_id for %d" % grh_id)
		assert_true(entry.has("file"), "%d has file" % grh_id)
		assert_true(entry.has("region"), "%d has region" % grh_id)
		var region: Dictionary = entry["region"]
		assert_gt(int(region.get("w", 0)), 0, "%d region.w > 0" % grh_id)
		assert_gt(int(region.get("h", 0)), 0, "%d region.h > 0" % grh_id)


func test_daga_icon_resolves_to_correct_atlas():
	# Regression guard for the original bug: GRH 510 must point to atlas
	# file 16039.png (Cucsi Graficos.ini: `Grh510=1-16039-0-0-32-32`),
	# NOT whatever 5600 happened to map to before the fix.
	var entry = SpriteCatalog.item_icon(510)
	assert_typeof(entry, TYPE_DICTIONARY, "Daga icon (GRH 510) must resolve")
	assert_eq(String(entry.get("file", "")), "16039.png",
		"GRH 510 must reference atlas 16039.png — if this fails, the "
		+ "section-comment regex in parse_cucsi_graphics.py probably "
		+ "regressed.")
