class_name MeditationAura extends Node2D
## Placeholder visual for the meditation effect (effect_id = 1).
##
## Real Cucsi `Meditando.ind` sprites are out of scope this round; they'll
## come in a future "effects catalog" PR. Until then this draws a yellow/gold
## semi-transparent circle that pulses its alpha on a sine wave — enough for
## the human's visual verification pass once both server + client land.
##
## Anchored at (0, tile_size/2) so it sits centered behind the character's
## feet, regardless of body height. The drawing is via _draw() against the
## node's local origin; movement is the parent LayeredCharacter's job.

const RADIUS := 32.0
const PULSE_HZ := 1.0          # one full sine cycle per second
const ALPHA_MIN := 0.18
const ALPHA_MAX := 0.55
const COLOR_RGB := Color(1.0, 0.85, 0.2)  # gold

var _phase: float = 0.0


func _ready() -> void:
	# z_index defaults to 0 here — the parent (LayeredCharacter) sets ours
	# to Z_EFFECT (-1) so we render BELOW the body. Repeat the assignment
	# defensively in case this node is mounted elsewhere.
	z_index = -1


func _process(delta: float) -> void:
	_phase = fposmod(_phase + delta * PULSE_HZ, 1.0)
	queue_redraw()


func _draw() -> void:
	# Sine wave from 0..1 across the cycle, mapped to ALPHA_MIN..ALPHA_MAX.
	var s = (sin(_phase * TAU) + 1.0) * 0.5
	var alpha = lerp(ALPHA_MIN, ALPHA_MAX, s)
	var color = Color(COLOR_RGB.r, COLOR_RGB.g, COLOR_RGB.b, alpha)
	draw_circle(Vector2.ZERO, RADIUS, color)
	# Subtle outer ring at constant low alpha gives the aura a defined edge.
	var ring_color = Color(COLOR_RGB.r, COLOR_RGB.g, COLOR_RGB.b, ALPHA_MIN * 0.6)
	draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 32, ring_color, 2.0, true)
