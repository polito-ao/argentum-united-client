extends Node2D

# Ullathorpe tile-render PoC — loads docs/maps/parsed/mapa1.json from the
# server repo and draws each tile as a Sprite2D using AtlasTexture to index
# into sprite sheets in Cucsi's Graficos/ folder.
#
# Paths below are absolute because the source data lives outside this Godot
# project (Cucsi reference drop + sibling server repo). Change them if your
# checkout lives elsewhere, or set env var CUCSI_MAP_JSON / CUCSI_GRAFICOS.
#
# Starts with layer 1 only (ground). Set DRAW_LAYERS to e.g. [1, 2] to add
# overlays. Layer 3/4 (walls/roofs) need z-ordering + character-occlusion
# logic we haven't written yet — see docs/maps/ulla_port_notes.md.

const DEFAULT_MAP_JSON := "C:/Users/agusp/Documents/GitHub/argentum-united-server/docs/maps/parsed/mapa1.json"
const DEFAULT_GRAFICOS := "C:/Users/agusp/Documents/Cucsiii/clientecucsi/Graficos"
const TILE_SIZE := 32
const DRAW_LAYERS := [1]  # add 2, 3, 4 progressively

@onready var tiles_root: Node2D = $Tiles
@onready var camera: Camera2D = $Camera
@onready var status_label: Label = $UI/StatusLabel

var _texture_cache: Dictionary = {}   # file_name -> Texture2D
var _fallback_texture: Texture2D
var _missing_files: Dictionary = {}   # file_name -> true (for diagnostics)


func _ready() -> void:
	_fallback_texture = _make_fallback_texture()
	var map_json := _resolve_path("CUCSI_MAP_JSON", DEFAULT_MAP_JSON)
	var data := _load_json(map_json)
	if data == null:
		_set_status("Failed to load %s" % map_json)
		return

	var width: int = int(data.get("width", 100))
	var height: int = int(data.get("height", 100))
	camera.position = Vector2(width * TILE_SIZE / 2.0, height * TILE_SIZE / 2.0)

	var grh_lookup: Dictionary = data["grh_lookup"]
	var tiles: Array = data["tiles"]
	var drawn := 0
	var fallbacks := 0
	for tile in tiles:
		for layer_num in DRAW_LAYERS:
			var grh_id: int = int(tile["layer%d" % layer_num])
			if grh_id == 0:
				continue
			var info = grh_lookup.get(str(grh_id))
			var texture := _get_atlas_texture(info) if info != null else null
			if texture == null:
				texture = _fallback_texture
				fallbacks += 1
			var sprite := Sprite2D.new()
			sprite.centered = false
			sprite.texture = texture
			sprite.position = Vector2(
				(tile["x"] - 1) * TILE_SIZE,
				(tile["y"] - 1) * TILE_SIZE
			)
			sprite.z_index = layer_num
			tiles_root.add_child(sprite)
			drawn += 1

	_set_status("Ulla: %d tiles drawn, %d fallbacks (%d unique missing PNGs)"
		% [drawn, fallbacks, _missing_files.size()])
	if _missing_files.size() > 0:
		print("[ulla_preview] missing files (first 10): ",
			_missing_files.keys().slice(0, 10))


func _process(_delta: float) -> void:
	# Simple pan with arrow keys / WASD, zoom with +/-
	var pan := Vector2.ZERO
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		pan.x -= 1
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		pan.x += 1
	if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W):
		pan.y -= 1
	if Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S):
		pan.y += 1
	if pan != Vector2.ZERO:
		camera.position += pan * 300.0 * _delta / max(camera.zoom.x, 0.1)

	if Input.is_action_just_pressed("ui_page_up") or Input.is_key_pressed(KEY_EQUAL):
		camera.zoom *= 1.05
	if Input.is_action_just_pressed("ui_page_down") or Input.is_key_pressed(KEY_MINUS):
		camera.zoom *= 0.95


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	var text := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}


func _get_atlas_texture(info: Dictionary) -> Texture2D:
	var file_name := String(info["file"])
	if _missing_files.has(file_name):
		return null
	if not _texture_cache.has(file_name):
		var graficos_root := _resolve_path("CUCSI_GRAFICOS", DEFAULT_GRAFICOS)
		var img_path := "%s/%s" % [graficos_root, file_name]
		var img := Image.load_from_file(img_path)
		if img == null:
			_missing_files[file_name] = true
			return null
		_texture_cache[file_name] = ImageTexture.create_from_image(img)
	var atlas := AtlasTexture.new()
	atlas.atlas = _texture_cache[file_name]
	atlas.region = Rect2(
		int(info["sx"]), int(info["sy"]),
		int(info["w"]),  int(info["h"])
	)
	return atlas


func _make_fallback_texture() -> Texture2D:
	var img := Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGB8)
	img.fill(Color.MAGENTA)
	return ImageTexture.create_from_image(img)


func _resolve_path(env_var: String, default_path: String) -> String:
	var env_val := OS.get_environment(env_var)
	return env_val if env_val != "" else default_path


func _set_status(msg: String) -> void:
	if is_instance_valid(status_label):
		status_label.text = msg
	print("[ulla_preview] ", msg)
