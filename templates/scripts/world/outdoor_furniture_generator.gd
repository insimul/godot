extends Node3D
## Outdoor furniture generator — places outdoor furniture and decorations
## in settlements matching OutdoorFurnitureGenerator.ts.
## Uses MultiMeshInstance3D for repeated props for performance.

## World-type-specific furniture sets.
const FURNITURE_SETS := {
	"medieval-fantasy": ["lamp_post", "bench", "well", "market_stall", "water_trough", "food_stall", "weapon_rack", "barrel", "crate"],
	"dark-fantasy": ["lamp_post", "bench", "well", "barrel", "crate", "hanging_lantern", "weapon_rack"],
	"cyberpunk": ["streetlight", "terminal", "planter", "chair_set", "bench"],
	"sci-fi-space": ["streetlight", "terminal", "planter", "chair_set"],
	"modern": ["streetlight", "bench", "planter", "picnic_table", "chair_set"],
	"western": ["barrel", "well", "water_trough", "signpost", "food_stall", "bench"],
	"generic": ["lamp_post", "bench", "barrel", "crate", "planter"],
}

## Furniture type → approximate height for placement.
const FURNITURE_SIZES := {
	"lamp_post": 2.5,
	"streetlight": 3.0,
	"bench": 0.8,
	"well": 1.2,
	"barrel": 0.8,
	"crate": 0.6,
	"market_stall": 2.2,
	"food_stall": 2.2,
	"weapon_rack": 1.8,
	"water_trough": 0.6,
	"planter": 0.8,
	"picnic_table": 0.9,
	"chair_set": 0.8,
	"terminal": 1.2,
	"signpost": 2.0,
	"hanging_lantern": 2.5,
	"flower_cart": 1.0,
}

var _world_type: String = "medieval-fantasy"
var _multimesh_batches: Dictionary = {}  # type → Array[Transform3D]

func _ready() -> void:
	add_to_group("world_generator")

func generate_from_data(world_data: Dictionary) -> void:
	_world_type = world_data.get("meta", {}).get("worldType", "medieval-fantasy")
	var settlements: Array = world_data.get("geography", {}).get("settlements", [])
	if settlements.is_empty():
		settlements = world_data.get("settlements", [])

	var total := 0
	for settlement in settlements:
		var pos_dict: Dictionary = settlement.get("position", {})
		var center := Vector3(pos_dict.get("x", 0), pos_dict.get("y", 0), pos_dict.get("z", 0))
		var radius: float = settlement.get("radius", 50.0)
		var sid: String = settlement.get("id", "")

		total += _populate_settlement(center, radius, sid, settlement)

	# Create MultiMeshInstance3D for batched types
	_flush_batches()

	if total > 0:
		print("[Insimul] OutdoorFurnitureGenerator: %d items placed" % total)

func _populate_settlement(center: Vector3, radius: float, sid: String, settlement: Dictionary) -> int:
	var furniture_set: Array = FURNITURE_SETS.get(_world_type, FURNITURE_SETS["generic"])
	var rng := RandomNumberGenerator.new()
	rng.seed = sid.hash()

	# Determine furniture count based on settlement size
	var population: int = settlement.get("population", 100)
	var item_count := clampi(population / 10, 5, 50)

	var streets: Array = []
	var sn: Variant = settlement.get("streetNetwork", null)
	if sn is Dictionary:
		streets = sn.get("segments", [])

	var placed := 0
	for i in range(item_count):
		var furn_type: String = furniture_set[rng.randi() % furniture_set.size()]
		var pos: Vector3

		if streets.size() > 0 and rng.randf() < 0.7:
			# Place along a street
			var seg: Dictionary = streets[rng.randi() % streets.size()]
			var waypoints: Array = seg.get("waypoints", [])
			if waypoints.size() >= 2:
				var t := rng.randf()
				var wp_a: Dictionary = waypoints[0]
				var wp_b: Dictionary = waypoints[waypoints.size() - 1]
				var a := Vector3(wp_a.get("x", 0), 0, wp_a.get("z", 0))
				var b := Vector3(wp_b.get("x", 0), 0, wp_b.get("z", 0))
				var along := a.lerp(b, t)
				var dir := (b - a).normalized()
				var perp := Vector3(-dir.z, 0, dir.x)
				var side: float = -5.0 if rng.randf() > 0.5 else 5.0
				pos = along + perp * side
			else:
				pos = center + _random_offset(rng, radius * 0.8)
		else:
			pos = center + _random_offset(rng, radius * 0.8)

		# Try to use terrain height
		var terrain := _find_terrain()
		if terrain != null and terrain.has_method("sample_height"):
			pos.y = terrain.sample_height(pos.x, pos.z)

		# Batch frequently-repeated types
		if furn_type in ["lamp_post", "streetlight", "barrel", "crate"]:
			if not _multimesh_batches.has(furn_type):
				_multimesh_batches[furn_type] = []
			(_multimesh_batches[furn_type] as Array).append(Transform3D(Basis(), pos))
		else:
			var node := _create_furniture(furn_type, rng)
			node.position = pos
			add_child(node)

		placed += 1

	return placed

func _flush_batches() -> void:
	for furn_type: String in _multimesh_batches:
		var transforms: Array = _multimesh_batches[furn_type]
		if transforms.is_empty():
			continue

		var mesh := _get_furniture_mesh(furn_type)
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = mesh
		multi.instance_count = transforms.size()

		for i in range(transforms.size()):
			multi.set_instance_transform(i, transforms[i])

		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = multi
		mmi.name = "Batch_%s" % furn_type
		add_child(mmi)

	_multimesh_batches.clear()

func _create_furniture(furn_type: String, rng: RandomNumberGenerator) -> Node3D:
	var node := Node3D.new()
	node.name = furn_type.capitalize().replace("_", "")

	match furn_type:
		"bench":
			_add_bench(node)
		"well":
			_add_well(node)
		"market_stall", "food_stall":
			_add_market_stall(node, furn_type == "food_stall")
		"weapon_rack":
			_add_weapon_rack(node)
		"water_trough":
			_add_water_trough(node)
		"planter":
			_add_planter(node, rng)
		"picnic_table":
			_add_picnic_table(node)
		"terminal":
			_add_terminal(node)
		"signpost":
			_add_signpost(node)
		"hanging_lantern":
			_add_hanging_lantern(node)
		_:
			# Fallback: simple mesh
			var m := MeshInstance3D.new()
			m.mesh = BoxMesh.new()
			(m.mesh as BoxMesh).size = Vector3(0.5, 0.5, 0.5)
			m.position.y = 0.25
			node.add_child(m)

	return node

func _get_furniture_mesh(furn_type: String) -> Mesh:
	match furn_type:
		"lamp_post", "streetlight":
			var mesh := CylinderMesh.new()
			mesh.top_radius = 0.05
			mesh.bottom_radius = 0.08
			mesh.height = FURNITURE_SIZES.get(furn_type, 2.5)
			return mesh
		"barrel":
			var mesh := CylinderMesh.new()
			mesh.top_radius = 0.3
			mesh.bottom_radius = 0.35
			mesh.height = 0.8
			return mesh
		"crate":
			var mesh := BoxMesh.new()
			mesh.size = Vector3(0.6, 0.6, 0.6)
			return mesh
		_:
			var mesh := BoxMesh.new()
			mesh.size = Vector3(0.5, 0.5, 0.5)
			return mesh

func _add_bench(parent: Node3D) -> void:
	var wood_mat := StandardMaterial3D.new()
	wood_mat.albedo_color = Color(0.45, 0.3, 0.15)

	var seat := MeshInstance3D.new()
	seat.mesh = BoxMesh.new()
	(seat.mesh as BoxMesh).size = Vector3(2.0, 0.1, 0.5)
	seat.position.y = 0.45
	seat.material_override = wood_mat
	parent.add_child(seat)

	for lx in [-0.8, 0.8]:
		var leg := MeshInstance3D.new()
		leg.mesh = BoxMesh.new()
		(leg.mesh as BoxMesh).size = Vector3(0.08, 0.45, 0.4)
		leg.position = Vector3(lx, 0.225, 0)
		leg.material_override = wood_mat
		parent.add_child(leg)

func _add_well(parent: Node3D) -> void:
	var stone_mat := StandardMaterial3D.new()
	stone_mat.albedo_color = Color(0.5, 0.48, 0.43)

	var base := MeshInstance3D.new()
	base.mesh = CylinderMesh.new()
	(base.mesh as CylinderMesh).top_radius = 0.8
	(base.mesh as CylinderMesh).bottom_radius = 0.9
	(base.mesh as CylinderMesh).height = 0.8
	base.position.y = 0.4
	base.material_override = stone_mat
	parent.add_child(base)

	# Roof support posts
	var wood_mat := StandardMaterial3D.new()
	wood_mat.albedo_color = Color(0.4, 0.28, 0.12)
	for px in [-0.6, 0.6]:
		var post := MeshInstance3D.new()
		post.mesh = CylinderMesh.new()
		(post.mesh as CylinderMesh).top_radius = 0.04
		(post.mesh as CylinderMesh).bottom_radius = 0.04
		(post.mesh as CylinderMesh).height = 1.5
		post.position = Vector3(px, 1.55, 0)
		post.material_override = wood_mat
		parent.add_child(post)

func _add_market_stall(parent: Node3D, is_food: bool) -> void:
	var wood_mat := StandardMaterial3D.new()
	wood_mat.albedo_color = Color(0.45, 0.3, 0.15)

	# Counter
	var counter := MeshInstance3D.new()
	counter.mesh = BoxMesh.new()
	(counter.mesh as BoxMesh).size = Vector3(2.5, 0.9, 1.0)
	counter.position.y = 0.45
	counter.material_override = wood_mat
	parent.add_child(counter)

	# Roof canopy
	var canopy := MeshInstance3D.new()
	canopy.mesh = BoxMesh.new()
	(canopy.mesh as BoxMesh).size = Vector3(3.0, 0.05, 1.5)
	canopy.position.y = 2.2
	var canopy_mat := StandardMaterial3D.new()
	canopy_mat.albedo_color = Color(0.6, 0.15, 0.1) if is_food else Color(0.15, 0.3, 0.15)
	canopy.material_override = canopy_mat
	parent.add_child(canopy)

	# Support poles
	for px in [-1.2, 1.2]:
		var pole := MeshInstance3D.new()
		pole.mesh = CylinderMesh.new()
		(pole.mesh as CylinderMesh).top_radius = 0.04
		(pole.mesh as CylinderMesh).bottom_radius = 0.04
		(pole.mesh as CylinderMesh).height = 2.2
		pole.position = Vector3(px, 1.1, -0.5)
		pole.material_override = wood_mat
		parent.add_child(pole)

func _add_weapon_rack(parent: Node3D) -> void:
	var wood_mat := StandardMaterial3D.new()
	wood_mat.albedo_color = Color(0.4, 0.28, 0.12)

	var frame := MeshInstance3D.new()
	frame.mesh = BoxMesh.new()
	(frame.mesh as BoxMesh).size = Vector3(1.5, 1.8, 0.15)
	frame.position.y = 0.9
	frame.material_override = wood_mat
	parent.add_child(frame)

func _add_water_trough(parent: Node3D) -> void:
	var wood_mat := StandardMaterial3D.new()
	wood_mat.albedo_color = Color(0.4, 0.28, 0.12)

	var trough := MeshInstance3D.new()
	trough.mesh = BoxMesh.new()
	(trough.mesh as BoxMesh).size = Vector3(1.5, 0.5, 0.6)
	trough.position.y = 0.25
	trough.material_override = wood_mat
	parent.add_child(trough)

func _add_planter(parent: Node3D, rng: RandomNumberGenerator) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.3, 0.15)

	var pot := MeshInstance3D.new()
	pot.mesh = CylinderMesh.new()
	(pot.mesh as CylinderMesh).top_radius = 0.4
	(pot.mesh as CylinderMesh).bottom_radius = 0.3
	(pot.mesh as CylinderMesh).height = 0.6
	pot.position.y = 0.3
	pot.material_override = mat
	parent.add_child(pot)

	var plant := MeshInstance3D.new()
	plant.mesh = SphereMesh.new()
	(plant.mesh as SphereMesh).radius = 0.35
	plant.position.y = 0.75
	var plant_mat := StandardMaterial3D.new()
	plant_mat.albedo_color = Color(0.15 + rng.randf() * 0.15, 0.4 + rng.randf() * 0.2, 0.1)
	plant.material_override = plant_mat
	parent.add_child(plant)

func _add_picnic_table(parent: Node3D) -> void:
	var wood_mat := StandardMaterial3D.new()
	wood_mat.albedo_color = Color(0.5, 0.35, 0.18)

	var top := MeshInstance3D.new()
	top.mesh = BoxMesh.new()
	(top.mesh as BoxMesh).size = Vector3(1.8, 0.08, 0.8)
	top.position.y = 0.75
	top.material_override = wood_mat
	parent.add_child(top)

	for sx in [-0.7, 0.7]:
		var seat := MeshInstance3D.new()
		seat.mesh = BoxMesh.new()
		(seat.mesh as BoxMesh).size = Vector3(1.8, 0.06, 0.3)
		seat.position = Vector3(0, 0.45, sx)
		seat.material_override = wood_mat
		parent.add_child(seat)

func _add_terminal(parent: Node3D) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.28, 0.3)

	var base := MeshInstance3D.new()
	base.mesh = BoxMesh.new()
	(base.mesh as BoxMesh).size = Vector3(0.6, 1.2, 0.3)
	base.position.y = 0.6
	base.material_override = mat
	parent.add_child(base)

	var screen := MeshInstance3D.new()
	screen.mesh = BoxMesh.new()
	(screen.mesh as BoxMesh).size = Vector3(0.5, 0.35, 0.02)
	screen.position = Vector3(0, 1.0, 0.16)
	var screen_mat := StandardMaterial3D.new()
	screen_mat.albedo_color = Color(0.1, 0.3, 0.5)
	screen_mat.emission_enabled = true
	screen_mat.emission = Color(0.1, 0.3, 0.5)
	screen.material_override = screen_mat
	parent.add_child(screen)

func _add_signpost(parent: Node3D) -> void:
	var wood_mat := StandardMaterial3D.new()
	wood_mat.albedo_color = Color(0.4, 0.28, 0.12)

	var post := MeshInstance3D.new()
	post.mesh = CylinderMesh.new()
	(post.mesh as CylinderMesh).top_radius = 0.05
	(post.mesh as CylinderMesh).bottom_radius = 0.06
	(post.mesh as CylinderMesh).height = 2.0
	post.position.y = 1.0
	post.material_override = wood_mat
	parent.add_child(post)

	var sign_board := MeshInstance3D.new()
	sign_board.mesh = BoxMesh.new()
	(sign_board.mesh as BoxMesh).size = Vector3(0.8, 0.3, 0.05)
	sign_board.position = Vector3(0.3, 1.7, 0)
	sign_board.material_override = wood_mat
	parent.add_child(sign_board)

func _add_hanging_lantern(parent: Node3D) -> void:
	var metal_mat := StandardMaterial3D.new()
	metal_mat.albedo_color = Color(0.2, 0.2, 0.22)

	var chain := MeshInstance3D.new()
	chain.mesh = CylinderMesh.new()
	(chain.mesh as CylinderMesh).top_radius = 0.02
	(chain.mesh as CylinderMesh).bottom_radius = 0.02
	(chain.mesh as CylinderMesh).height = 0.5
	chain.position.y = 2.25
	chain.material_override = metal_mat
	parent.add_child(chain)

	var lantern := MeshInstance3D.new()
	lantern.mesh = BoxMesh.new()
	(lantern.mesh as BoxMesh).size = Vector3(0.2, 0.3, 0.2)
	lantern.position.y = 1.95
	var lantern_mat := StandardMaterial3D.new()
	lantern_mat.albedo_color = Color(0.8, 0.65, 0.35)
	lantern_mat.emission_enabled = true
	lantern_mat.emission = Color(0.9, 0.7, 0.3)
	lantern.material_override = lantern_mat
	parent.add_child(lantern)

	var light := OmniLight3D.new()
	light.position.y = 1.95
	light.light_color = Color(0.9, 0.7, 0.4)
	light.light_energy = 1.0
	light.omni_range = 6.0
	light.name = "LanternLight"
	parent.add_child(light)

func _random_offset(rng: RandomNumberGenerator, max_dist: float) -> Vector3:
	var angle := rng.randf() * TAU
	var dist := rng.randf() * max_dist
	return Vector3(cos(angle) * dist, 0, sin(angle) * dist)

func _find_terrain() -> Node:
	for gen in get_tree().get_nodes_in_group("world_generator"):
		if gen.has_method("sample_height"):
			return gen
	return null
