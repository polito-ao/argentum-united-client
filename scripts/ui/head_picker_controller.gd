class_name HeadPickerController
extends RefCounted

## Head-picker logic for character creation. Wraps the prev/next index
## navigation, the HEAD_OPTIONS request/response round-trip, and the live
## sprite-preview update.
##
## Pure logic + Control widget refs — no scene tree dependency, fully
## testable headless. Construct in setup() per the controller-lifecycle
## memory: we need `connection` to send packets.
##
## Responsibilities:
##   - On race change: send HEAD_OPTIONS_REQUEST(race), show "Loading..."
##   - On HEAD_OPTIONS_RESPONSE: cache list, default to index 0, refresh preview
##   - prev() / next() / pick_random(): update index (wrap-around) + preview
##   - selected_head_id(): payload value for CHARACTER_CREATE
##
## Defensive fallbacks:
##   - Response never arrives or empty → fall back to a single hardcoded
##     default head_id per race; picker UI stays visible but arrows no-op.
##   - Sprite catalog missing the head → preview hides gracefully.

const PacketIds = preload("res://scripts/network/packet_ids.gd")

# Wrap-around vs clamp: we picked WRAP. With small lists (~10-20 heads) it
# matches Cucsi's UX expectations and avoids dead-end button clicks.
const WRAP_AROUND := true

# Fallback head_id used when:
#   - HEAD_OPTIONS_RESPONSE never arrives (PR landed client-only)
#   - Server returns an empty list
# Head 1 always exists in the parsed Cucsi catalog.
const FALLBACK_HEAD_ID := 1

# Body used for the preview composite. Server is the source of truth for the
# in-world body at spawn time; the picker just needs *a* body to anchor the
# head_offset so it looks roughly right. Body 1 is the universal humanoid
# fallback in the parsed catalog.
const PREVIEW_BODY_ID := 1

var _connection
var _body_sprite: Sprite2D
var _head_sprite: Sprite2D
var _label: Label
var _prev_button: Button
var _next_button: Button
var _container: Control            # whole picker section, hidden until ready
var _loading_label: Label          # shown while waiting for the response

var _race: String = ""
var _head_ids: Array = []          # ints
var _index: int = 0


func _init(refs: Dictionary) -> void:
	_connection    = refs.get("connection", null)
	_body_sprite   = refs.get("body_sprite", null)
	_head_sprite   = refs.get("head_sprite", null)
	_label         = refs.get("label", null)
	_prev_button   = refs.get("prev_button", null)
	_next_button   = refs.get("next_button", null)
	_container     = refs.get("container", null)
	_loading_label = refs.get("loading_label", null)

	if _connection == null:
		push_error("HeadPickerController: null connection — wiring bug")

	if _prev_button != null:
		_prev_button.pressed.connect(prev)
	if _next_button != null:
		_next_button.pressed.connect(next)


# Set the race the picker is selecting heads for. Sends HEAD_OPTIONS_REQUEST
# and shows the "Loading..." state until the response arrives. Calling with
# the same race is a no-op so we don't spam the server on tab refocus.
func set_race(race: String) -> void:
	if race == _race and not _head_ids.is_empty():
		return
	_race = race
	_head_ids = []
	_index = 0
	_show_loading()
	if _connection != null and not race.is_empty():
		_connection.send_packet(PacketIds.HEAD_OPTIONS_REQUEST, {"race": race})


# Apply a HEAD_OPTIONS_RESPONSE payload: { race, head_ids: [Int, ...] }.
# Drops responses for a race the user has already moved away from (race
# selector can flip faster than the network round-trip).
func handle_options_response(payload: Dictionary) -> void:
	var resp_race: String = String(payload.get("race", ""))
	if resp_race != _race:
		return
	var ids = payload.get("head_ids", [])
	if not (ids is Array):
		ids = []
	# Coerce to ints (msgpack may yield mixed types when the server is
	# generous; the catalog lookups below need ints).
	_head_ids = []
	for v in ids:
		_head_ids.append(int(v))
	_index = 0
	_refresh_view()


# Returns the currently-selected head_id. Falls back to FALLBACK_HEAD_ID if
# the list is empty (response missing or in-flight) so CHARACTER_CREATE
# always has something to send.
func selected_head_id() -> int:
	if _head_ids.is_empty():
		return FALLBACK_HEAD_ID
	return int(_head_ids[_index])


func prev() -> void:
	if _head_ids.size() < 2:
		return
	if WRAP_AROUND:
		_index = (_index - 1 + _head_ids.size()) % _head_ids.size()
	else:
		_index = max(0, _index - 1)
	_refresh_view()


func next() -> void:
	if _head_ids.size() < 2:
		return
	if WRAP_AROUND:
		_index = (_index + 1) % _head_ids.size()
	else:
		_index = min(_head_ids.size() - 1, _index + 1)
	_refresh_view()


func pick_random() -> void:
	if _head_ids.size() < 2:
		return
	# Avoid landing on the same index for instant feedback.
	var new_idx := _index
	while new_idx == _index:
		new_idx = randi_range(0, _head_ids.size() - 1)
	_index = new_idx
	_refresh_view()


func current_index() -> int:
	return _index


func head_ids() -> Array:
	return _head_ids.duplicate()


# --- private ----------------------------------------------------------------


func _show_loading() -> void:
	if _container != null:
		_container.visible = true
	if _loading_label != null:
		_loading_label.visible = true
		_loading_label.text = "Loading heads..."
	if _label != null:
		_label.text = ""
	if _body_sprite != null:
		_body_sprite.visible = false
	if _head_sprite != null:
		_head_sprite.visible = false


func _refresh_view() -> void:
	if _container != null:
		_container.visible = true
	if _loading_label != null:
		_loading_label.visible = false

	if _head_ids.is_empty():
		# Fallback path: server returned nothing useful. Keep the section
		# rendered with the hardcoded default so the layout doesn't jump,
		# but skip the counter label.
		if _label != null:
			_label.text = "Cabeza %d" % FALLBACK_HEAD_ID
		_paint_preview(FALLBACK_HEAD_ID)
		return

	var head_id := int(_head_ids[_index])
	if _label != null:
		_label.text = "Cabeza %d / %d" % [_index + 1, _head_ids.size()]
	_paint_preview(head_id)


func _paint_preview(head_id: int) -> void:
	# Body (anchor for head_offset). Server is the actual source of truth
	# for in-world body at spawn time; preview anchors on body 1 which is
	# guaranteed to exist in the parsed Cucsi catalog.
	var body_tex: Texture2D = _frame_texture(SpriteFramesBuilder.for_body(PREVIEW_BODY_ID))
	var head_tex: Texture2D = _frame_texture(SpriteFramesBuilder.for_head(head_id))

	# Anchor body bottom-aligned at the BodySprite's authored position
	# (set in the .tscn to ~feet of the preview area). The body texture is
	# uncentered; offset.y = -h aligns its bottom to the anchor and
	# offset.x = -w/2 horizontally centers it.
	if _body_sprite != null:
		_body_sprite.texture = body_tex
		_body_sprite.visible = body_tex != null
		if body_tex != null:
			var bsz := body_tex.get_size()
			_body_sprite.offset = Vector2(-bsz.x / 2.0, -bsz.y)

	# Head sits at body anchor + head_offset, then gets centered/raised by
	# its own offset just like the body so the sprite hugs the right spot.
	if _head_sprite != null:
		_head_sprite.texture = head_tex
		_head_sprite.visible = head_tex != null
		if head_tex != null and _body_sprite != null:
			var hsz := head_tex.get_size()
			_head_sprite.position = _body_sprite.position + _head_offset_for_body(PREVIEW_BODY_ID)
			_head_sprite.offset = Vector2(-hsz.x / 2.0, -hsz.y)


# Pull the south-facing first frame as a static preview texture.
func _frame_texture(sf: SpriteFrames) -> Texture2D:
	if sf == null:
		return null
	if not sf.has_animation("walk_south"):
		return null
	if sf.get_frame_count("walk_south") <= 0:
		return null
	return sf.get_frame_texture("walk_south", 0)


func _head_offset_for_body(body_id: int) -> Vector2:
	var entry = SpriteCatalog.body(body_id)
	if entry == null or not (entry is Dictionary):
		return Vector2.ZERO
	var off = entry.get("head_offset", {"x": 0, "y": 0})
	return Vector2(float(off.get("x", 0)), float(off.get("y", 0)))
