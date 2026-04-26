extends GutTest
## Tests for the EffectSprite layer — placeholder meditation aura today,
## extensible to any effect_id the server adds later.

func before_all():
	if not SpriteCatalog.is_loaded():
		SpriteCatalog.load_catalogs()
	SpriteFramesBuilder.clear_cache()


# --- start / stop lifecycle --------------------------------------------------

func test_start_meditation_mounts_an_aura_node():
	var lc := LayeredCharacter.new()
	add_child_autofree(lc)
	lc.apply_layers({"body_id": 1, "head_id": 1})

	assert_eq(lc.active_effect(), -1, "no effect active by default")
	assert_false(lc.effect_layer.visible, "effect layer hidden by default")

	lc.start_effect(LayeredCharacter.EFFECT_MEDITATION)

	assert_eq(lc.active_effect(), LayeredCharacter.EFFECT_MEDITATION,
		"meditation effect tracked as active")
	assert_true(lc.effect_layer.visible, "effect layer becomes visible")
	assert_eq(lc.effect_layer.get_child_count(), 1,
		"exactly one aura child mounted")
	assert_true(lc.effect_layer.get_child(0) is MeditationAura,
		"meditation effect_id mounts a MeditationAura")


func test_stop_meditation_clears_the_aura():
	var lc := LayeredCharacter.new()
	add_child_autofree(lc)
	lc.apply_layers({"body_id": 1, "head_id": 1})
	lc.start_effect(LayeredCharacter.EFFECT_MEDITATION)

	lc.stop_effect(LayeredCharacter.EFFECT_MEDITATION)
	# Aura is queue_free'd — wait one frame for the tree to actually drop it.
	await get_tree().process_frame

	assert_eq(lc.active_effect(), -1, "no effect after stop")
	assert_false(lc.effect_layer.visible, "effect layer hidden after stop")
	assert_eq(lc.effect_layer.get_child_count(), 0,
		"aura children cleaned up")


func test_start_same_effect_twice_does_not_stack():
	var lc := LayeredCharacter.new()
	add_child_autofree(lc)
	lc.apply_layers({"body_id": 1, "head_id": 1})

	lc.start_effect(LayeredCharacter.EFFECT_MEDITATION)
	lc.start_effect(LayeredCharacter.EFFECT_MEDITATION)
	assert_eq(lc.effect_layer.get_child_count(), 1,
		"second start of the same effect is a no-op")


func test_stop_with_wrong_effect_id_is_a_noop():
	var lc := LayeredCharacter.new()
	add_child_autofree(lc)
	lc.apply_layers({"body_id": 1, "head_id": 1})

	lc.start_effect(LayeredCharacter.EFFECT_MEDITATION)
	# Stale STOP for an effect that's not active — must not clear meditation.
	lc.stop_effect(999)
	assert_eq(lc.active_effect(), LayeredCharacter.EFFECT_MEDITATION,
		"stop with mismatched effect_id leaves the active one alone")
	assert_true(lc.effect_layer.visible, "aura still up after mismatched stop")


func test_unknown_effect_id_is_logged_and_ignored():
	var lc := LayeredCharacter.new()
	add_child_autofree(lc)
	lc.apply_layers({"body_id": 1, "head_id": 1})

	# 999 isn't wired — start_effect should warn (not crash) and leave the
	# layer empty so future packets keep working.
	lc.start_effect(999)
	assert_eq(lc.active_effect(), -1, "unknown effect_id stays inactive")
	assert_false(lc.effect_layer.visible, "effect layer remains hidden")
	assert_eq(lc.effect_layer.get_child_count(), 0, "no aura child added")


# --- multi-target independence ----------------------------------------------

func test_multiple_characters_have_independent_effect_state():
	var a := LayeredCharacter.new()
	add_child_autofree(a)
	a.apply_layers({"body_id": 1, "head_id": 1})

	var b := LayeredCharacter.new()
	add_child_autofree(b)
	b.apply_layers({"body_id": 1, "head_id": 1})

	a.start_effect(LayeredCharacter.EFFECT_MEDITATION)
	# B unaffected.
	assert_eq(b.active_effect(), -1, "B's effect state independent of A's")
	assert_false(b.effect_layer.visible, "B's aura stays hidden")

	# Stopping A leaves... A stopped. Trivially.
	a.stop_effect(LayeredCharacter.EFFECT_MEDITATION)
	assert_eq(a.active_effect(), -1, "A stopped")
	# Now start on B — A still off.
	b.start_effect(LayeredCharacter.EFFECT_MEDITATION)
	assert_eq(b.active_effect(), LayeredCharacter.EFFECT_MEDITATION, "B is on")
	assert_eq(a.active_effect(), -1, "A still off")


# --- cleanup paths -----------------------------------------------------------

func test_clear_effects_removes_active_aura():
	var lc := LayeredCharacter.new()
	add_child_autofree(lc)
	lc.apply_layers({"body_id": 1, "head_id": 1})
	lc.start_effect(LayeredCharacter.EFFECT_MEDITATION)

	# CHAR_DEATH path on the local player calls clear_effects directly so
	# that the aura goes even if the EFFECT_STOP packet hasn't arrived yet.
	lc.clear_effects()
	await get_tree().process_frame

	assert_eq(lc.active_effect(), -1, "no effect after clear_effects")
	assert_false(lc.effect_layer.visible, "effect layer hidden after clear")
	assert_eq(lc.effect_layer.get_child_count(), 0, "aura children gone")


func test_effect_layer_z_index_is_below_body():
	var lc := LayeredCharacter.new()
	add_child_autofree(lc)
	lc.apply_layers({"body_id": 1, "head_id": 1})
	lc.start_effect(LayeredCharacter.EFFECT_MEDITATION)

	# Aura must render BEHIND the body — z_index strictly less than body's.
	assert_lt(lc.effect_layer.z_index, lc.body_sprite.z_index,
		"effect layer z_index is below body z_index")
