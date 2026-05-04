extends Node3D
## Building placement system — places buildings along streets with proper
## facing direction and collision avoidance.
## Matches BuildingPlacementSystem.ts and StreetAlignedPlacement.ts.

const LOT_SPACING := 20.0
const GRID_SIZE := 1.0
const MAX_SLOPE_ANGLE := PI / 6.0  # 30 degrees

## Zone-based scaling: downtown buildings are taller/wider.
const ZONE_SCALE := {
	"commercial": 1.3,
	"downtown": 1.4,
	"residential": 1.0,
	"industrial": 1.2,
	"outskirts": 0.9,
}

var _placed_buildings: Array[Dictionary] = []
var _terrain: Node = null

func _ready() -> void:
	add_to_group("world_generator")

## Place buildings from world data with street alignment.
func generate_from_data(world_data: Dictionary) -> void:
	_terrain = _find_terrain()

	var entities: Dictionary = world_data.get("entities", {})
	var buildings: Array = entities.get("buildings", [])
	var settlements: Array = world_data.get("geography", {}).get("settlements", [])
	if settlements.is_empty():
		settlements = world_data.get("settlements", [])

	# Build settlement lookup for street networks
	var settlement_map: Dictionary = {}
	for s in settlements:
		settlement_map[s.get("id", "")] = s

	for bld in buildings:
		var pos_dict: Dictionary = bld.get("position", {})
		var pos := Vector3(pos_dict.get("x", 0), pos_dict.get("y", 0), pos_dict.get("z", 0))
		var rot: float = bld.get("rotation", 0.0)
		var spec: Dictionary = bld.get("spec", {})
		var width: float = spec.get("width", 10.0)
		var depth: float = spec.get("depth", 10.0)
		var role: String = spec.get("buildingRole", "residential")
		var settlement_id: String = bld.get("settlementId", "")

		# Snap to grid
		pos = _snap_to_grid(pos)

		# Apply terrain height
		if _terrain != null and _terrain.has_method("sample_height"):
			pos.y = _terrain.sample_height(pos.x, pos.z)

		# Apply zone scaling
		var zone := _get_zone(pos, settlement_map.get(settlement_id, {}))
		var scale_factor: float = ZONE_SCALE.get(zone, 1.0)

		# Check collision with existing buildings
		if _check_collision(pos, width * scale_factor, depth * scale_factor):
			pos = _nudge_position(pos, width * scale_factor, depth * scale_factor)

		# Calculate street-facing rotation if not provided
		if rot == 0.0 and settlement_id != "":
			var settlement: Dictionary = settlement_map.get(settlement_id, {})
			rot = _calculate_street_facing(pos, settlement)

		_placed_buildings.append({
			"id": bld.get("id", ""),
			"position": pos,
			"rotation": rot,
			"width": width * scale_factor,
			"depth": depth * scale_factor,
			"role": role,
			"zone_scale": scale_factor,
		})

	print("[Insimul] BuildingPlacementSystem: %d buildings placed" % _placed_buildings.size())

func get_placed_buildings() -> Array[Dictionary]:
	return _placed_buildings

func _snap_to_grid(pos: Vector3) -> Vector3:
	return Vector3(
		roundf(pos.x / GRID_SIZE) * GRID_SIZE,
		pos.y,
		roundf(pos.z / GRID_SIZE) * GRID_SIZE
	)

func _check_collision(pos: Vector3, width: float, depth: float) -> bool:
	var half_w := width / 2.0
	var half_d := depth / 2.0

	for existing in _placed_buildings:
		var epos: Vector3 = existing["position"]
		var ew: float = existing["width"] / 2.0
		var ed: float = existing["depth"] / 2.0

		# AABB overlap check
		if absf(pos.x - epos.x) < (half_w + ew) and absf(pos.z - epos.z) < (half_d + ed):
			return true

	return false

func _nudge_position(pos: Vector3, width: float, depth: float) -> Vector3:
	# Try offsets in cardinal directions
	var offsets := [
		Vector3(LOT_SPACING, 0, 0),
		Vector3(-LOT_SPACING, 0, 0),
		Vector3(0, 0, LOT_SPACING),
		Vector3(0, 0, -LOT_SPACING),
	]

	for offset in offsets:
		var new_pos := pos + offset
		if not _check_collision(new_pos, width, depth):
			if _terrain != null and _terrain.has_method("sample_height"):
				new_pos.y = _terrain.sample_height(new_pos.x, new_pos.z)
			return new_pos

	return pos  # Return original if no free slot found

func _calculate_street_facing(pos: Vector3, settlement: Dictionary) -> float:
	var street_network: Variant = settlement.get("streetNetwork", null)
	if street_network == null or not (street_network is Dictionary):
		# Face toward settlement center
		var s_pos: Dictionary = settlement.get("position", {})
		var center := Vector3(s_pos.get("x", pos.x), 0, s_pos.get("z", pos.z))
		return rad_to_deg(atan2(center.x - pos.x, center.z - pos.z))

	# Find nearest street segment and face perpendicular to it
	var segments: Array = street_network.get("segments", [])
	var nearest_angle := 0.0
	var nearest_dist := INF

	for seg in segments:
		var waypoints: Array = seg.get("waypoints", [])
		if waypoints.size() < 2:
			continue
		for i in range(waypoints.size() - 1):
			var wp_a: Dictionary = waypoints[i]
			var wp_b: Dictionary = waypoints[i + 1]
			var a := Vector3(wp_a.get("x", 0), 0, wp_a.get("z", 0))
			var b := Vector3(wp_b.get("x", 0), 0, wp_b.get("z", 0))

			var closest := _closest_point_on_segment(pos, a, b)
			var dist: float = pos.distance_to(closest)

			if dist < nearest_dist:
				nearest_dist = dist
				var dir := (b - a).normalized()
				# Face perpendicular to street, toward the street
				var to_street := (closest - pos).normalized()
				nearest_angle = rad_to_deg(atan2(to_street.x, to_street.z))

	return nearest_angle

func _closest_point_on_segment(point: Vector3, a: Vector3, b: Vector3) -> Vector3:
	var ab := b - a
	var ap := point - a
	var t := clampf(ap.dot(ab) / ab.dot(ab), 0.0, 1.0)
	return a + ab * t

func _get_zone(pos: Vector3, settlement: Dictionary) -> String:
	if settlement.is_empty():
		return "residential"

	var s_pos: Dictionary = settlement.get("position", {})
	var center := Vector3(s_pos.get("x", 0), 0, s_pos.get("z", 0))
	var radius: float = settlement.get("radius", 50.0)
	var dist: float = pos.distance_to(center)
	var ratio := dist / maxf(radius, 1.0)

	if ratio < 0.2:
		return "downtown"
	elif ratio < 0.5:
		return "commercial"
	elif ratio < 0.8:
		return "residential"
	else:
		return "outskirts"

func _find_terrain() -> Node:
	for gen in get_tree().get_nodes_in_group("world_generator"):
		if gen.has_method("sample_height"):
			return gen
	return null
