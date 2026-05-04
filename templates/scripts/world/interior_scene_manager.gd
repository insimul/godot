extends Node3D
## Interior scene manager — manages loading/unloading interior scenes when
## the player enters/exits buildings.
## Matches InteriorSceneManager.ts.

## Maps businessType → Array of interior GLTF asset paths (res://).
const INTERIOR_MODEL_MAP := {
	"tavern": [
		"assets/models/interiors/british_pub.glb",
		"assets/models/interiors/old_bar.glb",
		"assets/models/interiors/silent_hill_old_bar_2.glb",
		"assets/models/interiors/food_bar.glb",
	],
	"restaurant": [
		"assets/models/interiors/restaurant.glb",
		"assets/models/interiors/modern_diner.glb",
		"assets/models/interiors/for_pashapashas_diner.glb",
	],
	"shop": [
		"assets/models/interiors/convenience_store_2.glb",
		"assets/models/interiors/one_stop.glb",
	],
	"residence": [
		"assets/models/interiors/small_apartment_morning_version.glb",
		"assets/models/interiors/modern_apartment_interior.glb",
		"assets/models/interiors/mansion_furnished.glb",
	],
	"church": [
		"assets/models/interiors/silent_hill_3_cathedral.glb",
	],
}

signal entered_interior(building_id: String)
signal exited_interior()

var _active_interior: Node3D = null
var _active_building_id: String = ""
var _interior_cache: Dictionary = {}  # building_id → Node3D
var _exterior_nodes: Array[Node3D] = []
var _is_inside := false
var _fade_overlay: ColorRect = null

func _ready() -> void:
	add_to_group("world_generator")
	_create_fade_overlay()

func generate_from_data(_world_data: Dictionary) -> void:
	# Connect to building collision system
	for node in get_tree().get_nodes_in_group("world_generator"):
		if node.has_signal("building_entered"):
			node.building_entered.connect(_on_building_entered)
		if node.has_signal("building_exited"):
			node.building_exited.connect(_on_building_exited)

## Register exterior nodes to hide when entering a building.
func register_exterior_node(node: Node3D) -> void:
	_exterior_nodes.append(node)

func switch_to_interior(building_id: String, building_data: Dictionary) -> void:
	if _is_inside:
		return

	_is_inside = true
	_active_building_id = building_id

	# Fade to black
	await _fade_in()

	# Hide exterior
	for node in _exterior_nodes:
		if is_instance_valid(node):
			node.visible = false

	# Load or create interior
	if _interior_cache.has(building_id):
		_active_interior = _interior_cache[building_id]
		_active_interior.visible = true
	else:
		_active_interior = _create_interior(building_id, building_data)
		_interior_cache[building_id] = _active_interior
		add_child(_active_interior)

	# Position player at interior spawn
	var player := _find_player()
	if player != null:
		player.global_position = _active_interior.global_position + Vector3(0, 1, 2)

	entered_interior.emit(building_id)

	# Fade from black
	await _fade_out()

func switch_to_exterior() -> void:
	if not _is_inside:
		return

	await _fade_in()

	_is_inside = false

	# Hide interior
	if _active_interior != null:
		_active_interior.visible = false

	# Show exterior
	for node in _exterior_nodes:
		if is_instance_valid(node):
			node.visible = true

	_active_building_id = ""
	exited_interior.emit()

	await _fade_out()

func is_inside() -> bool:
	return _is_inside

func get_active_building_id() -> String:
	return _active_building_id

func _create_interior(building_id: String, building_data: Dictionary) -> Node3D:
	var spec: Dictionary = building_data.get("spec", {})
	var role: String = spec.get("buildingRole", "residential")
	var biz_id: String = building_data.get("businessId", "")

	# Try to load pre-built interior model
	var model_paths: Array = INTERIOR_MODEL_MAP.get(role, [])
	if model_paths.size() > 0:
		var hash_val := building_id.hash()
		var path: String = model_paths[absi(hash_val) % model_paths.size()]
		var full_path := "res://" + path
		if ResourceLoader.exists(full_path):
			var scene := load(full_path) as PackedScene
			if scene != null:
				var instance := scene.instantiate() as Node3D
				instance.name = "Interior_%s" % building_id
				# Add interior lighting
				_add_interior_lighting(instance, role)
				return instance

	# Fallback: procedural interior
	return _generate_procedural_interior(building_id, building_data)

func _generate_procedural_interior(building_id: String, building_data: Dictionary) -> Node3D:
	var spec: Dictionary = building_data.get("spec", {})
	var width: float = spec.get("width", 10.0)
	var depth: float = spec.get("depth", 10.0)
	var floors: int = spec.get("floors", 1)
	var role: String = spec.get("buildingRole", "residential")

	var interior := Node3D.new()
	interior.name = "Interior_%s" % building_id

	var pos_dict: Dictionary = building_data.get("position", {})
	interior.position = Vector3(pos_dict.get("x", 0), pos_dict.get("y", 0), pos_dict.get("z", 0))

	# Floor
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.mesh = BoxMesh.new()
	(floor_mesh.mesh as BoxMesh).size = Vector3(width, 0.1, depth)
	floor_mesh.position.y = 0.05
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = _get_floor_color(role)
	floor_mesh.material_override = floor_mat
	floor_mesh.name = "Floor"
	interior.add_child(floor_mesh)

	# Ceiling
	var ceil_mesh := MeshInstance3D.new()
	ceil_mesh.mesh = BoxMesh.new()
	(ceil_mesh.mesh as BoxMesh).size = Vector3(width, 0.1, depth)
	ceil_mesh.position.y = 3.0
	var ceil_mat := StandardMaterial3D.new()
	ceil_mat.albedo_color = Color(0.85, 0.83, 0.8)
	ceil_mesh.material_override = ceil_mat
	ceil_mesh.name = "Ceiling"
	interior.add_child(ceil_mesh)

	# Walls
	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = _get_wall_color(role)
	_add_interior_wall(interior, Vector3(0, 1.5, -depth / 2.0), Vector3(width, 3.0, 0.15), wall_mat)
	_add_interior_wall(interior, Vector3(0, 1.5, depth / 2.0), Vector3(width, 3.0, 0.15), wall_mat)
	_add_interior_wall(interior, Vector3(-width / 2.0, 1.5, 0), Vector3(0.15, 3.0, depth), wall_mat)
	_add_interior_wall(interior, Vector3(width / 2.0, 1.5, 0), Vector3(0.15, 3.0, depth), wall_mat)

	# Add lighting
	_add_interior_lighting(interior, role)

	return interior

func _add_interior_wall(parent: Node3D, pos: Vector3, size: Vector3, mat: StandardMaterial3D) -> void:
	var wall := MeshInstance3D.new()
	wall.mesh = BoxMesh.new()
	(wall.mesh as BoxMesh).size = size
	wall.position = pos
	wall.material_override = mat
	wall.name = "Wall"
	parent.add_child(wall)

	var body := StaticBody3D.new()
	body.position = pos
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	parent.add_child(body)

func _add_interior_lighting(parent: Node3D, role: String) -> void:
	var light := OmniLight3D.new()
	light.position.y = 2.8
	light.omni_range = 12.0
	light.shadow_enabled = true
	light.name = "InteriorLight"

	match role:
		"tavern", "inn", "bar":
			light.light_color = Color(0.95, 0.75, 0.45)
			light.light_energy = 1.2
		"church", "temple":
			light.light_color = Color(0.9, 0.85, 0.7)
			light.light_energy = 1.5
		"shop", "merchant":
			light.light_color = Color(0.95, 0.92, 0.85)
			light.light_energy = 1.8
		_:
			light.light_color = Color(0.9, 0.85, 0.75)
			light.light_energy = 1.4

	parent.add_child(light)

func _get_floor_color(role: String) -> Color:
	match role:
		"tavern", "inn":
			return Color(0.35, 0.22, 0.12)
		"church":
			return Color(0.55, 0.52, 0.48)
		"shop":
			return Color(0.4, 0.35, 0.28)
		_:
			return Color(0.45, 0.35, 0.22)

func _get_wall_color(role: String) -> Color:
	match role:
		"tavern", "inn":
			return Color(0.5, 0.38, 0.22)
		"church":
			return Color(0.65, 0.62, 0.58)
		"shop":
			return Color(0.65, 0.6, 0.52)
		_:
			return Color(0.7, 0.65, 0.58)

func _on_building_entered(building_id: String, building_data: Dictionary) -> void:
	switch_to_interior(building_id, building_data)

func _on_building_exited(_building_id: String) -> void:
	switch_to_exterior()

func _create_fade_overlay() -> void:
	_fade_overlay = ColorRect.new()
	_fade_overlay.color = Color(0, 0, 0, 0)
	_fade_overlay.anchors_preset = Control.PRESET_FULL_RECT
	_fade_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_overlay.z_index = 100
	_fade_overlay.name = "FadeOverlay"

	var canvas := CanvasLayer.new()
	canvas.layer = 100
	canvas.name = "FadeLayer"
	canvas.add_child(_fade_overlay)
	add_child(canvas)

func _fade_in() -> void:
	if _fade_overlay == null:
		return
	var tween := create_tween()
	tween.tween_property(_fade_overlay, "color:a", 1.0, 0.3)
	await tween.finished

func _fade_out() -> void:
	if _fade_overlay == null:
		return
	var tween := create_tween()
	tween.tween_property(_fade_overlay, "color:a", 0.0, 0.3)
	await tween.finished

func _find_player() -> Node3D:
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		return players[0] as Node3D
	return null
