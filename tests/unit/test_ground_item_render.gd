extends GutTest
## Tests the ground-item dispatch decision: world.gd reads `icon_grh_id`
## from GROUND_ITEM_SPAWN.item_data and routes to the sprite renderer when
## present, or falls back to the legacy yellow-rect placeholder otherwise.
##
## We exercise the static helper `World.ground_item_icon_grh_id(item_data)`
## directly so the test stays decoupled from scene-tree mounting. The
## function returns 0 to mean "fall back" and >0 to mean "render the
## Cucsi icon for this GRH id". The actual rendering (catalog lookup,
## AtlasTexture construction) is exercised at runtime against the real
## SpriteCatalog and is covered separately.

const WorldScript = preload("res://scenes/world/world.gd")


# --- positive cases (catalog rendering should be attempted) ---

func test_returns_grh_id_when_present_and_positive():
	var item_data := {"name": "Monedas de Oro", "icon_grh_id": 511}
	assert_eq(WorldScript.ground_item_icon_grh_id(item_data), 511)


func test_handles_string_grh_id_via_int_coercion():
	# MessagePack will hand us ints, but be defensive: the helper
	# `int()`s whatever it gets.
	var item_data := {"icon_grh_id": "504"}
	assert_eq(WorldScript.ground_item_icon_grh_id(item_data), 504)


func test_returns_grh_id_even_when_other_fields_missing():
	# Server's payload may be sparse — only icon_grh_id matters here.
	var item_data := {"icon_grh_id": 503}
	assert_eq(WorldScript.ground_item_icon_grh_id(item_data), 503)


# --- fallback cases (return 0 -> caller renders the yellow rect) ---

func test_returns_zero_when_icon_grh_id_missing():
	# Server pre-PR: payload won't carry the field at all.
	var item_data := {"name": "Pocion Roja"}
	assert_eq(WorldScript.ground_item_icon_grh_id(item_data), 0)


func test_returns_zero_when_icon_grh_id_is_zero():
	var item_data := {"icon_grh_id": 0}
	assert_eq(WorldScript.ground_item_icon_grh_id(item_data), 0)


func test_returns_zero_for_negative_id():
	# Defensive: a negative id is malformed wire data; treat as fallback.
	var item_data := {"icon_grh_id": -1}
	assert_eq(WorldScript.ground_item_icon_grh_id(item_data), 0)


func test_returns_zero_for_empty_dict():
	assert_eq(WorldScript.ground_item_icon_grh_id({}), 0)


func test_returns_zero_when_item_data_is_not_a_dict():
	# Some servers may ship null when no item metadata is available; the
	# helper must not crash.
	assert_eq(WorldScript.ground_item_icon_grh_id(null), 0)
	assert_eq(WorldScript.ground_item_icon_grh_id(""), 0)
	assert_eq(WorldScript.ground_item_icon_grh_id(42), 0)
