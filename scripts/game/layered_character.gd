class_name LayeredCharacter extends Node2D
## Composite character node: 1 Node2D parent + 5 AnimatedSprite2D children
## (body, head, helmet, weapon, shield) drawn in z-order. Built
## programmatically so we don't have to author identical scenes for
## self / other players / future NPCs.
##
## Server contract this consumes:
##   sprite_layers = { body_id, head_id, helmet_id?, weapon_id?, shield_id? }
## helmet_id, weapon_id, shield_id may be missing or null — those layers
## stay hidden in that case.
##
## All visible layers play the same animation (walk_<dir>) in lockstep,
## driven by set_direction() / set_walking().

const TILE_SIZE_DEFAULT := 32  # caller can override via set_tile_size()

# z order: body bottom, head above body, then equip layers above. Single
# Node2D z_index so the whole character sits on the same map z-stack.
const Z_BODY := 0
const Z_HEAD := 1
const Z_HELMET := 2
const Z_SHIELD := 3
const Z_WEAPON := 4

var body_sprite: AnimatedSprite2D
var head_sprite: AnimatedSprite2D
var helmet_sprite: AnimatedSprite2D
var weapon_sprite: AnimatedSprite2D
var shield_sprite: AnimatedSprite2D

var _tile_size: int = TILE_SIZE_DEFAULT
var _direction: String = CharacterDirection.SOUTH
var _walking: bool = false

# Track which body id is mounted so the head_offset stays in sync.
var _body_id: int = -1
var _head_id: int = -1


func _init() -> void:
	body_sprite = _make_layer("BodySprite", Z_BODY)
	head_sprite = _make_layer("HeadSprite", Z_HEAD)
	helmet_sprite = _make_layer("HelmetSprite", Z_HELMET)
	weapon_sprite = _make_layer("WeaponSprite", Z_WEAPON)
	shield_sprite = _make_layer("ShieldSprite", Z_SHIELD)


func _make_layer(layer_name: String, z: int) -> AnimatedSprite2D:
	var s := AnimatedSprite2D.new()
	s.name = layer_name
	s.centered = false
	s.z_index = z
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.visible = false
	add_child(s)
	return s


func set_tile_size(t: int) -> void:
	_tile_size = max(1, t)


# --- Loadout application ----------------------------------------------------

func apply_layers(sprite_layers: Dictionary) -> void:
	# Server sends body_id + head_id always, plus optional helmet/weapon/shield.
	var body_id := int(sprite_layers.get("body_id", 1))
	var head_id := int(sprite_layers.get("head_id", 1))
	_set_body(body_id)
	_set_head(head_id)
	_set_optional(helmet_sprite, sprite_layers.get("helmet_id", null), "helmet")
	_set_optional(weapon_sprite, sprite_layers.get("weapon_id", null), "weapon")
	_set_optional(shield_sprite, sprite_layers.get("shield_id", null), "shield")
	# Re-apply so newly-set layers get the current direction + walking state.
	_fanout_animation()


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


func _set_optional(layer: AnimatedSprite2D, id_value, kind: String) -> void:
	if id_value == null:
		layer.visible = false
		layer.sprite_frames = null
		return
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
		return
	layer.sprite_frames = sf
	layer.visible = true
	_anchor_layer(layer)


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
