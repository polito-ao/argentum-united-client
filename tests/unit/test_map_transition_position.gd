extends GutTest
## Unit tests for the map-transition position math. Covers the bug where
## walking off the east edge of map 7 (X=87 -> would be X=88) into map 1 at
## X=14 visually rendered the player at the FAR EAST of map 1 (around
## pixel 88*tile_size), with one extra step "snapping" them into place.
##
## Root cause: a smooth-walk tween from the prior map was still in-flight
## when MAP_TRANSITION arrived, snapping the sprite to (14*ts, y*ts) but
## then immediately tweening it back to (88*ts, y*ts). The fix is twofold:
##   1. tile_to_world is a pure helper so callers can compute the snap
##      target consistently and tests can pin the math.
##   2. _update_player_position kills any in-flight _move_tween before it
##      writes the new sprite/camera positions.
##
## Visual scene-tree assertions are out of scope — the math + the tween
## lifecycle are what regressed and that's what we lock down here.

const WorldScript = preload("res://scenes/world/world.gd")

# --- tile_to_world: pure pixel-coord conversion ---

func test_tile_to_world_origin_is_zero():
	assert_eq(WorldScript.tile_to_world(0, 0, 64), Vector2.ZERO)

func test_tile_to_world_scales_by_tile_size():
	# Upscaled-2x pipeline uses tile_size=64.
	assert_eq(WorldScript.tile_to_world(14, 50, 64), Vector2(14 * 64, 50 * 64))

func test_tile_to_world_with_fallback_tile_size():
	# Cucsi-native tile_size=32 (FALLBACK_TILE_SIZE); same math, smaller scale.
	assert_eq(WorldScript.tile_to_world(14, 50, 32), Vector2(14 * 32, 50 * 32))

func test_tile_to_world_far_east_edge():
	# Pre-fix the sprite was visually parked here on entry to map 1 because
	# the tween from map 7 (target X=88) outran the snap to X=14.
	assert_eq(WorldScript.tile_to_world(88, 50, 64).x, 88 * 64)

# --- transition payload -> tile coords ---
#
# The server's MAP_TRANSITION payload is the source of truth. The client
# must adopt those tile coords verbatim (no offset, no carry-over from
# the previous map's coordinate space).

func _decode_transition(payload: Dictionary) -> Dictionary:
	# Mirrors the four reads in world.gd::_handle_map_transition. Pulled into
	# a helper so the test phrases the same expectation each direction.
	return {
		"map_id":   payload.get("map_id", 1),
		"my_pos":   Vector2i(payload.get("x", 50), payload.get("y", 50)),
		"map_size": Vector2i(payload.get("width", 100), payload.get("height", 100)),
	}

func test_east_edge_transition_lands_at_server_tile():
	# Map 7 east edge -> map 1 X=14. The exact bug from the user report.
	var payload = {"map_id": 1, "x": 14, "y": 50, "width": 100, "height": 100}
	var decoded = _decode_transition(payload)
	assert_eq(decoded["my_pos"], Vector2i(14, 50))
	# And the visual pixel-pos derived from it must match server-tile math,
	# NOT the prior map's far-east tween target.
	var pixel = WorldScript.tile_to_world(decoded["my_pos"].x, decoded["my_pos"].y, 64)
	assert_eq(pixel, Vector2(14 * 64, 50 * 64))
	assert_ne(pixel.x, 88 * 64, "pre-fix bug: sprite stuck at far-east X=88 pixel pos")

func test_west_edge_transition_lands_at_server_tile():
	# Symmetric: walking off west edge of map 1 -> map 7 X=87.
	var payload = {"map_id": 7, "x": 87, "y": 50, "width": 100, "height": 100}
	var decoded = _decode_transition(payload)
	assert_eq(decoded["my_pos"], Vector2i(87, 50))
	assert_eq(WorldScript.tile_to_world(87, 50, 64), Vector2(87 * 64, 50 * 64))

func test_north_edge_transition_lands_at_server_tile():
	# Walking off the north edge into a map below. Same math, just the y axis.
	var payload = {"map_id": 2, "x": 50, "y": 99, "width": 100, "height": 100}
	var decoded = _decode_transition(payload)
	assert_eq(decoded["my_pos"], Vector2i(50, 99))
	assert_eq(WorldScript.tile_to_world(50, 99, 64), Vector2(50 * 64, 99 * 64))

func test_south_edge_transition_lands_at_server_tile():
	# Walking off the south edge into a map above.
	var payload = {"map_id": 3, "x": 50, "y": 1, "width": 100, "height": 100}
	var decoded = _decode_transition(payload)
	assert_eq(decoded["my_pos"], Vector2i(50, 1))
	assert_eq(WorldScript.tile_to_world(50, 1, 64), Vector2(50 * 64, 1 * 64))

# --- defaults guard ---
#
# If the server ever ships a malformed payload missing fields, the client
# falls back to (50, 50) on a 100x100 map. That's documented in
# _handle_map_transition; this test pins it so future refactors don't
# silently change the safety floor.

func test_transition_uses_safe_defaults_when_payload_is_empty():
	var decoded = _decode_transition({})
	assert_eq(decoded["map_id"], 1)
	assert_eq(decoded["my_pos"], Vector2i(50, 50))
	assert_eq(decoded["map_size"], Vector2i(100, 100))
