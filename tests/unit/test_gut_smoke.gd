extends GutTest
## Sanity test — verifies GUT loads, runs, and asserts.
## If this passes, the test infrastructure is wired correctly.

func test_gut_is_alive():
	assert_eq(2 + 2, 4, "math still works")

func test_string_assertion():
	assert_string_contains("ullathorpe", "horp")
