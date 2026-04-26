class_name LayeredCharacter extends Node2D
## Composite character node: 1 Node2D parent + 5 AnimatedSprite2D children
## (body, head, helmet, weapon, shield) drawn in z-order, plus an effect
## layer rendered BELOW the body for auras (meditation, blessings, VIP).
## Built programmatically so we don't have to author identical scenes for
## self / other players / future NPCs.
##
## Server contract this consumes:
##   sprite_layers = { body_id, head_id, helmet_id?, weapon_id?, shield_id? }
## helmet_id, weapon_id, shield_id may be missing or null — those layers
## stay hidden in that case.
##
## apply_layers() is idempotent: it can be called again mid-session when the
## server pushes a refreshed sprite_layers (e.g. INVENTORY_UPDATE after
## equip/unequip). Direction + walking state survive the swap, and the
## active animation's frame index is preserved per visible layer so the
## walk cycle doesn't snap to frame 0 mid-step.
##
## All visible layers play the same animation (walk_<dir>) in lockstep,
## driven by set_direction() / set_walking().

const TILE_SIZE_DEFAULT := 32  # caller can override via set_tile_size()
const MeditationAuraScript := preload("res://scripts/game/meditation_aura.gd")

# z order: effect (under), body bottom, head above body, then equip layers above.
# Single Node2D z_index so the whole character sits on the same map z-stack.
const Z_EFFECT := -1
const Z_BODY := 0
const Z_HEAD := 1
const Z_HELMET := 2
const Z_SHIELD := 3
const Z_WEAPON := 4

# Effect ids (mirror server constants — see packet_ids.gd).
const EFFECT_MEDITATION := 1

var body_sprite: AnimatedSprite2D
var head_sprite: AnimatedSprite2D
var helmet_sprite: AnimatedSprite2D
var weapon_sprite: AnimatedSprite2D
var shield_sprite: AnimatedSprite2D
# EffectSprite is a Node2D — for the meditation placeholder we render with
# _draw() instead of an AnimatedSprite2D since real Cucsi effect frames are
# out of scope this round (see PR description). The node is reused for any
# future effect_id; only one effect is active at a time per character.
var effect_layer: Node2D

var _tile_size: int = TILE_SIZE_DEFAULT
var _direction: String = CharacterDirection.SOUTH
var _walking: bool = false

# Track which body id is mounted so the head_offset stays in sync.
var _body_id: int = -1
var _head_id: int = -1
# Track equip-layer ids so we can skip rebuilding sprite_frames when nothing
# changed (and so tests can introspect what's mounted).
var _helmet_id: int = -1
var _weapon_id: int = -1
var _shield_id: int = -1

# Currently-active effect id, or -1 if none.
var _active_effect: int = -1


func _init() -> void:
	body_sprite = _make_layer("BodySprite", Z_BODY)
	head_sprite = _make_layer("HeadSprite", Z_HEAD)
	helmet_sprite = _make_layer("HelmetSprite", Z_HELMET)
	weapon_sprite = _make_layer("WeaponSprite", Z_WEAPON)
	shield_sprite = _make_layer("ShieldSprite", Z_SHIELD)
	effect_layer = _make_effect_layer()


func _make_layer(layer_name: String, z: int) -> AnimatedSprite2D:
	var s := AnimatedSprite2D.new()
	s.name = layer_name
	s.centered = false
	s.z_index = z
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.visible = false
	add_child(s)
	return s


func _make_effect_layer() -> Node2D:
	# Empty container; the actual aura node is added on start_effect() and
	# removed on stop_effect(). Rendered below the body via Z_EFFECT.
	var n := Node2D.new()
	n.name = "EffectSprite"
	n.z_index = Z_EFFECT
	n.visible = false
	# Center on the character's feet (bottom-center of the tile).
	n.position = Vector2(_tile_size / 2.0, _tile_size / 2.0)
	add_child(n)
	return n


func set_tile_size(t: int) -> void:
	_tile_size = max(1, t)
	if effect_layer != null:
		effect_layer.position = Vector2(_tile_size / 2.0, _tile_size / 2.0)


# --- Loadout application ----------------------------------------------------

func apply_layers(sprite_layers: Dictionary) -> void:
	# Idempotent: callable on first spawn AND on every later equip / unequip
	# pushed by the server (INVENTORY_UPDATE, PLAYER_LAYERS_UPDATE). Direction
	# and walking state survive the swap. Per-layer current-frame indices are
	# captured before the rebuild and restored after, so the walk cycle keeps
	# its phase across mid-step gear changes.
	var saved_frames := _capture_frame_state()

	# Server sends body_id always; head_id may be null for non-humanoid NPCs
	# (animals, golems, etc.). Helmet/weapon/shield are optional and don't
	# apply to NPCs at all in the current contract.
	var body_id := int(sprite_layers.get("body_id", 1))
	_set_body(body_id)
	var head_value = sprite_layers.get("head_id", 1)
	if head_value == null:
		# Non-humanoid: keep HeadSprite hidden.
		head_sprite.visible = false
		head_sprite.sprite_frames = null
		_head_id = -1
	else:
		_set_head(int(head_value))
	_helmet_id = _set_optional(helmet_sprite, sprite_layers.get("helmet_id", null), "helmet")
	_weapon_id = _set_optional(weapon_sprite, sprite_layers.get("weapon_id", null), "weapon")
	_shield_id = _set_optional(shield_sprite, sprite_layers.get("shield_id", null), "shield")
	# Re-apply so newly-set layers get the current direction + walking state.
	_fanout_animation()
	_restore_frame_state(saved_frames)


func _capture_frame_state() -> Dictionary:
	# Returns { layer_name -> frame_index } for each currently-visible layer
	# so we can restore mid-cycle across an apply_layers re-entry. We don't
	# need to capture animation name because _direction is preserved on `self`
	# and _fanout_animation() will re-set the same anim_name afterward.
	var snap := {}
	for layer in [body_sprite, head_sprite, helmet_sprite, weapon_sprite, shield_sprite]:
		if layer.visible and layer.sprite_frames != null:
			snap[layer.name] = layer.frame
	return snap


func _restore_frame_state(snap: Dictionary) -> void:
	for layer in [body_sprite, head_sprite, helmet_sprite, weapon_sprite, shield_sprite]:
		if not layer.visible or layer.sprite_frames == null:
			continue
		var anim_name := CharacterDirection.anim(_direction)
		if not layer.sprite_frames.has_animation(anim_name):
			continue
		var prev_frame: int = int(snap.get(layer.name, 0))
		var max_frame: int = int(layer.sprite_frames.get_frame_count(anim_name)) - 1
		if max_frame < 0:
			continue
		# Clamp — the new SpriteFrames may have fewer frames than the old one
		# (e.g. west has 5 vs south's 6). Modulo would shift the visual phase.
		var target: int = mini(prev_frame, max_frame)
		layer.frame = target
		# AnimatedSprite2D.play() restarts at frame 0 if a different animation
		# was just assigned, so we set frame AFTER the play() in
		# _fanout_animation() ran — which it did, by virtue of being called
		# before this. Re-call play() if walking so the timing keeps ticking
		# from `target` rather than 0.
		if _walking:
			layer.play(anim_name)
			layer.frame = target


func _set_body(body_id: int) -> void:
	var sf := SpriteFramesBuilder.for_body(body_id)
	if sf == null:
		# Fallback: try id=1; if that's also missing, hide the layer.
		if body_id != 1:
			push_warning("[LayeredCharacter] body_id=%d missing, falling back to body_id=1" % body_id)
			sf = SpriteFramesBuilder.for_body(1)
		if sf == null:
			body_sprite.visible = false
			_body_id = -1
			return
	body_sprite.sprite_frames = sf
	body_sprite.visible = true
	_body_id = body_id
	_anchor_layer(body_sprite)
	# Head offset depends on the body — re-apply.
	_apply_head_offset()


func _set_head(head_id: int) -> void:
	var sf := SpriteFramesBuilder.for_head(head_id)
	if sf == null:
		if head_id != 1:
			push_warning("[LayeredCharacter] head_id=%d missing, falling back to head_id=1" % head_id)
			sf = SpriteFramesBuilder.for_head(1)
		if sf == null:
			head_sprite.visible = false
			_head_id = -1
			return
	head_sprite.sprite_frames = sf
	head_sprite.visible = true
	_head_id = head_id
	_anchor_layer(head_sprite)
	_apply_head_offset()


func _set_optional(layer: AnimatedSprite2D, id_value, kind: String) -> int:
	# Returns the id we ended up mounting (for caller bookkeeping), or -1 if
	# the layer is now hidden (null id, or unknown id not in catalog).
	if id_value == null:
		layer.visible = false
		layer.sprite_frames = null
		return -1
	var id_int := int(id_value)
	var sf: SpriteFrames = null
	match kind:
		"helmet":
			sf = SpriteFramesBuilder.for_helmet(id_int)
		"weapon":
			sf = SpriteFramesBuilder.for_weapon(id_int)
		"shield":
			sf = SpriteFramesBuilder.for_shield(id_int)
	if sf == null:
		push_warning("[LayeredCharacter] %s_id=%d missing — layer hidden" % [kind, id_int])
		layer.visible = false
		return -1
	layer.sprite_frames = sf
	layer.visible = true
	_anchor_layer(layer)
	return id_int


func _anchor_layer(layer: AnimatedSprite2D) -> void:
	# Anchor each layer to the tile's bottom-center (Cucsi convention) so tall
	# bodies overflow upward and read naturally against the grid. We pull the
	# frame size from the first frame of walk_south (every layer has one).
	if layer.sprite_frames == null:
		return
	if not layer.sprite_frames.has_animation(CharacterDirection.ANIM_PREFIX + CharacterDirection.SOUTH):
		return
	var frame_count := layer.sprite_frames.get_frame_count(CharacterDirection.ANIM_PREFIX + CharacterDirection.SOUTH)
	if frame_count <= 0:
		return
	var tex: Texture2D = layer.sprite_frames.get_frame_texture(
		CharacterDirection.ANIM_PREFIX + CharacterDirection.SOUTH, 0
	)
	if tex == null:
		return
	var sz: Vector2 = tex.get_size()
	# offset.x centers horizontally on the tile, offset.y aligns the bottom of
	# the sprite to the bottom of the tile.
	layer.offset = Vector2(-(sz.x - _tile_size) / 2.0, -(sz.y - _tile_size))


func _apply_head_offset() -> void:
	# Body provides the head_offset; it's relative to the body's anchor.
	if _body_id < 0:
		head_sprite.position = Vector2.ZERO
		return
	var entry = SpriteCatalog.body(_body_id)
	if entry == null or not (entry is Dictionary):
		head_sprite.position = Vector2.ZERO
		return
	var off = entry.get("head_offset", {"x": 0, "y": 0})
	head_sprite.position = Vector2(float(off.get("x", 0)), float(off.get("y", 0)))


# --- Animation drive --------------------------------------------------------

func set_direction(direction: String) -> void:
	if direction == _direction:
		return
	_direction = direction
	_fanout_animation()


func set_walking(walking: bool) -> void:
	if walking == _walking:
		return
	_walking = walking
	_fanout_animation()


func step(dx: int, dy: int) -> void:
	# Convenience: caller passes the (dx, dy) of the just-started tween,
	# we update direction and start playing.
	set_direction(CharacterDirection.from_delta(dx, dy))
	set_walking(true)


func stop() -> void:
	set_walking(false)


func _fanout_animation() -> void:
	var anim_name := CharacterDirection.anim(_direction)
	for layer in [body_sprite, head_sprite, helmet_sprite, weapon_sprite, shield_sprite]:
		if not layer.visible or layer.sprite_frames == null:
			continue
		if not layer.sprite_frames.has_animation(anim_name):
			continue
		layer.animation = anim_name
		if _walking:
			layer.play(anim_name)
		else:
			layer.stop()
			layer.frame = 0


func current_direction() -> String:
	return _direction


func is_walking() -> bool:
	return _walking


# --- Effects (auras, blessings, etc.) ---------------------------------------

func start_effect(effect_id: int) -> void:
	# Idempotent: starting the same effect twice is a no-op (avoids stacking
	# multiple aura nodes). Starting a different effect replaces the current
	# one — only one effect rendered at a time per character. Server design
	# can later relax this by giving each effect its own slot.
	if _active_effect == effect_id:
		return
	_clear_effect_children()
	var node := _build_effect_node(effect_id)
	if node == null:
		push_warning("[LayeredCharacter] unknown effect_id=%d — ignoring" % effect_id)
		return
	effect_layer.add_child(node)
	effect_layer.visible = true
	_active_effect = effect_id


func stop_effect(effect_id: int) -> void:
	# Only stop if the active effect matches — otherwise a stale STOP for a
	# previously-replaced effect would clear the current one.
	if _active_effect != effect_id:
		return
	_clear_effect_children()
	effect_layer.visible = false
	_active_effect = -1


func clear_effects() -> void:
	# Used by the world scene on CHAR_DEATH / despawn paths to make sure no
	# orphan auras outlive the character they were on.
	_clear_effect_children()
	effect_layer.visible = false
	_active_effect = -1


func active_effect() -> int:
	return _active_effect


func _clear_effect_children() -> void:
	for child in effect_layer.get_children():
		child.queue_free()


func _build_effect_node(effect_id: int) -> Node2D:
	match effect_id:
		EFFECT_MEDITATION:
			return MeditationAuraScript.new()
	return null
