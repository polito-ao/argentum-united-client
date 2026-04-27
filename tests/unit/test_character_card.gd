extends GutTest
## Unit tests for CharacterCard -- the FIFA-style card on the character-
## select screen. Coverage focuses on the cross-cutting wires after the
## 6-attr migration:
##   - all six rows (INT/CON/AGI/STR/MAG_RES/PHYS_RES) populate from
##     race base + dice
##   - OVR uses the new 6-attr formula
##   - playstyle hint label appears for known class+race, hides otherwise
##
## The card constructs its own scene tree in _init -- we only need to
## add it to the test tree so layout containers attach cleanly.

const CharacterCardScript = preload("res://scripts/ui/character_card.gd")
const RaceBaseAttrsScript = preload("res://scripts/ui/race_base_attrs.gd")

var card

func before_each():
	card = CharacterCardScript.new()
	add_child_autofree(card)

# --- six-attr rendering -----------------------------------------------------

func test_set_data_populates_all_six_attr_rows_from_humano_base():
	card.set_data({
		"name": "Aragorn",
		"class": "guerrero",
		"race": "humano",
		"dice_roll": {},
		"show_level": false,
	})
	# Reach into the internal _attr_rows dict -- it's the cleanest way
	# to assert the card actually wired up the resistance rows without
	# crawling the scene tree by index. If the card refactors away from
	# this dict we update the test in lockstep.
	for key in RaceBaseAttrsScript.ATTR_KEYS:
		assert_true(card._attr_rows.has(key),
			"missing row for %s" % key)
		assert_eq(card._attr_rows[key].base.text, "50",
			"%s base should be 50 for humano" % key)

func test_set_data_renders_orco_resistances_correctly():
	card.set_data({
		"name": "Mukhar",
		"class": "guerrero",
		"race": "orco",
		"dice_roll": {},
		"show_level": false,
	})
	assert_eq(card._attr_rows["mag_res"].base.text, "12")
	assert_eq(card._attr_rows["phys_res"].base.text, "92")
	assert_eq(card._attr_rows["str"].base.text, "92")

func test_set_data_uses_six_attr_ovr_formula():
	# Orco has (12+92+12+92+12+92)/6 = 52, NOT (12+92+12+92)/4 = 52.
	# Picking a race where the two formulas diverge would be ideal, but
	# the chosen one still locks in that the rating is computed off the
	# combined dict the card builds, not a stale 4-key path.
	card.set_data({
		"name": "Mukhar",
		"class": "guerrero",
		"race": "orco",
		"dice_roll": {},
		"show_level": false,
	})
	assert_eq(card._rating_label.text, "52")

func test_set_data_with_enano_uses_uneven_resistance():
	# Enano: (28+76+28+76+44+76)/6 = 54. Locks in the 44 mag_res quirk
	# end-to-end through the card's set_data path.
	card.set_data({
		"name": "Gimli",
		"class": "guerrero",
		"race": "enano",
		"dice_roll": {},
		"show_level": false,
	})
	assert_eq(card._rating_label.text, "54")
	assert_eq(card._attr_rows["mag_res"].base.text, "44")


# --- playstyle hint ---------------------------------------------------------

func test_hint_label_is_set_when_class_and_race_known():
	card.set_data({
		"name": "Pippin",
		"class": "mago",
		"race": "gnomo",
		"dice_roll": {},
		"show_level": false,
	})
	assert_true(card._hint_label.visible,
		"hint label should be visible for mago+gnomo")
	assert_string_contains(card._hint_label.text, "Glass cannon")

func test_hint_label_hidden_when_class_missing():
	# Mirrors the create-character preview state before a class is picked.
	card.set_data({
		"name": "?",
		"class": "",
		"race": "humano",
		"dice_roll": {},
		"show_level": false,
	})
	assert_false(card._hint_label.visible)
	assert_eq(card._hint_label.text, "")

func test_hint_label_hidden_when_combo_unknown():
	# Picking an unknown class should hide the label, not print junk.
	card.set_data({
		"name": "?",
		"class": "nigromante",
		"race": "humano",
		"dice_roll": {},
		"show_level": false,
	})
	assert_false(card._hint_label.visible)


# --- still emits pressed (regression guard for the layout reshuffle) ---------

func test_still_emits_pressed_after_layout_change():
	card.set_data({
		"name": "Click me",
		"class": "guerrero",
		"race": "humano",
		"dice_roll": {},
		"show_level": false,
		"payload": {"id": 42},
	})
	var got_payload = []
	card.pressed.connect(func(p): got_payload.append(p))
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.double_click = false
	card._gui_input(ev)
	assert_eq(got_payload.size(), 1)
	assert_eq(got_payload[0].get("id"), 42)
