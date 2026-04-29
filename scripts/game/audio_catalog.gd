extends Node

## AudioCatalog — autoload that lazily resolves Cucsi audio ids into
## Godot AudioStream resources for SFX.
##
## Music is owned separately by MusicDirector (which loads from
## `assets/audio/music_curated/` directly). The legacy auto-rendered
## `assets/audio/music/<id>.ogg` and `assets/audio/themes/<id>.mp3`
## paths are no longer played -- removed alongside this autoload's
## music + theme APIs.
##
## The audio assets live under `res://assets/audio/sfx/` and are NOT
## committed (see CLAUDE.md + assets/audio/README.md -- mirror of the
## upscaled_2x pattern). Devs run `python tools/convert_cucsi_audio.py`
## once to populate the tree, or pull a tarball from Drive.
##
## Defensive contract: if a file is missing on disk, return null and emit
## a one-shot warning per id. Callers MUST handle null gracefully so the
## game stays playable in silent mode while assets propagate.
##
## Caching: streams are loaded once and stashed in a Dictionary keyed by
## resource path. The autoload lives for the whole process lifetime, so
## the cache survives scene changes -- same lifetime story as
## MapTextureCache + SpriteCatalog.

const SFX_DIR := "res://assets/audio/sfx/"

# Curated SFX live in a parallel tree under `assets/audio/sfx_curated/`,
# tracked in git (vs. the auto-generated `sfx/` tree which is gitignored).
# The server addresses these by `wav_name` (string) instead of `wav_id`
# (int). We auto-probe extensions in order so recordings can ship in
# whatever format the source happens to be in.
const CURATED_SFX_BASE := "res://assets/audio/sfx_curated/"
const CURATED_SFX_EXTENSIONS := [".wav", ".mp3", ".flac", ".ogg"]

# id -> AudioStream. Negative or null cached entries mean "we tried, file
# was missing, don't spam the log again".
var _cache: Dictionary = {}
var _warned_missing: Dictionary = {}
# wav_name (String) -> AudioStream (or null for "tried, missing"). Same
# warn-once semantics as `_cache` but keyed by name rather than path so
# repeated probes across the four extensions don't re-walk the disk.
var _curated_cache: Dictionary = {}


func sfx(wav_id: int) -> AudioStream:
	return _load("%s%d.wav" % [SFX_DIR, wav_id], wav_id, "sfx")


# Resolve a curated SFX by name. Tries each extension in CURATED_SFX_EXTENSIONS
# in order until one exists, caches the result (including the null miss),
# and warns once if nothing resolves. Empty name returns null silently --
# callers (e.g. PLAY_SFX dispatch) use empty-string to mean "fall back to
# wav_id" so we don't want to spam warnings for that path.
func sfx_curated(wav_name: String) -> AudioStream:
	if wav_name.is_empty():
		return null
	if _curated_cache.has(wav_name):
		return _curated_cache[wav_name]
	for ext in CURATED_SFX_EXTENSIONS:
		var path: String = CURATED_SFX_BASE + wav_name + ext
		if ResourceLoader.exists(path):
			var stream = load(path)
			if stream != null and stream is AudioStream:
				_curated_cache[wav_name] = stream
				return stream
	push_warning("AudioCatalog: no curated SFX for '%s' (tried %s)" % [wav_name, ", ".join(CURATED_SFX_EXTENSIONS)])
	_curated_cache[wav_name] = null
	return null


# Test helper: clears warning + cache state so a single test run can
# reassert the "warns once" behavior. Production code should never call this.
func _reset_for_tests() -> void:
	_cache.clear()
	_warned_missing.clear()
	_curated_cache.clear()


# --- private ---------------------------------------------------------------

func _load(path: String, id: int, kind: String) -> AudioStream:
	if _cache.has(path):
		return _cache[path]

	if not ResourceLoader.exists(path):
		_warn_once(path, "AudioCatalog: missing %s id=%d at %s" % [kind, id, path])
		_cache[path] = null
		return null

	var stream = load(path)
	if stream == null or not (stream is AudioStream):
		_warn_once(path, "AudioCatalog: %s id=%d at %s did not load as AudioStream" % [kind, id, path])
		_cache[path] = null
		return null

	_cache[path] = stream
	return stream


func _warn_once(key: String, msg: String) -> void:
	if _warned_missing.has(key):
		return
	_warned_missing[key] = true
	push_warning(msg)
