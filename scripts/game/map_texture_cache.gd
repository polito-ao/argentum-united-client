extends Node
# Autoload singleton. Persists decoded ImageTextures across world scene
# lifetimes so re-entering the world (salir → entrar) doesn't re-decode the
# same PNGs. Also runs a single background worker thread that preloads
# atlases for maps the player can transition into from their current map
# (via mapaN.json's tile_exits list). This means by the time the player
# walks to an exit tile, the destination map's atlases are already decoded
# and the transition render does ~0 disk I/O.

# Mutex guards both dictionaries so background loaders can write while the
# main thread reads during a render.
var _cache: Dictionary = {}     # cache_key -> ImageTexture
var _missing: Dictionary = {}   # cache_key -> true
var _mutex := Mutex.new()

# Background preloader state.
const MAP_JSON_DIR := "C:/Users/agusp/Documents/GitHub/argentum-united-server/docs/maps/parsed"
const DRAW_LAYERS := [1, 2, 3, 4]
var _preloaded_maps: Dictionary = {}  # map_id -> true (queued OR finished)
var _queue: Array = []                # FIFO of map_ids
var _queue_mutex := Mutex.new()       # guards _queue + _preloaded_maps
var _queue_sem := Semaphore.new()
var _worker: Thread = null
var _shutting_down: bool = false


func _ready() -> void:
	_worker = Thread.new()
	_worker.start(_worker_loop)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		_shutting_down = true
		_queue_sem.post()
		if _worker != null and _worker.is_started():
			_worker.wait_to_finish()


# --- Texture cache (mutex-safe, callable from any thread) ---

func get_cached(cache_key: String) -> Texture2D:
	_mutex.lock()
	var v = _cache.get(cache_key)
	_mutex.unlock()
	return v


func set_cached(cache_key: String, tex: Texture2D) -> void:
	_mutex.lock()
	_cache[cache_key] = tex
	_mutex.unlock()


func is_missing(cache_key: String) -> bool:
	_mutex.lock()
	var v = _missing.has(cache_key)
	_mutex.unlock()
	return v


func mark_missing(cache_key: String) -> void:
	_mutex.lock()
	_missing[cache_key] = true
	_mutex.unlock()


func has_either(cache_key: String) -> bool:
	_mutex.lock()
	var v = _cache.has(cache_key) or _missing.has(cache_key)
	_mutex.unlock()
	return v


func count() -> int:
	_mutex.lock()
	var n = _cache.size()
	_mutex.unlock()
	return n


# --- Background preload queue ---

func queue_preload(map_id: int) -> void:
	# Idempotent: queueing a map that's already preloaded (or queued) is a
	# no-op. Safe to call repeatedly.
	if map_id <= 0:
		return
	_queue_mutex.lock()
	var skip := _preloaded_maps.has(map_id)
	if not skip:
		_preloaded_maps[map_id] = true
		_queue.append(map_id)
	_queue_mutex.unlock()
	if not skip:
		_queue_sem.post()


func mark_already_loaded(map_id: int) -> void:
	# World scene calls this when it just finished rendering map_id, so the
	# bg worker doesn't redundantly try to preload it.
	_queue_mutex.lock()
	_preloaded_maps[map_id] = true
	_queue_mutex.unlock()


# --- Worker thread ---

func _worker_loop() -> void:
	while true:
		_queue_sem.wait()
		if _shutting_down:
			return
		_queue_mutex.lock()
		var map_id := -1
		if not _queue.is_empty():
			map_id = _queue.pop_front()
		_queue_mutex.unlock()
		if map_id < 0:
			continue
		_preload_map(map_id)


func _preload_map(map_id: int) -> void:
	var t0 := Time.get_ticks_msec()
	var path := "%s/mapa%d.json" % [MAP_JSON_DIR, map_id]
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return
	var data: Dictionary = parsed
	var graficos_root := String(data.get("graficos_root", ""))
	var floors_root := String(data.get("floors_root", ""))
	var grh_lookup: Dictionary = data.get("grh_lookup", {})
	var tiles: Array = data.get("tiles", [])
	var to_load: Dictionary = {}
	for layer_num in DRAW_LAYERS:
		for tile in tiles:
			var grh_id: int = int(tile["layer%d" % layer_num])
			if grh_id == 0:
				continue
			var info = grh_lookup.get(str(grh_id))
			if info == null:
				continue
			var file_name := String(info["file"])
			var is_floor: bool = bool(info.get("floor", false))
			var cache_key := ("floor:" + file_name) if is_floor else file_name
			if has_either(cache_key) or to_load.has(cache_key):
				continue
			var root: String = floors_root if is_floor and floors_root != "" else graficos_root
			if root == "":
				mark_missing(cache_key)
				continue
			to_load[cache_key] = "%s/%s" % [root, file_name]
	if to_load.is_empty():
		print("[preload] map %d: nothing new (cache=%d)" % [map_id, count()])
		return
	var keys := to_load.keys()
	var paths := to_load.values()
	var results: Array = []
	results.resize(keys.size())
	var loader := func(idx: int) -> void:
		results[idx] = Image.load_from_file(paths[idx])
	var gid := WorkerThreadPool.add_group_task(
		loader, keys.size(), -1, false, "preload_map_%d" % map_id
	)
	WorkerThreadPool.wait_for_group_task_completion(gid)
	# ImageTexture.create_from_image must run on the main thread (GPU upload).
	# Marshal back via call_deferred — runs next idle frame.
	call_deferred("_apply_preloaded", map_id, keys, paths, results, t0)


func _apply_preloaded(map_id: int, keys: Array, paths: Array, results: Array, t0: int) -> void:
	var loaded := 0
	var failed := 0
	for i in keys.size():
		var img: Image = results[i]
		if img == null:
			mark_missing(keys[i])
			failed += 1
		else:
			set_cached(keys[i], ImageTexture.create_from_image(img))
			loaded += 1
	print("[preload] map %d: +%d atlases (failed %d) in %dms, cache=%d" %
		[map_id, loaded, failed, Time.get_ticks_msec() - t0, count()])
