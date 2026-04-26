class_name CharacterCard
extends PanelContainer

## FIFA-style character card. Shows name + class/race header, big OVR-like
## rating, the four attrs (INT/CON/AGI/STR) in two columns (Base | +Dice),
## and a portrait placeholder on the right.
##
## Used in two places:
##   1. The character-select list (one card per existing character, click
##      to select). For existing characters the server doesn't currently
##      ship dice_roll on Character#to_summary, so dice column is +0
##      until that lands -- see PR body / RaceBaseAttrs comment.
##   2. The live creation preview -- updates as the user picks class/race/
##      throw and types a name.
##
## Construct with .new() then call set_data(...) once or many times.

signal pressed(payload: Dictionary)

const RaceBaseAttrsScript = preload("res://scripts/ui/race_base_attrs.gd")

# Card sizing -- keeps three cards comfortably stacked in the panel.
const CARD_MIN_SIZE := Vector2(480, 180)
const PORTRAIT_SIZE := Vector2(120, 160)

# Tier accent colors (FIFA flourish -- gold/silver/bronze).
const TIER_GOLD_THRESHOLD := 70
const TIER_SILVER_THRESHOLD := 50
const TIER_GOLD := Color(0.86, 0.71, 0.20, 1.0)
const TIER_SILVER := Color(0.74, 0.76, 0.80, 1.0)
const TIER_BRONZE := Color(0.66, 0.42, 0.22, 1.0)

# Class accent colors used as portrait placeholder background. Soft, just
# enough to differentiate the seven classes visually until real portraits
# land. TODO: portrait. Drop a TextureRect with class portrait art here
# once it ships.
const CLASS_COLORS := {
	"mago":     Color(0.30, 0.20, 0.55, 1.0),
	"bardo":    Color(0.55, 0.35, 0.20, 1.0),
	"clerigo":  Color(0.85, 0.78, 0.55, 1.0),
	"paladin":  Color(0.70, 0.65, 0.30, 1.0),
	"asesino":  Color(0.20, 0.20, 0.20, 1.0),
	"cazador":  Color(0.25, 0.45, 0.25, 1.0),
	"guerrero": Color(0.55, 0.20, 0.20, 1.0),
}
const CLASS_COLOR_FALLBACK := Color(0.35, 0.35, 0.35, 1.0)

# Internal payload re-emitted on the pressed signal.
var _payload: Dictionary = {}

# Built once in _init, mutated on subsequent set_data() calls.
var _name_label: Label
var _subtitle_label: Label
var _rating_label: Label
var _portrait_rect: ColorRect
var _portrait_class_label: Label
var _attr_rows: Dictionary = {}


func _init() -> void:
	custom_minimum_size = CARD_MIN_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_layout()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and not mb.double_click:
			pressed.emit(_payload)


# --- public API -------------------------------------------------------------


func set_data(data: Dictionary) -> void:
	_payload = data.get("payload", {})

	var char_name: String = String(data.get("name", "?"))
	var class_slug: String = String(data.get("class", ""))
	var race_slug: String = String(data.get("race", ""))
	var level: int = int(data.get("level", 1))
	var show_level: bool = bool(data.get("show_level", true))
	var dice: Dictionary = data.get("dice_roll", {})

	var base := RaceBaseAttrsScript.for_race(race_slug)
	var effective := RaceBaseAttrsScript.combine(base, dice)
	var ovr := RaceBaseAttrsScript.rating(effective)

	_name_label.text = char_name if not char_name.is_empty() else "?"
	var subtitle_parts: Array = []
	if not class_slug.is_empty():
		subtitle_parts.append(class_slug.capitalize())
	if not race_slug.is_empty():
		subtitle_parts.append(race_slug.capitalize())
	if show_level:
		subtitle_parts.append("Lv %d" % level)
	_subtitle_label.text = "  -  ".join(subtitle_parts)

	_rating_label.text = str(ovr)
	_rating_label.add_theme_color_override("font_color", _tier_color(ovr))

	for key in ["int", "con", "agi", "str"]:
		var row = _attr_rows[key]
		row.base.text = str(int(base.get(key, 0)))
		var d := int(dice.get(key, 0))
		if d > 0:
			row.dice.text = "+%d" % d
		else:
			row.dice.text = "+0"
		var dim: Color
		if d == 0:
			dim = Color(0.65, 0.65, 0.65)
		else:
			dim = Color(0.35, 0.85, 0.35)
		row.dice.add_theme_color_override("font_color", dim)

	# Portrait -- TODO: portrait. Drop a TextureRect with real class art
	# once it exists. For now ColorRect + class label.
	_portrait_rect.color = CLASS_COLORS.get(class_slug, CLASS_COLOR_FALLBACK)
	if class_slug.is_empty():
		_portrait_class_label.text = "?"
	else:
		_portrait_class_label.text = class_slug.capitalize()

	_apply_tier_border(ovr)


# --- layout -----------------------------------------------------------------


func _build_layout() -> void:
	var stylebox := StyleBoxFlat.new()
	stylebox.bg_color = Color(0.10, 0.10, 0.13, 0.95)
	stylebox.set_corner_radius_all(8)
	stylebox.set_border_width_all(2)
	stylebox.border_color = TIER_BRONZE
	stylebox.content_margin_left = 12
	stylebox.content_margin_right = 12
	stylebox.content_margin_top = 10
	stylebox.content_margin_bottom = 10
	add_theme_stylebox_override("panel", stylebox)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	add_child(hbox)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 6)
	hbox.add_child(left)

	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 24)
	_name_label.text = "?"
	left.add_child(_name_label)

	_subtitle_label = Label.new()
	_subtitle_label.add_theme_font_size_override("font_size", 14)
	_subtitle_label.add_theme_color_override("font_color", Color(0.78, 0.74, 0.55))
	_subtitle_label.text = ""
	left.add_child(_subtitle_label)

	var mid := HBoxContainer.new()
	mid.add_theme_constant_override("separation", 16)
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(mid)

	_rating_label = Label.new()
	_rating_label.text = "?"
	_rating_label.add_theme_font_size_override("font_size", 56)
	_rating_label.custom_minimum_size = Vector2(80, 0)
	_rating_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rating_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mid.add_child(_rating_label)

	var stat_grid := GridContainer.new()
	stat_grid.columns = 3
	stat_grid.add_theme_constant_override("h_separation", 10)
	stat_grid.add_theme_constant_override("v_separation", 4)
	stat_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_child(stat_grid)

	for key in ["int", "con", "agi", "str"]:
		var key_label := Label.new()
		key_label.text = key.to_upper()
		key_label.add_theme_font_size_override("font_size", 14)
		key_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
		stat_grid.add_child(key_label)

		var base_label := Label.new()
		base_label.text = "?"
		base_label.add_theme_font_size_override("font_size", 16)
		base_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		base_label.custom_minimum_size = Vector2(36, 0)
		stat_grid.add_child(base_label)

		var dice_label := Label.new()
		dice_label.text = "+0"
		dice_label.add_theme_font_size_override("font_size", 14)
		dice_label.custom_minimum_size = Vector2(36, 0)
		stat_grid.add_child(dice_label)

		_attr_rows[key] = {"base": base_label, "dice": dice_label}

	# Right column: portrait placeholder. TODO: portrait
	var portrait_box := Control.new()
	portrait_box.custom_minimum_size = PORTRAIT_SIZE
	portrait_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(portrait_box)

	_portrait_rect = ColorRect.new()
	_portrait_rect.color = CLASS_COLOR_FALLBACK
	_portrait_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_portrait_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_box.add_child(_portrait_rect)

	_portrait_class_label = Label.new()
	_portrait_class_label.text = "?"
	_portrait_class_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_portrait_class_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_portrait_class_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_portrait_class_label.add_theme_font_size_override("font_size", 14)
	_portrait_class_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_portrait_class_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_portrait_class_label.add_theme_constant_override("outline_size", 4)
	_portrait_class_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_box.add_child(_portrait_class_label)


func _tier_color(ovr: int) -> Color:
	if ovr >= TIER_GOLD_THRESHOLD:
		return TIER_GOLD
	if ovr >= TIER_SILVER_THRESHOLD:
		return TIER_SILVER
	return TIER_BRONZE


func _apply_tier_border(ovr: int) -> void:
	var sb := get_theme_stylebox("panel") as StyleBoxFlat
	if sb == null:
		return
	sb.border_color = _tier_color(ovr)
