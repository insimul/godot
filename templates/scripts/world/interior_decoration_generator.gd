extends Node3D
## Interior decoration generator — places non-colliding decorative props
## (rugs, paintings, candles, lanterns) matching InteriorDecorationGenerator.ts
## and FurnitureModelLoader.ts.

## Decoration pools by building context.
const DECORATION_POOLS := {
	"tavern": ["shield", "banner", "animal_head", "candle_holder", "barrel_decor", "lantern"],
	"inn": ["painting", "mirror", "candle_holder", "flower_pot", "rug"],
	"church": ["religious_icon", "stained_glass", "banner", "candle_holder", "candelabra"],
	"shop": ["painting", "mirror", "price_list", "sign", "lantern"],
	"blacksmith": ["shield", "weapon_rack_decor", "banner", "lantern"],
	"residential": ["rug", "painting", "flower_pot", "candle_holder", "mirror"],
	"warehouse": ["lantern", "barrel_decor", "crate_decor"],
	"office": ["painting", "bookshelf_decor", "candle_holder", "rug"],
}

## Rug color palettes.
const RUG_COLORS := [
	Color(0.6, 0.15, 0.1),   # Red
	Color(0.15, 0.2, 0.5),   # Blue
	Color(0.5, 0.35, 0.15),  # Brown
	Color(0.2, 0.35, 0.15),  # Green
	Color(0.5, 0.3, 0.4),    # Mauve
]

## Wall decor: height at which items are mounted.
const WALL_DECOR_HEIGHT := 1.8

func _ready() -> void:
	add_to_group("world_generator")

## Decorate a room interior with appropriate props.
func decorate_room(room_node: Node3D, role: String, room_func: String,
		room_width: float, room_depth: float, building_id: String) -> void:
	var pool: Array = DECORATION_POOLS.get(role, DECORATION_POOLS["residential"])
	var rng := RandomNumberGenerator.new()
	rng.seed = (building_id + room_func).hash()

	# Place 2-5 decorations per room
	var count := rng.randi_range(2, 5)

	for i in range(count):
		var decor_type: String = pool[rng.randi() % pool.size()]
		var decor := _create_decoration(decor_type, rng)
		var pos := _get_decoration_position(decor_type, room_width, room_depth, i, rng)
		decor.position = pos
		room_node.add_child(decor)

## Load furniture from bundled GLTF assets. Falls back to procedural if not found.
func load_furniture_model(furniture_type: String, asset_manifest: Dictionary) -> Node3D:
	var category := "furniture"
	var asset_key: String = "assets/models/%s/polyhaven/%s" % [category, furniture_type]

	# Check manifest for mapped path
	var entries: Array = asset_manifest.get("entries", [])
	for entry in entries:
		if entry.get("role", "") == furniture_type or entry.get("id", "") == furniture_type:
			var path: String = entry.get("path", "")
			if path != "" and ResourceLoader.exists("res://" + path):
				var scene := load("res://" + path) as PackedScene
				if scene != null:
					return scene.instantiate()

	# Fallback: use procedural mesh
	return null

func _create_decoration(decor_type: String, rng: RandomNumberGenerator) -> Node3D:
	var node := Node3D.new()
	node.name = decor_type.capitalize().replace("_", "")
	var mat := StandardMaterial3D.new()

	match decor_type:
		"rug":
			var mesh := MeshInstance3D.new()
			mesh.mesh = BoxMesh.new()
			var rw := rng.randf_range(1.8, 3.0)
			var rd := rng.randf_range(1.2, 2.0)
			(mesh.mesh as BoxMesh).size = Vector3(rw, 0.02, rd)
			mesh.position.y = 0.11
			mat.albedo_color = RUG_COLORS[rng.randi() % RUG_COLORS.size()]
			mesh.material_override = mat
			mesh.name = "Rug"
			node.add_child(mesh)

		"painting", "mirror":
			var mesh := MeshInstance3D.new()
			mesh.mesh = BoxMesh.new()
			(mesh.mesh as BoxMesh).size = Vector3(0.8, 0.6, 0.05)
			mesh.position.y = WALL_DECOR_HEIGHT
			if decor_type == "painting":
				mat.albedo_color = Color(rng.randf_range(0.3, 0.7), rng.randf_range(0.2, 0.5), rng.randf_range(0.1, 0.4))
			else:
				mat.albedo_color = Color(0.75, 0.78, 0.8)
				mat.metallic = 0.8
			mesh.material_override = mat
			mesh.name = decor_type.capitalize()
			node.add_child(mesh)

			# Frame
			var frame := MeshInstance3D.new()
			frame.mesh = BoxMesh.new()
			(frame.mesh as BoxMesh).size = Vector3(0.9, 0.7, 0.03)
			frame.position.y = WALL_DECOR_HEIGHT
			frame.position.z = -0.02
			var frame_mat := StandardMaterial3D.new()
			frame_mat.albedo_color = Color(0.35, 0.25, 0.1)
			frame.material_override = frame_mat
			frame.name = "Frame"
			node.add_child(frame)

		"shield":
			var mesh := MeshInstance3D.new()
			mesh.mesh = CylinderMesh.new()
			(mesh.mesh as CylinderMesh).top_radius = 0.35
			(mesh.mesh as CylinderMesh).bottom_radius = 0.35
			(mesh.mesh as CylinderMesh).height = 0.05
			mesh.position.y = WALL_DECOR_HEIGHT
			mesh.rotation.x = PI / 2.0
			mat.albedo_color = Color(0.4, 0.38, 0.35)
			mat.metallic = 0.6
			mesh.material_override = mat
			mesh.name = "Shield"
			node.add_child(mesh)

		"banner":
			var mesh := MeshInstance3D.new()
			mesh.mesh = BoxMesh.new()
			(mesh.mesh as BoxMesh).size = Vector3(0.6, 1.2, 0.02)
			mesh.position.y = WALL_DECOR_HEIGHT + 0.2
			mat.albedo_color = Color(rng.randf_range(0.3, 0.7), rng.randf_range(0.1, 0.3), rng.randf_range(0.1, 0.3))
			mesh.material_override = mat
			mesh.name = "Banner"
			node.add_child(mesh)

		"candle_holder", "candelabra":
			var mesh := MeshInstance3D.new()
			mesh.mesh = CylinderMesh.new()
			(mesh.mesh as CylinderMesh).top_radius = 0.03
			(mesh.mesh as CylinderMesh).bottom_radius = 0.08
			(mesh.mesh as CylinderMesh).height = 0.3
			mesh.position.y = 0.85
			mat.albedo_color = Color(0.7, 0.6, 0.3)
			mesh.material_override = mat
			mesh.name = "CandleBase"
			node.add_child(mesh)

			# Candle flame (emissive)
			var flame := MeshInstance3D.new()
			flame.mesh = SphereMesh.new()
			(flame.mesh as SphereMesh).radius = 0.04
			(flame.mesh as SphereMesh).height = 0.08
			flame.position.y = 1.02
			var flame_mat := StandardMaterial3D.new()
			flame_mat.albedo_color = Color(1.0, 0.8, 0.3)
			flame_mat.emission_enabled = true
			flame_mat.emission = Color(1.0, 0.7, 0.2)
			flame_mat.emission_energy_multiplier = 3.0
			flame.material_override = flame_mat
			flame.name = "Flame"
			node.add_child(flame)

			# Point light
			var light := OmniLight3D.new()
			light.position.y = 1.05
			light.light_color = Color(0.95, 0.7, 0.3)
			light.light_energy = 0.5
			light.omni_range = 3.0
			light.shadow_enabled = false
			light.name = "CandleLight"
			node.add_child(light)

		"flower_pot":
			var pot := MeshInstance3D.new()
			pot.mesh = CylinderMesh.new()
			(pot.mesh as CylinderMesh).top_radius = 0.15
			(pot.mesh as CylinderMesh).bottom_radius = 0.1
			(pot.mesh as CylinderMesh).height = 0.25
			pot.position.y = 0.85
			mat.albedo_color = Color(0.55, 0.3, 0.15)
			pot.material_override = mat
			pot.name = "Pot"
			node.add_child(pot)

			var plant := MeshInstance3D.new()
			plant.mesh = SphereMesh.new()
			(plant.mesh as SphereMesh).radius = 0.15
			plant.position.y = 1.1
			var plant_mat := StandardMaterial3D.new()
			plant_mat.albedo_color = Color(0.2, 0.5, 0.15)
			plant.material_override = plant_mat
			plant.name = "Plant"
			node.add_child(plant)

		"lantern":
			var mesh := MeshInstance3D.new()
			mesh.mesh = BoxMesh.new()
			(mesh.mesh as BoxMesh).size = Vector3(0.15, 0.25, 0.15)
			mesh.position.y = 0.95
			mat.albedo_color = Color(0.3, 0.28, 0.25)
			mesh.material_override = mat
			mesh.name = "Lantern"
			node.add_child(mesh)

			var glow := OmniLight3D.new()
			glow.position.y = 1.0
			glow.light_color = Color(0.9, 0.7, 0.4)
			glow.light_energy = 0.4
			glow.omni_range = 2.5
			glow.name = "LanternGlow"
			node.add_child(glow)

		_:
			# Generic small decoration
			var mesh := MeshInstance3D.new()
			mesh.mesh = BoxMesh.new()
			(mesh.mesh as BoxMesh).size = Vector3(0.3, 0.3, 0.3)
			mesh.position.y = 0.85
			mat.albedo_color = Color(0.5, 0.4, 0.3)
			mesh.material_override = mat
			mesh.name = "Decor"
			node.add_child(mesh)

	return node

func _get_decoration_position(decor_type: String, rw: float, rd: float,
		index: int, rng: RandomNumberGenerator) -> Vector3:
	match decor_type:
		"rug":
			# Center of room
			return Vector3(rw / 2.0, 0, rd / 2.0)
		"painting", "mirror", "shield", "banner", "stained_glass", "religious_icon":
			# On walls
			var wall := index % 4
			match wall:
				0: return Vector3(rw / 2.0, 0, 0.05)
				1: return Vector3(0.05, 0, rd / 2.0)
				2: return Vector3(rw - 0.05, 0, rd / 2.0)
				_: return Vector3(rw / 2.0, 0, rd - 0.05)
		"candle_holder", "candelabra", "lantern", "flower_pot":
			# On surfaces (tables, counters) or corners
			return Vector3(
				rng.randf_range(0.5, rw - 0.5),
				0,
				rng.randf_range(0.5, rd - 0.5)
			)
		_:
			return Vector3(
				rng.randf_range(0.3, rw - 0.3),
				0,
				rng.randf_range(0.3, rd - 0.3)
			)
