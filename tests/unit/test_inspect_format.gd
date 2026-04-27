extends GutTest
## Unit tests for World.format_inspect_report — the pure-function helper
## that builds the chat-system-line report when the player left-clicks a
## tile to inspect it. No scene tree, no network, no HUD: the helper takes
## the click position + a snapshot of world state and returns a string.

const World = preload("res://scenes/world/world.gd")

# --- Empty tile ---

func test_empty_tile_says_nothing_here():
	var report = World.format_inspect_report(
		Vector2i(10, 10),
		Vector2i(50, 50),  # self elsewhere
		100, 100,
		{}, {}, {}, {}
	)
	assert_eq(report, "No hay nada aquí.")

# --- Self ---

func test_self_on_clicked_tile_includes_hp():
	var report = World.format_inspect_report(
		Vector2i(50, 50),
		Vector2i(50, 50),
		87, 120,
		{}, {}, {}, {}
	)
	assert_eq(report, "Aquí: Tú (HP 87/120)")

func test_self_with_zero_max_hp_falls_back_to_just_tu():
	# HUD bar reports 0/0 before the first UPDATE_HP — don't print "HP 0/0".
	var report = World.format_inspect_report(
		Vector2i(50, 50),
		Vector2i(50, 50),
		0, 0,
		{}, {}, {}, {}
	)
	assert_eq(report, "Aquí: Tú")

# --- Single entity, one-line shorthand ---

func test_single_npc_uses_aqui_shorthand():
	var npcs = {
		1: {"pos": Vector2i(5, 5), "name": "Lobo", "hp": 75, "max_hp": 150}
	}
	var report = World.format_inspect_report(
		Vector2i(5, 5),
		Vector2i(50, 50),
		100, 100,
		{}, npcs, {}, {}
	)
	assert_eq(report, "Aquí: NPC: Lobo (HP 75/150)")

func test_single_player_uses_aqui_shorthand():
	var players = {
		42: {"pos": Vector2i(7, 7), "name": "Ana"}
	}
	var report = World.format_inspect_report(
		Vector2i(7, 7),
		Vector2i(50, 50),
		100, 100,
		players, {}, {}, {}
	)
	assert_eq(report, "Aquí: Jugador: Ana")

func test_single_ground_item_uses_aqui_shorthand():
	var ground_items = {
		1: {
			"pos": Vector2i(3, 3),
			"item_data": {"name": "Espada Corta"},
			"amount": 1,
		}
	}
	var report = World.format_inspect_report(
		Vector2i(3, 3),
		Vector2i(50, 50),
		100, 100,
		{}, {}, ground_items, {}
	)
	assert_eq(report, "Aquí: Item: Espada Corta")

func test_ground_item_amount_above_one_appends_xN():
	var ground_items = {
		1: {
			"pos": Vector2i(3, 3),
			"item_data": {"name": "Monedas de oro"},
			"amount": 50,
		}
	}
	var report = World.format_inspect_report(
		Vector2i(3, 3),
		Vector2i(50, 50),
		100, 100,
		{}, {}, ground_items, {}
	)
	assert_eq(report, "Aquí: Item: Monedas de oro x50")

func test_chest_closed_state_renders_label():
	var chests = {
		1: {"pos": Vector2i(8, 8), "state": "closed"}
	}
	var report = World.format_inspect_report(
		Vector2i(8, 8),
		Vector2i(50, 50),
		100, 100,
		{}, {}, {}, chests
	)
	assert_eq(report, "Aquí: Cofre (cerrado)")

func test_chest_opened_state_renders_label():
	var chests = {
		1: {"pos": Vector2i(8, 8), "state": "opened"}
	}
	var report = World.format_inspect_report(
		Vector2i(8, 8),
		Vector2i(50, 50),
		100, 100,
		{}, {}, {}, chests
	)
	assert_eq(report, "Aquí: Cofre (abierto)")

# --- Multi-entity tile ---

func test_multi_entity_tile_uses_bullet_list():
	var npcs = {
		1: {"pos": Vector2i(5, 5), "name": "Lobo", "hp": 75, "max_hp": 150}
	}
	var ground_items = {
		1: {"pos": Vector2i(5, 5), "item_data": {"name": "Espada Corta"}, "amount": 1},
		2: {"pos": Vector2i(5, 5), "item_data": {"name": "Monedas de oro"}, "amount": 50},
	}
	var report = World.format_inspect_report(
		Vector2i(5, 5),
		Vector2i(50, 50),
		100, 100,
		{}, npcs, ground_items, {}
	)
	# Multi-entity uses "Hay aquí:\n  • ..." and lists every entity.
	assert_string_contains(report, "Hay aquí:")
	assert_string_contains(report, "  • NPC: Lobo (HP 75/150)")
	assert_string_contains(report, "  • Item: Espada Corta")
	assert_string_contains(report, "  • Item: Monedas de oro x50")

func test_self_on_tile_with_others_lists_self_first():
	var npcs = {
		1: {"pos": Vector2i(5, 5), "name": "Lobo", "hp": 50, "max_hp": 100}
	}
	var report = World.format_inspect_report(
		Vector2i(5, 5),
		Vector2i(5, 5),  # self on the same tile
		90, 100,
		{}, npcs, {}, {}
	)
	assert_string_contains(report, "Hay aquí:")
	# Self appears in the report. Order is implementation-defined for
	# other entities, but self should be listed.
	assert_string_contains(report, "Tú (HP 90/100)")
	assert_string_contains(report, "NPC: Lobo (HP 50/100)")

# --- NPC HP fallback ---

func test_npc_without_max_hp_omits_hp_clause():
	var npcs = {
		1: {"pos": Vector2i(5, 5), "name": "Aldeano", "hp": 0, "max_hp": 0}
	}
	var report = World.format_inspect_report(
		Vector2i(5, 5),
		Vector2i(50, 50),
		100, 100,
		{}, npcs, {}, {}
	)
	assert_eq(report, "Aquí: NPC: Aldeano")

# --- Filtering ---

func test_entity_on_other_tile_is_not_listed():
	var npcs = {
		1: {"pos": Vector2i(99, 99), "name": "FarLobo", "hp": 1, "max_hp": 1}
	}
	var report = World.format_inspect_report(
		Vector2i(5, 5),
		Vector2i(50, 50),
		100, 100,
		{}, npcs, {}, {}
	)
	assert_eq(report, "No hay nada aquí.")
