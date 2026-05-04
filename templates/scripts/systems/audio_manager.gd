extends Node
## Audio Manager — autoloaded singleton.
## Manages ambient soundscapes, footstep audio, and UI sounds.
## Loads audio from res://assets/audio/ if available, gracefully degrades if not.

## Audio bus layout
const BUS_AMBIENT := "Ambient"
const BUS_SFX := "SFX"
const BUS_MUSIC := "Music"

## Footstep timing
const FOOTSTEP_INTERVAL := 0.4  # seconds between steps while walking
const FOOTSTEP_RUN_INTERVAL := 0.28

## Ambient layer crossfade
const CROSSFADE_DURATION := 3.0

var _ambient_player: AudioStreamPlayer = null
var _music_player: AudioStreamPlayer = null
var _footstep_player: AudioStreamPlayer = null
var _ui_player: AudioStreamPlayer = null

var _footstep_timer := 0.0
var _is_walking := false
var _is_running := false
var _player: Node3D = null

var _ambient_streams: Dictionary = {}  # time_of_day → AudioStream
var _footstep_streams: Dictionary = {}  # surface_type → AudioStream
var _ui_streams: Dictionary = {}  # action → AudioStream
var _current_ambient_key := ""

## Master volume (0-1)
var master_volume := 1.0
var ambient_volume := 0.5
var sfx_volume := 0.7
var music_volume := 0.4

func _ready() -> void:
	_create_players()
	_load_audio_assets()

func _process(delta: float) -> void:
	_update_footsteps(delta)
	_update_ambient()

# ─────────────────────────────────────────────
# Audio player setup
# ─────────────────────────────────────────────

func _create_players() -> void:
	_ambient_player = AudioStreamPlayer.new()
	_ambient_player.name = "AmbientPlayer"
	_ambient_player.volume_db = linear_to_db(ambient_volume)
	add_child(_ambient_player)

	_music_player = AudioStreamPlayer.new()
	_music_player.name = "MusicPlayer"
	_music_player.volume_db = linear_to_db(music_volume)
	add_child(_music_player)

	_footstep_player = AudioStreamPlayer.new()
	_footstep_player.name = "FootstepPlayer"
	_footstep_player.volume_db = linear_to_db(sfx_volume)
	add_child(_footstep_player)

	_ui_player = AudioStreamPlayer.new()
	_ui_player.name = "UIPlayer"
	_ui_player.volume_db = linear_to_db(sfx_volume)
	add_child(_ui_player)

# ─────────────────────────────────────────────
# Asset loading
# ─────────────────────────────────────────────

func _load_audio_assets() -> void:
	# Try loading ambient audio by time of day
	var ambient_paths := {
		"day":   "res://assets/audio/ambient/day.ogg",
		"night": "res://assets/audio/ambient/night.ogg",
		"dawn":  "res://assets/audio/ambient/dawn.ogg",
		"rain":  "res://assets/audio/ambient/rain.ogg",
		"wind":  "res://assets/audio/ambient/wind.ogg",
	}
	for key in ambient_paths:
		var path: String = ambient_paths[key]
		if ResourceLoader.exists(path):
			_ambient_streams[key] = load(path)

	# Fallback: check for generic ambient
	if _ambient_streams.is_empty():
		for candidate in ["res://assets/audio/ambient/medieval_village.mp3",
						   "res://assets/audio/ambient/ambient.ogg",
						   "res://assets/audio/ambient/ambient.mp3"]:
			if ResourceLoader.exists(candidate):
				_ambient_streams["day"] = load(candidate)
				break

	# Footstep audio
	var footstep_paths := {
		"stone": "res://assets/audio/footstep/stone.ogg",
		"grass": "res://assets/audio/footstep/grass.ogg",
		"wood":  "res://assets/audio/footstep/wood.ogg",
		"dirt":  "res://assets/audio/footstep/dirt.ogg",
	}
	for key in footstep_paths:
		var path: String = footstep_paths[key]
		if ResourceLoader.exists(path):
			_footstep_streams[key] = load(path)
		# Also check .mp3 variants
		var mp3_path: String = path.replace(".ogg", ".mp3")
		if not _footstep_streams.has(key) and ResourceLoader.exists(mp3_path):
			_footstep_streams[key] = load(mp3_path)

	# UI sounds
	var ui_paths := {
		"button":  "res://assets/audio/interact/button.ogg",
		"door":    "res://assets/audio/interact/door.ogg",
		"pickup":  "res://assets/audio/interact/pickup.ogg",
		"equip":   "res://assets/audio/interact/equip.ogg",
	}
	for key in ui_paths:
		var path: String = ui_paths[key]
		if ResourceLoader.exists(path):
			_ui_streams[key] = load(path)
		var mp3_path: String = path.replace(".ogg", ".mp3")
		if not _ui_streams.has(key) and ResourceLoader.exists(mp3_path):
			_ui_streams[key] = load(mp3_path)

	var total: int = _ambient_streams.size() + _footstep_streams.size() + _ui_streams.size()
	if total > 0:
		print("[Insimul] AudioManager: loaded %d audio assets" % total)
	else:
		print("[Insimul] AudioManager: no audio assets found — running silent")

# ─────────────────────────────────────────────
# Ambient soundscape
# ─────────────────────────────────────────────

func _update_ambient() -> void:
	if _ambient_streams.is_empty():
		return

	var target_key := _get_ambient_key()
	if target_key == _current_ambient_key:
		return

	if _ambient_streams.has(target_key):
		_current_ambient_key = target_key
		_ambient_player.stream = _ambient_streams[target_key]
		_ambient_player.play()
	elif _ambient_streams.has("day") and _current_ambient_key == "":
		# Fallback to generic
		_current_ambient_key = "day"
		_ambient_player.stream = _ambient_streams["day"]
		_ambient_player.play()

func _get_ambient_key() -> String:
	var hour: float = GameClock.current_hour
	# Check weather first
	var weather_node: Node = get_node_or_null("/root/Main/WeatherSystem")
	if weather_node and weather_node.has_method("_weather_name"):
		# If raining/storming, use rain ambient
		if _ambient_streams.has("rain"):
			var weather_type: int = weather_node.get("current_weather")
			if weather_type >= 3:  # RAIN or STORM
				return "rain"

	if hour >= 5.0 and hour < 7.0:
		return "dawn" if _ambient_streams.has("dawn") else "day"
	elif hour >= 7.0 and hour < 19.0:
		return "day"
	else:
		return "night" if _ambient_streams.has("night") else "day"

# ─────────────────────────────────────────────
# Footstep audio
# ─────────────────────────────────────────────

func set_walking(walking: bool, running: bool = false) -> void:
	_is_walking = walking
	_is_running = running

func _update_footsteps(delta: float) -> void:
	if not _is_walking or _footstep_streams.is_empty():
		return

	var interval: float = FOOTSTEP_RUN_INTERVAL if _is_running else FOOTSTEP_INTERVAL
	_footstep_timer += delta
	if _footstep_timer >= interval:
		_footstep_timer = 0.0
		_play_footstep()

func _play_footstep() -> void:
	# Default to stone surface; could be extended with surface detection
	var surface := "stone"
	if _footstep_streams.has(surface):
		_footstep_player.stream = _footstep_streams[surface]
		_footstep_player.pitch_scale = randf_range(0.9, 1.1)
		_footstep_player.play()
	elif not _footstep_streams.is_empty():
		# Use whatever is available
		var key: String = _footstep_streams.keys()[0]
		_footstep_player.stream = _footstep_streams[key]
		_footstep_player.pitch_scale = randf_range(0.9, 1.1)
		_footstep_player.play()

# ─────────────────────────────────────────────
# Public API
# ─────────────────────────────────────────────

## Play a UI/interaction sound effect.
func play_sfx(action: String) -> void:
	if _ui_streams.has(action):
		_ui_player.stream = _ui_streams[action]
		_ui_player.play()

## Play a one-shot sound at a position (3D spatial).
func play_at(stream: AudioStream, pos: Vector3, volume: float = 0.0) -> void:
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.volume_db = volume
	player.position = pos
	player.finished.connect(player.queue_free)
	add_child(player)
	player.play()

## Set master volume (0-1).
func set_master_volume(vol: float) -> void:
	master_volume = clampf(vol, 0.0, 1.0)
	AudioServer.set_bus_volume_db(0, linear_to_db(master_volume))

## Set ambient volume (0-1).
func set_ambient_volume(vol: float) -> void:
	ambient_volume = clampf(vol, 0.0, 1.0)
	_ambient_player.volume_db = linear_to_db(ambient_volume)

## Set SFX volume (0-1).
func set_sfx_volume(vol: float) -> void:
	sfx_volume = clampf(vol, 0.0, 1.0)
	_footstep_player.volume_db = linear_to_db(sfx_volume)
	_ui_player.volume_db = linear_to_db(sfx_volume)
