extends GutTest
## Unit tests for BankController. Real GridContainer + Control overlay are
## fine without a scene tree. Connection + HUD + InventoryController are
## stubbed; the controller only sends packets and reads inventory.focused_slot.

const PacketIds = preload("res://scripts/network/packet_ids.gd")

var bank: BankController
var grid: GridContainer
var overlay: Control
var conn: _StubConnection
var hud: _StubHud
var inv: _StubInventory

func before_each():
	grid = GridContainer.new()
	overlay = Control.new()
	overlay.visible = false
	conn = _StubConnection.new()
	hud = _StubHud.new()
	inv = _StubInventory.new()
	bank = BankController.new({
		bank_grid    = grid,
		bank_overlay = overlay,
		connection   = conn,
		hud          = hud,
		inventory    = inv,
	})

func after_each():
	grid.free()
	overlay.free()

# --- open / close ---

func test_open_sends_BANK_OPEN_and_shows_overlay():
	bank.open()
	assert_eq(conn.sent.size(), 1)
	assert_eq(conn.sent[0].id, PacketIds.BANK_OPEN)
	assert_true(bank.is_open())

func test_close_hides_overlay():
	bank.open()
	bank.close()
	assert_false(bank.is_open())

func test_toggle_opens_then_closes():
	bank.toggle()
	assert_true(bank.is_open())
	bank.toggle()
	assert_false(bank.is_open())

# --- handle_contents ---

func test_handle_contents_renders_each_slot():
	bank.handle_contents({
		"items": [
			{"slot": 0, "item_id": 50, "name": "Pocion", "amount": 5, "item_data": {}},
			{"slot": 1, "item_id": 1,  "name": "Espada", "amount": 1, "item_data": {}},
		],
		"max_slots": 50,
	})
	assert_eq(grid.get_child_count(), 2)

func test_handle_contents_replaces_previous_render():
	bank.handle_contents({"items": [{"slot": 0, "name": "X", "amount": 1}], "max_slots": 50})
	# Free the queue_free'd children synchronously — GUT runs without the
	# regular tree tick, so manually flush before re-rendering.
	for child in grid.get_children():
		child.queue_free()
		child.free()
	bank.handle_contents({"items": [{"slot": 0, "name": "Y", "amount": 2}], "max_slots": 50})
	assert_eq(grid.get_child_count(), 1)

# --- deposit / withdraw ---

func test_deposit_focused_with_no_selection_hints_and_no_packet():
	inv.focused_slot_value = -1
	assert_false(bank.deposit_focused())
	assert_eq(hud.messages.size(), 1)
	assert_eq(conn.sent.size(), 0)

func test_deposit_focused_with_selection_sends_BANK_DEPOSIT():
	inv.focused_slot_value = 3
	assert_true(bank.deposit_focused())
	assert_eq(conn.sent[0].id, PacketIds.BANK_DEPOSIT)
	assert_eq(conn.sent[0].payload.slot, 3)

func test_withdraw_slot_sends_BANK_WITHDRAW():
	bank.withdraw_slot(7, 5)
	assert_eq(conn.sent[0].id, PacketIds.BANK_WITHDRAW)
	assert_eq(conn.sent[0].payload.slot, 7)
	assert_eq(conn.sent[0].payload.amount, 5)

# --- null connection (loud-but-safe) ---

func test_open_no_op_when_connection_null():
	var orphan = BankController.new({
		bank_grid    = grid,
		bank_overlay = overlay,
		connection   = null,
		hud          = hud,
		inventory    = inv,
	})
	orphan.open()
	assert_false(overlay.visible)

# --- helpers ---

class _StubConnection extends RefCounted:
	var sent: Array = []
	func send_packet(id, payload = {}):
		sent.append({"id": id, "payload": payload})

class _StubHud extends RefCounted:
	var messages: Array = []
	func add_message(text: String):
		messages.append(text)

class _StubInventory extends RefCounted:
	var focused_slot_value: int = -1
	func focused_slot() -> int:
		return focused_slot_value
