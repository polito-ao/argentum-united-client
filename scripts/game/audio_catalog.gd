extends Node

## AudioCatalog — autoload that lazily resolves Cucsi audio ids into
## Godot AudioStream resources.
##
## The audio assets live under `res://assets/audio/` and are NOT committed
## (see CLAUDE.md + assets/audio/README.md -- mirror of the upscaled_2x
## pattern). Devs run `python tools/convert_cucsi_audio.py` once to
## populate the tree, or pull a tarball from Drive.
##
## Defensive contract: if a file is missing on disk, return null and emit
## a one-shot warning per id. Callers MUST handle null gracefully so the
## game stays playable in silent mode while assets propagate.
##
## Caching: streams are loaded once and stashed in a Dictionary keyed by
## resource path. The autoload lives for the whole process lifetime, so
## the cache survives scene changes -- same lifetime story as
## MapTextureCache + SpriteCatalog.

const MUSIC_DIR := "res://assets/audio/music/"
const SFX_DIR := "res://assets/audio/sfx/"
const THEMES_DIR := "res://assets/audio/themes/"

# Theme name -> MP3 id. Picked from the 11 available themes (1.mp3 .. 11.mp3).
# Names are stable client-side identifiers; if we ever map to server-driven
# themes, this is the swap-in point. Pinning 1 -> login, 2 -> character_select
# is documented in the PR body.
const THEME_IDS := {
	"login": 1,
	"character_select": 2,
}

# id -> AudioStream. Negative or null cached entries mean "we tried, file
# was missing, don't spam the log again".
var _cache: Dictionary = {}
var _warned_missing: Dictionary = {}


func sfx(wav_id: int) -> AudioStream:
	return _load("%s%d.wav" % [SFX_DIR, wav_id], wav_id, "sfx")


func music(music_id: int) -> AudioStream:
	return _load("%s%d.ogg" % [MUSIC_DIR, music_id], music_id, "music")


# Themes are loaded by symbolic name; the name -> mp3 id mapping is
# stable client-side. Returns null if the name is unknown OR the
# underlying file is missing.
func theme(name: String) -> AudioStream:
	if not THEME_IDS.has(name):
		_warn_once("theme:" + name, "AudioCatalog.theme(\"%s\") -- unknown theme name" % name)
		return null
	var mp3_id: int = int(THEME_IDS[name])
	return _load("%s%d.mp3" % [THEMES_DIR, mp3_id], mp3_id, "theme")


# Test helper: clears warning + cache state so a single test run can
# reassert the "warns once" behavior. Production code should never call this.
func _reset_for_tests() -> void:
	_cache.clear()
	_warned_missing.clear()


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
