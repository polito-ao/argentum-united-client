extends GutTest
## Unit tests for RaceBaseAttrs -- the static race-base table + FIFA "OVR"
## rating formula. Pinned because the formula is deliberately reviewable
## and we want a loud failure if someone changes it without a teammate
## seeing the spec break.

const RaceBaseAttrsScript = preload("res://scripts/ui/race_base_attrs.gd")


# --- table lookup -----------------------------------------------------------

func test_humano_balanced_50_across_the_board():
	var attrs = RaceBaseAttrsScript.for_race("humano")
	assert_eq(attrs.get("int"), 50)
	assert_eq(attrs.get("con"), 50)
	assert_eq(attrs.get("agi"), 50)
	assert_eq(attrs.get("str"), 50)

func test_gnomo_int_agi_high_con_str_low():
	var attrs = RaceBaseAttrsScript.for_race("gnomo")
	assert_eq(attrs.get("int"), 92)
	assert_eq(attrs.get("agi"), 92)
	assert_eq(attrs.get("con"), 12)
	assert_eq(attrs.get("str"), 12)

func test_orco_str_con_high_int_agi_low():
	var attrs = RaceBaseAttrsScript.for_race("orco")
	assert_eq(attrs.get("str"), 92)
	assert_eq(attrs.get("con"), 92)
	assert_eq(attrs.get("int"), 12)
	assert_eq(attrs.get("agi"), 12)

func test_unknown_race_falls_back_to_balanced():
	var attrs = RaceBaseAttrsScript.for_race("unknown_race")
	assert_eq(attrs.get("int"), 50)
	assert_eq(attrs.get("con"), 50)
	assert_eq(attrs.get("agi"), 50)
	assert_eq(attrs.get("str"), 50)

func test_for_race_returns_a_copy_not_table_reference():
	# Mutating the returned dict should not poison subsequent calls.
	var first = RaceBaseAttrsScript.for_race("humano")
	first["int"] = 999
	var second = RaceBaseAttrsScript.for_race("humano")
	assert_eq(second.get("int"), 50)


# --- rating formula ---------------------------------------------------------

func test_rating_humano_balanced():
	# (50+50+50+50)/4 = 50
	assert_eq(RaceBaseAttrsScript.rating({"int": 50, "con": 50, "agi": 50, "str": 50}), 50)

func test_rating_orco_max_strength_build():
	# (12+92+12+92)/4 = 52
	assert_eq(RaceBaseAttrsScript.rating({"int": 12, "con": 92, "agi": 12, "str": 92}), 52)

func test_rating_floors_decimal_division():
	# (51+50+50+50)/4 = 50.25 -> 50
	assert_eq(RaceBaseAttrsScript.rating({"int": 51, "con": 50, "agi": 50, "str": 50}), 50)

func test_rating_with_dice_bonus_via_combine():
	var base = RaceBaseAttrsScript.for_race("humano")
	var dice = {"int": 3, "con": 2, "agi": 0, "str": 5}
	var effective = RaceBaseAttrsScript.combine(base, dice)
	# (53+52+50+55)/4 = 52.5 -> 52
	assert_eq(RaceBaseAttrsScript.rating(effective), 52)

func test_rating_handles_missing_keys_as_zero():
	assert_eq(RaceBaseAttrsScript.rating({}), 0)
	assert_eq(RaceBaseAttrsScript.rating({"int": 100}), 25)

func test_combine_treats_missing_dice_keys_as_zero():
	var base = {"int": 50, "con": 50, "agi": 50, "str": 50}
	var dice = {"int": 4} # missing the rest
	var effective = RaceBaseAttrsScript.combine(base, dice)
	assert_eq(effective.get("int"), 54)
	assert_eq(effective.get("con"), 50)
	assert_eq(effective.get("agi"), 50)
	assert_eq(effective.get("str"), 50)
