extends Node3D
## Terrain heightmap mesh generator.
## Reads heightmap data from world_data and generates a 3D terrain mesh
## with slope-based texturing and collision.
## Add to the "world_generator" group.

@export var terrain_size := {{TERRAIN_SIZE}}
@export var height_scale := {{HEIGHT_SCALE}}
@export var ground_color := Color({{GROUND_COLOR_R}}, {{GROUND_COLOR_G}}, {{GROUND_COLOR_B}})
@export var slope_color := Color({{SLOPE_COLOR_R}}, {{SLOPE_COLOR_G}}, {{SLOPE_COLOR_B}})
@export var peak_color := Color({{PEAK_COLOR_R}}, {{PEAK_COLOR_G}}, {{PEAK_COLOR_B}})

## Slope threshold (0-1) above which slope_color blends in.
@export var slope_threshold := 0.3
## Height threshold (0-1) above which peak_color blends in.
@export var peak_threshold := 0.7

var _heightmap: Array = []
var _heightmap_res: int = 0

func _ready() -> void:
	add_to_group("world_generator")

func generate_from_data(world_data: Dictionary) -> void:
	var terrain: Dictionary = world_data.get("terrain", {})
	if terrain.is_empty():
		var geo: Dictionary = world_data.get("geography", {})
		terrain = {
			"size": geo.get("terrainSize", terrain_size),
			"heightmap": geo.get("heightmap", null),
			"slopeMap": geo.get("slopeMap", null),
		}

	terrain_size = terrain.get("size", terrain_size)
	var heightmap_data: Variant = terrain.get("heightmap", null)
	var slope_data: Variant = terrain.get("slopeMap", null)

	if heightmap_data == null or not (heightmap_data is Array) or heightmap_data.size() == 0:
		_generate_flat_terrain()
		return

	_heightmap = heightmap_data
	_heightmap_res = _heightmap.size()
	_generate_heightmap_mesh(slope_data)
	print("[Insimul] TerrainGenerator: %dx%d heightmap, size=%d, height_scale=%.1f" % [_heightmap_res, _heightmap_res, terrain_size, height_scale])

## Sample terrain height at world coordinates. Returns 0 if no heightmap.
func sample_height(world_x: float, world_z: float) -> float:
	if _heightmap_res == 0:
		return 0.0
	var half := terrain_size / 2.0
	var u := (world_x + half) / terrain_size
	var v := (world_z + half) / terrain_size
	u = clampf(u, 0.0, 1.0)
	v = clampf(v, 0.0, 1.0)
	var fx := u * (_heightmap_res - 1)
	var fz := v * (_heightmap_res - 1)
	var ix := int(fx)
	var iz := int(fz)
	var dx := fx - ix
	var dz := fz - iz
	ix = mini(ix, _heightmap_res - 2)
	iz = mini(iz, _heightmap_res - 2)
	var h00: float = _get_height(ix, iz)
	var h10: float = _get_height(ix + 1, iz)
	var h01: float = _get_height(ix, iz + 1)
	var h11: float = _get_height(ix + 1, iz + 1)
	var h0 := lerpf(h00, h10, dx)
	var h1 := lerpf(h01, h11, dx)
	return lerpf(h0, h1, dz) * height_scale

func _get_height(col: int, row: int) -> float:
	if row < 0 or row >= _heightmap_res or col < 0 or col >= _heightmap_res:
		return 0.0
	var r: Variant = _heightmap[row]
	if r is Array and col < r.size():
		return float(r[col])
	return 0.0

func _get_slope(slope_data: Variant, col: int, row: int) -> float:
	if slope_data == null or not (slope_data is Array):
		return 0.0
	if row < 0 or row >= slope_data.size():
		return 0.0
	var r: Variant = slope_data[row]
	if r is Array and col < r.size():
		return float(r[col])
	return 0.0

func _generate_flat_terrain() -> void:
	var mesh_inst := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(terrain_size, terrain_size)
	mesh_inst.mesh = mesh
	mesh_inst.name = "TerrainMesh"

	var mat := StandardMaterial3D.new()
	mat.albedo_color = ground_color
	mesh_inst.material_override = mat

	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(terrain_size, 0.1, terrain_size)
	col.shape = shape
	body.add_child(col)
	mesh_inst.add_child(body)

	add_child(mesh_inst)
	print("[Insimul] TerrainGenerator: flat terrain (no heightmap), size=%d" % terrain_size)

func _generate_heightmap_mesh(slope_data: Variant) -> void:
	var res := _heightmap_res
	var half := terrain_size / 2.0
	var cell_size := terrain_size / float(res - 1)
	var vert_count := res * res
	var tri_count := (res - 1) * (res - 1) * 2

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	vertices.resize(vert_count)
	normals.resize(vert_count)
	uvs.resize(vert_count)
	colors.resize(vert_count)
	indices.resize(tri_count * 3)

	# Build vertices
	for row in range(res):
		for col in range(res):
			var idx := row * res + col
			var h := _get_height(col, row)
			var x := -half + col * cell_size
			var z := -half + row * cell_size
			var y := h * height_scale

			vertices[idx] = Vector3(x, y, z)
			uvs[idx] = Vector2(float(col) / (res - 1), float(row) / (res - 1))

			# Slope-based vertex color
			var slope := _get_slope(slope_data, col, row)
			var color := ground_color
			if h > peak_threshold:
				var t := clampf((h - peak_threshold) / (1.0 - peak_threshold), 0.0, 1.0)
				color = ground_color.lerp(peak_color, t)
			if slope > slope_threshold:
				var t := clampf((slope - slope_threshold) / (1.0 - slope_threshold), 0.0, 1.0)
				color = color.lerp(slope_color, t)
			colors[idx] = color

	# Build indices (two triangles per quad)
	var ii := 0
	for row in range(res - 1):
		for col in range(res - 1):
			var tl := row * res + col
			var tr := tl + 1
			var bl := (row + 1) * res + col
			var br := bl + 1
			indices[ii] = tl; ii += 1
			indices[ii] = bl; ii += 1
			indices[ii] = tr; ii += 1
			indices[ii] = tr; ii += 1
			indices[ii] = bl; ii += 1
			indices[ii] = br; ii += 1

	# Compute normals from triangle faces
	for i in range(vert_count):
		normals[i] = Vector3.UP
	for i in range(0, indices.size(), 3):
		var i0: int = indices[i]
		var i1: int = indices[i + 1]
		var i2: int = indices[i + 2]
		var v0: Vector3 = vertices[i0]
		var v1: Vector3 = vertices[i1]
		var v2: Vector3 = vertices[i2]
		var face_normal := (v1 - v0).cross(v2 - v0).normalized()
		normals[i0] += face_normal
		normals[i1] += face_normal
		normals[i2] += face_normal
	for i in range(vert_count):
		normals[i] = normals[i].normalized()

	# Create ArrayMesh
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh = mesh
	mesh_inst.name = "TerrainMesh"

	# Material with vertex colors
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	mesh_inst.material_override = mat

	# Collision from triangle mesh
	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	var col_shape := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(_build_collision_faces(vertices, indices))
	col_shape.shape = shape
	body.add_child(col_shape)
	mesh_inst.add_child(body)

	add_child(mesh_inst)

func _build_collision_faces(vertices: PackedVector3Array, indices: PackedInt32Array) -> PackedVector3Array:
	var faces := PackedVector3Array()
	faces.resize(indices.size())
	for i in range(indices.size()):
		faces[i] = vertices[indices[i]]
	return faces
