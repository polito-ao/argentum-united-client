extends GutTest
## Unit tests for BroadcastLinkDispatcher. The dispatcher routes link
## Dictionaries to client-side handlers. We use a stub world that records
## which handler was called with which params.

const BroadcastLinkDispatcher = preload("res://scripts/ui/broadcast_link_dispatcher.gd")

var world: _StubWorld

func before_each():
	world = _StubWorld.new()

# --- map_jump ---

func test_map_jump_calls_world_pulse_minimap_marker():
	BroadcastLinkDispatcher.dispatch(world, {
		"kind": "map_jump",
		"params": {"map_id": 1, "x": 50, "y": 50},
	})
	assert_eq(world.pulse_calls.size(), 1)
	assert_eq(world.pulse_calls[0].map_id, 1)
	assert_eq(world.pulse_calls[0].x, 50)
	assert_eq(world.pulse_calls[0].y, 50)

func test_map_jump_handles_missing_params_with_zeros():
	BroadcastLinkDispatcher.dispatch(world, {
		"kind": "map_jump",
		"params": {},
	})
	assert_eq(world.pulse_calls.size(), 1)
	assert_eq(world.pulse_calls[0].map_id, 0)

# --- unknown kind ---

func test_unknown_kind_does_not_crash():
	# Should log a warning, not crash. We don't capture push_warning,
	# we just assert no handler fired.
	BroadcastLinkDispatcher.dispatch(world, {
		"kind": "open_panel",
		"params": {"id": "spellbook"},
	})
	assert_eq(world.pulse_calls.size(), 0)

func test_missing_kind_does_not_crash():
	BroadcastLinkDispatcher.dispatch(world, {
		"params": {"x": 1},
	})
	assert_eq(world.pulse_calls.size(), 0)

func test_non_dictionary_link_does_not_crash():
	BroadcastLinkDispatcher.dispatch(world, "not a dict")
	BroadcastLinkDispatcher.dispatch(world, null)
	BroadcastLinkDispatcher.dispatch(world, 42)
	assert_eq(world.pulse_calls.size(), 0)

# --- null world ---

func test_null_world_with_known_kind_does_not_crash():
	BroadcastLinkDispatcher.dispatch(null, {
		"kind": "map_jump",
		"params": {"map_id": 1, "x": 1, "y": 1},
	})
	# No assertions on side effects — just don't crash.
	assert_true(true)

# --- helpers ---

class _StubWorld extends RefCounted:
	var pulse_calls: Array = []
	func pulse_minimap_marker(map_id: int, x: int, y: int) -> void:
		pulse_calls.append({"map_id": map_id, "x": x, "y": y})
