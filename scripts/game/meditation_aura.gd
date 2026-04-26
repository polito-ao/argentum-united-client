class_name MeditationAura extends Node2D
## Visual for the meditation effect (effect_id = 1).
##
## Renders the real Cucsi meditation sprite (Fxs.ini[4] = FxMeditar.CHICO,
## Grh134 — a 10-frame loop on 3069.png) via AnimatedSprite2D when the
## effects catalog is loaded. If the catalog or its texture is missing, falls
## back to a procedural gold pulsing circle so the world keeps rendering even
## when the parsed assets aren't on disk yet.
##
## Anchored at (0, 0) in local space — the parent LayeredCharacter positions
## the effect_layer at the character's feet (tile_size/2, tile_size/2). The
## effect's own offset (from Fxs.ini) is applied as a position nudge here.
##
## Z order: parent sets z_index = Z_EFFECT (-1) so we render BELOW the body.

const EFFECT_MEDITATION_ID := 1

# Fallback drawing constants — kept verbatim from the placeholder so the
# behaviour matches when the catalog can't load.
const RADIUS := 32.0
const PULSE_HZ := 1.0
const ALPHA_MIN := 0.18
const ALPHA_MAX := 0.55
const COLOR_RGB := Color(1.0, 0.85, 0.2)  # gold

# Whether we already warned about the fallback path this session — single
# warning is enough; spamming the console on every spawn is noise.
static var _warned_fallback: bool = false

var _phase: float = 0.0
var _sprite: AnimatedSprite2D = null
var _using_fallback: bool = false


func _ready() -> void:
	# Defensive z_index — parent normally sets this to Z_EFFECT, but when
	# mounted in isolation (tests, preview tools) we still want it below
	# nominal-zero siblings.
	z_index = -1
	_setup_visual()


func _setup_visual() -> void:
	var entry = _load_effect_entry()
	if entry == null:
		_init_fallback("catalog entry effect_id=%d missing" % EFFECT_MEDITATION_ID)
		return
	var sf: SpriteFrames = SpriteFramesBuilder.for_effect(EFFECT_MEDITATION_ID)
	if sf == null:
		_init_fallback("SpriteFrames build returned null for effect_id=%d" % EFFECT_MEDITATION_ID)
		return
	_sprite = AnimatedSprite2D.new()
	_sprite.name = "MeditationSprite"
	_sprite.sprite_frames = sf
	_sprite.animation = "default"
	_sprite.centered = true
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# Apply the effect's offset (Fxs.ini OffsetX/Y, parser-doubled).
	var off: Vector2 = _entry_offset(entry)
	_sprite.position = off
	add_child(_sprite)
	_sprite.play("default")


func _load_effect_entry():
	# Indirected so tests can stub or override later if needed. SpriteCatalog
	# is the autoload — null-safe here for headless contexts that build a
	# bare MeditationAura without the full project loaded.
	if not Engine.has_singleton("SpriteCatalog") and SpriteCatalog == null:
		return null
	return SpriteCatalog.effect(EFFECT_MEDITATION_ID)


func _entry_offset(entry) -> Vector2:
	if not (entry is Dictionary):
		return Vector2.ZERO
	var raw = entry.get("offset", null)
	if not (raw is Dictionary):
		return Vector2.ZERO
	return Vector2(float(raw.get("x", 0)), float(raw.get("y", 0)))


func _init_fallback(reason: String) -> void:
	_using_fallback = true
	if not _warned_fallback:
		push_warning("[MeditationAura] using procedural fallback (%s)" % reason)
		_warned_fallback = true
	# _process + _draw drive the placeholder — see below.
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	if not _using_fallback:
		# AnimatedSprite2D animates itself once .play() runs; we don't need
		# to drive frames manually. Skip the per-frame redraw too.
		set_process(false)
		return
	_phase = fposmod(_phase + delta * PULSE_HZ, 1.0)
	queue_redraw()


func _draw() -> void:
	if not _using_fallback:
		return
	# Sine wave from 0..1 across the cycle, mapped to ALPHA_MIN..ALPHA_MAX.
	var s = (sin(_phase * TAU) + 1.0) * 0.5
	var alpha = lerp(ALPHA_MIN, ALPHA_MAX, s)
	var color = Color(COLOR_RGB.r, COLOR_RGB.g, COLOR_RGB.b, alpha)
	draw_circle(Vector2.ZERO, RADIUS, color)
	# Subtle outer ring at constant low alpha gives the aura a defined edge.
	var ring_color = Color(COLOR_RGB.r, COLOR_RGB.g, COLOR_RGB.b, ALPHA_MIN * 0.6)
	draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 32, ring_color, 2.0, true)


# --- Test introspection -----------------------------------------------------

func is_using_fallback() -> bool:
	return _using_fallback
