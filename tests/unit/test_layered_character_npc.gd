extends GutTest
## Tests LayeredCharacter behavior for NPC payloads. NPCs ship a body_id always
## and a head_id that is null for non-humanoid creatures (animals, golems, etc.).
## Helmet / weapon / shield are not part of the NPC contract and stay hidden.

func before_all():
	if not SpriteCatalog.is_loaded():
		SpriteCatalog.load_catalogs()
	SpriteFramesBuilder.clear_cache()

# --- humanoid NPC: body + head -----------------------------------------------

func test_humanoid_npc_sets_body_and_head_frames():
	var lc := LayeredCharacter.new()
	add_child_autofree(lc)
	lc.apply_layers({"body_id": 1, "head_id": 1})

	assert_not_null(lc.body_sprite.sprite_frames, "body sprite frames should be set")
	assert_true(lc.body_sprite.visible, "body should be visible")
	assert_not_null(lc.head_sprite.sprite_frames, "head sprite frames should be set")
	assert_true(lc.head_sprite.visible, "head should be visible")

func test_humanoid_npc_equipment_layers_hidden():
	var lc := LayeredCharacter.new()
	add_child_autofree(lc)
	lc.apply_layers({"body_id": 1, "head_id": 1})

	assert_false(lc.helmet_sprite.visible, "helmet should be hidden when not provided")
	assert_false(lc.weapon_sprite.visible, "weapon should be hidden when not provided")
	assert_false(lc.shield_sprite.visible, "shield should be hidden when not provided")

# --- non-humanoid NPC: body only (head_id = null) ----------------------------

func test_non_humanoid_npc_hides_head():
	var lc := LayeredCharacter.new()
	add_child_autofree(lc)
	lc.apply_layers({"body_id": 1, "head_id": null})

	assert_not_null(lc.body_sprite.sprite_frames, "body sprite frames should still be set")
	assert_true(lc.body_sprite.visible, "body should still be visible")
	assert_false(lc.head_sprite.visible, "head should be hidden when head_id is null")
	assert_null(lc.head_sprite.sprite_frames, "head should have no sprite frames")

func test_head_visibility_toggles_when_head_id_changes():
	var lc := LayeredCharacter.new()
	add_child_autofree(lc)

	# Start humanoid: head visible.
	lc.apply_layers({"body_id": 1, "head_id": 1})
	assert_true(lc.head_sprite.visible, "head visible after humanoid apply")

	# Switch to non-humanoid: head hidden.
	lc.apply_layers({"body_id": 1, "head_id": null})
	assert_false(lc.head_sprite.visible, "head hidden after null head_id")

	# Back to humanoid: head visible again.
	lc.apply_layers({"body_id": 1, "head_id": 1})
	assert_true(lc.head_sprite.visible, "head visible after humanoid re-apply")

# --- walk animation drives every visible layer -------------------------------

func test_set_walking_plays_animation_on_visible_layers_only():
	var lc := LayeredCharacter.new()
	add_child_autofree(lc)
	lc.apply_layers({"body_id": 1, "head_id": null})
	lc.set_direction(CharacterDirection.EAST)
	lc.set_walking(true)

	assert_true(lc.body_sprite.is_playing(), "body should play walk anim")
	# Hidden head must not be playing — guards against driving an unset SpriteFrames.
	assert_false(lc.head_sprite.is_playing(), "hidden head should not play")

func test_stop_resets_to_frame_zero():
	var lc := LayeredCharacter.new()
	add_child_autofree(lc)
	lc.apply_layers({"body_id": 1, "head_id": 1})
	lc.set_direction(CharacterDirection.NORTH)
	lc.set_walking(true)
	lc.set_walking(false)

	assert_false(lc.body_sprite.is_playing(), "body stops on idle")
	assert_eq(lc.body_sprite.frame, 0, "body resets to frame 0")
	assert_false(lc.head_sprite.is_playing(), "head stops on idle")
	assert_eq(lc.head_sprite.frame, 0, "head resets to frame 0")
