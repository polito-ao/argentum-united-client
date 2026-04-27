extends GutTest
## Unit tests for the full 6-attr race base table -- INT/CON/AGI/STR plus
## MAG_RES and PHYS_RES. Pinned because the FIFA card now drives its OVR
## off all six values, and a typo in the table would silently misrate
## every existing character's card on the select screen.
##
## Source of truth: server CLAUDE.md, Race attribute scale section.

const RaceBaseAttrsScript = preload("res://scripts/ui/race_base_attrs.gd")

const EXPECTED := {
	"gnomo":  {"int": 92, "con": 12, "agi": 92, "str": 12, "mag_res": 92, "phys_res": 12},
	"elfo":   {"int": 76, "con": 28, "agi": 76, "str": 28, "mag_res": 76, "phys_res": 28},
	"humano": {"int": 50, "con": 50, "agi": 50, "str": 50, "mag_res": 50, "phys_res": 50},
	"enano":  {"int": 28, "con": 76, "agi": 28, "str": 76, "mag_res": 44, "phys_res": 76},
	"orco":   {"int": 12, "con": 92, "agi": 12, "str": 92, "mag_res": 12, "phys_res": 92},
}


func test_every_race_has_all_six_keys():
	for race in EXPECTED.keys():
		var attrs = RaceBaseAttrsScript.for_race(race)
		for key in RaceBaseAttrsScript.ATTR_KEYS:
			assert_true(attrs.has(key),
				"%s missing key %s" % [race, key])

func test_every_race_has_expected_values():
	for race in EXPECTED.keys():
		var attrs = RaceBaseAttrsScript.for_race(race)
		var want = EXPECTED[race]
		for key in want.keys():
			assert_eq(attrs.get(key), want[key],
				"%s.%s should be %d" % [race, key, want[key]])

func test_enano_mag_res_is_intentionally_44():
	# The dwarf is durable in body but not warded -- canonical from the
	# server table. Pinning this so a "looks-like-a-typo" cleanup doesn't
	# silently flatten the race identity.
	var attrs = RaceBaseAttrsScript.for_race("enano")
	assert_eq(attrs.get("mag_res"), 44)
	assert_eq(attrs.get("phys_res"), 76)

func test_unknown_race_fallback_has_all_six_keys():
	var attrs = RaceBaseAttrsScript.for_race("not_a_real_race")
	for key in RaceBaseAttrsScript.ATTR_KEYS:
		assert_true(attrs.has(key))
		assert_eq(attrs.get(key), 50)


# --- 6-attr OVR formula -----------------------------------------------------

func test_humano_ovr_is_50_with_six_attrs():
	# (50*6)/6 = 50. New formula must still give the textbook humano its
	# baseline 50 OVR -- otherwise the gold/silver/bronze tier badge
	# changes meaning across the existing roster.
	var attrs = RaceBaseAttrsScript.for_race("humano")
	assert_eq(RaceBaseAttrsScript.rating(attrs), 50)

func test_gnomo_ovr_uses_all_six_attrs():
	# (92+12+92+12+92+12)/6 = 52
	var attrs = RaceBaseAttrsScript.for_race("gnomo")
	assert_eq(RaceBaseAttrsScript.rating(attrs), 52)

func test_orco_ovr_uses_all_six_attrs():
	# (12+92+12+92+12+92)/6 = 52
	var attrs = RaceBaseAttrsScript.for_race("orco")
	assert_eq(RaceBaseAttrsScript.rating(attrs), 52)

func test_enano_ovr_with_uneven_resistances():
	# (28+76+28+76+44+76)/6 = 54.66 -> 54. Locks in the specific knock-on
	# of enano's 44 mag_res so a future "round mag_res up to 50" tweak
	# loudly fails this spec rather than slipping through.
	var attrs = RaceBaseAttrsScript.for_race("enano")
	assert_eq(RaceBaseAttrsScript.rating(attrs), 54)

func test_combine_carries_all_six_keys():
	var base = RaceBaseAttrsScript.for_race("humano")
	var dice = {"int": 5, "str": 3} # only primary attrs come from dice today
	var effective = RaceBaseAttrsScript.combine(base, dice)
	assert_eq(effective.get("int"), 55)
	assert_eq(effective.get("con"), 50)
	assert_eq(effective.get("agi"), 50)
	assert_eq(effective.get("str"), 53)
	# Resistances pass through untouched -- no dice bonus on them yet.
	assert_eq(effective.get("mag_res"), 50)
	assert_eq(effective.get("phys_res"), 50)
