extends Node
# Autoload singleton. Persists decoded ImageTextures across world scene
# lifetimes so re-entering the world (salir → entrar) doesn't re-decode the
# same PNGs. The cache also serves as the destination for the background
# map preloader (added separately).

# Mutex guards both dictionaries so background loaders can write while the
# main thread reads during a render. All public methods are mutex-safe.
var _cache: Dictionary = {}     # cache_key -> ImageTexture
var _missing: Dictionary = {}   # cache_key -> true
var _mutex := Mutex.new()


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
	# True if cache_key is already loaded OR confirmed missing — i.e., no
	# point trying to load it again.
	_mutex.lock()
	var v = _cache.has(cache_key) or _missing.has(cache_key)
	_mutex.unlock()
	return v


func count() -> int:
	_mutex.lock()
	var n = _cache.size()
	_mutex.unlock()
	return n
