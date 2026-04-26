class_name PacketIds

# ONLY sacred IDs hardcoded in the client — needed to bootstrap the config fetch.
const CONFIG_REQUEST = 0x0002
const CONFIG_RESPONSE = 0x0003
const DEV_LOGIN = 0x0012 # dev bypass, disappears in production

# All other IDs are mirrored from the server for convenience + client-side lookup,
# but validated against the server's config on boot. Drift = hard error.
const AUTH_REQUEST = 0x0010
const AUTH_RESPONSE = 0x0011

const CHARACTER_LIST_REQUEST = 0x0020
const CHARACTER_LIST_RESPONSE = 0x0021
const CHARACTER_SELECT = 0x0022
const CHARACTER_SELECT_RESPONSE = 0x0023
const CHARACTER_CREATE = 0x0024
const CHARACTER_CREATE_RESPONSE = 0x0025

const MAP_LOAD = 0x0030
const PLAYER_SPAWN = 0x0031
const PLAYER_MOVE = 0x0032
const PLAYER_MOVED = 0x0033
const PLAYER_DESPAWN = 0x0034
const MAP_TRANSITION = 0x0035
const MOVE_REJECTED = 0x0036

const CHAT_SEND = 0x0040
const CHAT_BROADCAST = 0x0041
const CHAT_CLEAR = 0x0042
const SYSTEM_MESSAGE = 0x0043

const ATTACK = 0x0050
const DAMAGE_NUMBER = 0x0051
const MISS = 0x0052
const UPDATE_HP = 0x0053
const CHAR_DEATH = 0x0054
const CAST_SPELL = 0x0055
const UPDATE_MANA = 0x0056
const RESPAWN = 0x0057
const USE_POTION = 0x0058
const ATTACK_NPC = 0x0059

const NPC_SPAWN = 0x0060
const NPC_MOVED = 0x0061
const NPC_DEATH = 0x0062
const NPC_ATTACK = 0x0063
const NPC_RESPAWN = 0x0064
const UPDATE_GOLD = 0x0065
const UPDATE_XP = 0x0066

const INVENTORY_REQUEST = 0x0070
const INVENTORY_RESPONSE = 0x0071
const USE_ITEM = 0x0072
const EQUIP_ITEM = 0x0073
const INVENTORY_UPDATE = 0x0074
const DROP_ITEM = 0x0075
const PICKUP_ITEM = 0x0076
const GROUND_ITEM_SPAWN = 0x0077
const GROUND_ITEM_DESPAWN = 0x0078

const BANK_OPEN = 0x0090
const BANK_CONTENTS = 0x0091
const BANK_DEPOSIT = 0x0092
const BANK_WITHDRAW = 0x0093

const DEV_LIST_REQUEST = 0x00A0
const DEV_LIST_RESPONSE = 0x00A1
const DEV_SPAWN = 0x00A2

const CHEST_SPAWN = 0x00B0
const CHEST_OPEN = 0x00B1
const CHEST_OPENED = 0x00B2
const CHEST_DESPAWN = 0x00B3

const SETTINGS_SAVE = 0x0080
const MEDITATE_TOGGLE = 0x0081
const HIDE_TOGGLE = 0x0082
const EXIT_TO_SELECT = 0x0083
const EXITED_TO_SELECT = 0x0084
const HIDE_STATE_CHANGED = 0x0085

# Called on boot after CONFIG_RESPONSE arrives.
# Errors hard if server's IDs don't match our constants.
static func validate_server_config(server_packet_ids: Dictionary) -> Array:
	var mismatches: Array = []

	# Iterate over all our constants
	for prop in _get_all_constants():
		var our_value = prop.value
		var server_value = server_packet_ids.get(prop.name, null)
		if server_value != null and server_value != our_value:
			mismatches.append({
				"name": prop.name,
				"client": our_value,
				"server": server_value
			})

	return mismatches

# Returns game constants (classes, races) loaded from server
static var classes: Array = []
static var races: Array = []
static var max_character_slots: int = 3
# exp_table[N] = XP needed to advance within level N (index 0 = level 1)
static var exp_table: Array = []
# Full spell catalog from server; client filters by class + level to build a character's spellbook.
static var spells: Array = []

static func load_game_config(config: Dictionary) -> void:
	classes = config.get("classes", [])
	races = config.get("races", [])
	max_character_slots = config.get("max_character_slots", 3)
	exp_table = config.get("exp_table", [])
	spells = config.get("spells", [])

# Spells the character can currently cast (class matches + level >= learn_level).
static func spells_for(class_type: String, level: int) -> Array:
	return spells.filter(func(s):
		return s.get("classes", []).has(class_type) and level >= int(s.get("learn_level", 999))
	)

# XP needed within `level` to reach the next one. Returns 0 if table is empty.
static func xp_for_level(level: int) -> int:
	var idx = level - 1
	if idx < 0 or idx >= exp_table.size():
		return 0
	return int(exp_table[idx])

# Lists all constants in this script via reflection.
# Returns array of { name: String, value: int }.
static func _get_all_constants() -> Array:
	var script = load("res://scripts/network/packet_ids.gd")
	var consts = script.get_script_constant_map()
	return consts.keys().map(func(k): return {"name": k, "value": consts[k]})
