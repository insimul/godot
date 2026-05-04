extends Node3D
## Procedural nature/vegetation generator.
## Creates 4 tree types (pine/oak/palm/dead), rocks with irregular scaling,
## geological features (boulders, pillars, outcrops, crystals), and ground
## cover (grass, flowers, shrubs).
## Uses MultiMeshInstance3D batching for ground cover performance.
## Add to the "world_generator" group.

const MULTIMESH_THRESHOLD := 16

## LOD cull distances (meters) — defaults; override via set_lod_profile()
const LOD_TREE := 120.0
const LOD_ROCK := 80.0
const LOD_SHRUB := 60.0
const LOD_GRASS := 30.0
const LOD_FLOWER := 40.0
const LOD_GEOLOGICAL := 100.0

## Geological feature type constants
enum GeologicalFeatureType { BOULDER, ROCK_CLUSTER, STONE_PILLAR, ROCK_OUTCROP, CRYSTAL_FORMATION }

## Biome geological density presets (biome_key -> density)
const BIOME_GEOLOGICAL_DENSITY := {
	"forest": 0.2,
	"plains": 0.1,
	"mountains": 0.7,
	"desert": 0.5,
	"tundra": 0.4,
	"wasteland": 0.6,
	"tropical": 0.15,
	"swamp": 0.15,
	"urban": 0.02,
}

## Biome geological feature types
const BIOME_GEOLOGICAL_FEATURES := {
	"forest": [GeologicalFeatureType.BOULDER, GeologicalFeatureType.ROCK_CLUSTER],
	"plains": [GeologicalFeatureType.BOULDER],
	"mountains": [GeologicalFeatureType.BOULDER, GeologicalFeatureType.STONE_PILLAR, GeologicalFeatureType.ROCK_OUTCROP, GeologicalFeatureType.CRYSTAL_FORMATION],
	"desert": [GeologicalFeatureType.BOULDER, GeologicalFeatureType.ROCK_OUTCROP, GeologicalFeatureType.STONE_PILLAR],
	"tundra": [GeologicalFeatureType.BOULDER, GeologicalFeatureType.ROCK_CLUSTER],
	"wasteland": [GeologicalFeatureType.BOULDER, GeologicalFeatureType.ROCK_OUTCROP, GeologicalFeatureType.STONE_PILLAR],
	"tropical": [GeologicalFeatureType.BOULDER, GeologicalFeatureType.CRYSTAL_FORMATION],
	"swamp": [GeologicalFeatureType.BOULDER, GeologicalFeatureType.ROCK_CLUSTER],
	"urban": [GeologicalFeatureType.BOULDER],
}

## Color palette per foliage type.
const TYPE_COLORS := {
	"grass":    Color(0.3, 0.6, 0.2),
	"bush":     Color(0.2, 0.5, 0.15),
	"shrub":    Color(0.2, 0.5, 0.15),
	"flower":   Color(0.8, 0.3, 0.5),
	"fern":     Color(0.15, 0.55, 0.2),
	"mushroom": Color(0.7, 0.55, 0.35),
	"vine":     Color(0.25, 0.6, 0.25),
	"tree":     Color(0.2, 0.5, 0.15),
	"pine":     Color(0.15, 0.4, 0.15),
	"oak":      Color(0.2, 0.5, 0.15),
	"palm":     Color(0.2, 0.6, 0.2),
	"dead_tree": Color(0.3, 0.25, 0.2),
	"rock":     Color(0.4, 0.4, 0.35),
	"boulder":  Color(0.4, 0.4, 0.35),
	"pillar":   Color(0.35, 0.35, 0.3),
	"outcrop":  Color(0.45, 0.42, 0.38),
	"crystal":  Color(0.5, 0.3, 0.7),
}

const TRUNK_COLOR := Color(0.35, 0.22, 0.12)

var _material_cache := {}
var _registered_tree_variants: Array[PackedScene] = []
var _building_proximity_checker: Callable
var _lod_profile := { "distances": [50.0, 80.0, 120.0], "reduction_factors": [1.0, 0.5, 0.25] }
var _geological_feature_count := 0

func _ready() -> void:
	add_to_group("world_generator")

## Register a custom tree variant scene for use during generation.
func register_tree_variant(prefab: PackedScene) -> void:
	if prefab and not _registered_tree_variants.has(prefab):
		_registered_tree_variants.append(prefab)

## Set a callable that returns true if a position is within the given distance of any building.
## Signature: func(pos: Vector3, distance: float) -> bool
func set_building_proximity_checker(checker: Callable) -> void:
	_building_proximity_checker = checker

## Override LOD distances and reduction factors.
## distances: Array of float (near to far), reduction_factors: Array of float (1.0 = full detail).
func set_lod_profile(distances: Array, reduction_factors: Array) -> void:
	_lod_profile["distances"] = distances
	_lod_profile["reduction_factors"] = reduction_factors

func generate_from_data(world_data: Dictionary) -> void:
	var geo: Dictionary = world_data.get("geography", {})
	var layers: Array = geo.get("foliageLayers", [])
	if layers.is_empty():
		layers = DataLoader.load_foliage_layers()

	var total_instances := 0
	for layer in layers:
		var instances: Array = layer.get("instances", [])
		if instances.is_empty():
			continue
		var foliage_type: String = layer.get("type", "grass")
		_spawn_layer(foliage_type, instances)
		total_instances += instances.size()

	print("[Insimul] NatureGenerator: %d layers, %d instances" % [layers.size(), total_instances])

# ─────────────────────────────────────────────
# Layer spawning dispatcher
# ─────────────────────────────────────────────

func _spawn_layer(foliage_type: String, instances: Array) -> void:
	match foliage_type:
		"pine", "oak", "palm", "dead_tree", "tree":
			_spawn_trees(foliage_type, instances)
		"rock", "boulder", "pillar", "outcrop", "crystal":
			_spawn_geological(foliage_type, instances)
		"grass", "fern":
			_spawn_ground_cover(foliage_type, instances)
		"flower":
			_spawn_ground_cover(foliage_type, instances)
		_:
			# bush, shrub, mushroom, vine, etc.
			_spawn_shrubs(foliage_type, instances)

# ─────────────────────────────────────────────
# Trees — multi-part procedural geometry
# ─────────────────────────────────────────────

const LOD_PROXY_DISTANCE := 50.0  # Switch to proxy at this distance

func _spawn_trees(tree_type: String, instances: Array) -> void:
	for inst in instances:
		var pos := Vector3(inst.get("x", 0.0), inst.get("y", 0.0), inst.get("z", 0.0))
		var rot: float = inst.get("rotation", 0.0)
		var sc: float = inst.get("scale", 1.0)

		# Resolve generic "tree" to a specific type based on hash
		var resolved_type := tree_type
		if resolved_type == "tree":
			var h: int = (int(pos.x * 73.0) + int(pos.z * 137.0)) % 4
			resolved_type = ["pine", "oak", "palm", "dead_tree"][h]

		var tree: Node3D
		match resolved_type:
			"pine":
				tree = _create_pine()
			"oak":
				tree = _create_oak()
			"palm":
				tree = _create_palm()
			"dead_tree":
				tree = _create_dead_tree()
			_:
				tree = _create_pine()

		tree.position = pos
		tree.rotation.y = rot
		tree.scale = Vector3(sc, sc, sc)
		# Full detail visible up to LOD_PROXY_DISTANCE
		_set_lod_range(tree, 0.0, LOD_PROXY_DISTANCE)
		add_child(tree)

		# LOD proxy — simplified geometry visible from LOD_PROXY_DISTANCE to LOD_TREE
		var proxy := _create_tree_proxy(resolved_type)
		proxy.position = pos
		proxy.rotation.y = rot
		proxy.scale = Vector3(sc, sc, sc)
		proxy.visibility_range_begin = LOD_PROXY_DISTANCE
		proxy.visibility_range_end = LOD_TREE
		add_child(proxy)

func _create_tree_proxy(tree_type: String) -> MeshInstance3D:
	var proxy := MeshInstance3D.new()
	proxy.name = "TreeProxy"
	match tree_type:
		"pine":
			var cone := CylinderMesh.new()
			cone.top_radius = 0.0
			cone.bottom_radius = 1.5
			cone.height = 10.0
			cone.radial_segments = 4
			proxy.mesh = cone
			proxy.position.y = 5.0
			proxy.material_override = _get_mat("pine_proxy", Color(0.15, 0.35, 0.15))
		"oak":
			var sphere := SphereMesh.new()
			sphere.radius = 2.0
			sphere.height = 3.0
			sphere.radial_segments = 6
			sphere.rings = 3
			proxy.mesh = sphere
			proxy.position.y = 6.0
			proxy.material_override = _get_mat("oak_proxy", Color(0.2, 0.45, 0.15))
		"palm":
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.15
			cyl.bottom_radius = 0.25
			cyl.height = 10.0
			cyl.radial_segments = 4
			proxy.mesh = cyl
			proxy.position.y = 5.0
			proxy.material_override = _get_mat("palm_proxy", TRUNK_COLOR)
		"dead_tree":
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.1
			cyl.bottom_radius = 0.25
			cyl.height = 7.0
			cyl.radial_segments = 4
			proxy.mesh = cyl
			proxy.position.y = 3.5
			proxy.material_override = _get_mat("dead_proxy", Color(0.3, 0.25, 0.2))
	return proxy

## Return all registered tree template meshes for cloning.
func get_tree_templates() -> Array[Node3D]:
	var templates: Array[Node3D] = []
	for type_name in ["pine", "oak", "palm", "dead"]:
		var t := _create_tree_by_type(type_name)
		if t:
			templates.append(t)
	return templates

func _create_tree_by_type(type_name: String) -> Node3D:
	match type_name:
		"pine": return _create_pine()
		"oak": return _create_oak()
		"palm": return _create_palm()
		"dead": return _create_dead_tree()
	return null

func _create_pine() -> Node3D:
	var root := Node3D.new()
	root.name = "Pine"
	var trunk_mat := _get_mat("trunk", TRUNK_COLOR)
	var leaf_mat := _get_mat("pine_leaf", Color(0.15, 0.4, 0.15))

	# Trunk
	var trunk := _make_cylinder(0.4, 0.8, 8.0, 6)
	trunk.position.y = 4.0
	trunk.material_override = trunk_mat
	root.add_child(trunk)

	# 3 stacked cones for foliage
	for i in range(3):
		var cone := _make_cone(0.0, 4.0 - float(i) * 0.5, 4.0, 5)
		cone.position.y = 6.0 + float(i) * 2.5
		cone.material_override = leaf_mat
		root.add_child(cone)

	return root

func _create_oak() -> Node3D:
	var root := Node3D.new()
	root.name = "Oak"
	var trunk_mat := _get_mat("trunk", TRUNK_COLOR)
	var leaf_mat := _get_mat("oak_leaf", Color(0.2, 0.5, 0.15))

	# Trunk
	var trunk := _make_cylinder(0.8, 1.4, 5.0, 6)
	trunk.position.y = 2.5
	trunk.material_override = trunk_mat
	root.add_child(trunk)

	# 6 overlapping canopy spheres
	var canopy_offsets := [
		Vector3(0, 6.5, 0), Vector3(2, 6.0, 1.2), Vector3(-1.8, 6.3, -1),
		Vector3(0.5, 7.2, -1.8), Vector3(-0.8, 7.0, 1.5), Vector3(1.5, 7.3, -0.5),
	]
	var canopy_sizes := [3.0, 2.5, 2.3, 2.0, 2.2, 1.8]
	for i in range(canopy_offsets.size()):
		var sphere := _make_sphere(canopy_sizes[i], 4)
		sphere.position = canopy_offsets[i]
		sphere.scale.y = 0.6
		sphere.material_override = leaf_mat
		root.add_child(sphere)

	return root

func _create_palm() -> Node3D:
	var root := Node3D.new()
	root.name = "Palm"
	var trunk_mat := _get_mat("trunk", TRUNK_COLOR)
	var frond_mat := _get_mat("palm_leaf", Color(0.2, 0.6, 0.2))

	# Trunk (slightly tilted)
	var trunk := _make_cylinder(0.4, 0.6, 10.0, 6)
	trunk.position.y = 5.0
	trunk.rotation.z = PI / 16.0
	trunk.material_override = trunk_mat
	root.add_child(trunk)

	# 6 radial fronds
	for i in range(6):
		var frond := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.5, 4.0, 0.2)
		frond.mesh = box
		frond.position.y = 10.0
		frond.rotation.y = (float(i) / 6.0) * TAU
		frond.rotation.x = PI / 4.0
		frond.material_override = frond_mat
		root.add_child(frond)

	return root

func _create_dead_tree() -> Node3D:
	var root := Node3D.new()
	root.name = "DeadTree"
	var bark_mat := _get_mat("dead_bark", Color(0.3, 0.25, 0.2))

	# Main trunk
	var trunk := _make_cylinder(0.3, 0.7, 7.0, 5)
	trunk.position.y = 3.5
	trunk.material_override = bark_mat
	root.add_child(trunk)

	# 3 bare branches
	for i in range(3):
		var branch := _make_cylinder(0.1, 0.2, 2.0, 4)
		branch.position.y = 5.0 + float(i) * 0.5
		branch.rotation.z = PI / 3.0 + float(i) * 0.2
		branch.rotation.y = (float(i) / 3.0) * TAU
		branch.material_override = bark_mat
		root.add_child(branch)

	return root

# ─────────────────────────────────────────────
# Geological features — rocks, boulders, pillars, outcrops, crystals
# ─────────────────────────────────────────────

func _spawn_geological(geo_type: String, instances: Array) -> void:
	for inst in instances:
		var pos := Vector3(inst.get("x", 0.0), inst.get("y", 0.0), inst.get("z", 0.0))
		var rot: float = inst.get("rotation", 0.0)
		var sc: float = inst.get("scale", 1.0)

		var node: Node3D
		match geo_type:
			"rock":
				node = _create_rock(sc)
			"boulder":
				node = _create_boulder(sc)
			"pillar":
				node = _create_pillar(sc)
			"outcrop":
				node = _create_outcrop(sc)
			"crystal":
				node = _create_crystal(sc)
			_:
				node = _create_rock(sc)

		node.position = pos
		node.rotation.y = rot
		_set_lod(node, LOD_GEOLOGICAL if geo_type != "rock" else LOD_ROCK)
		add_child(node)

func _create_rock(sc: float) -> Node3D:
	var root := Node3D.new()
	root.name = "Rock"
	var rock := _make_sphere(1.0, 4)
	var rock_mat := _get_mat("rock", Color(0.4, 0.4, 0.35))
	rock.material_override = rock_mat
	# Irregular scaling for natural look
	var sx: float = sc * (0.8 + fmod(absf(sc * 73.7), 1.0) * 0.4)
	var sy: float = sc * (0.6 + fmod(absf(sc * 31.3), 1.0) * 0.3)
	var sz: float = sc
	rock.scale = Vector3(sx, sy, sz)
	rock.position.y = sy * 0.25
	root.add_child(rock)
	# Collision body sized to the rock footprint
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(sx, sy * 0.7, sz)
	col.shape = box
	col.position.y = sy * 0.35
	body.add_child(col)
	root.add_child(body)
	return root

func _create_boulder(sc: float) -> Node3D:
	var root := Node3D.new()
	root.name = "Boulder"
	var boulder := _make_sphere(2.0 + sc * 1.5, 5)
	var mat := _get_mat("boulder", Color(0.42, 0.42, 0.38))
	boulder.material_override = mat
	var bsx: float = 1.0 + fmod(absf(sc * 47.3), 1.0) * 0.3
	var bsy: float = 0.6 + fmod(absf(sc * 19.7), 1.0) * 0.4
	var bsz: float = 1.0 + fmod(absf(sc * 83.1), 1.0) * 0.3
	boulder.scale = Vector3(bsx, bsy, bsz)
	boulder.position.y = sc * 0.25
	root.add_child(boulder)
	# Collision body
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var radius: float = 2.0 + sc * 1.5
	box.size = Vector3(radius * bsx, radius * bsy * 0.7, radius * bsz)
	col.shape = box
	col.position.y = sc * 0.25
	body.add_child(col)
	root.add_child(body)
	return root

func _create_pillar(sc: float) -> Node3D:
	var height: float = 3.0 + sc * 2.5
	var radius: float = 0.5 + sc * 0.4
	var pillar := _make_cylinder(radius * 0.7, radius * 2.0, height, 6)
	var mat := _get_mat("pillar", Color(0.35, 0.35, 0.3))
	pillar.material_override = mat
	pillar.position.y = height / 2.0
	pillar.rotation.x = (fmod(absf(sc * 57.3), 1.0) - 0.5) * 0.15
	pillar.rotation.z = (fmod(absf(sc * 23.7), 1.0) - 0.5) * 0.15
	return pillar

func _create_outcrop(sc: float) -> Node3D:
	var root := Node3D.new()
	root.name = "Outcrop"
	var mat := _get_mat("outcrop", Color(0.45, 0.42, 0.38))

	# Base slab
	var base_w: float = 4.0 + sc * 1.5
	var base_h: float = 1.5 + sc * 0.5
	var base_d: float = 3.0 + sc
	var base := MeshInstance3D.new()
	var base_box := BoxMesh.new()
	base_box.size = Vector3(base_w, base_h, base_d)
	base.mesh = base_box
	base.position.y = base_h / 2.0
	base.material_override = mat
	root.add_child(base)

	# 1-2 stacked layers
	var layer_count: int = 1 + int(fmod(absf(sc * 41.7), 2.0))
	var prev_y: float = base_h
	for i in range(layer_count):
		var shrink: float = 0.7 - float(i) * 0.15
		var layer := MeshInstance3D.new()
		var layer_box := BoxMesh.new()
		var lh: float = 0.8 + fmod(absf(sc * float(i + 1) * 17.3), 1.0) * 0.5
		layer_box.size = Vector3(base_w * shrink, lh, base_d * shrink)
		layer.mesh = layer_box
		layer.position.y = prev_y + lh / 2.0
		layer.position.x = (fmod(absf(sc * float(i) * 29.1), 1.0) - 0.5) * 0.5
		layer.material_override = mat
		root.add_child(layer)
		prev_y += lh

	return root

func _create_crystal(sc: float) -> Node3D:
	var root := Node3D.new()
	root.name = "Crystal"

	# Rock base
	var base := _make_sphere(1.5, 4)
	var rock_mat := _get_mat("crystal_base", Color(0.4, 0.4, 0.35))
	base.material_override = rock_mat
	base.scale = Vector3(1.2, 0.5, 1.2)
	base.position.y = 0.2
	root.add_child(base)

	# Crystal spires
	var crystal_color := Color(
		minf(1.0, 0.4 * 0.5 + 0.3),
		minf(1.0, 0.4 * 0.3 + 0.2),
		minf(1.0, 0.35 * 0.5 + 0.5)
	)
	var crystal_mat := StandardMaterial3D.new()
	crystal_mat.albedo_color = crystal_color
	crystal_mat.emission_enabled = true
	crystal_mat.emission = crystal_color * 0.15
	crystal_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	crystal_mat.albedo_color.a = 0.85

	var crystal_count: int = 3 + int(fmod(absf(sc * 53.7), 4.0))
	for i in range(crystal_count):
		var height: float = 1.0 + fmod(absf(sc * float(i + 1) * 37.3), 1.0) * 2.5
		var radius: float = 0.15 + fmod(absf(sc * float(i + 1) * 13.7), 1.0) * 0.35
		var crystal := _make_cone(0.0, radius * 2.0, height, 6)
		crystal.position = Vector3(
			(fmod(absf(float(i) * 47.3), 1.0) - 0.5) * 1.5,
			height / 2.0,
			(fmod(absf(float(i) * 71.1), 1.0) - 0.5) * 1.5
		)
		crystal.rotation.x = (fmod(absf(float(i) * 23.7), 1.0) - 0.5) * 0.5
		crystal.rotation.z = (fmod(absf(float(i) * 59.3), 1.0) - 0.5) * 0.5
		crystal.material_override = crystal_mat
		root.add_child(crystal)

	return root

# ─────────────────────────────────────────────
# Ground cover — grass, flowers, ferns (MultiMesh batched)
# ─────────────────────────────────────────────

func _spawn_ground_cover(foliage_type: String, instances: Array) -> void:
	var mesh := _create_ground_mesh(foliage_type)
	var color: Color = TYPE_COLORS.get(foliage_type, Color(0.3, 0.6, 0.2))
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if foliage_type == "grass" or foliage_type == "fern":
		mat.albedo_color.a = 0.7
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.emission_enabled = true
		mat.emission = color * 0.15

	var lod_dist: float = LOD_GRASS if foliage_type == "grass" else LOD_FLOWER

	if instances.size() > MULTIMESH_THRESHOLD:
		var multi_mesh := MultiMesh.new()
		multi_mesh.transform_format = MultiMesh.TRANSFORM_3D
		multi_mesh.mesh = mesh
		multi_mesh.instance_count = instances.size()

		for i in range(instances.size()):
			var inst: Dictionary = instances[i]
			var pos := Vector3(inst.get("x", 0.0), inst.get("y", 0.0), inst.get("z", 0.0))
			var rot: float = inst.get("rotation", 0.0)
			var sc: float = inst.get("scale", 1.0)
			var t := Transform3D()
			t = t.scaled(Vector3(sc, sc, sc))
			t = t.rotated(Vector3.UP, rot)
			t.origin = pos
			multi_mesh.set_instance_transform(i, t)

		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = multi_mesh
		mmi.material_override = mat
		mmi.name = "GroundCover_%s" % foliage_type
		mmi.visibility_range_end = lod_dist
		add_child(mmi)
	else:
		for i in range(instances.size()):
			var inst: Dictionary = instances[i]
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.material_override = mat
			mi.position = Vector3(inst.get("x", 0.0), inst.get("y", 0.0), inst.get("z", 0.0))
			mi.rotation.y = inst.get("rotation", 0.0)
			var sc: float = inst.get("scale", 1.0)
			mi.scale = Vector3(sc, sc, sc)
			mi.visibility_range_end = lod_dist
			add_child(mi)

func _create_ground_mesh(foliage_type: String) -> Mesh:
	match foliage_type:
		"grass", "fern":
			# Crossed-plane X-pattern for volumetric appearance
			return _create_crossed_planes(
				Vector2(0.4, 0.4) if foliage_type == "grass" else Vector2(0.6, 0.6)
			)
		"flower":
			var m := SphereMesh.new()
			m.radius = 0.15
			m.height = 0.5
			return m
		_:
			var m := SphereMesh.new()
			m.radius = 0.2
			m.height = 0.4
			return m

## Create two crossed planes (X pattern) for volumetric grass/fern rendering.
func _create_crossed_planes(size: Vector2) -> ArrayMesh:
	var hw: float = size.x / 2.0
	var hh: float = size.y / 2.0
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	# Plane 1: aligned with X axis (front-back)
	vertices.append(Vector3(-hw, 0, 0))   # 0
	vertices.append(Vector3(hw, 0, 0))    # 1
	vertices.append(Vector3(hw, size.y, 0))   # 2
	vertices.append(Vector3(-hw, size.y, 0))  # 3

	# Plane 2: aligned with Z axis (left-right), rotated 90°
	vertices.append(Vector3(0, 0, -hw))   # 4
	vertices.append(Vector3(0, 0, hw))    # 5
	vertices.append(Vector3(0, size.y, hw))   # 6
	vertices.append(Vector3(0, size.y, -hw))  # 7

	for _i in range(8):
		normals.append(Vector3.UP)
	uvs.append_array(PackedVector2Array([
		Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0),
		Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0),
	]))

	# Two quads (4 triangles)
	indices.append_array(PackedInt32Array([
		0, 1, 2, 0, 2, 3,  # Plane 1
		4, 5, 6, 4, 6, 7,  # Plane 2
	]))

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

# ─────────────────────────────────────────────
# Shrubs — individual mesh instances
# ─────────────────────────────────────────────

func _spawn_shrubs(foliage_type: String, instances: Array) -> void:
	var mesh: Mesh
	match foliage_type:
		"bush", "shrub":
			var m := SphereMesh.new()
			m.radius = 0.5
			m.height = 0.8
			mesh = m
		"mushroom":
			var m := CylinderMesh.new()
			m.top_radius = 0.2
			m.bottom_radius = 0.05
			m.height = 0.3
			mesh = m
		_:
			var m := SphereMesh.new()
			m.radius = 0.3
			m.height = 0.6
			mesh = m

	var color: Color = TYPE_COLORS.get(foliage_type, Color(0.3, 0.6, 0.2))
	var mat := _get_mat("shrub_%s" % foliage_type, color)

	for inst in instances:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mat
		mi.position = Vector3(inst.get("x", 0.0), inst.get("y", 0.0), inst.get("z", 0.0))
		mi.rotation.y = inst.get("rotation", 0.0)
		var sc: float = inst.get("scale", 1.0)
		mi.scale = Vector3(sc, sc, sc)
		mi.visibility_range_end = LOD_SHRUB
		add_child(mi)

# ─────────────────────────────────────────────
# Mesh helpers
# ─────────────────────────────────────────────

func _make_cylinder(top_r: float, bottom_r: float, height: float, segments: int) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = top_r
	m.bottom_radius = bottom_r
	m.height = height
	m.radial_segments = segments
	mi.mesh = m
	return mi

func _make_cone(top_r: float, bottom_r: float, height: float, segments: int) -> MeshInstance3D:
	return _make_cylinder(top_r, bottom_r, height, segments)

func _make_sphere(diameter: float, segments: int) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := SphereMesh.new()
	m.radius = diameter / 2.0
	m.height = diameter
	m.radial_segments = segments * 2
	m.rings = segments
	mi.mesh = m
	return mi

func _get_mat(key: String, color: Color) -> StandardMaterial3D:
	if _material_cache.has(key):
		return _material_cache[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	_material_cache[key] = mat
	return mat

func _set_lod(node: Node3D, cull_distance: float) -> void:
	if node is MeshInstance3D:
		node.visibility_range_end = cull_distance
	for child in node.get_children():
		if child is MeshInstance3D:
			child.visibility_range_end = cull_distance

func _set_lod_range(node: Node3D, begin: float, end: float) -> void:
	if node is MeshInstance3D:
		node.visibility_range_begin = begin
		node.visibility_range_end = end
	for child in node.get_children():
		if child is MeshInstance3D:
			child.visibility_range_begin = begin
			child.visibility_range_end = end

# ─────────────────────────────────────────────
# Terrain-aware placement (stub)
# ─────────────────────────────────────────────

## Generate terrain-aware placements that respect slope, elevation, and terrain features.
## This is a stub for future terrain analysis integration (e.g., slope-based density modulation,
## elevation-based biome blending, moisture map sampling).
func generate_terrain_aware_placements() -> void:
	# TODO: Integrate with terrain heightmap for slope-based density
	# TODO: Sample moisture/temperature maps for biome-specific placement
	# TODO: Respect cliff faces and water edges
	print("[Insimul] generate_terrain_aware_placements stub — use generate_from_data for current placement logic")

# ─────────────────────────────────────────────
# LOD statistics
# ─────────────────────────────────────────────

## Return a dictionary of nature object counts by category.
func get_lod_stats() -> Dictionary:
	var stats := {}
	var tree_count := 0
	var rock_count := 0
	var shrub_count := 0
	var ground_cover_count := 0
	var geological_count := _geological_feature_count

	for child in get_children():
		if child.name.begins_with("Pine") or child.name.begins_with("Oak") or child.name.begins_with("Palm") or child.name.begins_with("DeadTree") or child.name.begins_with("TreeProxy"):
			tree_count += 1
		elif child.name.begins_with("Rock") or child.name.begins_with("Boulder") or child.name.begins_with("Pillar") or child.name.begins_with("Outcrop") or child.name.begins_with("Crystal"):
			geological_count += 1
		elif child.name.begins_with("GroundCover_"):
			if child is MultiMeshInstance3D:
				ground_cover_count += child.multimesh.instance_count if child.multimesh else 0
			else:
				ground_cover_count += 1
		elif child.name.begins_with("shrub_") or child.name.begins_with("bush_") or child.name.begins_with("mushroom_"):
			shrub_count += 1

	stats["Trees"] = tree_count
	stats["Rocks"] = rock_count
	stats["Shrubs"] = shrub_count
	stats["GroundCover"] = ground_cover_count
	stats["GeologicalTotal"] = geological_count
	stats["RegisteredTreeVariants"] = _registered_tree_variants.size()
	stats["LODProfile"] = _lod_profile
	return stats
