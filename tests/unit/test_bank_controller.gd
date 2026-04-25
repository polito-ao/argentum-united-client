extends GutTest
## Unit tests for BankController. Two-pane overlay; double-click moves
## (with amount prompt for stacks); right-click moves the entire stack.
##
## Slots are real PanelContainers — clicks tested by emitting the slot's
## signals directly rather than wiring real GUI input events through the
## scene tree.

const PacketIds = preload("res://scripts/network/packet_ids.gd")

var bank: BankController
var bank_grid: GridContainer
var inv_grid: GridContainer
var overlay: Control
var amount_overlay: Control
var amount_input: LineEdit
var conn: _StubConnection
var hud: _StubHud
var inv: _StubInventory

func before_each():
	bank_grid = GridContainer.new()
	inv_grid = GridContainer.new()
	overlay = Control.new()
	overlay.visible = false
	amount_overlay = Control.new()
	amount_overlay.visible = false
	amount_input = LineEdit.new()
	add_child_autofree(amount_input)
	conn = _StubConnection.new()
	hud = _StubHud.new()
	inv = _StubInventory.new()
	bank = BankController.new({
		bank_grid       = bank_grid,
		inv_grid        = inv_grid,
		bank_overlay    = overlay,
		amount_overlay  = amount_overlay,
		amount_input    = amount_input,
		connection      = conn,
		hud             = hud,
		inventory       = inv,
	})

func after_each():
	bank_grid.free()
	inv_grid.free()
	overlay.free()
	amount_overlay.free()

# --- open / close ---

func test_open_sends_bank_open_and_shows_overlay():
	bank.open()
	assert_eq(conn.sent.size(), 1)
	assert_eq(conn.sent[0].id, PacketIds.BANK_OPEN)
	assert_true(bank.is_open())

func test_close_hides_overlay_and_amount_prompt():
	bank.open()
	amount_overlay.visible = true
	bank.close()
	assert_false(bank.is_open())
	assert_false(bank.is_amount_prompt_open())

# --- handle_contents ---

func test_handle_contents_renders_bank_grid():
	bank.handle_contents({
		"items": [
			{"slot": 0, "item_id": 50, "name": "Pocion", "amount": 5, "item_data": {}},
			{"slot": 1, "item_id": 1,  "name": "Espada", "amount": 1, "item_data": {}},
		],
		"max_slots": 50,
	})
	assert_eq(bank_grid.get_child_count(), 2)

# --- refresh_inventory_mirror ---

func test_refresh_inventory_mirror_renders_open_bank():
	inv.items_value = [
		{"item_id": 50, "amount": 3, "item_data": {"name": "Pocion"}},
		null,
		{"item_id": 1, "amount": 1, "item_data": {"name": "Espada"}},
	]
	# open() already calls refresh under the hood; null slot must be skipped.
	bank.open()
	assert_eq(inv_grid.get_child_count(), 2)

func test_refresh_inventory_mirror_no_op_when_bank_closed():
	inv.items_value = [{"item_id": 50, "amount": 3, "item_data": {"name": "Pocion"}}]
	bank.refresh_inventory_mirror()
	assert_eq(inv_grid.get_child_count(), 0)

# --- moves: deposit (from inventory pane) ---

func test_move_one_from_inventory_sends_bank_deposit_amount_1():
	bank._on_slot_move_one("deposit", 3)
	assert_eq(conn.sent[0].id, PacketIds.BANK_DEPOSIT)
	assert_eq(conn.sent[0].payload.slot, 3)
	assert_eq(conn.sent[0].payload.amount, 1)

func test_move_all_from_inventory_sends_bank_deposit_amount_0_sentinel():
	bank._on_slot_move_all("deposit", 3)
	assert_eq(conn.sent[0].id, PacketIds.BANK_DEPOSIT)
	# 0 = "whole stack" sentinel; server resolves to actual stack size.
	assert_eq(conn.sent[0].payload.amount, 0)

# --- moves: withdraw (from bank pane) ---

func test_move_one_from_bank_sends_bank_withdraw_amount_1():
	bank._on_slot_move_one("withdraw", 7)
	assert_eq(conn.sent[0].id, PacketIds.BANK_WITHDRAW)
	assert_eq(conn.sent[0].payload.slot, 7)
	assert_eq(conn.sent[0].payload.amount, 1)

func test_move_all_from_bank_sends_bank_withdraw_amount_0_sentinel():
	bank._on_slot_move_all("withdraw", 7)
	assert_eq(conn.sent[0].id, PacketIds.BANK_WITHDRAW)
	assert_eq(conn.sent[0].payload.amount, 0)

# --- amount prompt ---

func test_prompt_amount_opens_overlay_and_prefills_max():
	bank._on_slot_prompt_amount("deposit", 2, 7)
	assert_true(bank.is_amount_prompt_open())
	assert_eq(amount_input.text, "7")

func test_confirm_amount_clamps_to_max_and_sends_packet():
	bank._on_slot_prompt_amount("deposit", 2, 7)
	amount_input.text = "9999"
	bank.confirm_amount()
	assert_eq(conn.sent[0].id, PacketIds.BANK_DEPOSIT)
	assert_eq(conn.sent[0].payload.amount, 7)
	assert_false(bank.is_amount_prompt_open())

func test_confirm_amount_treats_invalid_text_as_one():
	bank._on_slot_prompt_amount("withdraw", 0, 5)
	amount_input.text = "abc"
	bank.confirm_amount()
	assert_eq(conn.sent[0].payload.amount, 1)

func test_cancel_amount_sends_no_packet():
	bank._on_slot_prompt_amount("deposit", 1, 4)
	bank.cancel_amount()
	assert_eq(conn.sent.size(), 0)
	assert_false(bank.is_amount_prompt_open())

# --- null connection (loud-but-safe) ---

func test_open_no_op_when_connection_null():
	var orphan = BankController.new({
		bank_grid       = bank_grid,
		inv_grid        = inv_grid,
		bank_overlay    = overlay,
		amount_overlay  = amount_overlay,
		amount_input    = amount_input,
		connection      = null,
		hud             = hud,
		inventory       = inv,
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
	var items_value: Array = []
	func items() -> Array:
		return items_value
