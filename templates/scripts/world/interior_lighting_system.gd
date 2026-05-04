extends Node3D
## Interior lighting system — dynamic interior lighting responsive to
## day/night cycle matching InteriorLightingSystem.ts.

const DAY_START := 6.0
const DAY_END := 18.0
const DUSK_END := 20.0
const DAWN_START := 5.0

const DAY_AMBIENT := 0.6
const NIGHT_AMBIENT := 0.15

## Lighting presets for different building types.
const LIGHTING_PRESETS := {
	"bright": {"color": Color(0.95, 0.92, 0.85), "energy": 2.0, "range": 10.0},
	"dim": {"color": Color(0.7, 0.6, 0.5), "energy": 0.8, "range": 6.0},
	"warm": {"color": Color(0.95, 0.75, 0.45), "energy": 1.5, "range": 8.0},
	"cool": {"color": Color(0.7, 0.78, 0.9), "energy": 1.3, "range": 8.0},
	"candlelit": {"color": Color(0.95, 0.65, 0.3), "energy": 1.0, "range": 5.0},
}

## Role → preset mapping.
const ROLE_PRESET := {
	"tavern": "candlelit",
	"inn": "warm",
	"bar": "candlelit",
	"church": "dim",
	"temple": "dim",
	"shop": "bright",
	"merchant": "bright",
	"blacksmith": "warm",
	"forge": "warm",
	"warehouse": "dim",
	"hospital": "bright",
	"clinic": "bright",
	"office": "bright",
	"residential": "warm",
}

## Furniture types that get lamp lights placed on them.
const LAMP_FURNITURE := ["table", "counter", "workbench", "desk", "altar", "podium"]
## Room types that count as large (get more lights).
const LARGE_ROOMS := ["tavern_main", "church_nave", "warehouse", "guild_hall", "theater"]

var _interior_lights: Array[Dictionary] = []

func _ready() -> void:
	add_to_group("world_generator")

## Create interior lighting for a building.
## Call this after interior geometry is generated.
func create_lighting(interior_node: Node3D, role: String,
		rooms: Array[Dictionary] = []) -> void:
	var preset_name: String = ROLE_PRESET.get(role, "warm")
	var preset: Dictionary = LIGHTING_PRESETS.get(preset_name, LIGHTING_PRESETS["warm"])

	if rooms.is_empty():
		# Single room fallback
		_add_room_lighting(interior_node, preset, role, 10.0, 10.0)
		return

	for room in rooms:
		var rw: float = room.get("width", 10.0)
		var rd: float = room.get("depth", 10.0)
		var ox: float = room.get("offset_x", 0.0)
		var oz: float = room.get("offset_z", 0.0)
		var room_func: String = room.get("function", "living_room")

		var room_preset := preset
		# Override for specific room types
		match room_func:
			"kitchen":
				room_preset = LIGHTING_PRESETS["bright"]
			"bedroom":
				room_preset = LIGHTING_PRESETS["warm"]
			"storage":
				room_preset = LIGHTING_PRESETS["dim"]

		var room_container := Node3D.new()
		room_container.position = Vector3(ox, 0, oz)
		room_container.name = "Lights_%s" % room.get("name", "Room").replace(" ", "_")

		var is_large: bool = room_func in LARGE_ROOMS
		var light_count := 4 if is_large else 2
		if rw * rd > 40.0:
			light_count = clampi(ceili(rw * rd / 20.0), 2, 8)

		for i in range(light_count):
			var lx: float = rw * (0.25 + 0.5 * (float(i % 2)))
			var lz: float = rd * (0.25 + 0.5 * (float(i / 2) / maxf(float(light_count / 2), 1.0)))

			var light := OmniLight3D.new()
			light.position = Vector3(lx, 2.6, lz)
			light.light_color = room_preset["color"]
			light.light_energy = room_preset["energy"] / float(light_count) * 2.0
			light.omni_range = room_preset["range"]
			light.shadow_enabled = light_count <= 4
			light.name = "RoomLight_%d" % i
			room_container.add_child(light)

		interior_node.add_child(room_container)

		_interior_lights.append({
			"node": room_container,
			"preset": room_preset,
			"role": role,
		})

func _add_room_lighting(parent: Node3D, preset: Dictionary, role: String,
		width: float, depth: float) -> void:
	# Main ceiling light
	var main_light := OmniLight3D.new()
	main_light.position = Vector3(width / 2.0, 2.6, depth / 2.0)
	main_light.light_color = preset["color"]
	main_light.light_energy = preset["energy"]
	main_light.omni_range = preset["range"]
	main_light.shadow_enabled = true
	main_light.name = "MainLight"
	parent.add_child(main_light)

	# Window lights (simulate daylight from windows)
	_add_window_light(parent, Vector3(width / 2.0, 2.0, 0.1), Vector3.FORWARD, role)
	_add_window_light(parent, Vector3(0.1, 2.0, depth / 2.0), Vector3.RIGHT, role)

	_interior_lights.append({
		"node": parent,
		"preset": preset,
		"role": role,
	})

func _add_window_light(parent: Node3D, pos: Vector3, dir: Vector3, _role: String) -> void:
	var window_light := SpotLight3D.new()
	window_light.position = pos
	window_light.light_color = Color(0.85, 0.88, 0.95)
	window_light.light_energy = 0.8
	window_light.spot_range = 6.0
	window_light.spot_angle = 45.0
	window_light.shadow_enabled = false
	window_light.name = "WindowLight"

	# Point the spot light inward
	window_light.look_at_from_position(pos, pos + dir * 3.0 + Vector3.DOWN * 0.5, Vector3.UP)
	parent.add_child(window_light)

## Update lighting based on time of day. Call from _process or game_clock update.
func update_time_of_day(hour: float) -> void:
	var time_factor := _compute_time_factor(hour)

	for light_data in _interior_lights:
		var node: Node3D = light_data.get("node")
		if not is_instance_valid(node):
			continue

		# Adjust window lights based on daylight
		for child in node.get_children():
			if child is SpotLight3D:
				child.light_energy = 0.8 * time_factor

func _compute_time_factor(hour: float) -> float:
	if hour >= DAY_START and hour <= DAY_END:
		return 1.0
	elif hour >= DAWN_START and hour < DAY_START:
		return (hour - DAWN_START) / (DAY_START - DAWN_START)
	elif hour > DAY_END and hour <= DUSK_END:
		return 1.0 - (hour - DAY_END) / (DUSK_END - DAY_END)
	else:
		return 0.0
