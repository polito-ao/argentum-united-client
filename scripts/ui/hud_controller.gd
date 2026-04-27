extends RefCounted
class_name HUDController

## Read-update HUD widget controller. Owns the labels/bars/messages-feed
## that world.gd would otherwise touch directly. Constructed once in
## world.gd's _ready, fed already-resolved Control refs (so it stays
## testable — instantiate with stub Labels in tests, no scene tree
## required).
##
## What's NOT in here: interactive subsystems (chat input, inventory grid,
## settings overlay, drop dialog, buttons). Those have their own state
## machines and warrant separate controllers in later passes.
##
## `add_message(msg)` historically wrote to a floating yellow `MessagesLabel`
## mid-screen. That label is gone — the HUD now forwards to the chat
## console (set via `set_chat_sink`). System-line messages and broadcast
## chat share the same visual surface, distinguished by color.

var _hp_bar: ProgressBar
var _hp_text: Label
var _mp_bar: ProgressBar
var _mp_text: Label
var _xp_bar: ProgressBar
var _xp_label: Label
var _level_label: Label
var _name_label: Label
var _city_label: Label
var _str_label: Label
var _cele_label: Label
var _gold_label: Label
var _eq_helm: Label
var _eq_armor: Label
var _eq_weapon: Label
var _eq_shield: Label
var _eq_magres: Label
var _position_label: Label
var _fps_label: Label

# Chat sink for `add_message` forwarding. Set via `set_chat_sink` once the
# ChatController is built in world.gd's setup(). HUDController is built
# earlier in _ready(), so until the sink is wired we buffer messages and
# flush them on first `set_chat_sink`. In practice `add_message` is never
# called in that window today, but buffering keeps the API safe.
var _chat_sink = null
var _pending_messages: Array = []

func _init(refs: Dictionary) -> void:
	_hp_bar         = refs.hp_bar
	_hp_text        = refs.hp_text
	_mp_bar         = refs.mp_bar
	_mp_text        = refs.mp_text
	_xp_bar         = refs.xp_bar
	_xp_label       = refs.xp_label
	_level_label    = refs.level_label
	_name_label     = refs.name_label
	_city_label     = refs.city_label
	_str_label      = refs.str_label
	_cele_label     = refs.cele_label
	_gold_label     = refs.gold_label
	_eq_helm        = refs.eq_helm
	_eq_armor       = refs.eq_armor
	_eq_weapon      = refs.eq_weapon
	_eq_shield      = refs.eq_shield
	_eq_magres      = refs.eq_magres
	_position_label = refs.position_label
	_fps_label      = refs.fps_label

# --- HP / MP / XP bars ---

func update_hp(hp: int, max_hp: int) -> void:
	_hp_bar.max_value = max(max_hp, 1)
	_hp_bar.value = clamp(hp, 0, max_hp)
	_hp_text.text = "%d / %d" % [hp, max_hp]

# Read-back used by the inspect-tile feature to surface the player's own
# HP without world.gd having to mirror the value on a separate field.
func current_hp() -> int:
	return int(_hp_bar.value)

func current_max_hp() -> int:
	return int(_hp_bar.max_value)

func update_mp(mana: int, max_mana: int) -> void:
	_mp_bar.max_value = max(max_mana, 1)
	_mp_bar.value = clamp(mana, 0, max_mana)
	_mp_text.text = "%d / %d" % [mana, max_mana]

# Caller passes the threshold so the controller stays uncoupled from
# PacketIds / config sources. xp_for_level <= 0 means "no curve loaded yet".
func update_xp(xp_in_level: int, xp_for_level: int) -> void:
	if xp_for_level <= 0:
		_xp_bar.max_value = 1
		_xp_bar.value = 0
		_xp_label.text = "EXP %d" % xp_in_level
		return
	_xp_bar.max_value = xp_for_level
	_xp_bar.value = clamp(xp_in_level, 0, xp_for_level)
	_xp_label.text = "EXP %d / %d" % [xp_in_level, xp_for_level]

# --- Header (level / name / city) ---

func update_character_header(character_name: String, level: int, city: Variant) -> void:
	_level_label.text = str(level)
	_name_label.text = character_name if character_name else "?"
	_city_label.text = "<%s>" % city if city else "<SIN CIUDAD>"

func set_level(level: int) -> void:
	_level_label.text = str(level)

# --- Stats panel ---

func update_stats(strength: int, agility: int, gold: int) -> void:
	_str_label.text = "STR %d" % strength
	_cele_label.text = "CELE %d" % agility
	_gold_label.text = "$ %s" % _format_gold(gold)

func set_gold(gold: int) -> void:
	_gold_label.text = "$ %s" % _format_gold(gold)

# --- Equipment row ---

func update_equipment(eq: Dictionary) -> void:
	_eq_helm.text    = "%02d" % int(eq.get("helmet", 0))
	_eq_armor.text   = "%02d" % int(eq.get("armor", 0))
	_eq_weapon.text  = "%02d" % int(eq.get("weapon", 0))
	_eq_shield.text  = "%02d" % int(eq.get("shield", 0))
	_eq_magres.text  = "%02d" % int(eq.get("mag_res", 0))

# --- Status displays (position, FPS) ---

func set_position_label(map_id: int, x: int, y: int) -> void:
	_position_label.text = "Map %d @ (%d, %d)" % [map_id, x, y]

func set_fps(value: int) -> void:
	_fps_label.text = "FPS %d" % value

# --- System messages (delegated to chat console) ---

# Wire the chat sink. Anything that arrived via add_message before this
# call gets flushed in original order. Pass any object that responds to
# `append_system(String)` — typically a ChatController, but tests pass
# stubs.
func set_chat_sink(sink) -> void:
	_chat_sink = sink
	if _chat_sink == null:
		return
	for msg in _pending_messages:
		_chat_sink.append_system(msg)
	_pending_messages.clear()

func add_message(msg: String) -> void:
	if _chat_sink == null:
		_pending_messages.append(msg)
		return
	_chat_sink.append_system(msg)

# --- Helpers ---

# Thousands separator with dots (Argentum/Spanish style): 1.091.884
static func _format_gold(n: int) -> String:
	var s = str(n)
	var out := ""
	var count = 0
	for i in range(s.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			out = "." + out
		out = s[i] + out
		count += 1
	return out
