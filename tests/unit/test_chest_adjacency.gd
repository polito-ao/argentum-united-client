extends GutTest
## Unit tests for the chest-adjacency helper used by world.gd to decide
## which chest the F-key (open_chest) action targets. Mirrors the server's
## Manhattan-distance-1 rule (cardinal neighbors only — diagonals don't count).
##
## The helper is a static function on world.gd so tests don't have to spin up
## the full world scene tree.

const WorldScript = preload("res://scenes/world/world.gd")

func _chest(pos: Vector2i, state: String = "closed") -> Dictionary:
	# The real world.gd entry has a Node2D under "node"; the helper only
	# reads "pos" and "state", so we omit "node" here. Keeps the test
	# decoupled from rendering.
	return {"pos": pos, "state": state}

# --- positive cases (one cardinal neighbor) ---

func test_finds_chest_north_of_player():
	var chests = {42: _chest(Vector2i(5, 4))}
	assert_eq(WorldScript.find_adjacent_chest(Vector2i(5, 5), chests), 42)

func test_finds_chest_south_of_player():
	var chests = {42: _chest(Vector2i(5, 6))}
	assert_eq(WorldScript.find_adjacent_chest(Vector2i(5, 5), chests), 42)

func test_finds_chest_east_of_player():
	var chests = {42: _chest(Vector2i(6, 5))}
	assert_eq(WorldScript.find_adjacent_chest(Vector2i(5, 5), chests), 42)

func test_finds_chest_west_of_player():
	var chests = {42: _chest(Vector2i(4, 5))}
	assert_eq(WorldScript.find_adjacent_chest(Vector2i(5, 5), chests), 42)

# --- negative cases ---

func test_returns_minus_one_when_no_chests():
	assert_eq(WorldScript.find_adjacent_chest(Vector2i(5, 5), {}), -1)

func test_diagonal_chest_does_not_count_as_adjacent():
	var chests = {42: _chest(Vector2i(6, 6))}
	assert_eq(WorldScript.find_adjacent_chest(Vector2i(5, 5), chests), -1)

func test_chest_two_tiles_away_does_not_count():
	var chests = {42: _chest(Vector2i(5, 7))}
	assert_eq(WorldScript.find_adjacent_chest(Vector2i(5, 5), chests), -1)

func test_chest_on_same_tile_does_not_count_as_adjacent():
	# Manhattan distance 0 — server rule is exactly 1.
	var chests = {42: _chest(Vector2i(5, 5))}
	assert_eq(WorldScript.find_adjacent_chest(Vector2i(5, 5), chests), -1)

func test_already_opened_adjacent_chest_is_skipped():
	var chests = {42: _chest(Vector2i(5, 4), "opened")}
	assert_eq(WorldScript.find_adjacent_chest(Vector2i(5, 5), chests), -1)

# --- multiple chests ---

func test_returns_a_closed_neighbor_when_a_far_open_chest_exists():
	var chests = {
		1: _chest(Vector2i(20, 20), "opened"), # far + opened
		7: _chest(Vector2i(5, 6)),             # adjacent + closed
	}
	assert_eq(WorldScript.find_adjacent_chest(Vector2i(5, 5), chests), 7)

func test_returns_closed_neighbor_when_adjacent_chest_is_opened():
	# Two chests, both adjacent. The opened one shouldn't shadow the closed one.
	var chests = {
		1: _chest(Vector2i(5, 4), "opened"),
		2: _chest(Vector2i(6, 5), "closed"),
	}
	assert_eq(WorldScript.find_adjacent_chest(Vector2i(5, 5), chests), 2)
