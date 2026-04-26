extends Node
## Autoload. Loads the 5 sprite catalogs (bodies, heads, helmets, weapons,
## shields) emitted by tools/parse_cucsi_graphics.py at boot. Catalogs live
## as YAML (canonical, human-edited) plus a JSON sibling we actually load
## here — Godot 4.6 has no YAML parser and a custom one isn't worth the
## risk for a static data file the tool already emits.
##
## Each entry shape:
##   bodies:  { head_offset: {x,y}, animations: {walk_<dir>: {frames, speed_ms}} }
##   others:  { animations: {walk_<dir>: {frames, speed_ms}} }
##   frame:   { file: "<n>.png", region: {x, y, w, h} }
##
## All pixel coords are pre-doubled by the parser; consume them as-is.

const DATA_DIR := "res://assets/sprite_data/"

var _bodies: Dictionary = {}
var _heads: Dictionary = {}
var _helmets: Dictionary = {}
var _weapons: Dictionary = {}
var _shields: Dictionary = {}

var _loaded: bool = false


func _ready() -> void:
	load_catalogs()


func load_catalogs() -> void:
	_bodies = _load_one("bodies")
	_heads = _load_one("heads")
	_helmets = _load_one("helmets")
	_weapons = _load_one("weapons")
	_shields = _load_one("shields")
	_loaded = true
	print("[sprite_catalog] bodies=%d heads=%d helmets=%d weapons=%d shields=%d" %
		[_bodies.size(), _heads.size(), _helmets.size(), _weapons.size(), _shields.size()])


func _load_one(name: String) -> Dictionary:
	var path := DATA_DIR + name + ".json"
	if not FileAccess.file_exists(path):
		push_warning("[sprite_catalog] missing %s — run tools/parse_cucsi_graphics.py" % path)
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("[sprite_catalog] cannot open %s" % path)
		return {}
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_warning("[sprite_catalog] %s did not parse to a Dictionary" % path)
		return {}
	return parsed


# --- Public API ---------------------------------------------------------------

func body(id: int):
	return _bodies.get("body_%d" % id, null)


func head(id: int):
	return _heads.get("head_%d" % id, null)


func helmet(id: int):
	return _helmets.get("helmet_%d" % id, null)


func weapon(id: int):
	return _weapons.get("weapon_%d" % id, null)


func shield(id: int):
	return _shields.get("shield_%d" % id, null)


func is_loaded() -> bool:
	return _loaded
