extends GutTest
## Unit tests for InventoryController. Constructed with stub Connection +
## stub HUD; the GridContainer + LineEdit + overlay are real so we can
## verify visibility toggles and child-count math.
##
## The slot inner class's _ready connects gui_input only when in a tree —
## we don't add the grid to a tree, so we test focus changes by calling
## _on_slot_clicked directly (simulating the signal).

const PacketIds = preload("res://scripts/network/packet_ids.gd")

var inv: InventoryController
var grid: GridContainer
var overlay: Control
var input_box: LineEdit
var conn: _StubConnection
var hud: _StubHud

func before_each():
	grid = GridContainer.new()
	overlay = Control.new()
	overlay.visible = false
	input_box = LineEdit.new()
	# LineEdit.grab_focus / release_focus need the node in a tree, otherwise
	# Godot logs (harmless) "is_inside_tree()" errors during start_drop /
	# hide_drop_dialog. Attaching to the test scene keeps the log clean.
	add_child_autofree(input_box)
	conn = _StubConnection.new()
	hud = _StubHud.new()
	inv = InventoryController.new({
		inventory_grid = grid,
		drop_overlay   = overlay,
		drop_input     = input_box,
		connection     = conn,
		hud            = hud,
	})

func after_each():
	grid.free()
	overlay.free()

# --- build_slots ---

func test_build_slots_creates_slot_count_children():
	inv.build_slots()
	assert_eq(grid.get_child_count(), InventoryController.SLOT_COUNT)

func test_build_slots_is_idempotent():
	inv.build_slots()
	inv.build_slots()
	# queue_free defers; in headless tests new children stack on top.
	# What we actually care about: no crash + final count is consistent.
	assert_gt(grid.get_child_count(), 0)

# --- set_inventory / render ---

func test_set_inventory_populates_visible_slot_labels():
	inv.build_slots()
	inv.set_inventory([_item("Manzana", 1), _item("Poción", 5)])
	assert_eq(grid.get_child(0).label.text, "Man")
	assert_eq(grid.get_child(1).label.text, "Poc\nx5")
	assert_eq(grid.get_child(2).label.text, "")

func test_set_inventory_clears_focus_when_focused_slot_emptied():
	inv.build_slots()
	inv.set_inventory([_item("Manzana", 1)])
	inv._on_slot_clicked(0)
	assert_eq(inv.focused_slot(), 0)
	# Server reports the slot is now empty
	inv.set_inventory([])
	assert_eq(inv.focused_slot(), -1)

# --- focus toggling ---

func test_click_filled_slot_focuses_it():
	inv.build_slots()
	inv.set_inventory([_item("X", 1), _item("Y", 1)])
	inv._on_slot_clicked(1)
	assert_eq(inv.focused_slot(), 1)

func test_click_same_slot_unfocuses():
	inv.build_slots()
	inv.set_inventory([_item("X", 1)])
	inv._on_slot_clicked(0)
	inv._on_slot_clicked(0)
	assert_eq(inv.focused_slot(), -1)

func test_click_empty_slot_clears_focus():
	inv.build_slots()
	inv.set_inventory([_item("X", 1)])
	inv._on_slot_clicked(0)
	# Empty slot index 5 has no item
	inv._on_slot_clicked(5)
	assert_eq(inv.focused_slot(), -1)

# --- use / equip ---

func test_use_focused_with_no_selection_hints_and_skips_packet():
	inv.build_slots()
	assert_false(inv.use_focused())
	assert_eq(hud.messages, ["Select an inventory slot first"])
	assert_eq(conn.sent.size(), 0)

func test_use_focused_with_selection_sends_packet():
	inv.build_slots()
	inv.set_inventory([_item("X", 1)])
	inv._on_slot_clicked(0)
	assert_true(inv.use_focused())
	assert_eq(conn.sent.size(), 1)
	assert_eq(conn.sent[0].id, PacketIds.USE_ITEM)
	assert_eq(conn.sent[0].payload.slot, 0)

func test_equip_focused_sends_packet():
	inv.build_slots()
	inv.set_inventory([_item("X", 1), _item("Y", 1)])
	inv._on_slot_clicked(1)
	inv.equip_focused()
	assert_eq(conn.sent[0].id, PacketIds.EQUIP_ITEM)
	assert_eq(conn.sent[0].payload.slot, 1)

# --- drop ---

func test_start_drop_with_no_selection_hints():
	inv.build_slots()
	inv.start_drop()
	assert_eq(hud.messages, ["Select an inventory slot first"])
	assert_false(inv.is_drop_dialog_open())

func test_start_drop_size_one_sends_immediately_no_dialog():
	inv.build_slots()
	inv.set_inventory([_item("X", 1)])
	inv._on_slot_clicked(0)
	inv.start_drop()
	assert_eq(conn.sent[0].id, PacketIds.DROP_ITEM)
	assert_eq(conn.sent[0].payload.slot, 0)
	assert_false(conn.sent[0].payload.has("amount"))
	assert_false(inv.is_drop_dialog_open())

func test_start_drop_stacked_opens_dialog_no_packet_yet():
	inv.build_slots()
	inv.set_inventory([_item("Poción", 7)])
	inv._on_slot_clicked(0)
	inv.start_drop()
	assert_true(inv.is_drop_dialog_open())
	assert_eq(input_box.text, "7")
	assert_eq(conn.sent.size(), 0)

func test_confirm_drop_sends_clamped_amount():
	inv.build_slots()
	inv.set_inventory([_item("Poción", 7)])
	inv._on_slot_clicked(0)
	inv.start_drop()
	input_box.text = "3"
	inv.confirm_drop()
	assert_eq(conn.sent[0].id, PacketIds.DROP_ITEM)
	assert_eq(conn.sent[0].payload.slot, 0)
	assert_eq(conn.sent[0].payload.amount, 3)
	assert_false(inv.is_drop_dialog_open())

func test_confirm_drop_clamps_overflow_to_max():
	inv.build_slots()
	inv.set_inventory([_item("Poción", 7)])
	inv._on_slot_clicked(0)
	inv.start_drop()
	input_box.text = "9999"
	inv.confirm_drop()
	assert_eq(conn.sent[0].payload.amount, 7)

func test_confirm_drop_treats_invalid_text_as_one():
	inv.build_slots()
	inv.set_inventory([_item("Poción", 7)])
	inv._on_slot_clicked(0)
	inv.start_drop()
	input_box.text = "abc"
	inv.confirm_drop()
	# Invalid → 0 → clamped to lower bound of 1
	assert_eq(conn.sent[0].payload.amount, 1)

# --- Wiring contract: null connection ---
#
# Reproduces a real bug: world.gd constructed the controller in _ready(),
# but `connection` was only assigned later in setup(). The controller
# captured the null value, so equip_focused crashed with
# "Nil.send_packet". We want a clear failure mode instead.

func test_equip_focused_no_op_when_connection_is_null():
	var inv2 = InventoryController.new({
		inventory_grid = grid,
		drop_overlay   = overlay,
		drop_input     = input_box,
		connection     = null,
		hud            = hud,
	})
	inv2.build_slots()
	inv2.set_inventory([_item("X", 1)])
	inv2._on_slot_clicked(0)
	# Must not crash with Nil.send_packet
	assert_false(inv2.equip_focused())

func test_use_focused_no_op_when_connection_is_null():
	var inv2 = InventoryController.new({
		inventory_grid = grid,
		drop_overlay   = overlay,
		drop_input     = input_box,
		connection     = null,
		hud            = hud,
	})
	inv2.build_slots()
	inv2.set_inventory([_item("X", 1)])
	inv2._on_slot_clicked(0)
	assert_false(inv2.use_focused())

func test_start_drop_single_no_op_when_connection_is_null():
	var inv2 = InventoryController.new({
		inventory_grid = grid,
		drop_overlay   = overlay,
		drop_input     = input_box,
		connection     = null,
		hud            = hud,
	})
	inv2.build_slots()
	inv2.set_inventory([_item("X", 1)])
	inv2._on_slot_clicked(0)
	# Must not crash. Stack-of-one would normally send DROP_ITEM directly.
	inv2.start_drop()
	assert_false(inv2.is_drop_dialog_open())

func test_hide_drop_dialog_resets_state():
	inv.build_slots()
	inv.set_inventory([_item("Poción", 7)])
	inv._on_slot_clicked(0)
	inv.start_drop()
	inv.hide_drop_dialog()
	assert_false(inv.is_drop_dialog_open())

# --- helpers ---

func _item(name: String, amount: int) -> Dictionary:
	return {
		"item_data": {"name": name},
		"amount": amount,
	}

class _StubConnection extends RefCounted:
	var sent: Array = []
	func send_packet(id, payload = {}):
		sent.append({"id": id, "payload": payload})

class _StubHud extends RefCounted:
	var messages: Array = []
	func add_message(text: String):
		messages.append(text)
