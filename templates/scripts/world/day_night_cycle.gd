extends Node3D
## Day/Night Cycle — visual atmosphere system.
## Interpolates sun direction, sky color, ambient light, and fog across 8 keyframes.
## Reads fractional hour from GameClock every frame.
## Add to the "world_generator" group.

# ─────────────────────────────────────────────
# Keyframe data
# ─────────────────────────────────────────────

## Each keyframe: [hour, sunAlt, sunAz, sunIntensity, sunR,sunG,sunB,
##   hemiIntensity, hemiSkyR,G,B, hemiGndR,G,B,
##   skyZenR,G,B, skyHorR,G,B, skyGndR,G,B, fogDensity]

const KF_HOUR := 0
const KF_SUN_ALT := 1
const KF_SUN_AZ := 2
const KF_SUN_INTENSITY := 3
const KF_SUN_R := 4
const KF_SUN_G := 5
const KF_SUN_B := 6
const KF_HEMI_INTENSITY := 7
const KF_HEMI_SKY_R := 8
const KF_HEMI_SKY_G := 9
const KF_HEMI_SKY_B := 10
const KF_HEMI_GND_R := 11
const KF_HEMI_GND_G := 12
const KF_HEMI_GND_B := 13
const KF_SKY_ZEN_R := 14
const KF_SKY_ZEN_G := 15
const KF_SKY_ZEN_B := 16
const KF_SKY_HOR_R := 17
const KF_SKY_HOR_G := 18
const KF_SKY_HOR_B := 19
const KF_SKY_GND_R := 20
const KF_SKY_GND_G := 21
const KF_SKY_GND_B := 22
const KF_FOG_DENSITY := 23
const KF_SIZE := 24

# 8 keyframes: midnight, pre-dawn, sunrise, morning, midday, afternoon, sunset, dusk
var _keyframes: Array[PackedFloat64Array] = [
	# Midnight 0:00
	PackedFloat64Array([0.0,  -0.8, 0.0,    0.0,  0.1,0.1,0.2,
		0.15,  0.05,0.05,0.15,  0.02,0.02,0.05,
		0.02,0.02,0.06,  0.03,0.03,0.08,  0.01,0.01,0.03,  0.003]),
	# Pre-dawn 5:00
	PackedFloat64Array([5.0,  -0.3, 1.2,    0.0,  0.3,0.2,0.15,
		0.25,  0.15,0.12,0.2,   0.05,0.04,0.06,
		0.05,0.05,0.15,  0.15,0.1,0.12,   0.03,0.03,0.05,  0.004]),
	# Sunrise 6:30
	PackedFloat64Array([6.5,  0.15, 1.4,    0.6,  1.0,0.8,0.5,
		0.45,  0.6,0.45,0.3,    0.15,0.1,0.08,
		0.3,0.4,0.7,    0.85,0.5,0.25,   0.1,0.08,0.05,   0.002]),
	# Morning 8:00
	PackedFloat64Array([8.0,  0.6,  1.8,    0.85, 1.0,0.95,0.85,
		0.6,   0.7,0.75,0.85,   0.2,0.18,0.15,
		0.35,0.5,0.85,  0.6,0.7,0.85,    0.15,0.12,0.1,   0.001]),
	# Midday 12:00
	PackedFloat64Array([12.0, 1.2,  PI,     1.1,  1.0,0.98,0.95,
		0.7,   0.8,0.85,0.9,    0.25,0.22,0.18,
		0.4,0.55,0.9,   0.65,0.75,0.9,   0.2,0.18,0.12,   0.0005]),
	# Afternoon 16:00
	PackedFloat64Array([16.0, 0.7,  -1.8,   0.9,  1.0,0.92,0.8,
		0.65,  0.75,0.7,0.65,   0.22,0.18,0.12,
		0.4,0.5,0.8,    0.65,0.65,0.75,  0.18,0.15,0.1,   0.0008]),
	# Sunset 18:30
	PackedFloat64Array([18.5, 0.1,  -1.4,   0.5,  1.0,0.6,0.3,
		0.4,   0.7,0.4,0.25,    0.15,0.08,0.05,
		0.2,0.15,0.35,  0.9,0.4,0.15,   0.1,0.05,0.03,   0.002]),
	# Dusk 20:00
	PackedFloat64Array([20.0, -0.4, -1.0,   0.0,  0.15,0.1,0.2,
		0.2,   0.1,0.08,0.15,   0.04,0.03,0.06,
		0.05,0.04,0.12,  0.08,0.06,0.15,  0.02,0.02,0.04,  0.003]),
]

# Street lamp timing
const LIGHTS_ON_START := 18.0
const LIGHTS_ON_FULL := 19.5
const LIGHTS_OFF_START := 5.5
const LIGHTS_OFF_FULL := 7.0

# References (resolved at runtime)
var _sun: DirectionalLight3D = null
var _environment: Environment = null
var _street_lights: Array[Dictionary] = []  # [{light, base_intensity}]

func _ready() -> void:
	add_to_group("world_generator")

func generate_from_data(_world_data: Dictionary) -> void:
	# Find scene lighting nodes
	_sun = _find_node_of_type("DirectionalLight3D") as DirectionalLight3D
	var we: WorldEnvironment = _find_node_of_type("WorldEnvironment") as WorldEnvironment
	if we:
		_environment = we.environment
	# Enable fog on the environment
	if _environment:
		_environment.fog_enabled = true
		_environment.fog_light_color = Color(0.65, 0.75, 0.9)
		_environment.fog_density = 0.001
	# Collect street lights (OmniLight3D nodes in "street_light" group)
	for light in get_tree().get_nodes_in_group("street_light"):
		if light is OmniLight3D:
			_street_lights.append({"light": light, "base_intensity": light.light_energy})
	# Apply initial state
	_apply_cycle(GameClock.current_hour)
	print("[Insimul] DayNightCycle initialized — %d keyframes, %d street lights" % [_keyframes.size(), _street_lights.size()])

func _process(_delta: float) -> void:
	if _sun == null:
		return
	_apply_cycle(GameClock.current_hour)

# ─────────────────────────────────────────────
# Core interpolation
# ─────────────────────────────────────────────

func _apply_cycle(hour: float) -> void:
	var kf: PackedFloat64Array = _interpolate(hour)
	_apply_sun(kf)
	_apply_ambient(kf)
	_apply_sky(kf)
	_apply_fog(kf)
	_apply_street_lights(hour)

func _interpolate(hour: float) -> PackedFloat64Array:
	var h: float = fmod(fmod(hour, 24.0) + 24.0, 24.0)
	var count: int = _keyframes.size()

	# Find the two bracketing keyframes
	var idx_a: int = count - 1
	var idx_b: int = 0
	for i in range(count):
		if _keyframes[i][KF_HOUR] > h:
			idx_b = i
			idx_a = (i - 1 + count) % count
			break
		if i == count - 1:
			idx_a = i
			idx_b = 0

	var a: PackedFloat64Array = _keyframes[idx_a]
	var b: PackedFloat64Array = _keyframes[idx_b]

	# Calculate t with midnight wrap-around
	var a_hour: float = a[KF_HOUR]
	var b_hour: float = b[KF_HOUR]
	if b_hour <= a_hour:
		b_hour += 24.0
	var test_h: float = h
	if test_h < a_hour:
		test_h += 24.0
	var span: float = b_hour - a_hour
	var t: float = (test_h - a_hour) / maxf(span, 0.001)
	t = clampf(t, 0.0, 1.0)

	# Linearly interpolate all properties
	var result := PackedFloat64Array()
	result.resize(KF_SIZE)
	for i in range(KF_SIZE):
		result[i] = a[i] + (b[i] - a[i]) * t
	return result

# ─────────────────────────────────────────────
# Apply functions
# ─────────────────────────────────────────────

func _apply_sun(kf: PackedFloat64Array) -> void:
	if _sun == null:
		return
	var alt: float = kf[KF_SUN_ALT]
	var az: float = kf[KF_SUN_AZ]
	var cos_alt: float = cos(alt)

	# Compute direction vector from spherical coordinates
	var dir := Vector3(
		cos_alt * sin(az),
		-sin(alt),
		cos_alt * cos(az)
	).normalized()

	# Apply as look-at rotation
	if dir.length_squared() > 0.001:
		_sun.look_at(_sun.global_position + dir, Vector3.UP)

	_sun.light_energy = kf[KF_SUN_INTENSITY]
	_sun.light_color = Color(
		clampf(kf[KF_SUN_R], 0.0, 1.0),
		clampf(kf[KF_SUN_G], 0.0, 1.0),
		clampf(kf[KF_SUN_B], 0.0, 1.0)
	)

func _apply_ambient(kf: PackedFloat64Array) -> void:
	if _environment == null:
		return
	_environment.ambient_light_energy = kf[KF_HEMI_INTENSITY]
	_environment.ambient_light_color = Color(
		clampf(kf[KF_HEMI_SKY_R], 0.0, 1.0),
		clampf(kf[KF_HEMI_SKY_G], 0.0, 1.0),
		clampf(kf[KF_HEMI_SKY_B], 0.0, 1.0)
	)

func _apply_sky(kf: PackedFloat64Array) -> void:
	if _environment == null:
		return
	# Use the horizon color as the background color
	var horizon := Color(
		clampf(kf[KF_SKY_HOR_R], 0.0, 1.0),
		clampf(kf[KF_SKY_HOR_G], 0.0, 1.0),
		clampf(kf[KF_SKY_HOR_B], 0.0, 1.0)
	)
	_environment.background_color = horizon
	_environment.background_mode = Environment.BG_COLOR

func _apply_fog(kf: PackedFloat64Array) -> void:
	if _environment == null:
		return
	_environment.fog_density = kf[KF_FOG_DENSITY]
	# Tint fog toward horizon color for atmospheric coherence
	var horizon := Color(
		clampf(kf[KF_SKY_HOR_R], 0.0, 1.0),
		clampf(kf[KF_SKY_HOR_G], 0.0, 1.0),
		clampf(kf[KF_SKY_HOR_B], 0.0, 1.0)
	)
	_environment.fog_light_color = horizon

func _apply_street_lights(hour: float) -> void:
	var factor: float = _get_lamp_factor(hour)
	for entry in _street_lights:
		var light: OmniLight3D = entry["light"]
		var base_i: float = entry["base_intensity"]
		light.visible = factor > 0.01
		light.light_energy = base_i * factor

func _get_lamp_factor(hour: float) -> float:
	# Full night
	if hour >= LIGHTS_ON_FULL or hour < LIGHTS_OFF_START:
		return 1.0
	# Dusk ramp-up
	if hour >= LIGHTS_ON_START and hour < LIGHTS_ON_FULL:
		return (hour - LIGHTS_ON_START) / (LIGHTS_ON_FULL - LIGHTS_ON_START)
	# Dawn ramp-down
	if hour >= LIGHTS_OFF_START and hour < LIGHTS_OFF_FULL:
		return 1.0 - (hour - LIGHTS_OFF_START) / (LIGHTS_OFF_FULL - LIGHTS_OFF_START)
	# Daytime
	return 0.0

# ─────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────

func _find_node_of_type(type_name: String) -> Node:
	return _search_type(get_tree().root, type_name)

func _search_type(node: Node, type_name: String) -> Node:
	if node.get_class() == type_name:
		return node
	for child in node.get_children():
		var found: Node = _search_type(child, type_name)
		if found:
			return found
	return null
