extends GutTest
## Boundary tests for the day/night helper used by character_select to pick
## which background painting to load. Pure-function test -- no scene tree.

const CharacterSelectScript = preload("res://scenes/character/character_select.gd")


func test_18_59_is_day():
	assert_false(CharacterSelectScript._is_night(18, 59), "18:59 should be day")


func test_19_00_is_night():
	assert_true(CharacterSelectScript._is_night(19, 0), "19:00 should be night")


func test_19_30_is_night():
	assert_true(CharacterSelectScript._is_night(19, 30), "19:30 should be night")


func test_04_59_is_night():
	assert_true(CharacterSelectScript._is_night(4, 59), "04:59 should be night")


func test_05_00_is_night():
	assert_true(CharacterSelectScript._is_night(5, 0), "05:00 should be night")


func test_05_29_is_night():
	assert_true(CharacterSelectScript._is_night(5, 29), "05:29 should be night")


func test_05_30_is_day():
	assert_false(CharacterSelectScript._is_night(5, 30), "05:30 should be day")


func test_06_00_is_day():
	assert_false(CharacterSelectScript._is_night(6, 0), "06:00 should be day")


func test_12_00_is_day():
	assert_false(CharacterSelectScript._is_night(12, 0), "12:00 should be day")


func test_midnight_is_night():
	# Smoke check at 00:00 -- night extends through midnight to 05:30.
	assert_true(CharacterSelectScript._is_night(0, 0), "00:00 should be night")


func test_23_59_is_night():
	assert_true(CharacterSelectScript._is_night(23, 59), "23:59 should be night")
