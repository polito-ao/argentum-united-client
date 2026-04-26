extends GutTest
## Unit tests for CharacterCreateToggle. Exercises the visibility state
## machine using raw Controls -- no scene tree, no pixels.

const CharacterCreateToggleScript = preload("res://scripts/ui/character_create_toggle.gd")

var toggle: CharacterCreateToggle
var create_panel: Control
var preview_panel: Control
var new_button: Button
var cancel_button: Button


func before_each():
	create_panel = Control.new()
	preview_panel = Control.new()
	new_button = Button.new()
	cancel_button = Button.new()
	add_child_autofree(create_panel)
	add_child_autofree(preview_panel)
	add_child_autofree(new_button)
	add_child_autofree(cancel_button)

	toggle = CharacterCreateToggleScript.new({
		create_panel  = create_panel,
		preview_panel = preview_panel,
		new_button    = new_button,
		cancel_button = cancel_button,
	})


# --- initial state -----------------------------------------------------------

func test_starts_with_form_hidden():
	assert_false(create_panel.visible, "create form should start hidden")
	assert_false(preview_panel.visible, "preview should start hidden")
	assert_true(new_button.visible, "new-character button should start visible")
	assert_false(toggle.is_open())


# --- show() opens the form ---------------------------------------------------

func test_show_reveals_form_and_preview():
	toggle.show()
	assert_true(create_panel.visible)
	assert_true(preview_panel.visible)
	assert_false(new_button.visible, "new-character button hides while form is open")
	assert_true(toggle.is_open())

func test_show_via_new_button_press():
	new_button.pressed.emit()
	assert_true(create_panel.visible)
	assert_true(toggle.is_open())


# --- cancel() returns to list view ------------------------------------------

func test_cancel_hides_form_and_preview():
	toggle.show()
	toggle.cancel()
	assert_false(create_panel.visible)
	assert_false(preview_panel.visible)
	assert_true(new_button.visible)
	assert_false(toggle.is_open())

func test_cancel_via_button_press():
	toggle.show()
	cancel_button.pressed.emit()
	assert_false(create_panel.visible)
	assert_false(toggle.is_open())


# --- slot cap ---------------------------------------------------------------

func test_set_can_create_false_hides_new_button():
	toggle.set_can_create(false)
	assert_false(new_button.visible, "at slot cap, new-button hides entirely")

func test_show_is_noop_when_cannot_create():
	toggle.set_can_create(false)
	toggle.show()
	assert_false(create_panel.visible, "show() must not open the form at the cap")
	assert_false(toggle.is_open())

func test_set_can_create_false_force_closes_open_form():
	toggle.show()
	toggle.set_can_create(false)
	assert_false(create_panel.visible, "hitting the cap mid-creation closes the form")
	assert_false(new_button.visible)

func test_set_can_create_true_restores_new_button():
	toggle.set_can_create(false)
	toggle.set_can_create(true)
	assert_true(new_button.visible)


# --- repeated show/cancel are idempotent ------------------------------------

func test_show_twice_keeps_form_open():
	toggle.show()
	toggle.show()
	assert_true(create_panel.visible)

func test_cancel_twice_keeps_form_closed():
	toggle.cancel()
	toggle.cancel()
	assert_false(create_panel.visible)
	assert_true(new_button.visible)
