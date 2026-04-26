extends GutTest
## Unit tests for the CharacterDirection helper. Pure static functions —
## no scene tree, no autoloads, no fixtures.

const Dir = preload("res://scripts/game/character_direction.gd")

# --- from_delta: cardinal mapping ---------------------------------------------

func test_positive_dx_is_east():
	assert_eq(Dir.from_delta(1, 0), Dir.EAST)

func test_negative_dx_is_west():
	assert_eq(Dir.from_delta(-1, 0), Dir.WEST)

func test_positive_dy_is_south():
	assert_eq(Dir.from_delta(0, 1), Dir.SOUTH)

func test_negative_dy_is_north():
	assert_eq(Dir.from_delta(0, -1), Dir.NORTH)

# --- defaulting + tie-breaking ------------------------------------------------

func test_zero_delta_defaults_to_south():
	# Idle / spawn case — face the camera by convention.
	assert_eq(Dir.from_delta(0, 0), Dir.SOUTH)

func test_diagonal_breaks_ties_horizontally():
	# AO-style movement is strictly cardinal; this guards against the
	# server ever shipping a diagonal correction.
	assert_eq(Dir.from_delta(1, 1), Dir.EAST)
	assert_eq(Dir.from_delta(-1, 1), Dir.WEST)

# --- anim() composition --------------------------------------------------------

func test_anim_prefixes_walk():
	assert_eq(Dir.anim(Dir.SOUTH), "walk_south")
	assert_eq(Dir.anim(Dir.NORTH), "walk_north")
	assert_eq(Dir.anim(Dir.EAST), "walk_east")
	assert_eq(Dir.anim(Dir.WEST), "walk_west")

func test_anim_for_each_from_delta_result():
	# End-to-end: feed every cardinal delta through both helpers.
	assert_eq(Dir.anim(Dir.from_delta(0, -1)), "walk_north")
	assert_eq(Dir.anim(Dir.from_delta(0, 1)), "walk_south")
	assert_eq(Dir.anim(Dir.from_delta(1, 0)), "walk_east")
	assert_eq(Dir.anim(Dir.from_delta(-1, 0)), "walk_west")
