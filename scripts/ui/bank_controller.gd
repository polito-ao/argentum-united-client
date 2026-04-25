class_name BankController
extends RefCounted

## Bank UI overlay. B key (default) sends BANK_OPEN; server replies with
## BANK_CONTENTS which renders into the grid. Two actions:
##   - click a bank slot → withdraw the full stack
##   - select an inventory slot, then Depositar → deposit the full stack
##
## No banker NPC required for now; when merchant NPCs land in M5 they
## trigger the same packets, the overlay still opens here.
##
## Lifecycle: needs `connection` for sends → construct in setup() per the
## controller-lifecycle memory, not _ready().

const SLOT_SIZE = 42

var _grid: GridContainer
var _overlay: Control
var _connection
var _hud
var _inventory # InventoryController; untyped so tests can pass duck-typed stubs

var _items: Array = []
var _max_slots: int = 50

func _init(refs: Dictionary) -> void:
	_grid       = refs.bank_grid
	_overlay    = refs.bank_overlay
	_connection = refs.connection
	_hud        = refs.hud
	_inventory  = refs.inventory
	if _connection == null:
		push_error("BankController: null connection at construction — wiring bug")

# --- Open / close ---

func open() -> void:
	if _connection == null:
		return
	_connection.send_packet(PacketIds.BANK_OPEN, {})
	_overlay.visible = true

func close() -> void:
	_overlay.visible = false

func is_open() -> bool:
	return _overlay.visible

func toggle() -> void:
	if is_open():
		close()
	else:
		open()

# --- Server packet handler ---

# BANK_CONTENTS payload: { items: [...], max_slots: N }
func handle_contents(payload: Dictionary) -> void:
	_items = payload.get("items", [])
	_max_slots = int(payload.get("max_slots", 50))
	_render()

# --- Actions ---

func deposit_focused() -> bool:
	var slot_index = _inventory.focused_slot()
	if slot_index < 0:
		_hud.add_message("Selecciona un objeto del inventario para depositar")
		return false
	if _connection == null:
		return false
	_connection.send_packet(PacketIds.BANK_DEPOSIT, {"slot": slot_index, "amount": 9999})
	return true

func withdraw_slot(bank_slot: int, amount: int = 9999) -> void:
	if _connection == null:
		return
	_connection.send_packet(PacketIds.BANK_WITHDRAW, {"slot": bank_slot, "amount": amount})

# --- Rendering ---

func _render() -> void:
	for child in _grid.get_children():
		child.queue_free()

	for item in _items:
		var slot = _BankSlot.new(int(item.get("slot", 0)))
		slot.set_item(item)
		slot.clicked.connect(_on_slot_clicked)
		_grid.add_child(slot)

func _on_slot_clicked(bank_slot: int) -> void:
	withdraw_slot(bank_slot)

# --- Inner class: a single bank slot ---

class _BankSlot extends PanelContainer:
	signal clicked(bank_slot: int)
	const SLOT_SIZE = 42

	var bank_slot_index: int = -1
	var label: Label

	func _init(slot_idx: int):
		bank_slot_index = slot_idx
		custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
		label = Label.new()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_font_size_override("font_size", 10)
		add_child(label)

	func _ready():
		gui_input.connect(_on_gui_input)

	func _on_gui_input(event):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			clicked.emit(bank_slot_index)

	func set_item(item: Dictionary):
		var nm: String = item.get("name", "?")
		var amount = int(item.get("amount", 1))
		var short = nm.substr(0, min(3, nm.length())) if nm else "?"
		if amount > 1:
			label.text = "%s\nx%d" % [short, amount]
		else:
			label.text = short
		label.add_theme_color_override("font_color", Color.WHITE)
