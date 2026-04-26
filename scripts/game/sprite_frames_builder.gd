extends Node
## Autoload. Lazy-builds and caches SpriteFrames resources from SpriteCatalog
## entries. One SpriteFrames per (kind, id) — characters reuse the same
## resource across all wearers.
##
## Each SpriteFrames has 4 named animations:
##   walk_south / walk_north / walk_east / walk_west
## Each animation's frames are AtlasTexture instances pointing at
## res://assets/upscaled_2x/<file> with the catalog's region.
## Speed (FPS) = num_frames / (speed_ms / 1000.0), clamped to >= 1
## (a 1-frame static head still needs a positive FPS or play() is unhappy).

const ASSETS_ROOT := "res://assets/upscaled_2x/"

# Per-kind caches: id -> SpriteFrames
var _bodies: Dictionary = {}
var _heads: Dictionary = {}
var _helmets: Dictionary = {}
var _weapons: Dictionary = {}
var _shields: Dictionary = {}

# Texture cache shared across all builds (atlas PNGs are reused heavily).
var _textures: Dictionary = {}   # file_name -> Texture2D


func for_body(id: int) -> SpriteFrames:
	return _get_or_build(_bodies, id, SpriteCatalog.body(id))


func for_head(id: int) -> SpriteFrames:
	return _get_or_build(_heads, id, SpriteCatalog.head(id))


func for_helmet(id: int) -> SpriteFrames:
	return _get_or_build(_helmets, id, SpriteCatalog.helmet(id))


func for_weapon(id: int) -> SpriteFrames:
	return _get_or_build(_weapons, id, SpriteCatalog.weapon(id))


func for_shield(id: int) -> SpriteFrames:
	return _get_or_build(_shields, id, SpriteCatalog.shield(id))


func _get_or_build(cache: Dictionary, id: int, entry) -> SpriteFrames:
	if cache.has(id):
		return cache[id]
	if entry == null or not (entry is Dictionary):
		return null
	var sf := _build(entry)
	if sf == null:
		return null
	cache[id] = sf
	return sf


func _build(entry: Dictionary) -> SpriteFrames:
	var animations = entry.get("animations", null)
	if animations == null or not (animations is Dictionary):
		return null
	var sf := SpriteFrames.new()
	# SpriteFrames ships with a default "default" animation we don't use; remove
	# it to keep the resource tidy.
	if sf.has_animation("default"):
		sf.remove_animation("default")
	for dir_name in ["walk_south", "walk_north", "walk_east", "walk_west"]:
		var anim = animations.get(dir_name, null)
		if anim == null or not (anim is Dictionary):
			# Missing direction — abort the whole entry. Catalog entries should
			# never reach here in this state (parser enforces all 4 dirs); push
			# a warning so it shows up if data drift creeps in.
			push_warning("[sprite_frames_builder] entry missing direction %s — abandoning" % dir_name)
			return null
		var frames: Array = anim.get("frames", [])
		var speed_ms: int = int(anim.get("speed_ms", 0))
		if frames.is_empty():
			push_warning("[sprite_frames_builder] %s has zero frames" % dir_name)
			return null
		sf.add_animation(dir_name)
		sf.set_animation_loop(dir_name, true)
		sf.set_animation_speed(dir_name, _fps_for(frames.size(), speed_ms))
		for frame in frames:
			var tex := _atlas_for(frame)
			if tex == null:
				return null
			sf.add_frame(dir_name, tex)
	return sf


func _fps_for(num_frames: int, speed_ms: int) -> float:
	# Cucsi convention: speed_ms is the duration of the FULL cycle through
	# all frames. So FPS = frames / seconds.
	if speed_ms <= 0:
		return 1.0
	var fps := float(num_frames) / (float(speed_ms) / 1000.0)
	return max(fps, 1.0)


func _atlas_for(frame) -> AtlasTexture:
	if not (frame is Dictionary):
		return null
	var file_name: String = String(frame.get("file", ""))
	if file_name == "":
		return null
	var region_data = frame.get("region", {})
	if not (region_data is Dictionary):
		return null
	var base := _texture_for(file_name)
	if base == null:
		return null
	var atlas := AtlasTexture.new()
	atlas.atlas = base
	atlas.region = Rect2(
		float(region_data.get("x", 0)),
		float(region_data.get("y", 0)),
		float(region_data.get("w", 0)),
		float(region_data.get("h", 0)),
	)
	atlas.filter_clip = true
	return atlas


func _texture_for(file_name: String) -> Texture2D:
	if _textures.has(file_name):
		return _textures[file_name]
	var path := ASSETS_ROOT + file_name
	if not ResourceLoader.exists(path):
		# Defensive — parser is supposed to prevent this.
		push_warning("[sprite_frames_builder] texture not found: %s" % path)
		_textures[file_name] = null
		return null
	var tex: Texture2D = load(path)
	_textures[file_name] = tex
	return tex


func clear_cache() -> void:
	# Useful for tests / hot-reload tools — doesn't ship in production paths.
	_bodies.clear()
	_heads.clear()
	_helmets.clear()
	_weapons.clear()
	_shields.clear()
	_textures.clear()
