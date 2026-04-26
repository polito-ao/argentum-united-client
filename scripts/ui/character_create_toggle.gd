class_name CharacterCreateToggle
extends RefCounted

## Visibility-toggle controller for the character creation form.
##
## Today the create form sits next to the character list with ~12 visible
## form fields. This controller hides it behind a "+ Crear nuevo personaje"
## button. Cancel returns to the list view.
##
## Pure logic + Control widget refs -- no scene tree dependency, fully
## testable headless. Construct in setup() (matches controller-lifecycle
## rule for things that may need to call into the scene later).
##
## Inputs (all Control widgets, all required):
##   - create_panel    : the VBoxContainer that holds the form fields
##   - preview_panel   : the live-preview card container (hidden alongside
##                       the form so the panel layout doesn't carry a
##                       half-rendered preview when no creation is active)
##   - new_button      : the "+ Crear nuevo personaje" trigger
##   - cancel_button   : the "Cancelar" button on the form
##
## State:
##   - Starts hidden (form + preview), new_button visible
##   - show()    : flips to form-visible / preview-visible / new-button-hidden
##   - cancel()  : back to initial state
##
## Tests use this class directly with raw Controls. Don't try to test the
## scene tree -- visibility booleans + button signal wiring are enough.

var _create_panel: Control
var _preview_panel: Control
var _new_button: Button
var _cancel_button: Button

# Track whether the create form is supposed to be available at all. When the
# user already has 3 characters (the cap), we hide the new-character button
# so they can't even open the form. Defaults to true; gate via set_can_create.
var _can_create: bool = true


func _init(refs: Dictionary) -> void:
	_create_panel  = refs.get("create_panel", null)
	_preview_panel = refs.get("preview_panel", null)
	_new_button    = refs.get("new_button", null)
	_cancel_button = refs.get("cancel_button", null)

	if _create_panel == null:
		push_error("CharacterCreateToggle: missing create_panel ref")
	if _new_button != null:
		_new_button.pressed.connect(show)
	if _cancel_button != null:
		_cancel_button.pressed.connect(cancel)

	# Initial state: form hidden, new-button shown.
	cancel()


# --- public API -------------------------------------------------------------


func show() -> void:
	if not _can_create:
		# Slot cap reached. Refuse to open the form. Caller is responsible
		# for messaging this to the user (we just stay closed).
		return
	if _create_panel != null:
		_create_panel.visible = true
	if _preview_panel != null:
		_preview_panel.visible = true
	if _new_button != null:
		_new_button.visible = false


func cancel() -> void:
	if _create_panel != null:
		_create_panel.visible = false
	if _preview_panel != null:
		_preview_panel.visible = false
	if _new_button != null:
		_new_button.visible = _can_create


func is_open() -> bool:
	if _create_panel == null:
		return false
	return _create_panel.visible


# Update whether the user is allowed to create more characters at all. When
# false, the new-character button stays hidden and show() is a no-op. Useful
# at the 3-slot cap.
func set_can_create(value: bool) -> void:
	_can_create = value
	if not value:
		# Force-close in case the form was already open when the cap hit.
		cancel()
	elif _new_button != null and not is_open():
		_new_button.visible = true
