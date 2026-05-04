extends Node3D
## Procedural building generator (interior variant).
## Add to the "world_generator" group.
##
## When buildings have a modelAssetKey, the matching bundled GLTF/GLB is loaded
## at runtime via load(). Otherwise a procedural BoxMesh is used as fallback.

signal exit_door_clicked(building_id: String)

@export var base_color := Color({{BASE_COLOR_R}}, {{BASE_COLOR_G}}, {{BASE_COLOR_B}})
@export var roof_color := Color({{ROOF_COLOR_R}}, {{ROOF_COLOR_G}}, {{ROOF_COLOR_B}})

## Pre-loaded furniture scene templates keyed by furniture type.
var _furniture_templates: Dictionary = {}

func _ready() -> void:
	add_to_group("world_generator")

func generate_from_data(world_data: Dictionary) -> void:
	var entities: Dictionary = world_data.get("entities", {})
	var buildings: Array = entities.get("buildings", [])
	var loaded_count := 0
	var procedural_count := 0
	for bld in buildings:
		var pos_dict: Dictionary = bld.get("position", {})
		var pos := Vector3(pos_dict.get("x", 0), pos_dict.get("y", 0), pos_dict.get("z", 0))
		var rot: float = bld.get("rotation", 0.0)
		var model_key_raw = bld.get("modelAssetKey", "")
		var model_key: String = model_key_raw if model_key_raw is String else ""

		if model_key != "":
			var scene := load("res://" + model_key) as PackedScene
			if scene:
				var node := scene.instantiate()
				node.name = "Building_%s" % bld.get("id", "unknown")
				add_child(node)
				node.global_position = pos
				node.rotation.y = deg_to_rad(rot)
				loaded_count += 1
				continue

		# Fallback: procedural BoxMesh
		var spec: Dictionary = bld.get("spec", {})
		_generate_building_procedural(
			pos, rot,
			spec.get("floors", 2),
			spec.get("width", 10.0),
			spec.get("depth", 10.0),
			spec.get("buildingRole", "residential"),
		)
		procedural_count += 1

	print("[Insimul] BuildingGenerator: %d from assets, %d procedural" % [loaded_count, procedural_count])

## Pre-load furniture scene assets from a config dictionary.
## Config should have a "furnitureAssets" key mapping type names to resource paths.
## e.g. { "furnitureAssets": { "chair": "res://assets/furniture/chair.tscn", ... } }
func load_furniture_assets(config: Dictionary) -> void:
	# Dispose previous templates
	for key in _furniture_templates:
		var node: Node = _furniture_templates[key]
		if is_instance_valid(node):
			node.queue_free()
	_furniture_templates.clear()

	var assets: Dictionary = config.get("furnitureAssets", {})
	for furniture_type in assets:
		var path: String = assets[furniture_type]
		var scene := load(path) as PackedScene
		if scene:
			_furniture_templates[furniture_type] = scene
			print("[Insimul] Loaded furniture template: %s from %s" % [furniture_type, path])
		else:
			push_warning("[Insimul] Failed to load furniture asset: %s" % path)

## Clone a furniture template PackedScene and scale the instance to target dimensions.
## Returns null if the template type is not loaded.
func _clone_furniture(furniture_type: String, target_size: Vector3) -> Node3D:
	if not _furniture_templates.has(furniture_type):
		return null
	var scene: PackedScene = _furniture_templates[furniture_type]
	var instance := scene.instantiate() as Node3D
	if instance == null:
		return null

	# Compute scale factor from the instance's AABB to fit target dimensions
	var aabb := AABB()
	if instance is MeshInstance3D:
		aabb = (instance as MeshInstance3D).get_aabb()
	else:
		# Traverse children to find mesh bounds
		for child in instance.get_children():
			if child is MeshInstance3D:
				var child_aabb := (child as MeshInstance3D).get_aabb()
				if aabb.size == Vector3.ZERO:
					aabb = child_aabb
				else:
					aabb = aabb.merge(child_aabb)

	if aabb.size.length() > 0.001:
		var sx: float = target_size.x / maxf(aabb.size.x, 0.001)
		var sy: float = target_size.y / maxf(aabb.size.y, 0.001)
		var sz: float = target_size.z / maxf(aabb.size.z, 0.001)
		var uniform_scale := minf(sx, minf(sy, sz))
		instance.scale = Vector3(uniform_scale, uniform_scale, uniform_scale)

	return instance

## Place furniture in a room from a room spec dictionary.
## room_spec should have keys: position (Vector3), size (Vector3), furniture (Array of dicts).
## Each furniture dict: { "type": String, "position": Vector3, "size": Vector3 }
func _place_furniture_in_room(parent: Node3D, room_spec: Dictionary) -> void:
	var furniture_list: Array = room_spec.get("furniture", [])
	for item in furniture_list:
		var ftype: String = item.get("type", "")
		var fpos_dict: Dictionary = item.get("position", {})
		var fpos := Vector3(fpos_dict.get("x", 0), fpos_dict.get("y", 0), fpos_dict.get("z", 0))
		var fsize_dict: Dictionary = item.get("size", {})
		var fsize := Vector3(fsize_dict.get("x", 1), fsize_dict.get("y", 1), fsize_dict.get("z", 1))

		var furniture_node := _clone_furniture(ftype, fsize)
		if furniture_node:
			furniture_node.position = fpos
			furniture_node.name = "Furniture_%s" % ftype
			parent.add_child(furniture_node)

## Create an exit door with click/interaction detection using Area3D.
## Emits exit_door_clicked signal when the player interacts with the door.
func _create_exit_door(parent: Node3D, building_id: String, door_pos: Vector3,
		door_width: float, door_height: float) -> void:
	var door := MeshInstance3D.new()
	var door_box := BoxMesh.new()
	door_box.size = Vector3(door_width, door_height, 0.3)
	door.mesh = door_box
	door.name = "ExitDoor"
	door.position = door_pos

	var door_mat := StandardMaterial3D.new()
	door_mat.albedo_color = Color(0.45, 0.3, 0.15)
	door_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	door_mat.albedo_color.a = 0.7
	door.material_override = door_mat
	parent.add_child(door)

	# Area3D for click/interaction detection
	var area := Area3D.new()
	area.name = "ExitDoorArea"
	area.set_meta("interiorExit", true)
	area.set_meta("buildingId", building_id)
	var area_col := CollisionShape3D.new()
	var area_shape := BoxShape3D.new()
	area_shape.size = Vector3(door_width + 0.5, door_height, 1.0)
	area_col.shape = area_shape
	area.add_child(area_col)
	area.position = door_pos
	area.input_event.connect(
		func(_camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				exit_door_clicked.emit(building_id)
	)
	# Enable input ray picking on the area
	area.input_ray_pickable = true
	parent.add_child(area)

func _generate_building_procedural(pos: Vector3, rot: float, floors: int, width: float, depth: float, role: String) -> void:
	var floor_height := 3.0
	var total_height := floors * floor_height

	# Sample terrain height at corners for foundation adaptation
	var foundation_height := _compute_foundation(pos, rot, width, depth)
	var base_y: float = pos.y + foundation_height

	# Base
	var building := MeshInstance3D.new()
	building.mesh = BoxMesh.new()
	(building.mesh as BoxMesh).size = Vector3(width, total_height, depth)
	building.position = Vector3(pos.x, base_y + total_height / 2.0, pos.z)
	building.rotation.y = deg_to_rad(rot)
	building.name = "Building_%s" % role

	var mat := StandardMaterial3D.new()
	mat.albedo_color = base_color
	building.material_override = mat

	# Collision
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(width, total_height, depth)
	col.shape = shape
	body.add_child(col)
	building.add_child(body)

	# Foundation geometry (fill gap between terrain and building base)
	if foundation_height > 0.3:
		_add_foundation(building, width, depth, total_height, foundation_height)

	# Roof
	var roof := MeshInstance3D.new()
	roof.mesh = BoxMesh.new()
	(roof.mesh as BoxMesh).size = Vector3(width + 1, 1, depth + 1)
	roof.position = Vector3(0, total_height / 2.0 + 0.5, 0)
	var roof_mat := StandardMaterial3D.new()
	roof_mat.albedo_color = roof_color
	roof.material_override = roof_mat
	building.add_child(roof)

	# Exit door with interaction area at front of building
	var door_width := 1.2
	var door_height := 2.2
	var ground_y := -total_height / 2.0
	var front_z := depth / 2.0
	_create_exit_door(building, "building_%s" % role,
		Vector3(0, ground_y + door_height / 2.0, front_z),
		door_width, door_height)

	# Place furniture in each room (if templates are loaded)
	if _furniture_templates.size() > 0:
		for floor_i in range(floors):
			var room_spec := {
				"position": { "x": 0, "y": floor_height * floor_i, "z": 0 },
				"size": { "x": width - 1.0, "y": floor_height, "z": depth - 1.0 },
				"furniture": []  # Populated by world data or config
			}
			_place_furniture_in_room(building, room_spec)

	add_child(building)

## Sample terrain at building corners and return the height delta needed.
func _compute_foundation(pos: Vector3, rot: float, width: float, depth: float) -> float:
	var terrain: Node = _find_terrain()
	if terrain == null or not terrain.has_method("sample_height"):
		return 0.0

	var cos_r: float = cos(deg_to_rad(rot))
	var sin_r: float = sin(deg_to_rad(rot))
	var hw: float = width / 2.0
	var hd: float = depth / 2.0

	# Sample 4 corners + center
	var corners := [
		Vector2(-hw, -hd), Vector2(hw, -hd),
		Vector2(-hw, hd), Vector2(hw, hd), Vector2(0, 0),
	]

	var max_h: float = pos.y
	for c in corners:
		var wx: float = pos.x + cos_r * c.x - sin_r * c.y
		var wz: float = pos.z + sin_r * c.x + cos_r * c.y
		var h: float = terrain.sample_height(wx, wz)
		max_h = maxf(max_h, h)

	return maxf(0.0, max_h - pos.y)

## Add foundation mesh to fill the gap under a building.
func _add_foundation(building: MeshInstance3D, width: float, depth: float,
		total_height: float, fnd_height: float) -> void:
	var fnd_mat := StandardMaterial3D.new()
	fnd_mat.albedo_color = Color(0.45, 0.42, 0.38)  # Stone gray

	if fnd_height <= 1.0:
		# Short foundation: solid stone perimeter wall
		var fnd := MeshInstance3D.new()
		var fnd_box := BoxMesh.new()
		fnd_box.size = Vector3(width + 0.2, fnd_height, depth + 0.2)
		fnd.mesh = fnd_box
		fnd.position.y = -(total_height / 2.0) - fnd_height / 2.0
		fnd.material_override = fnd_mat
		fnd.name = "Foundation"
		building.add_child(fnd)
	elif fnd_height <= 2.5:
		# Medium foundation: stilted posts with cross-beams
		var post_positions := [
			Vector2(-width/2.0 + 0.3, -depth/2.0 + 0.3),
			Vector2(width/2.0 - 0.3, -depth/2.0 + 0.3),
			Vector2(-width/2.0 + 0.3, depth/2.0 - 0.3),
			Vector2(width/2.0 - 0.3, depth/2.0 - 0.3),
		]
		# Add center posts for wide buildings
		if width > 8.0:
			post_positions.append(Vector2(0, -depth/2.0 + 0.3))
			post_positions.append(Vector2(0, depth/2.0 - 0.3))

		var post_mat := StandardMaterial3D.new()
		post_mat.albedo_color = Color(0.35, 0.22, 0.12)  # Wood brown

		for pp in post_positions:
			var post := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.15
			cyl.bottom_radius = 0.15
			cyl.height = fnd_height
			cyl.radial_segments = 6
			post.mesh = cyl
			post.position = Vector3(pp.x, -(total_height / 2.0) - fnd_height / 2.0, pp.y)
			post.material_override = post_mat
			post.name = "StiltPost"
			building.add_child(post)

		# Cross-beams connecting posts
		var beam := MeshInstance3D.new()
		var beam_box := BoxMesh.new()
		beam_box.size = Vector3(width - 0.4, 0.15, 0.15)
		beam.mesh = beam_box
		beam.position.y = -(total_height / 2.0) - fnd_height * 0.4
		beam.material_override = post_mat
		beam.name = "CrossBeam"
		building.add_child(beam)
	else:
		# Tall foundation: terraced retaining wall
		var wall_count: int = ceili(fnd_height / 1.2)
		var wall_height: float = fnd_height / float(wall_count)
		for i in range(wall_count):
			var shrink: float = 1.0 - float(i) * 0.08
			var wall := MeshInstance3D.new()
			var wall_box := BoxMesh.new()
			wall_box.size = Vector3(
				(width + 0.4) * shrink,
				wall_height,
				(depth + 0.4) * shrink
			)
			wall.mesh = wall_box
			wall.position.y = -(total_height / 2.0) - fnd_height + wall_height * (float(i) + 0.5)
			wall.material_override = fnd_mat
			wall.name = "RetainingWall_%d" % i
			building.add_child(wall)

func _find_terrain() -> Node:
	for gen in get_tree().get_nodes_in_group("world_generator"):
		if gen.has_method("sample_height"):
			return gen
	return null
