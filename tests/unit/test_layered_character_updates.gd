extends GutTest
## Tests that LayeredCharacter.apply_layers is idempotent — callable mid-session
## when the server pushes refreshed sprite_layers (equip/unequip path), without
## leaking nodes, losing direction state, or snapping the walk cycle to frame 0
## mid-step.

func before_all():
	if not SpriteCatalog.is_loaded():
		SpriteCatalog.load_catalogs()
	SpriteFramesBuilder.clear_cache()


# --- idempotency / no leaks --------------------------------------------------

func test_apply_layers_does_not_leak_nodes_across_calls():
	var lc := LayeredCharacter.new()
	add_child_autofree(lc)
	# First call (typical spawn).
	lc.apply_layers({"body_id": 1, "head_id": 1})
	var initial_child_count := lc.get_child_count()

	# Re-apply with a different loadout — equip a helmet.
	lc.apply_layers({"body_id": 1, "head_id": 1, "helmet_id": 1})
	assert_eq(lc.get_child_count(), initial_child_count,
		"re-applying layers must NOT add new layer nodes")

	# Re-apply again — back to no helmet. Same invariant.
	lc.apply_layers({"body_id": 1, "head_id": 1})
	assert_eq(lc.get_child_count(), initial_child_count,
		"unequipping likewise must not change child count")


func test_helmet_visible_after_equip_and_hidden_after_unequip():
	var lc := LayeredCharacter.new()
	add_child_autofree(lc)

	lc.apply_layers({"body_id": 1, "head_id": 1})
	assert_false(lc.helmet_sprite.visible, "helmet hidden when no helmet_id supplied")

	lc.apply_layers({"body_id": 1, "head_id": 1, "helmet_id": 1})
	assert_true(lc.helmet_sprite.visible, "helmet visible after equip")
	assert_not_null(lc.helmet_sprite.sprite_frames, "helmet has sprite_frames")

	lc.apply_layers({"body_id": 1, "head_id": 1})
	assert_false(lc.helmet_sprite.visible, "helmet hidden after unequip")


# --- direction state preserved across apply_layers ---------------------------

func test_direction_preserved_across_reapply():
	var lc := LayeredCharacter.new()
	add_child_autofree(lc)

	lc.apply_layers({"body_id": 1, "head_id": 1})
	lc.set_direction(CharacterDirection.NORTH)
	# Equip mid-state — direction must stick.
	lc.apply_layers({"body_id": 1, "head_id": 1, "helmet_id": 1})
	assert_eq(lc.current_direction(), CharacterDirection.NORTH,
		"direction must survive an apply_layers re-entry")


func test_walking_state_preserved_across_reapply():
	var lc := LayeredCharacter.new()
	add_child_autofree(lc)

	lc.apply_layers({"body_id": 1, "head_id": 1})
	lc.set_direction(CharacterDirection.EAST)
	lc.set_walking(true)
	lc.apply_layers({"body_id": 1, "head_id": 1, "helmet_id": 1})
	assert_true(lc.is_walking(), "walking flag must survive re-apply")
	assert_true(lc.body_sprite.is_playing(), "body should keep playing across the swap")


# --- body swap re-applies head_offset ----------------------------------------

func test_body_swap_reapplies_head_offset():
	var lc := LayeredCharacter.new()
	add_child_autofree(lc)

	lc.apply_layers({"body_id": 1, "head_id": 1})
	var off_body_1: Vector2 = lc.head_sprite.position

	# Swap to a different body — even if the head_offset is identical for
	# that body in the catalog, the call path that re-applies it must run
	# (otherwise stale offsets would survive a body change).
	lc.apply_layers({"body_id": 2, "head_id": 1})
	assert_not_null(lc.body_sprite.sprite_frames, "body 2 mounted")
	assert_not_null(lc.head_sprite.sprite_frames, "head still mounted after body swap")

	# Whatever body 2's head_offset is, head_sprite.position must equal it.
	var entry = SpriteCatalog.body(2)
	assert_not_null(entry, "body_2 must exist in the catalog for this test")
	var expected_off = entry.get("head_offset", {"x": 0, "y": 0})
	var expected := Vector2(float(expected_off.get("x", 0)), float(expected_off.get("y", 0)))
	assert_eq(lc.head_sprite.position, expected,
		"head_offset re-applied from new body's catalog entry")
	# Sanity: if body_2 happens to share body_1's offset, the assertion still
	# holds — we explicitly compare to body_2's catalog entry, not assume diff.
	if expected != off_body_1:
		gut.p("body_1 and body_2 head_offsets differ — swap visibly relocated the head")


# --- unknown equipment ids are non-fatal -------------------------------------

func test_unknown_helmet_id_hides_layer_without_crashing():
	var lc := LayeredCharacter.new()
	add_child_autofree(lc)

	# 999_999 is virtually guaranteed missing from helmets.json. Layer must
	# stay hidden (no crash, no half-mounted state).
	lc.apply_layers({"body_id": 1, "head_id": 1, "helmet_id": 999999})
	assert_false(lc.helmet_sprite.visible,
		"unknown helmet_id leaves the layer hidden")


# --- mid-step frame preservation ---------------------------------------------

func test_walk_cycle_does_not_snap_to_frame_zero_on_reapply():
	var lc := LayeredCharacter.new()
	add_child_autofree(lc)

	lc.apply_layers({"body_id": 1, "head_id": 1})
	lc.set_direction(CharacterDirection.SOUTH)
	lc.set_walking(true)
	# Force the body to a non-zero frame to simulate "mid-step".
	lc.body_sprite.frame = 2

	lc.apply_layers({"body_id": 1, "head_id": 1, "helmet_id": 1})
	# After the swap, body should still be at (or near) frame 2 — clamped
	# only if the new SpriteFrames has fewer frames in this direction.
	var max_frame := lc.body_sprite.sprite_frames.get_frame_count("walk_south") - 1
	var expected_frame = min(2, max_frame)
	assert_eq(lc.body_sprite.frame, expected_frame,
		"frame index preserved across apply_layers (clamped to new max)")
