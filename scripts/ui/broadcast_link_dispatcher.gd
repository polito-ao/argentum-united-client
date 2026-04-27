class_name BroadcastLinkDispatcher

## Routes BROADCAST_MESSAGE link clicks to client-side handlers.
##
## Each "kind" is a static handler. Add new kinds in feature PRs that
## ship the corresponding UI (open_panel, highlight_entity, etc.). For
## now only `map_jump` is implemented as a proof of concept — every
## other kind logs a warning and no-ops.
##
## The dispatcher is intentionally a bag of static functions: there is
## no per-call state, and link payloads are small Dictionaries straight
## from MessagePack. Callers pass the world reference so handlers can
## reach the minimap / camera / scene tree without reaching for autoloads.

# Pans the world's minimap to (x, y) on `map_id` and pulses a marker.
# If the player isn't on that map, we open the minimap and pulse the
# marker only — we never teleport. Free-will travel is preserved.
static func dispatch(world, link) -> void:
	if not (link is Dictionary):
		push_warning("BroadcastLinkDispatcher: link is not a Dictionary: %s" % [link])
		return
	var kind: String = String(link.get("kind", ""))
	var params: Dictionary = link.get("params", {}) if link.get("params", {}) is Dictionary else {}
	if kind.is_empty():
		push_warning("BroadcastLinkDispatcher: link missing 'kind'")
		return
	match kind:
		"map_jump":
			_handle_map_jump(world, params)
		_:
			push_warning("Unknown broadcast link kind: %s" % kind)

static func _handle_map_jump(world, params: Dictionary) -> void:
	if world == null:
		push_warning("BroadcastLinkDispatcher.map_jump: null world")
		return
	var dest_map_id: int = int(params.get("map_id", 0))
	var dest_x: int = int(params.get("x", 0))
	var dest_y: int = int(params.get("y", 0))
	# `pulse_minimap_marker` lives on world.gd; it knows about the
	# `_MinimapDrawer` and whether the destination is the current map.
	if world.has_method("pulse_minimap_marker"):
		world.pulse_minimap_marker(dest_map_id, dest_x, dest_y)
	else:
		push_warning("BroadcastLinkDispatcher.map_jump: world has no pulse_minimap_marker")
