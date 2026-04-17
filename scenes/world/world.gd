extends Node2D

const TILE_SIZE = 32

var connection: ServerConnection
var my_pos: Vector2i = Vector2i(50, 50)
var my_heading: String = "south"
var map_id: int = 1
var map_size: Vector2i = Vector2i(100, 100)

var players: Dictionary = {}  # id -> { pos: Vector2i, name: String, node: Node2D }
var npcs: Dictionary = {}     # id -> { pos: Vector2i, name: String, hp: int, max_hp: int, node: Node2D }

@onready var camera: Camera2D = $Camera
@onready var player_sprite: Node2D = $PlayerSprite
@onready var entities_layer: Node2D = $Entities
@onready var hud: Control = $UILayer/HUD
@onready var hp_bar: ProgressBar = $UILayer/HUD/VBoxContainer/HPBar
@onready var mp_bar: ProgressBar = $UILayer/HUD/VBoxContainer/MPBar
@onready var info_label: Label = $UILayer/HUD/VBoxContainer/InfoLabel
@onready var chat_display: RichTextLabel = $UILayer/HUD/ChatPanel/ChatDisplay
@onready var chat_input: LineEdit = $UILayer/HUD/ChatPanel/ChatInput
@onready var messages_label: Label = $UILayer/HUD/MessagesLabel

var _messages: Array = []
var _is_dead: bool = false
const MAX_MESSAGES = 6

func setup(conn: ServerConnection, select_payload: Dictionary, map_data: Dictionary):
	connection = conn
	connection.packet_received.connect(_on_packet_received)

	map_id = map_data.get("map_id", 1)
	my_pos = Vector2i(map_data.get("x", 50), map_data.get("y", 50))
	map_size = Vector2i(map_data.get("width", 100), map_data.get("height", 100))

	var character = select_payload.get("character", {})
	var state = select_payload.get("state", {})

	info_label.text = "%s (%s %s Lv%d)" % [
		character.get("name", "?"),
		character.get("class", "?"),
		character.get("race", "?"),
		character.get("level", 1)
	]

	$PlayerSprite/NameLabel.text = character.get("name", "You")

	# Initialize HP/MP bars from state snapshot
	hp_bar.max_value = state.get("max_hp", 100)
	hp_bar.value = state.get("hp", 100)
	mp_bar.max_value = state.get("max_mana", 100)
	mp_bar.value = state.get("mana", 0)

	# Restore death state if character logged in dead
	if not state.get("alive", true):
		_is_dead = true
		_add_message("You are a ghost. Press SPACE to respawn.")

	_update_player_position()

func _ready():
	chat_input.text_submitted.connect(_on_chat_submitted)

func _update_player_position():
	player_sprite.position = Vector2(my_pos.x * TILE_SIZE, my_pos.y * TILE_SIZE)
	camera.position = player_sprite.position

var _move_cooldown: float = 0.0
const MOVE_INTERVAL: float = 0.15  # seconds between steps when holding arrow

func _process(delta):
	if _move_cooldown > 0:
		_move_cooldown -= delta

	if chat_input.has_focus():
		return

	if _move_cooldown <= 0:
		if Input.is_key_pressed(KEY_UP):
			my_heading = "north"
			_send_move(0, -1)
			_move_cooldown = MOVE_INTERVAL
		elif Input.is_key_pressed(KEY_DOWN):
			my_heading = "south"
			_send_move(0, 1)
			_move_cooldown = MOVE_INTERVAL
		elif Input.is_key_pressed(KEY_RIGHT):
			my_heading = "east"
			_send_move(1, 0)
			_move_cooldown = MOVE_INTERVAL
		elif Input.is_key_pressed(KEY_LEFT):
			my_heading = "west"
			_send_move(-1, 0)
			_move_cooldown = MOVE_INTERVAL

func _input(event):
	if chat_input.has_focus():
		return

	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_CTRL:
				_attack_facing()
			KEY_R:
				connection.send_packet(PacketIds.USE_POTION, {"hp": 150})
				_add_message("HP potion!")
			KEY_B:
				connection.send_packet(PacketIds.USE_POTION, {"mana": 300})
				_add_message("Mana potion!")
			KEY_T:
				chat_input.grab_focus()
				chat_input.text = "" # prevent the 'T' from appearing
				get_viewport().set_input_as_handled()
			KEY_I:
				connection.send_packet(PacketIds.INVENTORY_REQUEST)
			KEY_SPACE:
				if _is_dead:
					connection.send_packet(PacketIds.RESPAWN)
					_add_message("Respawning...")

func _send_move(dx: int, dy: int):
	var new_x = my_pos.x + dx
	var new_y = my_pos.y + dy

	# Client-side prediction: refuse to move optimistically if we know it's invalid
	if new_x < 0 or new_y < 0 or new_x >= map_size.x or new_y >= map_size.y:
		_update_player_sprite() # still update facing
		return

	# Check if target tile has an NPC (clients knows NPC positions)
	for npc_id in npcs:
		if npcs[npc_id].pos == Vector2i(new_x, new_y):
			_update_player_sprite() # face it, don't move
			return

	# Check if target tile has another alive player
	for player_id in players:
		if players[player_id].pos == Vector2i(new_x, new_y):
			_update_player_sprite()
			return

	connection.send_packet(PacketIds.PLAYER_MOVE, {"x": new_x, "y": new_y})
	my_pos = Vector2i(new_x, new_y)
	_update_player_position()
	_update_player_sprite()

func _attack_facing():
	var facing = _facing_offset()
	var target_pos = my_pos + facing

	# Find NPC at faced tile
	for npc_id in npcs:
		var npc = npcs[npc_id]
		if npc.pos == target_pos:
			connection.send_packet(PacketIds.ATTACK_NPC, {"npc_id": npc_id})
			_add_message("Attacking %s!" % npc.name)
			return

	# Find player at faced tile
	for player_id in players:
		var player = players[player_id]
		if player.pos == target_pos:
			connection.send_packet(PacketIds.ATTACK, {"target_id": player_id})
			_add_message("Attacking %s!" % player.name)
			return

	_add_message("Nothing to attack")

func _facing_offset() -> Vector2i:
	match my_heading:
		"north": return Vector2i(0, -1)
		"south": return Vector2i(0, 1)
		"east":  return Vector2i(1, 0)
		"west":  return Vector2i(-1, 0)
	return Vector2i(0, 1)

func _update_player_sprite():
	# Simple facing indicator using Label for now
	var arrow = {"north": "^", "south": "v", "east": ">", "west": "<"}
	$PlayerSprite/FacingLabel.text = arrow.get(my_heading, "v")

func _on_chat_submitted(text: String):
	if text.strip_edges().is_empty():
		connection.send_packet(PacketIds.CHAT_SEND, {"message": ""})
	else:
		connection.send_packet(PacketIds.CHAT_SEND, {"message": text})
	chat_input.text = ""
	chat_input.release_focus()

func _add_message(msg: String):
	_messages.append(msg)
	while _messages.size() > MAX_MESSAGES:
		_messages.pop_front()
	messages_label.text = "\n".join(_messages)

func _on_packet_received(packet_id: int, payload: Dictionary):
	match packet_id:
		PacketIds.PLAYER_SPAWN:
			_handle_player_spawn(payload)
		PacketIds.PLAYER_MOVED:
			_handle_player_moved(payload)
		PacketIds.PLAYER_DESPAWN:
			_handle_player_despawn(payload)
		PacketIds.NPC_SPAWN, PacketIds.NPC_RESPAWN:
			_handle_npc_spawn(payload)
		PacketIds.NPC_DEATH:
			_handle_npc_death(payload)
		PacketIds.NPC_ATTACK:
			_add_message("%s hits you for %d!" % [
				npcs.get(payload.get("npc_id", 0), {}).get("name", "NPC"),
				payload.get("damage", 0)
			])
		PacketIds.MAP_TRANSITION:
			_handle_map_transition(payload)
		PacketIds.MOVE_REJECTED:
			# Server rejected our optimistic move — revert to authoritative position
			my_pos = Vector2i(payload.get("x", my_pos.x), payload.get("y", my_pos.y))
			_update_player_position()
		PacketIds.DAMAGE_NUMBER:
			_handle_damage(payload)
		PacketIds.MISS:
			_add_message("MISS!")
		PacketIds.UPDATE_HP:
			hp_bar.value = payload.get("hp", 0)
			hp_bar.max_value = payload.get("max_hp", 1)
			if payload.get("hp", 0) > 0 and _is_dead:
				_is_dead = false
				_add_message("You have respawned!")
		PacketIds.UPDATE_MANA:
			mp_bar.value = payload.get("mana", 0)
			mp_bar.max_value = payload.get("max_mana", 1)
		PacketIds.CHAR_DEATH:
			_add_message("YOU DIED! Press SPACE to respawn")
			_is_dead = true
		PacketIds.CHAT_BROADCAST:
			var from_name = payload.get("from_name", null)
			var from_id = payload.get("from_id", null)
			var msg = payload.get("message", "")
			if from_name == null:
				from_name = "?"
			chat_display.append_text("[%s]: %s\n" % [from_name, msg])
			# Show bubble above the speaker
			_show_chat_bubble(from_id, msg)
		PacketIds.INVENTORY_RESPONSE:
			_handle_inventory(payload)
		_:
			push_error("DRIFT or MALICIOUS: unknown packet_id 0x%04x" % packet_id)

func _handle_player_spawn(payload: Dictionary):
	var id = payload.get("id", 0)
	var pos = Vector2i(payload.get("x", 0), payload.get("y", 0))
	var char_name = payload.get("character", {}).get("name", "?")

	var node = _create_entity_node(char_name, Color.CYAN)
	node.position = Vector2(pos.x * TILE_SIZE, pos.y * TILE_SIZE)
	entities_layer.add_child(node)

	players[id] = {"pos": pos, "name": char_name, "node": node}
	_add_message("%s appeared" % char_name)

func _handle_player_moved(payload: Dictionary):
	var id = payload.get("id", 0)
	if id in players:
		var pos = Vector2i(payload.get("x", 0), payload.get("y", 0))
		players[id].pos = pos
		players[id].node.position = Vector2(pos.x * TILE_SIZE, pos.y * TILE_SIZE)

func _handle_player_despawn(payload: Dictionary):
	var id = payload.get("id", 0)
	if id in players:
		_add_message("%s left" % players[id].name)
		players[id].node.queue_free()
		players.erase(id)

func _handle_npc_spawn(payload: Dictionary):
	var id = payload.get("npc_id", 0)
	var pos = Vector2i(payload.get("x", 0), payload.get("y", 0))
	var npc_name = payload.get("name", "NPC")
	var hp = payload.get("hp", 0)
	var max_hp = payload.get("max_hp", 0)

	# Remove existing if respawn
	if id in npcs and npcs[id].has("node"):
		npcs[id].node.queue_free()

	var node = _create_entity_node(npc_name, Color.RED)
	node.position = Vector2(pos.x * TILE_SIZE, pos.y * TILE_SIZE)
	entities_layer.add_child(node)

	npcs[id] = {"pos": pos, "name": npc_name, "hp": hp, "max_hp": max_hp, "node": node}

func _handle_npc_death(payload: Dictionary):
	var id = payload.get("npc_id", 0)
	if id in npcs:
		_add_message("%s died!" % npcs[id].name)
		npcs[id].node.queue_free()
		npcs.erase(id)

func _handle_map_transition(payload: Dictionary):
	map_id = payload.get("map_id", 1)
	my_pos = Vector2i(payload.get("x", 50), payload.get("y", 50))
	map_size = Vector2i(payload.get("width", 100), payload.get("height", 100))

	# Clear all entities
	for id in players:
		players[id].node.queue_free()
	players.clear()
	for id in npcs:
		npcs[id].node.queue_free()
	npcs.clear()

	_update_player_position()
	_add_message("Map %d (%dx%d)" % [map_id, map_size.x, map_size.y])

func _handle_damage(payload: Dictionary):
	var dmg = payload.get("damage", 0)
	var type = payload.get("type", "")
	var xp = payload.get("xp", 0)
	var gold = payload.get("gold", 0)

	if type == "gold":
		_add_message("+%d gold" % gold)
	elif dmg < 0:
		_add_message("Healed %d HP" % (-dmg))
	else:
		var msg = "%d %s damage" % [dmg, type]
		if xp > 0:
			msg += " [+%d XP]" % xp
		_add_message(msg)

func _handle_inventory(payload: Dictionary):
	var items = payload.get("items", [])
	if items.is_empty():
		_add_message("Inventory: empty")
	else:
		for item in items:
			var eq = " [E]" if item.get("equipped", false) else ""
			_add_message("  %s x%d%s" % [item.get("name", "?"), item.get("amount", 0), eq])

func _show_chat_bubble(from_id, msg: String):
	var target_node: Node2D = null

	if from_id == null:
		return

	# Check if it's us
	if from_id is int or from_id is float:
		# Check players
		if int(from_id) in players:
			target_node = players[int(from_id)].node

	if target_node == null:
		# It's our own message — show on player sprite
		target_node = player_sprite

	# Remove existing bubble if any
	var existing = target_node.get_node_or_null("ChatBubble")
	if existing:
		existing.queue_free()

	var bubble = Label.new()
	bubble.name = "ChatBubble"
	bubble.text = msg
	bubble.position = Vector2(0, -32)
	bubble.add_theme_font_size_override("font_size", 10)
	bubble.add_theme_color_override("font_color", Color.WHITE)
	target_node.add_child(bubble)

	# Auto-remove after 3 seconds
	get_tree().create_timer(3.0).timeout.connect(func():
		if is_instance_valid(bubble):
			bubble.queue_free()
	)

func _create_entity_node(entity_name: String, color: Color) -> Node2D:
	var node = Node2D.new()

	var rect = ColorRect.new()
	rect.size = Vector2(TILE_SIZE - 2, TILE_SIZE - 2)
	rect.position = Vector2(1, 1)
	rect.color = color
	node.add_child(rect)

	var label = Label.new()
	label.text = entity_name
	label.position = Vector2(-30, 34)
	label.size = Vector2(92, 16)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 10)
	node.add_child(label)

	return node
