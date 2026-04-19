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

const DEFAULT_MAP_JSON := "C:/Users/agusp/Documents/GitHub/argentum-united-server/docs/maps/parsed/room64_demo.json"
const DEFAULT_GRAFICOS := "C:/Users/agusp/Documents/Cucsiii/clientecucsi/Graficos"
const TILE_SIZE := 32
const DRAW_LAYERS := [1, 2, 3, 4]  # PoC has no characters; full compositing is safe

@onready var tiles_root: Node2D = $Tiles
@onready var camera: Camera2D = $Camera
@onready var status_label: Label = $UI/StatusLabel

var _texture_cache: Dictionary = {}   # file_name -> Texture2D
var _fallback_texture: Texture2D
var _missing_files: Dictionary = {}   # file_name -> true (for diagnostics)
var _tiles_by_pos: Dictionary = {}    # Vector2i(x0, y0) -> tile dict (for click-inspect)
var _show_grid: bool = true
var _grid_w: int = 100
var _grid_h: int = 100


func _ready() -> void:
	# Keep self's _draw (gridlines) above tiles. tiles_root's children have
	# z_index 1..4; setting self.z_index=10 and decoupling tiles_root from
	# parent z makes sprites stay at absolute z=1..4 while the grid draws
	# at z=10 on top.
	z_index = 10
	_fallback_texture = _make_fallback_texture()
	tiles_root.z_as_relative = false  # sprites stay at absolute z=1..4
	# Pitch-black viewport so GRH=0 void pockets (and out-of-map area) render
	# solid black instead of the default clear color. Scoped to this preview.
	RenderingServer.set_default_clear_color(Color.BLACK)
	var map_json := _resolve_path("CUCSI_MAP_JSON", DEFAULT_MAP_JSON)
	var data := _load_json(map_json)
	if data == null:
		_set_status("Failed to load %s" % map_json)
		return

	var width: int = int(data.get("width", 100))
	var height: int = int(data.get("height", 100))
	_grid_w = width
	_grid_h = height
	camera.position = Vector2(width * TILE_SIZE / 2.0, height * TILE_SIZE / 2.0)

	var grh_lookup: Dictionary = data["grh_lookup"]
	var tiles: Array = data["tiles"]
	var drawn := 0
	var fallbacks := 0
	for tile in tiles:
		_tiles_by_pos[Vector2i(int(tile["x"]) - 1, int(tile["y"]) - 1)] = tile
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
			# Cucsi anchor convention: bottom-CENTER of the sprite sits on the
			# tile's bottom-center. Tall sprites rise into lower-y tiles; wide
			# sprites straddle the tile horizontally. For 32x32 both adjustments
			# are zero.
			var sprite_w: int = int(info["w"]) if info != null else TILE_SIZE
			var sprite_h: int = int(info["h"]) if info != null else TILE_SIZE
			sprite.position = Vector2(
				(tile["x"] - 1) * TILE_SIZE - (sprite_w - TILE_SIZE) / 2,
				(tile["y"] - 1) * TILE_SIZE - (sprite_h - TILE_SIZE)
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


func _draw() -> void:
	if not _show_grid:
		return
	var w := _grid_w * TILE_SIZE
	var h := _grid_h * TILE_SIZE
	var color := Color(1, 1, 1, 0.15)
	# z_index default 0; layers use 1..4, so grid sits under tiles unless we
	# bump z_as_relative/ordering. For now, thin semi-transparent lines read
	# well enough on top of most tile art.
	for i in range(_grid_w + 1):
		draw_line(Vector2(i * TILE_SIZE, 0), Vector2(i * TILE_SIZE, h), color, 1.0)
	for i in range(_grid_h + 1):
		draw_line(Vector2(0, i * TILE_SIZE), Vector2(w, i * TILE_SIZE), color, 1.0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_G:
		_show_grid = not _show_grid
		queue_redraw()
		return
	if not (event is InputEventMouseButton and event.pressed
		and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var world_pos := get_global_mouse_position()
	var tx := int(floor(world_pos.x / TILE_SIZE))
	var ty := int(floor(world_pos.y / TILE_SIZE))
	var tile = _tiles_by_pos.get(Vector2i(tx, ty))
	if tile == null:
		_set_status("clicked outside map")
		return
	var msg := "tile (%d,%d)" % [tx + 1, ty + 1]
	for layer_num in [1, 2, 3, 4]:
		var grh := int(tile.get("layer%d" % layer_num, 0))
		if grh != 0:
			msg += "  L%d=Grh%d" % [layer_num, grh]
	if tile.get("blocked", false):
		msg += "  BLOCKED"
	_set_status(msg)


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
		_color_key_black_to_alpha(img)
		_texture_cache[file_name] = ImageTexture.create_from_image(img)
	var atlas := AtlasTexture.new()
	atlas.atlas = _texture_cache[file_name]
	atlas.region = Rect2(
		int(info["sx"]), int(info["sy"]),
		int(info["w"]),  int(info["h"])
	)
	return atlas


func _color_key_black_to_alpha(img: Image) -> void:
	# Cucsi PNGs use pure (0,0,0) as the color-key for transparency rather
	# than an alpha channel. Convert to RGBA8 and zero-alpha any pure-black
	# pixel so wall interiors stop rendering as solid black rectangles.
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	for y in range(h):
		for x in range(w):
			var c := img.get_pixel(x, y)
			if c.r == 0.0 and c.g == 0.0 and c.b == 0.0:
				img.set_pixel(x, y, Color(0, 0, 0, 0))


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
