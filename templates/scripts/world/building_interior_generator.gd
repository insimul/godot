extends Node3D
## Building interior generator — creates procedural multi-room interiors
## matching BuildingInteriorGenerator.ts.

const PARTITION_THICKNESS := 0.25
const INTERIOR_DOOR_WIDTH := 2.0
const INTERIOR_DOOR_HEIGHT := 3.0
const CEILING_HEIGHT := 3.0
const STAIR_WIDTH := 2.0
const STAIR_STEP_HEIGHT := 0.3
const WINDOW_WIDTH := 1.5
const WINDOW_HEIGHT := 1.8
const WINDOW_BOTTOM_Y := 1.2

## Room function → furniture list.
const ROOM_FURNITURE := {
	"living_room": ["chair", "table", "bookshelf", "rug"],
	"kitchen": ["counter", "table", "chair", "barrel"],
	"bedroom": ["bed", "wardrobe", "chest", "chair"],
	"dining_room": ["table", "chair", "chair", "shelf"],
	"tavern_main": ["counter", "stool", "stool", "table", "bench", "barrel"],
	"church_nave": ["pew", "pew", "pew", "altar", "candelabra"],
	"shop_floor": ["counter", "shelf", "shelf", "display_case"],
	"workshop": ["workbench", "anvil", "barrel", "chest"],
	"office": ["desk", "chair", "bookshelf", "safe"],
	"storage": ["barrel", "crate", "chest", "shelf"],
	"medical": ["bed", "desk", "shelf", "chair"],
}

## Surface texture colors by type.
const SURFACE_COLORS := {
	"wood_plank": Color(0.45, 0.3, 0.15),
	"stone_tile": Color(0.55, 0.52, 0.48),
	"plaster": Color(0.75, 0.72, 0.68),
	"wood_panel": Color(0.5, 0.35, 0.18),
	"stone_block": Color(0.5, 0.48, 0.43),
	"brick": Color(0.6, 0.35, 0.25),
	"marble": Color(0.85, 0.83, 0.8),
	"dirt": Color(0.4, 0.32, 0.2),
	"wood_beam": Color(0.35, 0.22, 0.1),
}

## Role → surface style mapping.
const ROLE_SURFACES := {
	"residential": {"floor": "wood_plank", "wall": "plaster", "ceiling": "plaster"},
	"tavern": {"floor": "wood_plank", "wall": "wood_panel", "ceiling": "wood_beam"},
	"inn": {"floor": "wood_plank", "wall": "wood_panel", "ceiling": "wood_beam"},
	"church": {"floor": "stone_tile", "wall": "stone_block", "ceiling": "stone_block"},
	"shop": {"floor": "wood_plank", "wall": "plaster", "ceiling": "plaster"},
	"blacksmith": {"floor": "stone_tile", "wall": "stone_block", "ceiling": "wood_beam"},
	"warehouse": {"floor": "stone_tile", "wall": "brick", "ceiling": "wood_beam"},
	"office": {"floor": "wood_plank", "wall": "plaster", "ceiling": "plaster"},
}

func _ready() -> void:
	add_to_group("world_generator")

## Generate a complete interior for a building.
## Returns a Node3D containing all interior geometry, furniture, and lighting.
func generate_interior(building_data: Dictionary) -> Node3D:
	var spec: Dictionary = building_data.get("spec", {})
	var width: float = spec.get("width", 10.0)
	var depth: float = spec.get("depth", 10.0)
	var floors: int = spec.get("floors", 1)
	var role: String = spec.get("buildingRole", "residential")
	var bld_id: String = building_data.get("id", "unknown")
	## Map furniture type → asset file path. Overrides default procedural models.
	var furn_assets: Dictionary = building_data.get("interiorConfig", {}).get("furnitureAssets", {})

	var interior := Node3D.new()
	interior.name = "Interior_%s" % bld_id

	var surfaces: Dictionary = ROLE_SURFACES.get(role, ROLE_SURFACES["residential"])

	for floor_idx in range(floors):
		var floor_y := floor_idx * CEILING_HEIGHT
		var rooms := _compute_room_layout(width, depth, role, floor_idx, floors)

		for room in rooms:
			_generate_room(interior, room, floor_y, surfaces, bld_id, furn_assets)

		# Add stairs between floors
		if floor_idx < floors - 1:
			_add_staircase(interior, width, depth, floor_y)

	return interior

func _compute_room_layout(width: float, depth: float, role: String,
		floor_idx: int, total_floors: int) -> Array[Dictionary]:
	var rooms: Array[Dictionary] = []

	if floor_idx == 0:
		match role:
			"tavern", "inn", "bar":
				rooms.append({"name": "Main Hall", "function": "tavern_main",
					"offset_x": 0, "offset_z": 0, "width": width * 0.7, "depth": depth})
				rooms.append({"name": "Kitchen", "function": "kitchen",
					"offset_x": width * 0.7, "offset_z": 0, "width": width * 0.3, "depth": depth * 0.5})
				rooms.append({"name": "Storage", "function": "storage",
					"offset_x": width * 0.7, "offset_z": depth * 0.5, "width": width * 0.3, "depth": depth * 0.5})
			"church", "temple":
				rooms.append({"name": "Nave", "function": "church_nave",
					"offset_x": 0, "offset_z": 0, "width": width, "depth": depth * 0.8})
				rooms.append({"name": "Vestry", "function": "storage",
					"offset_x": 0, "offset_z": depth * 0.8, "width": width, "depth": depth * 0.2})
			"shop", "merchant", "general_store":
				rooms.append({"name": "Shop Floor", "function": "shop_floor",
					"offset_x": 0, "offset_z": 0, "width": width, "depth": depth * 0.7})
				rooms.append({"name": "Back Room", "function": "storage",
					"offset_x": 0, "offset_z": depth * 0.7, "width": width, "depth": depth * 0.3})
			"blacksmith", "forge":
				rooms.append({"name": "Workshop", "function": "workshop",
					"offset_x": 0, "offset_z": 0, "width": width, "depth": depth})
			_:
				# Residential default
				rooms.append({"name": "Living Room", "function": "living_room",
					"offset_x": 0, "offset_z": 0, "width": width * 0.6, "depth": depth})
				rooms.append({"name": "Kitchen", "function": "kitchen",
					"offset_x": width * 0.6, "offset_z": 0, "width": width * 0.4, "depth": depth})
	else:
		# Upper floors: bedrooms and offices
		var room_count := maxi(1, floori(width * depth / 25.0))
		var room_width := width / float(room_count)

		for i in range(room_count):
			var func_name: String
			if i == 0 and total_floors > 2:
				func_name = "office"
			else:
				func_name = "bedroom"

			rooms.append({
				"name": "Room %d" % (i + 1),
				"function": func_name,
				"offset_x": i * room_width,
				"offset_z": 0,
				"width": room_width,
				"depth": depth,
			})

	return rooms

func _generate_room(parent: Node3D, room: Dictionary, floor_y: float,
		surfaces: Dictionary, bld_id: String, furniture_assets: Dictionary = {}) -> void:
	var rw: float = room["width"]
	var rd: float = room["depth"]
	var ox: float = room["offset_x"]
	var oz: float = room["offset_z"]
	var room_func: String = room["function"]
	var room_name: String = room["name"]

	var room_node := Node3D.new()
	room_node.name = room_name.replace(" ", "_")
	room_node.position = Vector3(ox, floor_y, oz)

	# Floor
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = SURFACE_COLORS.get(surfaces.get("floor", "wood_plank"), Color(0.45, 0.3, 0.15))

	var floor_mesh := MeshInstance3D.new()
	floor_mesh.mesh = BoxMesh.new()
	(floor_mesh.mesh as BoxMesh).size = Vector3(rw, 0.1, rd)
	floor_mesh.position = Vector3(rw / 2.0, 0.05, rd / 2.0)
	floor_mesh.material_override = floor_mat
	floor_mesh.name = "Floor"
	room_node.add_child(floor_mesh)

	# Ceiling
	var ceil_mat := StandardMaterial3D.new()
	ceil_mat.albedo_color = SURFACE_COLORS.get(surfaces.get("ceiling", "plaster"), Color(0.75, 0.72, 0.68))

	var ceil_mesh := MeshInstance3D.new()
	ceil_mesh.mesh = BoxMesh.new()
	(ceil_mesh.mesh as BoxMesh).size = Vector3(rw, 0.1, rd)
	ceil_mesh.position = Vector3(rw / 2.0, CEILING_HEIGHT, rd / 2.0)
	ceil_mesh.material_override = ceil_mat
	ceil_mesh.name = "Ceiling"
	room_node.add_child(ceil_mesh)

	# Partition walls (between rooms)
	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = SURFACE_COLORS.get(surfaces.get("wall", "plaster"), Color(0.75, 0.72, 0.68))

	# Left partition
	if ox > 0.1:
		var wall := MeshInstance3D.new()
		wall.mesh = BoxMesh.new()
		(wall.mesh as BoxMesh).size = Vector3(PARTITION_THICKNESS, CEILING_HEIGHT, rd)
		wall.position = Vector3(0, CEILING_HEIGHT / 2.0, rd / 2.0)
		wall.material_override = wall_mat
		wall.name = "LeftPartition"
		room_node.add_child(wall)

	# Back partition
	if oz > 0.1:
		var wall := MeshInstance3D.new()
		wall.mesh = BoxMesh.new()
		(wall.mesh as BoxMesh).size = Vector3(rw, CEILING_HEIGHT, PARTITION_THICKNESS)
		wall.position = Vector3(rw / 2.0, CEILING_HEIGHT / 2.0, 0)
		wall.material_override = wall_mat
		wall.name = "BackPartition"
		room_node.add_child(wall)

	# Place furniture — pass furniture_assets override map if present in building config
	_place_room_furniture(room_node, room_func, rw, rd, bld_id, furniture_assets)

	parent.add_child(room_node)

func _place_room_furniture(room_node: Node3D, room_func: String,
		rw: float, rd: float, bld_id: String, furniture_assets: Dictionary = {}) -> void:
	var furniture_list: Array = ROOM_FURNITURE.get(room_func, [])
	if furniture_list.is_empty():
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = (bld_id + room_func).hash()

	var placed := 0
	for furn_type in furniture_list:
		if placed >= 8:
			break

		var pos := _get_furniture_position(furn_type, rw, rd, placed, rng)
		var furn: Node3D
		# Check for asset override: load custom model if furnitureAssets maps this type
		var asset_path: String = furniture_assets.get(furn_type, "")
		if asset_path != "" and ResourceLoader.exists(asset_path):
			var scene: PackedScene = load(asset_path)
			if scene:
				furn = scene.instantiate()
			else:
				furn = _create_furniture_mesh(furn_type)
		else:
			furn = _create_furniture_mesh(furn_type)
		furn.position = pos
		room_node.add_child(furn)
		placed += 1

func _get_furniture_position(furn_type: String, rw: float, rd: float,
		index: int, rng: RandomNumberGenerator) -> Vector3:
	# Place furniture along walls or in the center based on type
	var margin := 0.5
	match furn_type:
		"bed", "wardrobe", "bookshelf", "shelf", "display_case":
			# Wall furniture — along back or side walls
			var side := index % 3
			match side:
				0: return Vector3(rw / 2.0, 0, margin)
				1: return Vector3(margin, 0, rd / 2.0)
				_: return Vector3(rw - margin, 0, rd / 2.0)
		"counter", "workbench", "desk":
			return Vector3(rw / 2.0, 0, rd * 0.3)
		"altar":
			return Vector3(rw / 2.0, 0, rd * 0.2)
		"pew":
			return Vector3(rw / 2.0, 0, rd * 0.3 + index * 1.5)
		_:
			# Scatter in room
			return Vector3(
				margin + rng.randf() * (rw - margin * 2),
				0,
				margin + rng.randf() * (rd - margin * 2)
			)

func _create_furniture_mesh(furn_type: String) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = furn_type.capitalize().replace(" ", "")
	var mat := StandardMaterial3D.new()

	match furn_type:
		"bed", "bed_single", "bed_double":
			mesh.mesh = BoxMesh.new()
			(mesh.mesh as BoxMesh).size = Vector3(1.2, 0.5, 2.0)
			mesh.position.y = 0.25
			mat.albedo_color = Color(0.6, 0.45, 0.3)
		"table":
			mesh.mesh = BoxMesh.new()
			(mesh.mesh as BoxMesh).size = Vector3(1.2, 0.8, 0.8)
			mesh.position.y = 0.4
			mat.albedo_color = Color(0.5, 0.35, 0.18)
		"chair", "stool":
			mesh.mesh = BoxMesh.new()
			(mesh.mesh as BoxMesh).size = Vector3(0.5, 0.5, 0.5)
			mesh.position.y = 0.25
			mat.albedo_color = Color(0.45, 0.32, 0.15)
		"bench", "pew":
			mesh.mesh = BoxMesh.new()
			(mesh.mesh as BoxMesh).size = Vector3(2.0, 0.5, 0.6)
			mesh.position.y = 0.25
			mat.albedo_color = Color(0.4, 0.28, 0.12)
		"counter", "workbench", "desk":
			mesh.mesh = BoxMesh.new()
			(mesh.mesh as BoxMesh).size = Vector3(2.0, 0.9, 0.7)
			mesh.position.y = 0.45
			mat.albedo_color = Color(0.5, 0.38, 0.2)
		"bookshelf", "shelf", "wardrobe":
			mesh.mesh = BoxMesh.new()
			(mesh.mesh as BoxMesh).size = Vector3(1.0, 2.0, 0.4)
			mesh.position.y = 1.0
			mat.albedo_color = Color(0.45, 0.3, 0.15)
		"chest", "safe":
			mesh.mesh = BoxMesh.new()
			(mesh.mesh as BoxMesh).size = Vector3(0.8, 0.5, 0.5)
			mesh.position.y = 0.25
			mat.albedo_color = Color(0.4, 0.25, 0.1)
		"barrel", "crate":
			mesh.mesh = CylinderMesh.new() if furn_type == "barrel" else BoxMesh.new()
			if furn_type == "barrel":
				(mesh.mesh as CylinderMesh).top_radius = 0.3
				(mesh.mesh as CylinderMesh).bottom_radius = 0.35
				(mesh.mesh as CylinderMesh).height = 0.8
			else:
				(mesh.mesh as BoxMesh).size = Vector3(0.6, 0.6, 0.6)
			mesh.position.y = 0.35
			mat.albedo_color = Color(0.5, 0.35, 0.2)
		"anvil":
			mesh.mesh = BoxMesh.new()
			(mesh.mesh as BoxMesh).size = Vector3(0.6, 0.6, 0.4)
			mesh.position.y = 0.3
			mat.albedo_color = Color(0.3, 0.3, 0.32)
		"altar":
			mesh.mesh = BoxMesh.new()
			(mesh.mesh as BoxMesh).size = Vector3(1.5, 1.0, 0.8)
			mesh.position.y = 0.5
			mat.albedo_color = Color(0.6, 0.58, 0.55)
		"display_case":
			mesh.mesh = BoxMesh.new()
			(mesh.mesh as BoxMesh).size = Vector3(1.0, 1.2, 0.6)
			mesh.position.y = 0.6
			mat.albedo_color = Color(0.5, 0.48, 0.42)
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.albedo_color.a = 0.8
		"candelabra":
			mesh.mesh = CylinderMesh.new()
			(mesh.mesh as CylinderMesh).top_radius = 0.15
			(mesh.mesh as CylinderMesh).bottom_radius = 0.1
			(mesh.mesh as CylinderMesh).height = 1.2
			mesh.position.y = 0.6
			mat.albedo_color = Color(0.7, 0.6, 0.3)
			mat.emission_enabled = true
			mat.emission = Color(0.9, 0.7, 0.3)
		"rug":
			mesh.mesh = BoxMesh.new()
			(mesh.mesh as BoxMesh).size = Vector3(2.0, 0.02, 1.5)
			mesh.position.y = 0.11
			mat.albedo_color = Color(0.5, 0.2, 0.15)
		_:
			mesh.mesh = BoxMesh.new()
			(mesh.mesh as BoxMesh).size = Vector3(0.5, 0.5, 0.5)
			mesh.position.y = 0.25
			mat.albedo_color = Color(0.5, 0.4, 0.3)

	mesh.material_override = mat
	return mesh

func _add_staircase(parent: Node3D, width: float, depth: float, floor_y: float) -> void:
	var stair_node := Node3D.new()
	stair_node.name = "Staircase"
	stair_node.position = Vector3(width - STAIR_WIDTH - 0.5, floor_y, depth / 2.0 - 1.0)

	var step_count := ceili(CEILING_HEIGHT / STAIR_STEP_HEIGHT)
	var step_depth := 2.0 / float(step_count)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.3, 0.15)

	for i in range(step_count):
		var step := MeshInstance3D.new()
		step.mesh = BoxMesh.new()
		(step.mesh as BoxMesh).size = Vector3(STAIR_WIDTH, STAIR_STEP_HEIGHT, step_depth)
		step.position = Vector3(0, STAIR_STEP_HEIGHT * (i + 0.5), step_depth * i)
		step.material_override = mat
		step.name = "Step_%d" % i
		stair_node.add_child(step)

	parent.add_child(stair_node)
