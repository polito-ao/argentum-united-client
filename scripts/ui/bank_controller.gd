class_name BankController
extends RefCounted

## Bank UI overlay (V key by default). Two-pane layout:
##   - Left:  bank slots (5 wide; 50 cap, 100 VIP)
##   - Right: inventory mirror (5 wide; 30 cap)
##
## Interactions on EITHER side:
##   - Double-click a slot:
##       stack > 1 → opens amount prompt (BankAmountOverlay)
##       stack = 1 → moves the single item immediately
##   - Right-click a slot → moves the entire stack
##
## Direction is implicit by which side was clicked: bank → withdraw,
## inventory → deposit.
##
## Lifecycle: needs `connection` to send packets, so construct in setup()
## (controller-lifecycle memory).

var _bank_grid: GridContainer
var _inv_grid: GridContainer
var _overlay: Control
var _amount_overlay: Control
var _amount_input: LineEdit
var _connection
var _hud
var _inventory # InventoryController; untyped so tests can pass duck-typed stubs

var _bank_items: Array = []
var _max_slots: int = 50

# Pending action for the amount prompt: { dir: "deposit"/"withdraw", slot: N, max: M }
var _pending: Dictionary = {}

func _init(refs: Dictionary) -> void:
	_bank_grid       = refs.bank_grid
	_inv_grid        = refs.inv_grid
	_overlay         = refs.bank_overlay
	_amount_overlay  = refs.amount_overlay
	_amount_input    = refs.amount_input
	_connection      = refs.connection
	_hud             = refs.hud
	_inventory       = refs.inventory
	if _connection == null:
		push_error("BankController: null connection at construction — wiring bug")

# --- Open / close ---

func open() -> void:
	if _connection == null:
		return
	_connection.send_packet(PacketIds.BANK_OPEN, {})
	_overlay.visible = true
	# Inventory mirror reflects whatever the inventory side has right now.
	_render_inv_mirror()

func close() -> void:
	_overlay.visible = false
	_hide_amount_prompt()

func is_open() -> bool:
	return _overlay.visible

func toggle() -> void:
	if is_open():
		close()
	else:
		open()

func is_amount_prompt_open() -> bool:
	return _amount_overlay.visible

# --- Server packet handlers / state sync ---

# BANK_CONTENTS payload: { items: [...], max_slots: N }
func handle_contents(payload: Dictionary) -> void:
	_bank_items = payload.get("items", [])
	_max_slots = int(payload.get("max_slots", 50))
	_render_bank()

# Called from world.gd whenever INVENTORY_UPDATE arrives AND bank is open,
# so the mirror tracks the source of truth without us subscribing.
func refresh_inventory_mirror() -> void:
	if not is_open():
		return
	_render_inv_mirror()

# --- Rendering ---

func _render_bank() -> void:
	for child in _bank_grid.get_children():
		child.queue_free()
	for item in _bank_items:
		var slot = _BankPaneSlot.new("withdraw", int(item.get("slot", 0)), item)
		slot.move_one.connect(_on_slot_move_one)
		slot.move_all.connect(_on_slot_move_all)
		slot.prompt_amount.connect(_on_slot_prompt_amount)
		_bank_grid.add_child(slot)

func _render_inv_mirror() -> void:
	for child in _inv_grid.get_children():
		child.queue_free()
	if _inventory == null:
		return
	var items = _inventory.items()
	for i in items.size():
		var item = items[i]
		if item == null:
			continue
		var slot = _BankPaneSlot.new("deposit", i, item)
		slot.move_one.connect(_on_slot_move_one)
		slot.move_all.connect(_on_slot_move_all)
		slot.prompt_amount.connect(_on_slot_prompt_amount)
		_inv_grid.add_child(slot)

# --- Slot signals ---

# Double-click on a single-stack slot, or fallback for unknown stack size.
func _on_slot_move_one(direction: String, slot_index: int) -> void:
	_send_move(direction, slot_index, 1)

# Right-click on any slot.
func _on_slot_move_all(direction: String, slot_index: int) -> void:
	# 9999 — server clamps to actual stack size. Same trick as the deposit/withdraw v1.
	_send_move(direction, slot_index, 9999)

# Double-click on a stack > 1 → prompt for amount.
func _on_slot_prompt_amount(direction: String, slot_index: int, max_amount: int) -> void:
	_pending = {"dir": direction, "slot": slot_index, "max": max_amount}
	_amount_input.text = str(max_amount)
	_amount_overlay.visible = true
	_amount_input.grab_focus()
	_amount_input.select_all()

func confirm_amount() -> void:
	if _pending.is_empty():
		_hide_amount_prompt()
		return
	var raw = _amount_input.text.strip_edges()
	var amount = int(raw) if raw.is_valid_int() else 0
	amount = clamp(amount, 1, _pending.max)
	_send_move(_pending.dir, _pending.slot, amount)
	_hide_amount_prompt()

func cancel_amount() -> void:
	_hide_amount_prompt()

func _hide_amount_prompt() -> void:
	_amount_overlay.visible = false
	_amount_input.release_focus()
	_pending = {}

func _send_move(direction: String, slot_index: int, amount: int) -> void:
	if _connection == null:
		return
	var packet_id = PacketIds.BANK_DEPOSIT if direction == "deposit" else PacketIds.BANK_WITHDRAW
	_connection.send_packet(packet_id, {"slot": slot_index, "amount": amount})

# --- Inner class: a single slot in either pane ---
#
# Direction tag baked in at construction time so right-click/double-click
# emit the right signal kind. Container parent keeps things tidy.

class _BankPaneSlot extends PanelContainer:
	signal move_one(direction: String, slot_index: int)
	signal move_all(direction: String, slot_index: int)
	signal prompt_amount(direction: String, slot_index: int, max_amount: int)

	const SLOT_SIZE = 42

	var label: Label
	var _direction: String # "deposit" (clicked from inventory pane) or "withdraw" (bank pane)
	var _slot_index: int
	var _amount: int

	func _init(direction: String, slot_index: int, item: Dictionary):
		_direction = direction
		_slot_index = slot_index
		_amount = int(item.get("amount", 1))

		custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
		label = Label.new()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_font_size_override("font_size", 10)
		# Inventory items carry name in item_data; bank items carry it at top level.
		var nm: String = item.get("name", "")
		if nm.is_empty():
			nm = item.get("item_data", {}).get("name", "?")
		var short = nm.substr(0, min(3, nm.length())) if nm else "?"
		label.text = "%s\nx%d" % [short, _amount] if _amount > 1 else short
		label.add_theme_color_override("font_color", Color.WHITE)
		add_child(label)

	# Override the virtual instead of connecting to the gui_input signal —
	# more direct dispatch and accept_event() reliably stops propagation.
	# The earlier signal-connect path didn't fire for right-click on this
	# panel for some reason; the override fixes it.
	func _gui_input(event):
		if not (event is InputEventMouseButton) or not event.pressed:
			return
		if event.button_index == MOUSE_BUTTON_RIGHT:
			move_all.emit(_direction, _slot_index)
			accept_event()
			return
		if event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
			if _amount <= 1:
				move_one.emit(_direction, _slot_index)
			else:
				prompt_amount.emit(_direction, _slot_index, _amount)
			accept_event()
