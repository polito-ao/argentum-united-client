extends GutTest
## Unit tests for HUDController. Constructed with stub Controls so no scene
## tree is needed — the controller only ever reads/writes .text, .value,
## and .max_value, all of which work on plain instances.

var hud: HUDController
var refs: Dictionary

func before_each():
	refs = {
		hp_bar         = ProgressBar.new(),
		hp_text        = Label.new(),
		mp_bar         = ProgressBar.new(),
		mp_text        = Label.new(),
		xp_bar         = ProgressBar.new(),
		xp_label       = Label.new(),
		level_label    = Label.new(),
		name_label     = Label.new(),
		city_label     = Label.new(),
		str_label      = Label.new(),
		cele_label     = Label.new(),
		gold_label     = Label.new(),
		eq_helm        = Label.new(),
		eq_armor       = Label.new(),
		eq_weapon      = Label.new(),
		eq_shield      = Label.new(),
		eq_magres      = Label.new(),
		position_label = Label.new(),
		fps_label      = Label.new(),
	}
	hud = HUDController.new(refs)

func after_each():
	for ctrl in refs.values():
		ctrl.free()

# --- HP / MP / XP ---

func test_update_hp_sets_bar_and_text():
	hud.update_hp(75, 100)
	assert_eq(refs.hp_bar.max_value, 100.0)
	assert_eq(refs.hp_bar.value, 75.0)
	assert_eq(refs.hp_text.text, "75 / 100")

func test_update_hp_clamps_overflow():
	hud.update_hp(150, 100)
	assert_eq(refs.hp_bar.value, 100.0)

func test_update_hp_handles_zero_max():
	# max_hp 0 would crash a ProgressBar — controller should floor at 1.
	hud.update_hp(0, 0)
	assert_eq(refs.hp_bar.max_value, 1.0)

func test_update_mp_sets_bar_and_text():
	hud.update_mp(40, 200)
	assert_eq(refs.mp_bar.value, 40.0)
	assert_eq(refs.mp_text.text, "40 / 200")

func test_update_xp_with_curve():
	hud.update_xp(150, 500)
	assert_eq(refs.xp_bar.max_value, 500.0)
	assert_eq(refs.xp_bar.value, 150.0)
	assert_eq(refs.xp_label.text, "EXP 150 / 500")

func test_update_xp_without_curve_shows_only_xp():
	hud.update_xp(75, 0)
	assert_eq(refs.xp_bar.max_value, 1.0)
	assert_eq(refs.xp_bar.value, 0.0)
	assert_eq(refs.xp_label.text, "EXP 75")

# --- Header ---

func test_update_character_header_with_city():
	hud.update_character_header("Ullathorpe", 12, "Banderbill")
	assert_eq(refs.level_label.text, "12")
	assert_eq(refs.name_label.text, "Ullathorpe")
	assert_eq(refs.city_label.text, "<Banderbill>")

func test_update_character_header_no_city_falls_back():
	hud.update_character_header("Wanderer", 1, null)
	assert_eq(refs.city_label.text, "<SIN CIUDAD>")

func test_update_character_header_blank_name_falls_back():
	hud.update_character_header("", 1, "X")
	assert_eq(refs.name_label.text, "?")

func test_set_level_only_updates_level_label():
	refs.name_label.text = "untouched"
	hud.set_level(99)
	assert_eq(refs.level_label.text, "99")
	assert_eq(refs.name_label.text, "untouched")

# --- Stats / gold ---

func test_update_stats_writes_all_three_labels():
	hud.update_stats(18, 12, 1500)
	assert_eq(refs.str_label.text, "STR 18")
	assert_eq(refs.cele_label.text, "CELE 12")
	assert_eq(refs.gold_label.text, "$ 1.500")

func test_set_gold_formats_with_dot_separator():
	hud.set_gold(1091884)
	assert_eq(refs.gold_label.text, "$ 1.091.884")

func test_set_gold_zero():
	hud.set_gold(0)
	assert_eq(refs.gold_label.text, "$ 0")

func test_set_gold_under_thousand():
	hud.set_gold(42)
	assert_eq(refs.gold_label.text, "$ 42")

# --- Equipment ---

func test_update_equipment_pads_to_two_digits():
	hud.update_equipment({helmet = 3, armor = 17, weapon = 99, shield = 0, mag_res = 5})
	assert_eq(refs.eq_helm.text, "03")
	assert_eq(refs.eq_armor.text, "17")
	assert_eq(refs.eq_weapon.text, "99")
	assert_eq(refs.eq_shield.text, "00")
	assert_eq(refs.eq_magres.text, "05")

func test_update_equipment_missing_keys_default_to_zero():
	hud.update_equipment({})
	assert_eq(refs.eq_helm.text, "00")
	assert_eq(refs.eq_armor.text, "00")

# --- Status ---

func test_set_position_label_format():
	hud.set_position_label(7, 50, 75)
	assert_eq(refs.position_label.text, "Map 7 @ (50, 75)")

func test_set_fps_format():
	hud.set_fps(60)
	assert_eq(refs.fps_label.text, "FPS 60")

# --- Messages feed (delegated to chat sink) ---

class _StubChatSink extends RefCounted:
	var lines: Array = []
	func append_system(msg: String) -> void:
		lines.append(msg)

func test_add_message_forwards_to_chat_sink():
	var sink = _StubChatSink.new()
	hud.set_chat_sink(sink)
	hud.add_message("hello")
	assert_eq(sink.lines, ["hello"])

func test_add_message_buffers_until_sink_attached():
	# HUDController is built in world.gd's _ready(); chat in setup(). Any
	# message that arrives before set_chat_sink must flush in order once
	# the sink is wired.
	hud.add_message("early1")
	hud.add_message("early2")
	var sink = _StubChatSink.new()
	hud.set_chat_sink(sink)
	assert_eq(sink.lines, ["early1", "early2"])

func test_add_message_after_sink_attached_does_not_replay_buffer():
	var sink = _StubChatSink.new()
	hud.set_chat_sink(sink)
	hud.add_message("a")
	hud.add_message("b")
	assert_eq(sink.lines, ["a", "b"])
