extends Node
## Audio manifest autoload — loads the audio manifest JSON and provides
## lookup functions matching AudioManager.ts and EnvironmentalAudioManager.ts.
## Registered as an autoload singleton in project.godot.

var _manifest: Dictionary = {}
var _loaded := false

func _ready() -> void:
	_load_manifest()

func _load_manifest() -> void:
	var path := "res://data/audio_manifest.json"
	if not FileAccess.file_exists(path):
		# Try loading from assets directory
		path = "res://assets/audio/manifest.json"
		if not FileAccess.file_exists(path):
			push_warning("[AudioManifest] No audio manifest found")
			return

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("[AudioManifest] Failed to open audio manifest")
		return

	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()

	if err != OK:
		push_warning("[AudioManifest] Failed to parse audio manifest: " + json.get_error_message())
		return

	_manifest = json.data if json.data is Dictionary else {}
	_loaded = true
	print("[Insimul] AudioManifest: loaded (%d world types)" % _manifest.size())

func is_loaded() -> bool:
	return _loaded

## Get audio entries for a specific world type and role.
## Returns Array of Dictionaries with "path" and "name" keys.
func get_audio(world_type: String, role: String) -> Array:
	var world_data: Dictionary = _manifest.get(world_type, {})
	if world_data.is_empty():
		world_data = _manifest.get("generic", {})
	return world_data.get(role, [])

## Get ambient audio for the given world type.
func get_ambient(world_type: String) -> Array:
	return get_audio(world_type, "ambient")

## Get footstep audio for the given world type.
func get_footsteps(world_type: String) -> Array:
	return get_audio(world_type, "footstep")

## Get effect/interaction audio for the given world type.
func get_effects(world_type: String) -> Array:
	return get_audio(world_type, "effects")

## Get voice audio for the given world type.
func get_voices(world_type: String) -> Array:
	return get_audio(world_type, "voices")

## Load an AudioStream from the manifest by world type and role.
## Returns null if not found or failed to load.
func load_audio_stream(world_type: String, role: String, index: int = 0) -> AudioStream:
	var entries := get_audio(world_type, role)
	if index >= entries.size():
		return null

	var entry: Dictionary = entries[index]
	var path: String = entry.get("path", "")
	if path == "":
		return null

	var full_path := "res://assets/audio/" + path
	if not ResourceLoader.exists(full_path):
		full_path = "res://" + path

	if ResourceLoader.exists(full_path):
		return load(full_path) as AudioStream

	return null

## Get all available world types in the manifest.
func get_world_types() -> PackedStringArray:
	return PackedStringArray(_manifest.keys())

## Get all available roles for a world type.
func get_roles(world_type: String) -> PackedStringArray:
	var world_data: Dictionary = _manifest.get(world_type, {})
	return PackedStringArray(world_data.keys())
