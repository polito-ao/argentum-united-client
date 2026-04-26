class_name DevController
extends RefCounted

## Dev-tool overlay (F2 by default). Cucsi-style search + spawn:
##   - Toggle category: Items / Criaturas / Cofres
##   - Type to search; debounced server query returns matches
##   - Double-click a result → amount prompt → server spawns N
##     (chests ignore amount; server always spawns 1 at the player's tile)
##
## Server-gated by ENV["DEV_AUTH"]; in production these packets get no
## response so the overlay stays empty.
##
## Lifecycle: needs `connection` to send → construct in setup() per the
## controller-lifecycle memory.

const QUERY_DEBOUNCE_MS = 200

var _overlay: Control
var _amount_overlay: Control
var _query_input: LineEdit
var _amount_input: LineEdit
var _results: ItemList
var _item_tab: Button
var _creature_tab: Button
var _chest_tab: Button
var _connection
var _hud

var _category: String = "item"
var _last_results: Array = []   # [{slug, name}, ...]
var _pending_slug: String = ""
var _query_timer: int = 0       # ms remaining on debounce

func _init(refs: Dictionary) -> void:
	_overlay         = refs.overlay
	_amount_overlay  = refs.amount_overlay
	_query_input     = refs.query_input
	_amount_input    = refs.amount_input
	_results         = refs.results
	_item_tab        = refs.item_tab
	_creature_tab    = refs.creature_tab
	_chest_tab       = refs.get("chest_tab", null)
	_connection      = refs.connection
	_hud             = refs.hud
	if _connection == null:
		push_error("DevController: null connection at construction — wiring bug")

	_query_input.text_changed.connect(_on_query_changed)
	_results.item_activated.connect(_on_result_activated)
	_item_tab.pressed.connect(func(): _switch_category("item"))
	_creature_tab.pressed.connect(func(): _switch_category("creature"))
	if _chest_tab != null:
		_chest_tab.pressed.connect(func(): _switch_category("chest"))

# --- Open / close ---

func open() -> void:
	if _connection == null:
		return
	_overlay.visible = true
	_query_input.grab_focus()
	# Refresh listing on open so the latest server-side catalog is reflected
	# (and tells us right away if dev mode is disabled — empty results).
	_request_list()

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

# --- Per-frame debounce tick ---
# world.gd's _process calls this. Keeps the 200ms typing-pause-then-query
# behaviour without spamming the server on every keystroke.
func process(delta_ms: int) -> void:
	if _query_timer <= 0:
		return
	_query_timer -= delta_ms
	if _query_timer <= 0:
		_request_list()

# --- Server packet handlers ---

# DEV_LIST_RESPONSE payload: {category, results: [{slug, name}, ...]}
func handle_list_response(payload: Dictionary) -> void:
	if payload.get("category", "") != _category:
		return # stale response from a category we already left
	_last_results = payload.get("results", [])
	_render_results()

# --- Category toggle ---

func _switch_category(category: String) -> void:
	_category = category
	_item_tab.button_pressed = (category == "item")
	_creature_tab.button_pressed = (category == "creature")
	if _chest_tab != null:
		_chest_tab.button_pressed = (category == "chest")
	_request_list()

# --- Search ---

func _on_query_changed(_new_text: String) -> void:
	_query_timer = QUERY_DEBOUNCE_MS

func _request_list() -> void:
	_query_timer = 0
	if _connection == null:
		return
	_connection.send_packet(PacketIds.DEV_LIST_REQUEST, {
		"category": _category,
		"query": _query_input.text,
	})

func _render_results() -> void:
	_results.clear()
	for entry in _last_results:
		var slug: String = entry.get("slug", "")
		var name: String = entry.get("name", "?")
		_results.add_item("%s   (%s)" % [name, slug])

# --- Spawn (double-click → amount prompt → confirm) ---

func _on_result_activated(idx: int) -> void:
	if idx < 0 or idx >= _last_results.size():
		return
	_pending_slug = _last_results[idx].get("slug", "")
	if _pending_slug.is_empty():
		return
	_amount_input.text = "1"
	_amount_overlay.visible = true
	_amount_input.grab_focus()
	_amount_input.select_all()

func confirm_amount() -> void:
	if _pending_slug.is_empty():
		_hide_amount_prompt()
		return
	var raw = _amount_input.text.strip_edges()
	var amount = int(raw) if raw.is_valid_int() else 1
	amount = max(amount, 1)
	if _connection != null:
		_connection.send_packet(PacketIds.DEV_SPAWN, {
			"category": _category,
			"slug": _pending_slug,
			"amount": amount,
		})
	_hide_amount_prompt()

func cancel_amount() -> void:
	_hide_amount_prompt()

func _hide_amount_prompt() -> void:
	_amount_overlay.visible = false
	_amount_input.release_focus()
	_pending_slug = ""
