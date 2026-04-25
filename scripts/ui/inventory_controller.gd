class_name InventoryController
extends RefCounted

## Inventory grid + drop-amount dialog. Owns:
##   - The 35-slot grid (visual: 5×7; capacity: 30; last row is padding)
##   - The local mirror of the server's inventory state
##   - The focused-slot pointer (target of USE_ITEM / EQUIP_ITEM)
##   - The drop-amount modal (open/close, parse, clamp, send DROP_ITEM)
##
## Dependencies are injected as a Dictionary so tests can pass stubs:
##   - inventory_grid: GridContainer that holds _InventorySlot children
##   - drop_overlay:   Control toggled visible while prompting amount
##   - drop_input:     LineEdit for the amount entry
##   - connection:     anything with send_packet(packet_id, payload)
##   - hud:            anything with add_message(text) — for "select a slot" hints

const SLOT_COUNT = 35

var _grid: GridContainer
var _drop_overlay: Control
var _drop_input: LineEdit
var _connection
var _hud

var _items: Array = []
var _focused_slot: int = -1
var _drop_pending_slot: int = -1
var _drop_pending_max: int = 0

func _init(refs: Dictionary) -> void:
	_grid          = refs.inventory_grid
	_drop_overlay  = refs.drop_overlay
	_drop_input    = refs.drop_input
	_connection    = refs.connection
	_hud           = refs.hud
	# Fail loud: if the caller passed a null connection (real-world cause:
	# constructing the controller before world.gd's setup() assigns
	# `connection = conn`), every send path would later crash with a
	# confusing "Nil.send_packet". Surface the wiring bug here instead.
	if _connection == null:
		push_error("InventoryController: null connection at construction — wiring bug")

# --- Setup ---

# Builds SLOT_COUNT empty slot panels and wires their click signals. Idempotent —
# safe to call again; existing children are freed first.
func build_slots() -> void:
	for child in _grid.get_children():
		child.queue_free()
	for i in SLOT_COUNT:
		var slot = _InventorySlot.new()
		slot.slot_index = i
		slot.clicked.connect(_on_slot_clicked)
		_grid.add_child(slot)

# --- State updates from server ---

# INVENTORY_UPDATE: full state replacement, keep our mirror in sync so drop-amount
# decisions can read stack sizes locally.
func set_inventory(items: Array) -> void:
	_items = items
	_render_items(_items)

# INVENTORY_RESPONSE: server snapshot — does NOT update _items (matches the prior
# inline behaviour where RESPONSE only re-rendered without mutating the mirror).
func render_only(items: Array) -> void:
	_render_items(items)

func _render_items(items: Array) -> void:
	var slots = _grid.get_children()
	for i in slots.size():
		var item = items[i] if i < items.size() else null
		slots[i].set_item(item)
		if i == _focused_slot and item == null:
			_focused_slot = -1
	_refresh_focus_highlights()

# --- Focus / clicks ---

func _on_slot_clicked(slot_index: int) -> void:
	var slot_node = _grid.get_child(slot_index)
	if not slot_node.has_item:
		_focused_slot = -1
	elif _focused_slot == slot_index:
		_focused_slot = -1
	else:
		_focused_slot = slot_index
	_refresh_focus_highlights()

func _refresh_focus_highlights() -> void:
	for i in _grid.get_child_count():
		_grid.get_child(i).set_focused(i == _focused_slot)

func focused_slot() -> int:
	return _focused_slot

# --- Action keys (use / equip / drop / pickup) ---

# Returns true if the action was sent. False if no slot focused — caller has
# already received the hint via hud.add_message.
func use_focused() -> bool:
	if _focused_slot < 0:
		_hud.add_message("Select an inventory slot first")
		return false
	if _connection == null:
		return false
	_connection.send_packet(PacketIds.USE_ITEM, {"slot": _focused_slot})
	return true

func equip_focused() -> bool:
	if _focused_slot < 0:
		_hud.add_message("Select an inventory slot first")
		return false
	if _connection == null:
		return false
	_connection.send_packet(PacketIds.EQUIP_ITEM, {"slot": _focused_slot})
	return true

# Drop entrypoint: empty stack → bail; size-1 stack → send immediately;
# multi-stack → open the drop-amount modal.
func start_drop() -> void:
	if _focused_slot < 0:
		_hud.add_message("Select an inventory slot first")
		return
	if _connection == null:
		return
	var item = _items[_focused_slot] if _focused_slot < _items.size() else null
	if item == null:
		return
	var amount = int(item.get("amount", 1))
	if amount <= 1:
		_connection.send_packet(PacketIds.DROP_ITEM, {"slot": _focused_slot})
		return
	_drop_pending_slot = _focused_slot
	_drop_pending_max = amount
	_drop_input.text = str(amount)
	_drop_overlay.visible = true
	_drop_input.grab_focus()
	_drop_input.select_all()

# --- Drop dialog ---

func confirm_drop() -> void:
	if _connection == null:
		hide_drop_dialog()
		return
	var raw = _drop_input.text.strip_edges()
	var amount = int(raw) if raw.is_valid_int() else 0
	amount = clamp(amount, 1, _drop_pending_max)
	_connection.send_packet(PacketIds.DROP_ITEM, {"slot": _drop_pending_slot, "amount": amount})
	hide_drop_dialog()

func hide_drop_dialog() -> void:
	_drop_overlay.visible = false
	_drop_pending_slot = -1
	_drop_pending_max = 0
	_drop_input.release_focus()

func is_drop_dialog_open() -> bool:
	return _drop_overlay.visible

# --- Inner class: a single inventory slot Panel ---

class _InventorySlot extends PanelContainer:
	signal clicked(slot_index: int)
	const SLOT_SIZE = 42
	var slot_index: int = -1
	var has_item: bool = false
	var label: Label

	func _init():
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
			clicked.emit(slot_index)

	func set_focused(focused: bool):
		modulate = Color(1.2, 1.2, 0.5, 1) if focused else Color(1, 1, 1, 1)

	func set_item(item):
		has_item = item != null
		if not has_item:
			label.text = ""
			return
		var data = item.get("item_data", {})
		var nm: String = data.get("name", "?")
		var amount = int(item.get("amount", 0))
		var short = nm.substr(0, min(3, nm.length())) if nm else "?"
		if amount > 1:
			label.text = "%s\nx%d" % [short, amount]
		else:
			label.text = short
		var color = Color(0.5, 1, 0.5) if item.get("equipped", false) else Color(1, 1, 1)
		label.add_theme_color_override("font_color", color)
