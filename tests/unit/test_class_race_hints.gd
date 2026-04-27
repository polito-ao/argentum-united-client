extends GutTest
## Unit tests for ClassRaceHints -- the 5x7 = 35-cell playstyle-hint matrix
## that drives the FIFA card footer. Pinned because UI copy regression is
## hard to spot visually with five races and seven classes (35 combos),
## and the card silently hides the label on empty strings, masking bugs.

const ClassRaceHintsScript = preload("res://scripts/ui/class_race_hints.gd")


func test_every_class_race_combo_has_a_hint():
	var missing := []
	for class_slug in ClassRaceHintsScript.CLASS_SLUGS:
		for race_slug in ClassRaceHintsScript.RACE_SLUGS:
			var hint = ClassRaceHintsScript.hint_for(class_slug, race_slug)
			if hint.is_empty():
				missing.append("%s+%s" % [class_slug, race_slug])
	assert_eq(missing.size(), 0,
		"missing hints: %s" % ", ".join(missing))

func test_full_matrix_is_thirty_five_cells():
	# 5 races x 7 classes = 35. Sanity-check no one slipped a class or
	# race in without a corresponding hint row.
	assert_eq(ClassRaceHintsScript.CLASS_SLUGS.size(), 7)
	assert_eq(ClassRaceHintsScript.RACE_SLUGS.size(), 5)
	assert_eq(ClassRaceHintsScript.HINTS.size(), 35)

func test_each_hint_under_eighty_chars_for_one_line_layout():
	# 80-char soft target. The card footer label has autowrap, so longer
	# is technically fine, but stretching past 80 starts wrapping into
	# two lines and breaks the FIFA-card vibe.
	for key in ClassRaceHintsScript.HINTS:
		var hint: String = ClassRaceHintsScript.HINTS[key]
		assert_true(hint.length() <= 80,
			"hint for %s is %d chars: %s" % [key, hint.length(), hint])

func test_unknown_class_returns_empty_string():
	assert_eq(ClassRaceHintsScript.hint_for("nigromante", "humano"), "")

func test_unknown_race_returns_empty_string():
	assert_eq(ClassRaceHintsScript.hint_for("mago", "trasgo"), "")

func test_empty_class_or_race_returns_empty_string():
	# Mirrors the "no class picked yet" state in the create-character
	# preview card.
	assert_eq(ClassRaceHintsScript.hint_for("", "humano"), "")
	assert_eq(ClassRaceHintsScript.hint_for("mago", ""), "")
	assert_eq(ClassRaceHintsScript.hint_for("", ""), "")

func test_signature_combos_have_expected_phrasing():
	# Spot-check a few flagship combos so a copy edit doesn't quietly
	# drift them off-tone.
	assert_string_contains(
		ClassRaceHintsScript.hint_for("mago", "gnomo"),
		"Glass cannon"
	)
	assert_string_contains(
		ClassRaceHintsScript.hint_for("guerrero", "orco"),
		"Frontline"
	)
	assert_string_contains(
		ClassRaceHintsScript.hint_for("cazador", "elfo"),
		"ranger"
	)
