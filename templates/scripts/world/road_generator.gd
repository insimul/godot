extends Node3D
## Road generator with sidewalks, center line markings, crosswalks, and street lights.
## Add to the "world_generator" group.

@export var road_color := Color({{ROAD_COLOR_R}}, {{ROAD_COLOR_G}}, {{ROAD_COLOR_B}})
@export var road_width := {{ROAD_WIDTH}}
@export var road_elevation := 0.5

## Visual detail constants
const SIDEWALK_WIDTH := 2.0
const SIDEWALK_COLOR := Color(0.52, 0.51, 0.49)
const CENTER_LINE_COLOR := Color(0.58, 0.53, 0.25)
const CENTER_LINE_WIDTH := 0.2
const DASH_LENGTH := 2.5
const GAP_LENGTH := 2.0
const CROSSWALK_COLOR := Color(0.68, 0.68, 0.66)
const CROSSWALK_STRIPE_W := 0.35
const CROSSWALK_STRIPE_GAP := 0.35
const CROSSWALK_STRIPE_LEN := 2.0
const LIGHT_SPACING := 25.0
const POLE_HEIGHT := 4.0
const POLE_COLOR := Color(0.15, 0.15, 0.15)
const GLOBE_COLOR := Color(1.0, 0.85, 0.55)
const LIGHT_RANGE := 18.0
const LIGHT_INTENSITY := 0.8

var _road_material: StandardMaterial3D
var _sidewalk_material: StandardMaterial3D
var _center_line_material: StandardMaterial3D
var _crosswalk_material: StandardMaterial3D
var _pole_material: StandardMaterial3D
var _globe_material: StandardMaterial3D

func _ready() -> void:
	add_to_group("world_generator")
	_road_material = _make_mat(road_color)
	_road_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_sidewalk_material = _make_mat(SIDEWALK_COLOR)
	_center_line_material = _make_mat(CENTER_LINE_COLOR)
	_crosswalk_material = _make_mat(CROSSWALK_COLOR)
	_pole_material = _make_mat(POLE_COLOR)
	_globe_material = StandardMaterial3D.new()
	_globe_material.albedo_color = GLOBE_COLOR
	_globe_material.emission_enabled = true
	_globe_material.emission = GLOBE_COLOR * 0.3

func generate_from_data(world_data: Dictionary) -> void:
	var street_count := 0
	var road_count := 0

	var geo: Dictionary = world_data.get("geography", {})
	var settlements: Array = geo.get("settlements", [])
	for settlement in settlements:
		var sn: Variant = settlement.get("streetNetwork", null)
		if sn == null or not (sn is Dictionary):
			continue
		var segments: Array = sn.get("segments", [])
		for seg in segments:
			var waypoints: Array = seg.get("waypoints", [])
			if waypoints.size() < 2:
				continue
			var w: float = seg.get("width", road_width)
			var points := _parse_waypoints(waypoints)
			var seg_name: String = "Street_%s_%s" % [seg.get("name", ""), seg.get("id", "")]
			_create_road_mesh(seg_name, points, w)
			_create_sidewalks(seg_name, points, w)
			_create_center_line(seg_name, points)
			_create_street_lights(seg_name, points, w)
			street_count += 1
		# Intersection discs + crosswalks
		var nodes: Array = sn.get("nodes", [])
		for node in nodes:
			var intersection_of: Array = node.get("intersectionOf", [])
			if intersection_of.size() >= 2:
				var pos: Dictionary = node.get("position", {})
				var center := Vector3(pos.get("x", 0.0), pos.get("y", 0.0) + road_elevation, pos.get("z", 0.0))
				_create_intersection_disc(center, road_width * 0.75)

	# Inter-settlement roads (simpler — no sidewalks/lights)
	var entities: Dictionary = world_data.get("entities", {})
	var roads: Array = entities.get("roads", [])
	for road in roads:
		var waypoints: Array = road.get("waypoints", [])
		if waypoints.size() < 2:
			continue
		var w: float = road.get("width", road_width)
		var points := _parse_waypoints(waypoints)
		_create_road_mesh("Road_%d" % road_count, points, w)
		road_count += 1

	print("[Insimul] Roads: %d streets (with sidewalks/lights), %d inter-settlement roads" % [street_count, road_count])

func generate_settlement_streets(settlement_id: String, street_network: Dictionary, sample_height: Callable) -> void:
	var segments: Array = street_network.get("segments", [])
	var nodes: Array = street_network.get("nodes", [])
	for seg in segments:
		var waypoints: Array = seg.get("waypoints", [])
		var width: float = seg.get("width", road_width)
		if waypoints.size() < 2:
			continue
		var points := _parse_waypoints(waypoints)
		for i in range(points.size()):
			# Sample center and offset positions; use the max so road clears terrain bumps
			var cx: float = points[i].x
			var cz: float = points[i].z
			var center_y: float = sample_height.call(cx, cz)
			var left_y: float = sample_height.call(cx - width * 0.5, cz)
			var right_y: float = sample_height.call(cx + width * 0.5, cz)
			points[i].y = maxf(center_y, maxf(left_y, right_y)) + road_elevation
		var seg_name: String = "Street_%s_%s" % [settlement_id, seg.get("id", "")]
		_create_road_mesh(seg_name, points, width)
		_create_sidewalks(seg_name, points, width)
		_create_center_line(seg_name, points)
		_create_street_lights(seg_name, points, width)
	for node in nodes:
		var intersection_of: Array = node.get("intersectionOf", [])
		if intersection_of.size() >= 2:
			var pos: Dictionary = node.get("position", {})
			var x: float = pos.get("x", 0.0)
			var z: float = pos.get("z", 0.0)
			var y: float = sample_height.call(x, z) + road_elevation
			_create_intersection_disc(Vector3(x, y, z), road_width * 0.75)

# ─────────────────────────────────────────────
# Road mesh (existing ribbon)
# ─────────────────────────────────────────────

func _parse_waypoints(waypoints: Array) -> PackedVector3Array:
	var points := PackedVector3Array()
	points.resize(waypoints.size())
	for i in range(waypoints.size()):
		var wp: Dictionary = waypoints[i]
		points[i] = Vector3(wp.get("x", 0.0), wp.get("y", 0.0) + road_elevation, wp.get("z", 0.0))
	return points

func _create_road_mesh(road_name: String, waypoints: PackedVector3Array, width: float) -> void:
	var mesh := _build_ribbon_mesh(waypoints, width)
	if mesh == null:
		return
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh = mesh
	mesh_inst.name = road_name
	mesh_inst.material_override = _road_material
	mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh_inst)
	mesh_inst.create_trimesh_collision()

func _create_intersection_disc(center: Vector3, radius: float) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.02
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh = mesh
	mesh_inst.position = center
	mesh_inst.material_override = _road_material
	mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh_inst)

# ─────────────────────────────────────────────
# Sidewalks
# ─────────────────────────────────────────────

func _create_sidewalks(seg_name: String, waypoints: PackedVector3Array, width: float) -> void:
	var half_street: float = width / 2.0
	var offset: float = half_street + SIDEWALK_WIDTH / 2.0
	# Left sidewalk
	var left_points := _offset_polyline(waypoints, -offset)
	var left_mesh := _build_ribbon_mesh(left_points, SIDEWALK_WIDTH)
	if left_mesh:
		var mi := MeshInstance3D.new()
		mi.mesh = left_mesh
		mi.name = "%s_SidewalkL" % seg_name
		mi.material_override = _sidewalk_material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	# Right sidewalk
	var right_points := _offset_polyline(waypoints, offset)
	var right_mesh := _build_ribbon_mesh(right_points, SIDEWALK_WIDTH)
	if right_mesh:
		var mi := MeshInstance3D.new()
		mi.mesh = right_mesh
		mi.name = "%s_SidewalkR" % seg_name
		mi.material_override = _sidewalk_material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)

func _offset_polyline(waypoints: PackedVector3Array, offset: float) -> PackedVector3Array:
	var result := PackedVector3Array()
	result.resize(waypoints.size())
	var n: int = waypoints.size()
	for i in range(n):
		var forward: Vector3
		if i == 0:
			forward = (waypoints[1] - waypoints[0]).normalized()
		elif i == n - 1:
			forward = (waypoints[n - 1] - waypoints[n - 2]).normalized()
		else:
			forward = (waypoints[i + 1] - waypoints[i - 1]).normalized()
		if forward.length_squared() < 0.0001:
			forward = Vector3.FORWARD
		var right := Vector3(forward.z, 0.0, -forward.x).normalized()
		result[i] = waypoints[i] + right * offset
	return result

# ─────────────────────────────────────────────
# Center line markings (dashed)
# ─────────────────────────────────────────────

func _create_center_line(seg_name: String, waypoints: PackedVector3Array) -> void:
	if waypoints.size() < 2:
		return

	# Walk the polyline and create dashes
	var dash_parent := Node3D.new()
	dash_parent.name = "%s_CenterLine" % seg_name
	add_child(dash_parent)

	var total_length := 0.0
	for i in range(1, waypoints.size()):
		total_length += waypoints[i].distance_to(waypoints[i - 1])

	var walked := 0.0
	var seg_idx := 0
	var seg_pos := 0.0
	var cycle: float = DASH_LENGTH + GAP_LENGTH

	while walked < total_length and seg_idx < waypoints.size() - 1:
		var cycle_pos: float = fmod(walked, cycle)
		if cycle_pos < DASH_LENGTH:
			# We're in a dash region — create a small box
			var seg_len: float = waypoints[seg_idx + 1].distance_to(waypoints[seg_idx])
			if seg_len < 0.01:
				seg_idx += 1
				continue
			var t: float = seg_pos / seg_len
			var pos: Vector3 = waypoints[seg_idx].lerp(waypoints[seg_idx + 1], t)
			var forward: Vector3 = (waypoints[seg_idx + 1] - waypoints[seg_idx]).normalized()
			var dash_len: float = minf(DASH_LENGTH - cycle_pos, 1.0)

			var dash := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(CENTER_LINE_WIDTH, 0.01, dash_len)
			dash.mesh = box
			dash.position = pos + Vector3.UP * 0.02
			dash.rotation.y = atan2(forward.x, forward.z)
			dash.material_override = _center_line_material
			dash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			dash_parent.add_child(dash)

		# Advance along polyline
		var step := 0.5
		walked += step
		seg_pos += step
		var seg_len2: float = waypoints[seg_idx + 1].distance_to(waypoints[seg_idx])
		while seg_pos >= seg_len2 and seg_idx < waypoints.size() - 2:
			seg_pos -= seg_len2
			seg_idx += 1
			seg_len2 = waypoints[seg_idx + 1].distance_to(waypoints[seg_idx])

# ─────────────────────────────────────────────
# Street lights
# ─────────────────────────────────────────────

func _create_street_lights(seg_name: String, waypoints: PackedVector3Array, width: float) -> void:
	if waypoints.size() < 2:
		return

	var total_length := 0.0
	for i in range(1, waypoints.size()):
		total_length += waypoints[i].distance_to(waypoints[i - 1])

	if total_length < LIGHT_SPACING:
		return

	var half_street: float = width / 2.0
	var offset: float = half_street + SIDEWALK_WIDTH * 0.5
	var skip_frac := 0.08
	var light_idx := 0

	var walked := total_length * skip_frac
	while walked < total_length * (1.0 - skip_frac):
		# Find position along polyline
		var pos := _sample_polyline(waypoints, walked)
		var forward := _sample_tangent(waypoints, walked)
		var right := Vector3(forward.z, 0.0, -forward.x).normalized()

		# Alternate sides
		var side: float = -1.0 if (light_idx % 2) == 0 else 1.0
		var light_pos := pos + right * (side * offset)

		_create_light_post(light_pos, forward, side)
		light_idx += 1
		walked += LIGHT_SPACING

func _create_light_post(pos: Vector3, forward: Vector3, side: float) -> void:
	var root := Node3D.new()
	root.name = "StreetLight"
	root.position = pos

	# Pole
	var pole := MeshInstance3D.new()
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.075
	pole_mesh.bottom_radius = 0.075
	pole_mesh.height = POLE_HEIGHT
	pole_mesh.radial_segments = 6
	pole.mesh = pole_mesh
	pole.position.y = POLE_HEIGHT / 2.0
	pole.material_override = _pole_material
	root.add_child(pole)

	# Arm (extends toward street)
	var arm := MeshInstance3D.new()
	var arm_mesh := CylinderMesh.new()
	arm_mesh.top_radius = 0.04
	arm_mesh.bottom_radius = 0.04
	arm_mesh.height = 0.6
	arm_mesh.radial_segments = 4
	arm.mesh = arm_mesh
	arm.position = Vector3(-side * 0.3, POLE_HEIGHT, 0)
	arm.rotation.z = PI / 2.0
	arm.material_override = _pole_material
	root.add_child(arm)

	# Globe
	var globe := MeshInstance3D.new()
	var globe_mesh := SphereMesh.new()
	globe_mesh.radius = 0.15
	globe_mesh.height = 0.3
	globe_mesh.radial_segments = 8
	globe_mesh.rings = 4
	globe.mesh = globe_mesh
	globe.position = Vector3(-side * 0.5, POLE_HEIGHT, 0)
	globe.material_override = _globe_material
	root.add_child(globe)

	# Point light
	var light := OmniLight3D.new()
	light.light_color = GLOBE_COLOR
	light.light_energy = LIGHT_INTENSITY
	light.omni_range = LIGHT_RANGE
	light.shadow_enabled = false
	light.position = Vector3(-side * 0.5, POLE_HEIGHT - 0.3, 0)
	light.add_to_group("street_light")
	root.add_child(light)

	add_child(root)

# ─────────────────────────────────────────────
# Street signs
# ─────────────────────────────────────────────

## Create a street name sign oriented parallel to the street direction.
## The sign is double-sided so it can be read from either side.
func create_street_sign(pos: Vector3, street_name: String, street_dir: Vector3) -> void:
	var root := Node3D.new()
	root.name = "StreetSign_%s" % street_name.replace(" ", "_")
	root.position = pos

	# Pole
	var pole := MeshInstance3D.new()
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.05
	pole_mesh.bottom_radius = 0.05
	pole_mesh.height = 2.5
	pole_mesh.radial_segments = 6
	pole.mesh = pole_mesh
	pole.position.y = 1.25
	pole.material_override = _pole_material
	root.add_child(pole)

	# Sign face — oriented parallel to street, readable from both sides
	var sign_mesh := QuadMesh.new()
	sign_mesh.size = Vector2(2.0, 0.5)
	var sign_inst := MeshInstance3D.new()
	sign_inst.mesh = sign_mesh
	sign_inst.position.y = 2.5

	# Orient sign parallel to street direction
	if street_dir.length_squared() > 0.001:
		sign_inst.rotation.y = atan2(street_dir.x, street_dir.z)

	# Sign material with street name text
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.37, 0.16)
	mat.emission_enabled = true
	mat.emission = Color(0.16, 0.37, 0.16)
	mat.emission_energy_multiplier = 0.5
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED  # Double-sided
	sign_inst.material_override = mat

	# Label3D for the street name (visible from both sides)
	var label := Label3D.new()
	label.text = street_name
	label.font_size = 48
	label.modulate = Color.WHITE
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	label.double_sided = true
	label.no_depth_test = false
	label.position = Vector3(0.0, 0.0, 0.01)
	sign_inst.add_child(label)

	root.add_child(sign_inst)
	add_child(root)

# ─────────────────────────────────────────────
# Polyline helpers
# ─────────────────────────────────────────────

func _sample_polyline(waypoints: PackedVector3Array, distance: float) -> Vector3:
	var walked := 0.0
	for i in range(waypoints.size() - 1):
		var seg_len: float = waypoints[i + 1].distance_to(waypoints[i])
		if walked + seg_len >= distance:
			var t: float = (distance - walked) / maxf(seg_len, 0.001)
			return waypoints[i].lerp(waypoints[i + 1], clampf(t, 0.0, 1.0))
		walked += seg_len
	return waypoints[waypoints.size() - 1]

func _sample_tangent(waypoints: PackedVector3Array, distance: float) -> Vector3:
	var walked := 0.0
	for i in range(waypoints.size() - 1):
		var seg_len: float = waypoints[i + 1].distance_to(waypoints[i])
		if walked + seg_len >= distance:
			return (waypoints[i + 1] - waypoints[i]).normalized()
		walked += seg_len
	if waypoints.size() >= 2:
		return (waypoints[waypoints.size() - 1] - waypoints[waypoints.size() - 2]).normalized()
	return Vector3.FORWARD

# ─────────────────────────────────────────────
# Ribbon mesh builder
# ─────────────────────────────────────────────

static func _build_ribbon_mesh(waypoints: PackedVector3Array, width: float) -> ArrayMesh:
	var n := waypoints.size()
	if n < 2:
		return null

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	vertices.resize(n * 2)
	normals.resize(n * 2)
	uvs.resize(n * 2)

	var half_width := width * 0.5
	var cumulative_length := 0.0

	for i in range(n):
		var forward: Vector3
		if i == 0:
			forward = (waypoints[1] - waypoints[0]).normalized()
		elif i == n - 1:
			forward = (waypoints[n - 1] - waypoints[n - 2]).normalized()
		else:
			forward = (waypoints[i + 1] - waypoints[i - 1]).normalized()
		if forward.length_squared() < 0.0001:
			forward = Vector3.FORWARD
		var right := Vector3(forward.z, 0.0, -forward.x).normalized()
		if right.length_squared() < 0.0001:
			right = Vector3.RIGHT

		vertices[i * 2]     = waypoints[i] - right * half_width
		vertices[i * 2 + 1] = waypoints[i] + right * half_width
		normals[i * 2]     = Vector3.UP
		normals[i * 2 + 1] = Vector3.UP
		if i > 0:
			cumulative_length += waypoints[i].distance_to(waypoints[i - 1])
		var v_coord := cumulative_length / width
		uvs[i * 2]     = Vector2(0.0, v_coord)
		uvs[i * 2 + 1] = Vector2(1.0, v_coord)

	var segment_count := n - 1
	var indices := PackedInt32Array()
	indices.resize(segment_count * 6)
	for i in range(segment_count):
		var bl := i * 2
		var br := i * 2 + 1
		var tl := (i + 1) * 2
		var tr := (i + 1) * 2 + 1
		indices[i * 6]     = bl
		indices[i * 6 + 1] = tl
		indices[i * 6 + 2] = br
		indices[i * 6 + 3] = br
		indices[i * 6 + 4] = tl
		indices[i * 6 + 5] = tr

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX]  = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

# ─────────────────────────────────────────────
# Lot-based sidewalk generation
# ─────────────────────────────────────────────

## Generates a sidewalk along the street-facing edge of a lot.
func generate_lot_sidewalks(lot_center: Vector3, lot_size: Vector3, street_direction: Vector3) -> void:
	var sidewalk_elevation := 0.08
	var forward := street_direction.normalized()
	var right := Vector3(forward.z, 0.0, -forward.x).normalized()
	if right.length_squared() < 0.0001:
		right = Vector3.RIGHT

	# Front edge of lot (closest to street)
	var half_depth: float = lot_size.z / 2.0
	var front_center := lot_center - forward * half_depth

	var half_width: float = lot_size.x / 2.0
	var points := PackedVector3Array()
	points.resize(2)
	points[0] = front_center - right * half_width + Vector3.UP * (road_elevation + sidewalk_elevation)
	points[1] = front_center + right * half_width + Vector3.UP * (road_elevation + sidewalk_elevation)

	var mesh := _build_ribbon_mesh(points, SIDEWALK_WIDTH)
	if mesh == null:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.name = "LotSidewalk_%d_%d" % [int(front_center.x), int(front_center.z)]
	mi.material_override = _sidewalk_material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.create_trimesh_collision()

# ─────────────────────────────────────────────
# Point-on-road query
# ─────────────────────────────────────────────

## Returns true if the given point is within the threshold distance of any road mesh.
## Useful for NPC navigation and placement validation.
func is_point_on_road(point: Vector3, threshold: float = 1.0) -> bool:
	for child in get_children():
		if not child is MeshInstance3D:
			continue
		var mi: MeshInstance3D = child
		if mi.mesh == null:
			continue
		# Simple AABB check first for performance
		var aabb := mi.get_aabb()
		var global_aabb := AABB(mi.global_position + aabb.position - Vector3(threshold, threshold, threshold),
			aabb.size + Vector3(threshold * 2.0, threshold * 2.0, threshold * 2.0))
		if global_aabb.has_point(point):
			return true
	return false

# ─────────────────────────────────────────────
# Polyline utilities
# ─────────────────────────────────────────────

## Interpolate a position along a polyline at a given distance from the start.
## Returns the last point if distance exceeds total length.
static func interpolate_polyline(waypoints: PackedVector3Array, distance: float) -> Vector3:
	if waypoints.is_empty():
		return Vector3.ZERO
	if waypoints.size() == 1 or distance <= 0.0:
		return waypoints[0]

	var walked := 0.0
	for i in range(waypoints.size() - 1):
		var seg_len: float = waypoints[i + 1].distance_to(waypoints[i])
		if walked + seg_len >= distance:
			var t: float = (distance - walked) / maxf(seg_len, 0.001)
			return waypoints[i].lerp(waypoints[i + 1], clampf(t, 0.0, 1.0))
		walked += seg_len
	return waypoints[waypoints.size() - 1]

## Calculate the total length of a polyline path.
static func polyline_length(waypoints: PackedVector3Array) -> float:
	if waypoints.size() < 2:
		return 0.0
	var length := 0.0
	for i in range(waypoints.size() - 1):
		length += waypoints[i + 1].distance_to(waypoints[i])
	return length

# ─────────────────────────────────────────────
# Settlement MST generation
# ─────────────────────────────────────────────

## Generate inter-settlement roads using a minimum spanning tree (Kruskal's algorithm).
## Connects settlement centers with the shortest total road network.
func generate_settlement_roads(settlement_centers: PackedVector3Array, default_width: float = -1.0) -> void:
	var n: int = settlement_centers.size()
	if n < 2:
		return
	var w: float = default_width if default_width > 0.0 else road_width

	# Build all edges sorted by distance
	var edges: Array = []
	for i in range(n):
		for j in range(i + 1, n):
			var d: float = settlement_centers[i].distance_to(settlement_centers[j])
			edges.append({ "a": i, "b": j, "dist": d })
	edges.sort_custom(func(e1, e2): return e1["dist"] < e2["dist"])

	# Union-Find
	var parent: Array[int] = []
	parent.resize(n)
	for i in range(n):
		parent[i] = i

	var find_root: Callable
	find_root = func(x: int) -> int:
		if parent[x] == x:
			return x
		parent[x] = find_root.call(parent[x])
		return parent[x]

	var edges_added := 0
	for edge in edges:
		var root_a: int = find_root.call(edge["a"])
		var root_b: int = find_root.call(edge["b"])
		if root_a == root_b:
			continue

		parent[root_a] = root_b
		var points := PackedVector3Array()
		points.resize(2)
		points[0] = settlement_centers[edge["a"]] + Vector3.UP * road_elevation
		points[1] = settlement_centers[edge["b"]] + Vector3.UP * road_elevation
		_create_road_mesh("SettlementRoad_%d" % edges_added, points, w)
		_create_center_line("SettlementRoad_%d" % edges_added, points)
		edges_added += 1

		if edges_added >= n - 1:
			break

	print("[Insimul] Generated %d settlement MST roads" % edges_added)

func _make_mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	return mat
