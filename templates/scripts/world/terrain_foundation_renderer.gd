extends Node3D
## Terrain foundation renderer — flattens terrain under buildings and creates
## visible foundation geometry matching TerrainFoundationRenderer.ts.
## Add to the "world_generator" group.

const FOUNDATION_TYPES := {
	"flat": 0,
	"raised": 1,
	"stilted": 2,
	"terraced": 3,
}

## Material cache to avoid per-building allocation.
var _mat_cache: Dictionary = {}

func _ready() -> void:
	add_to_group("world_generator")

## Called after terrain is generated but before buildings are placed.
## Flattens terrain vertices under each building and creates foundation meshes.
func generate_from_data(world_data: Dictionary) -> void:
	var entities: Dictionary = world_data.get("entities", {})
	var buildings: Array = entities.get("buildings", [])
	var terrain: Node = _find_terrain()
	if terrain == null or not terrain.has_method("sample_height"):
		return

	var count := 0
	for bld in buildings:
		var pos_dict: Dictionary = bld.get("position", {})
		var pos := Vector3(pos_dict.get("x", 0), pos_dict.get("y", 0), pos_dict.get("z", 0))
		var rot: float = bld.get("rotation", 0.0)
		var spec: Dictionary = bld.get("spec", {})
		var width: float = spec.get("width", 10.0)
		var depth: float = spec.get("depth", 10.0)
		var bld_id: String = bld.get("id", "fnd_%d" % count)

		var fnd_data := compute_foundation_data(terrain, pos, rot, width, depth)
		if fnd_data["type"] != "flat":
			_create_foundation_mesh(bld_id, pos, rot, width, depth, fnd_data)
			count += 1

	if count > 0:
		print("[Insimul] TerrainFoundationRenderer: %d foundations created" % count)

## Compute foundation data for a building site.
## Returns Dictionary with keys: type, heights (Array[float]), max_height, delta.
static func compute_foundation_data(terrain: Node, pos: Vector3, rot: float, width: float, depth: float) -> Dictionary:
	var cos_r := cos(deg_to_rad(rot))
	var sin_r := sin(deg_to_rad(rot))
	var hw := width / 2.0
	var hd := depth / 2.0

	var corners := [
		Vector2(-hw, -hd), Vector2(hw, -hd),
		Vector2(-hw, hd), Vector2(hw, hd),
	]

	var heights: Array[float] = []
	var min_h: float = INF
	var max_h: float = -INF

	for c in corners:
		var wx: float = pos.x + cos_r * c.x - sin_r * c.y
		var wz: float = pos.z + sin_r * c.x + cos_r * c.y
		var h: float = terrain.sample_height(wx, wz)
		heights.append(h)
		min_h = minf(min_h, h)
		max_h = maxf(max_h, h)

	var delta := max_h - min_h
	var fnd_type: String
	if delta < 0.3:
		fnd_type = "flat"
	elif delta < 1.0:
		fnd_type = "raised"
	elif delta < 2.5:
		fnd_type = "stilted"
	else:
		fnd_type = "terraced"

	return {
		"type": fnd_type,
		"heights": heights,
		"max_height": max_h,
		"min_height": min_h,
		"delta": delta,
	}

func _create_foundation_mesh(bld_id: String, pos: Vector3, rot: float,
		width: float, depth: float, fnd_data: Dictionary) -> void:
	var fnd_type: String = fnd_data["type"]
	var max_h: float = fnd_data["max_height"]
	var min_h: float = fnd_data["min_height"]
	var delta: float = fnd_data["delta"]

	var container := Node3D.new()
	container.name = "Foundation_%s" % bld_id
	container.position = Vector3(pos.x, 0.0, pos.z)
	container.rotation.y = deg_to_rad(rot)

	match fnd_type:
		"raised":
			_build_raised_foundation(container, width, depth, min_h, max_h)
		"stilted":
			_build_stilted_foundation(container, width, depth, min_h, max_h)
		"terraced":
			_build_terraced_foundation(container, width, depth, min_h, max_h, delta)

	add_child(container)

func _build_raised_foundation(parent: Node3D, width: float, depth: float,
		min_h: float, max_h: float) -> void:
	var height := max_h - min_h + 0.1
	var fnd := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(width + 0.2, height, depth + 0.2)
	fnd.mesh = box
	fnd.position.y = min_h + height / 2.0
	fnd.material_override = _get_material("stone")
	fnd.name = "RaisedFoundation"
	parent.add_child(fnd)

func _build_stilted_foundation(parent: Node3D, width: float, depth: float,
		min_h: float, max_h: float) -> void:
	var height := max_h - min_h + 0.1
	var hw := width / 2.0 - 0.3
	var hd := depth / 2.0 - 0.3

	var post_positions: Array[Vector2] = [
		Vector2(-hw, -hd), Vector2(hw, -hd),
		Vector2(-hw, hd), Vector2(hw, hd),
	]
	if width > 8.0:
		post_positions.append(Vector2(0, -hd))
		post_positions.append(Vector2(0, hd))

	var wood_mat := _get_material("wood")

	for pp in post_positions:
		var post := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.15
		cyl.bottom_radius = 0.15
		cyl.height = height
		cyl.radial_segments = 6
		post.mesh = cyl
		post.position = Vector3(pp.x, min_h + height / 2.0, pp.y)
		post.material_override = wood_mat
		post.name = "StiltPost"
		parent.add_child(post)

	# Cross-beams
	var beam := MeshInstance3D.new()
	var beam_box := BoxMesh.new()
	beam_box.size = Vector3(width - 0.4, 0.15, 0.15)
	beam.mesh = beam_box
	beam.position.y = min_h + height * 0.6
	beam.material_override = wood_mat
	beam.name = "CrossBeam"
	parent.add_child(beam)

	var beam2 := MeshInstance3D.new()
	var beam2_box := BoxMesh.new()
	beam2_box.size = Vector3(0.15, 0.15, depth - 0.4)
	beam2.mesh = beam2_box
	beam2.position.y = min_h + height * 0.6
	beam2.material_override = wood_mat
	beam2.name = "CrossBeamZ"
	parent.add_child(beam2)

func _build_terraced_foundation(parent: Node3D, width: float, depth: float,
		min_h: float, max_h: float, delta: float) -> void:
	var wall_count := ceili(delta / 1.2)
	var total_height := max_h - min_h + 0.1
	var wall_height := total_height / float(wall_count)
	var stone_mat := _get_material("retaining_stone")

	for i in range(wall_count):
		var shrink := 1.0 - float(i) * 0.08
		var wall := MeshInstance3D.new()
		var wall_box := BoxMesh.new()
		wall_box.size = Vector3(
			(width + 0.4) * shrink,
			wall_height,
			(depth + 0.4) * shrink
		)
		wall.mesh = wall_box
		wall.position.y = min_h + wall_height * (float(i) + 0.5)
		wall.material_override = stone_mat
		wall.name = "RetainingWall_%d" % i
		parent.add_child(wall)

func _get_material(mat_type: String) -> StandardMaterial3D:
	if _mat_cache.has(mat_type):
		return _mat_cache[mat_type]

	var mat := StandardMaterial3D.new()
	match mat_type:
		"stone":
			mat.albedo_color = Color(0.45, 0.42, 0.38)
		"wood":
			mat.albedo_color = Color(0.35, 0.22, 0.12)
		"retaining_stone":
			mat.albedo_color = Color(0.5, 0.48, 0.43)
		_:
			mat.albedo_color = Color(0.5, 0.5, 0.5)

	_mat_cache[mat_type] = mat
	return mat

func _find_terrain() -> Node:
	for gen in get_tree().get_nodes_in_group("world_generator"):
		if gen.has_method("sample_height"):
			return gen
	return null
