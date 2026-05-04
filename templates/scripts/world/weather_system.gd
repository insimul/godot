extends Node3D
## Weather System — procedural weather with rain particles, fog, and sky darkening.
## 5 weather types with weighted probability transitions.
## Add to the "world_generator" group.

enum WeatherType { CLEAR, CLOUDY, OVERCAST, RAIN, STORM }

## Transition probabilities from each state [clear, cloudy, overcast, rain, storm]
const TRANSITION_WEIGHTS := {
	WeatherType.CLEAR:    [0.6, 0.3, 0.08, 0.02, 0.0],
	WeatherType.CLOUDY:   [0.25, 0.4, 0.25, 0.08, 0.02],
	WeatherType.OVERCAST: [0.1, 0.2, 0.35, 0.25, 0.1],
	WeatherType.RAIN:     [0.05, 0.15, 0.3, 0.35, 0.15],
	WeatherType.STORM:    [0.02, 0.08, 0.2, 0.35, 0.35],
}

## Weather visual parameters
const WEATHER_PARAMS := {
	WeatherType.CLEAR:    {"fog_mult": 1.0, "sky_darken": 0.0, "rain_density": 0, "wind": 0.0},
	WeatherType.CLOUDY:   {"fog_mult": 1.5, "sky_darken": 0.15, "rain_density": 0, "wind": 1.0},
	WeatherType.OVERCAST: {"fog_mult": 2.5, "sky_darken": 0.3, "rain_density": 0, "wind": 2.0},
	WeatherType.RAIN:     {"fog_mult": 4.0, "sky_darken": 0.4, "rain_density": 500, "wind": 4.0},
	WeatherType.STORM:    {"fog_mult": 6.0, "sky_darken": 0.55, "rain_density": 1200, "wind": 8.0},
}

## Duration range per weather type (seconds)
const MIN_DURATION := 120.0
const MAX_DURATION := 300.0

var current_weather: WeatherType = WeatherType.CLEAR
var _target_weather: WeatherType = WeatherType.CLEAR
var _transition_timer := 0.0
var _duration := 180.0
var _elapsed := 0.0
var _blend := 0.0  # 0 = current fully applied, 1 = target fully applied
var _blend_speed := 0.1  # blend per second during transitions

var _rain_particles: GPUParticles3D = null
var _environment: Environment = null
var _base_fog_density := 0.001
var _player: Node3D = null

# Cloud meshes
var _cloud_container: Node3D = null
const CLOUD_COUNT := 12
const CLOUD_HEIGHT := 40.0
const CLOUD_SPREAD := 80.0

func _ready() -> void:
	add_to_group("world_generator")

func generate_from_data(_world_data: Dictionary) -> void:
	_find_environment()
	_create_rain_system()
	_create_clouds()
	_duration = randf_range(MIN_DURATION, MAX_DURATION)
	print("[Insimul] WeatherSystem initialized — starting %s" % _weather_name(current_weather))

func _process(delta: float) -> void:
	_elapsed += delta

	# Check for weather transition
	if _elapsed >= _duration:
		_elapsed = 0.0
		_duration = randf_range(MIN_DURATION, MAX_DURATION)
		_target_weather = _pick_next_weather()
		_blend = 0.0
		if _target_weather != current_weather:
			print("[Insimul] Weather changing: %s → %s" % [_weather_name(current_weather), _weather_name(_target_weather)])

	# Blend toward target
	if current_weather != _target_weather:
		_blend = minf(_blend + _blend_speed * delta, 1.0)
		if _blend >= 1.0:
			current_weather = _target_weather
			_blend = 0.0

	_apply_weather(delta)
	_update_clouds(delta)
	_follow_player()

# ─────────────────────────────────────────────
# Weather application
# ─────────────────────────────────────────────

func _apply_weather(_delta: float) -> void:
	var current_params: Dictionary = WEATHER_PARAMS[current_weather]
	var target_params: Dictionary = WEATHER_PARAMS[_target_weather]

	var fog_mult: float = lerpf(current_params["fog_mult"], target_params["fog_mult"], _blend)
	var sky_darken: float = lerpf(current_params["sky_darken"], target_params["sky_darken"], _blend)
	var rain_density: int = int(lerpf(current_params["rain_density"], target_params["rain_density"], _blend))
	var wind: float = lerpf(current_params["wind"], target_params["wind"], _blend)

	# Apply fog
	if _environment:
		_environment.fog_density = _base_fog_density * fog_mult
		# Darken ambient light
		var darken: float = 1.0 - sky_darken
		_environment.ambient_light_energy = clampf(_environment.ambient_light_energy * darken, 0.05, 0.7)

	# Rain particles
	if _rain_particles:
		_rain_particles.emitting = rain_density > 0
		_rain_particles.amount = maxi(rain_density, 1)
		if _rain_particles.process_material is ParticleProcessMaterial:
			var mat: ParticleProcessMaterial = _rain_particles.process_material
			# Wind pushes rain sideways
			mat.gravity = Vector3(wind * 0.5, -15.0, wind * 0.3)

# ─────────────────────────────────────────────
# Weather transitions
# ─────────────────────────────────────────────

func _pick_next_weather() -> WeatherType:
	var weights: Array = TRANSITION_WEIGHTS[current_weather]
	var r: float = randf()
	var cumulative := 0.0
	for i in range(weights.size()):
		cumulative += weights[i]
		if r <= cumulative:
			return i as WeatherType
	return WeatherType.CLEAR

func _weather_name(w: WeatherType) -> String:
	match w:
		WeatherType.CLEAR: return "Clear"
		WeatherType.CLOUDY: return "Cloudy"
		WeatherType.OVERCAST: return "Overcast"
		WeatherType.RAIN: return "Rain"
		WeatherType.STORM: return "Storm"
	return "Unknown"

# ─────────────────────────────────────────────
# Rain particle system
# ─────────────────────────────────────────────

func _create_rain_system() -> void:
	_rain_particles = GPUParticles3D.new()
	_rain_particles.name = "RainParticles"
	_rain_particles.amount = 1
	_rain_particles.emitting = false
	_rain_particles.lifetime = 2.0
	_rain_particles.visibility_aabb = AABB(Vector3(-30, -10, -30), Vector3(60, 50, 60))
	_rain_particles.position.y = 25.0

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, -1, 0)
	mat.spread = 5.0
	mat.gravity = Vector3(0, -15.0, 0)
	mat.initial_velocity_min = 8.0
	mat.initial_velocity_max = 12.0
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(25, 0.5, 25)
	mat.scale_min = 0.02
	mat.scale_max = 0.04
	_rain_particles.process_material = mat

	# Rain drop mesh (tiny stretched box)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.02, 0.4, 0.02)
	_rain_particles.draw_pass_1 = mesh

	# Rain material
	var rain_mat := StandardMaterial3D.new()
	rain_mat.albedo_color = Color(0.7, 0.75, 0.85, 0.4)
	rain_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_rain_particles.material_override = rain_mat

	add_child(_rain_particles)

# ─────────────────────────────────────────────
# Cloud system
# ─────────────────────────────────────────────

func _create_clouds() -> void:
	_cloud_container = Node3D.new()
	_cloud_container.name = "Clouds"
	_cloud_container.position.y = CLOUD_HEIGHT
	add_child(_cloud_container)

	var cloud_mat := StandardMaterial3D.new()
	cloud_mat.albedo_color = Color(0.9, 0.9, 0.92, 0.6)
	cloud_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cloud_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	for i in range(CLOUD_COUNT):
		var cloud := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = randf_range(8.0, 18.0)
		sphere.height = randf_range(3.0, 6.0)
		sphere.radial_segments = 8
		sphere.rings = 4
		cloud.mesh = sphere
		cloud.material_override = cloud_mat
		cloud.position = Vector3(
			randf_range(-CLOUD_SPREAD, CLOUD_SPREAD),
			randf_range(-2, 2),
			randf_range(-CLOUD_SPREAD, CLOUD_SPREAD)
		)
		cloud.set_meta("drift_speed", randf_range(0.5, 2.0))
		cloud.set_meta("drift_dir", Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized())
		_cloud_container.add_child(cloud)

func _update_clouds(delta: float) -> void:
	if _cloud_container == null:
		return
	# Only show clouds in non-clear weather
	var show_clouds: bool = current_weather != WeatherType.CLEAR or _target_weather != WeatherType.CLEAR
	_cloud_container.visible = show_clouds
	if not show_clouds:
		return

	for cloud in _cloud_container.get_children():
		if cloud is MeshInstance3D:
			var speed: float = cloud.get_meta("drift_speed", 1.0)
			var dir: Vector3 = cloud.get_meta("drift_dir", Vector3.RIGHT)
			cloud.position += dir * speed * delta
			# Wrap around
			if cloud.position.x > CLOUD_SPREAD:
				cloud.position.x = -CLOUD_SPREAD
			elif cloud.position.x < -CLOUD_SPREAD:
				cloud.position.x = CLOUD_SPREAD
			if cloud.position.z > CLOUD_SPREAD:
				cloud.position.z = -CLOUD_SPREAD
			elif cloud.position.z < -CLOUD_SPREAD:
				cloud.position.z = CLOUD_SPREAD

# ─────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────

func _follow_player() -> void:
	if _player == null:
		var players := get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			_player = players[0] as Node3D
	if _player and _rain_particles:
		_rain_particles.global_position = Vector3(_player.global_position.x, 25.0, _player.global_position.z)
	if _player and _cloud_container:
		_cloud_container.global_position = Vector3(_player.global_position.x, CLOUD_HEIGHT, _player.global_position.z)

func _find_environment() -> void:
	var we := _search_type(get_tree().root, "WorldEnvironment")
	if we and we is WorldEnvironment:
		_environment = we.environment
		if _environment:
			_base_fog_density = _environment.fog_density

func _search_type(node: Node, type_name: String) -> Node:
	if node.get_class() == type_name:
		return node
	for child in node.get_children():
		var found: Node = _search_type(child, type_name)
		if found:
			return found
	return null
