extends GutTest
## Unit tests for DevController. Real Controls (overlay, LineEdit,
## ItemList, Buttons) are fine outside the scene tree for this surface
## — we only call methods + read state.

const PacketIds = preload("res://scripts/network/packet_ids.gd")

var dev: DevController
var overlay: Control
var amount_overlay: Control
var query_input: LineEdit
var amount_input: LineEdit
var results: ItemList
var item_tab: Button
var creature_tab: Button
var conn: _StubConnection
var hud: _StubHud

func before_each():
	overlay = Control.new()
	overlay.visible = false
	amount_overlay = Control.new()
	amount_overlay.visible = false
	query_input = LineEdit.new()
	add_child_autofree(query_input)
	amount_input = LineEdit.new()
	add_child_autofree(amount_input)
	results = ItemList.new()
	item_tab = Button.new()
	item_tab.toggle_mode = true
	item_tab.button_pressed = true
	creature_tab = Button.new()
	creature_tab.toggle_mode = true
	conn = _StubConnection.new()
	hud = _StubHud.new()
	dev = DevController.new({
		overlay        = overlay,
		amount_overlay = amount_overlay,
		query_input    = query_input,
		amount_input   = amount_input,
		results        = results,
		item_tab       = item_tab,
		creature_tab   = creature_tab,
		connection     = conn,
		hud            = hud,
	})

func after_each():
	overlay.free()
	amount_overlay.free()
	results.free()
	item_tab.free()
	creature_tab.free()

# --- open / close ---

func test_open_shows_overlay_and_requests_initial_list():
	dev.open()
	assert_true(dev.is_open())
	# Initial query goes out immediately on open
	var req = _first_packet(PacketIds.DEV_LIST_REQUEST)
	assert_not_null(req)
	assert_eq(req.payload.category, "item") # default tab
	assert_eq(req.payload.query, "")

func test_close_hides_overlay_and_amount_prompt():
	dev.open()
	amount_overlay.visible = true
	dev.close()
	assert_false(dev.is_open())
	assert_false(dev.is_amount_prompt_open())

func test_toggle_opens_then_closes():
	dev.toggle()
	assert_true(dev.is_open())
	dev.toggle()
	assert_false(dev.is_open())

# --- category toggle ---

func test_switching_to_creature_category_re_requests_list():
	dev.open()
	conn.sent.clear()
	dev._switch_category("creature")
	var req = _first_packet(PacketIds.DEV_LIST_REQUEST)
	assert_not_null(req)
	assert_eq(req.payload.category, "creature")
	assert_true(creature_tab.button_pressed)
	assert_false(item_tab.button_pressed)

# --- list response ---

func test_handle_list_response_renders_results():
	dev._switch_category("item")
	dev.handle_list_response({
		"category": "item",
		"results": [
			{"slug": "pocion_de_vida", "name": "Pocion de Vida"},
			{"slug": "espada_corta", "name": "Espada Corta"},
		],
	})
	assert_eq(results.item_count, 2)

func test_handle_list_response_drops_stale_other_category_response():
	dev._switch_category("item")
	# Simulate a delayed creature-category response arriving after switch
	dev.handle_list_response({
		"category": "creature",
		"results": [{"slug": "lobo", "name": "Lobo"}],
	})
	assert_eq(results.item_count, 0)

# --- query debounce ---

func test_query_debounce_does_not_send_on_each_keystroke():
	dev.open()
	conn.sent.clear()
	dev._on_query_changed("p")
	dev._on_query_changed("po")
	dev._on_query_changed("poc")
	assert_eq(conn.sent.size(), 0) # not yet — debounce timer running

func test_process_fires_query_after_debounce_window():
	dev.open()
	conn.sent.clear()
	# In production the LineEdit's text_changed signal sets the input's
	# text BEFORE firing the callback. The stub mirrors that here.
	query_input.text = "poc"
	dev._on_query_changed("poc")
	dev.process(DevController.QUERY_DEBOUNCE_MS + 10)
	var req = _first_packet(PacketIds.DEV_LIST_REQUEST)
	assert_not_null(req)
	assert_eq(req.payload.query, "poc")

# --- spawn flow ---

func test_double_click_a_result_opens_amount_prompt_with_default_1():
	dev._switch_category("item")
	dev.handle_list_response({
		"category": "item",
		"results": [{"slug": "pocion_de_vida", "name": "Pocion de Vida"}],
	})
	dev._on_result_activated(0)
	assert_true(dev.is_amount_prompt_open())
	assert_eq(amount_input.text, "1")

func test_confirm_amount_sends_dev_spawn_and_closes_prompt():
	dev._switch_category("item")
	dev.handle_list_response({
		"category": "item",
		"results": [{"slug": "pocion_de_vida", "name": "Pocion de Vida"}],
	})
	dev._on_result_activated(0)
	amount_input.text = "25000"
	conn.sent.clear()
	dev.confirm_amount()

	var spawn = _first_packet(PacketIds.DEV_SPAWN)
	assert_not_null(spawn)
	assert_eq(spawn.payload.category, "item")
	assert_eq(spawn.payload.slug, "pocion_de_vida")
	assert_eq(spawn.payload.amount, 25000)
	assert_false(dev.is_amount_prompt_open())

func test_confirm_amount_clamps_invalid_text_to_one():
	dev._switch_category("creature")
	dev.handle_list_response({
		"category": "creature",
		"results": [{"slug": "lobo", "name": "Lobo"}],
	})
	dev._on_result_activated(0)
	amount_input.text = "abc"
	conn.sent.clear()
	dev.confirm_amount()
	var spawn = _first_packet(PacketIds.DEV_SPAWN)
	assert_eq(spawn.payload.amount, 1)

func test_cancel_amount_sends_no_spawn():
	dev._switch_category("item")
	dev.handle_list_response({
		"category": "item",
		"results": [{"slug": "pocion_de_vida", "name": "Pocion de Vida"}],
	})
	dev._on_result_activated(0)
	conn.sent.clear()
	dev.cancel_amount()
	assert_eq(conn.sent.size(), 0)
	assert_false(dev.is_amount_prompt_open())

# --- helpers ---

# Returns the first packet matching `id` (Dictionary), or null. Array.find
# with a Callable does value-equality in Godot 4, not predicate match — use
# filter() then take front.
func _first_packet(id: int):
	var matches = conn.sent.filter(func(p): return p.id == id)
	return matches.front() if matches.size() > 0 else null

class _StubConnection extends RefCounted:
	var sent: Array = []
	func send_packet(id, payload = {}):
		sent.append({"id": id, "payload": payload})

class _StubHud extends RefCounted:
	var messages: Array = []
	func add_message(text: String):
		messages.append(text)
