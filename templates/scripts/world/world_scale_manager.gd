extends Node3D
## Manages world terrain and scale.
## Add to the "world_generator" group.

@export var terrain_size := {{TERRAIN_SIZE}}
@export var ground_color := Color({{GROUND_COLOR_R}}, {{GROUND_COLOR_G}}, {{GROUND_COLOR_B}})
@export var sky_color := Color({{SKY_COLOR_R}}, {{SKY_COLOR_G}}, {{SKY_COLOR_B}})

# --- Scale constants ---
const SPAWN_CLEAR_RADIUS := 15.0
const COUNTRY_MIN_SIZE := 200.0
const COUNTRY_MAX_SIZE := 400.0
const STATE_MIN_SIZE := 60.0
const STATE_MAX_SIZE := 150.0

const POP_SCALE := {
	"tiny": {"min": 0, "max": 50, "radius": 20.0},
	"small": {"min": 51, "max": 200, "radius": 35.0},
	"medium": {"min": 201, "max": 1000, "radius": 55.0},
	"large": {"min": 1001, "max": 5000, "radius": 80.0},
	"huge": {"min": 5001, "max": 999999, "radius": 120.0},
}

## Ordered tier list for interpolation lookups.
const _POP_TIERS: Array[Dictionary] = [
	{"min": 0, "max": 50, "radius": 20.0},
	{"min": 51, "max": 200, "radius": 35.0},
	{"min": 201, "max": 1000, "radius": 55.0},
	{"min": 1001, "max": 5000, "radius": 80.0},
	{"min": 5001, "max": 999999, "radius": 120.0},
]

var _seed: String = "world"
## Runtime scale factor applied to all world positions (default 1.0)
var scale_factor: float = 1.0

func _ready() -> void:
	add_to_group("world_generator")

func generate_from_data(world_data: Dictionary) -> void:
	var geo: Dictionary = world_data.get("geography", {})
	terrain_size = geo.get("terrainSize", terrain_size)
	scale_factor = geo.get("worldScaleFactor", 1.0)
	print("[Insimul] WorldScaleManager initialized (terrain: %d, scale: %.2f)" % [terrain_size, scale_factor])
	_generate_terrain()
	_setup_sky()

func _generate_terrain() -> void:
	var plane := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(terrain_size, terrain_size)
	plane.mesh = mesh
	plane.name = "Terrain"

	var mat := StandardMaterial3D.new()
	mat.albedo_color = ground_color
	plane.material_override = mat

	# Add collision
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(terrain_size, 0.1, terrain_size)
	col.shape = shape
	body.add_child(col)
	plane.add_child(body)

	add_child(plane)

func _setup_sky() -> void:
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = sky_color
	environment.ambient_light_color = sky_color
	environment.ambient_light_energy = 0.5
	env.environment = environment
	add_child(env)

# ---------------------------------------------------------------------------
# Seeded random – mirrors the TypeScript createSeededRandom()
# ---------------------------------------------------------------------------

static func _create_seed_hash(seed_string: String) -> int:
	var h := 0
	for i in range(seed_string.length()):
		h = ((h << 5) - h) + seed_string.unicode_at(i)
		h = h & h  # force 32-bit wrap
	return h

## Returns [next_random_value, updated_hash] as a pair.
## Call pattern: var pair = _seeded_random(hash); hash = pair[1]; var val = pair[0]
static func _seeded_random(hash: int) -> Array:
	hash = (hash * 9301 + 49297) % 233280
	return [absf(float(hash)) / 233280.0, hash]

# ---------------------------------------------------------------------------
# Population helpers
# ---------------------------------------------------------------------------

## Calculate settlement radius based on population, with interpolation
## within each tier matching the TypeScript source.
static func get_settlement_radius(population: int) -> float:
	for i in range(_POP_TIERS.size()):
		var tier: Dictionary = _POP_TIERS[i]
		if population >= tier["min"] and population <= tier["max"]:
			var tier_range: float = float(tier["max"] - tier["min"])
			var tier_progress: float = tier_range if tier_range > 0.0 else 0.0
			if tier_range > 0.0:
				tier_progress = float(population - tier["min"]) / tier_range

			if i + 1 < _POP_TIERS.size():
				var next_radius: float = _POP_TIERS[i + 1]["radius"]
				return tier["radius"] + tier_progress * (next_radius - tier["radius"])
			return tier["radius"]
	return 20.0

## Calculate building count for a settlement based on population.
## Rough estimate: 1 building per 3-5 people (avg occupancy 4).
static func get_building_count(population: int) -> int:
	var avg_occupancy := 4
	return ceili(float(population) / avg_occupancy)

static func get_settlement_tier(population: int) -> String:
	if population < 100: return "hamlet"
	if population < 500: return "village"
	if population < 2000: return "town"
	if population < 10000: return "city"
	return "metropolis"

# ---------------------------------------------------------------------------
# Territory distribution – countries
# ---------------------------------------------------------------------------

## Distribute countries across the world map in a grid layout.
## Returns Array[Dictionary] with keys: id, name, bounds (Dictionary with
## minX, maxX, minZ, maxZ, centerX, centerZ), states (empty Array).
func distribute_countries(country_ids: PackedStringArray, country_names: PackedStringArray) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var count := country_ids.size()
	if count == 0:
		return result

	var half := float(terrain_size) / 2.0
	var cols := ceili(sqrt(float(count)))
	var rows := ceili(float(count) / cols)
	var cell_width := float(terrain_size) / cols
	var cell_height := float(terrain_size) / rows

	for index in range(count):
		var row := index / cols
		var col := index % cols

		var cell_min_x := -half + col * cell_width
		var cell_max_x := -half + (col + 1) * cell_width
		var cell_min_z := -half + row * cell_height
		var cell_max_z := -half + (row + 1) * cell_height

		var padding := 20.0

		var country := {
			"id": country_ids[index],
			"name": country_names[index] if index < country_names.size() else country_ids[index],
			"bounds": {
				"minX": cell_min_x + padding,
				"maxX": cell_max_x - padding,
				"minZ": cell_min_z + padding,
				"maxZ": cell_max_z - padding,
				"centerX": (cell_min_x + cell_max_x) / 2.0,
				"centerZ": (cell_min_z + cell_max_z) / 2.0,
			},
			"states": [],
		}
		result.append(country)

	return result

# ---------------------------------------------------------------------------
# Territory distribution – states within a country
# ---------------------------------------------------------------------------

## Distribute states within a country in a grid layout.
## country_data is a Dictionary as returned by distribute_countries().
func distribute_states(country_data: Dictionary, state_ids: PackedStringArray, state_names: PackedStringArray, state_terrains: PackedStringArray = PackedStringArray()) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var count := state_ids.size()
	if count == 0:
		return result

	var bounds: Dictionary = country_data["bounds"]
	var country_width: float = bounds["maxX"] - bounds["minX"]
	var country_height: float = bounds["maxZ"] - bounds["minZ"]

	var cols := ceili(sqrt(float(count)))
	var rows := ceili(float(count) / cols)
	var cell_width := country_width / cols
	var cell_height := country_height / rows

	for index in range(count):
		var row := index / cols
		var col := index % cols

		var cell_min_x: float = bounds["minX"] + col * cell_width
		var cell_max_x: float = bounds["minX"] + (col + 1) * cell_width
		var cell_min_z: float = bounds["minZ"] + row * cell_height
		var cell_max_z: float = bounds["minZ"] + (row + 1) * cell_height

		var padding := 5.0

		var state := {
			"id": state_ids[index],
			"name": state_names[index] if index < state_names.size() else state_ids[index],
			"countryId": country_data["id"],
			"bounds": {
				"minX": cell_min_x + padding,
				"maxX": cell_max_x - padding,
				"minZ": cell_min_z + padding,
				"maxZ": cell_max_z - padding,
				"centerX": (cell_min_x + cell_max_x) / 2.0,
				"centerZ": (cell_min_z + cell_max_z) / 2.0,
			},
			"settlements": [],
			"terrain": state_terrains[index] if index < state_terrains.size() else "",
		}
		result.append(state)

	return result

# ---------------------------------------------------------------------------
# Settlement distribution with collision detection (structured)
# ---------------------------------------------------------------------------

## Distribute settlements within a territory using seeded random placement
## with collision detection, matching the TypeScript source.
## bounds_dict has keys: minX, maxX, minZ, maxZ, centerX, centerZ.
## Returns Array[Dictionary] with keys: id, name, stateId, countryId,
## position (Vector3), radius, population, settlementType.
func distribute_settlements_in_territory(
	bounds_dict: Dictionary, territory_id: String, is_state: bool,
	settlement_ids: PackedStringArray, settlement_names: PackedStringArray,
	populations: PackedInt32Array, settlement_types: PackedStringArray,
	world_positions_x: PackedFloat32Array = PackedFloat32Array(),
	world_positions_z: PackedFloat32Array = PackedFloat32Array(),
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var count := settlement_ids.size()
	if count == 0:
		return result

	var name_hash := _create_seed_hash(_seed + "_" + territory_id)

	var bounds_w: float = bounds_dict["maxX"] - bounds_dict["minX"]
	var bounds_h: float = bounds_dict["maxZ"] - bounds_dict["minZ"]
	var margin := minf(bounds_w, bounds_h) * 0.25
	var safe_min_x: float = bounds_dict["minX"] + margin
	var safe_max_x: float = bounds_dict["maxX"] - margin
	var safe_min_z: float = bounds_dict["minZ"] + margin
	var safe_max_z: float = bounds_dict["maxZ"] - margin

	for index in range(count):
		var pop: int = populations[index] if index < populations.size() else 100
		var radius := get_settlement_radius(pop)
		var position: Vector3

		# Use stored world coordinates if available
		var has_world_pos := (
			index < world_positions_x.size()
			and index < world_positions_z.size()
			and world_positions_x[index] != 0.0
			and world_positions_z[index] != 0.0
		)

		if has_world_pos:
			position = Vector3(
				world_positions_x[index] * scale_factor, 0.0,
				world_positions_z[index] * scale_factor)
		elif count == 1:
			position = Vector3(bounds_dict["centerX"], 0.0, bounds_dict["centerZ"])
		else:
			var attempts := 0
			var max_attempts := 50
			var placed := false
			position = Vector3(bounds_dict["centerX"], 0.0, bounds_dict["centerZ"])

			while attempts < max_attempts:
				var pair_x := _seeded_random(name_hash)
				name_hash = pair_x[1]
				var pair_z := _seeded_random(name_hash)
				name_hash = pair_z[1]

				var x: float = safe_min_x + pair_x[0] * maxf(safe_max_x - safe_min_x, 1.0)
				var z: float = safe_min_z + pair_z[0] * maxf(safe_max_z - safe_min_z, 1.0)
				position = Vector3(x, 0.0, z)

				var too_close := false
				for j in range(result.size()):
					var d: float = position.distance_to(result[j]["position"])
					if d < (radius + result[j]["radius"] + 10.0):
						too_close = true
						break

				if not too_close:
					placed = true
					break
				attempts += 1

			# Grid fallback
			if not placed:
				var cols := ceili(sqrt(float(count)))
				var row := index / cols
				var col := index % cols
				var cell_width := (safe_max_x - safe_min_x) / cols
				var cell_height := (safe_max_z - safe_min_z) / ceili(float(count) / cols)

				position = Vector3(
					safe_min_x + col * cell_width + cell_width / 2.0,
					0.0,
					safe_min_z + row * cell_height + cell_height / 2.0
				)

		result.append({
			"id": settlement_ids[index],
			"name": settlement_names[index] if index < settlement_names.size() else settlement_ids[index],
			"stateId": territory_id if is_state else "",
			"countryId": "" if is_state else territory_id,
			"position": position,
			"radius": radius,
			"population": pop,
			"settlementType": settlement_types[index] if index < settlement_types.size() else "town",
		})

	return result

# ---------------------------------------------------------------------------
# Lot generation (legacy grid+jitter)
# ---------------------------------------------------------------------------

static func generate_lot_positions(settlement_position: Vector3, settlement_radius: float, lot_count: int, street_names: PackedStringArray = PackedStringArray()) -> Array[Vector3]:
	var positions: Array[Vector3] = []
	if lot_count <= 0:
		return positions

	var cols := ceili(sqrt(float(lot_count)))
	var rows := ceili(float(lot_count) / cols)
	var lot_spacing := 20.0
	var grid_width := (cols - 1) * lot_spacing
	var grid_height := (rows - 1) * lot_spacing

	var rng := RandomNumberGenerator.new()
	rng.seed = hash(settlement_position)

	for i in range(lot_count):
		var row := i / cols
		var col := i % cols

		var base_x := settlement_position.x - grid_width / 2.0 + col * lot_spacing
		var base_z := settlement_position.z - grid_height / 2.0 + row * lot_spacing

		var jitter_x := (rng.randf() - 0.5) * 4.0
		var jitter_z := (rng.randf() - 0.5) * 4.0

		var lot_x := base_x + jitter_x
		var lot_z := base_z + jitter_z

		# Push lots outside spawn clear radius
		var dx := lot_x - settlement_position.x
		var dz := lot_z - settlement_position.z
		var dist := sqrt(dx * dx + dz * dz)
		if dist < SPAWN_CLEAR_RADIUS:
			var angle: float
			if dist > 0.001:
				angle = atan2(dz, dx)
			else:
				angle = i * PI * 0.618
			lot_x = settlement_position.x + cos(angle) * SPAWN_CLEAR_RADIUS
			lot_z = settlement_position.z + sin(angle) * SPAWN_CLEAR_RADIUS

		positions.append(Vector3(lot_x, 0.0, lot_z))

	return positions

# ---------------------------------------------------------------------------
# Street-aligned settlement generation
# ---------------------------------------------------------------------------

## Generate a full street-aligned layout for a settlement.
## Returns Dictionary with keys:
##   "streets": Array[Dictionary] with {start, end, name}
##   "lots": Array[Dictionary] with {position, facing_angle, house_number, street_name, is_corner}
## Lots are sorted so commercial-friendly positions come first when biz_count > 0.
func generate_street_aligned_settlement(
	settlement_position: Vector3, settlement_radius: float,
	lot_count: int, biz_count: int = 0,
	street_names: PackedStringArray = PackedStringArray(),
	_existing_street_points: Array[Vector3] = [],
) -> Dictionary:
	if lot_count <= 0:
		return {"streets": [], "lots": []}

	var half := float(terrain_size) / 2.0
	var h := _create_seed_hash(_seed + "_lots")

	# --- Generate street network ---
	var pair := _seeded_random(h)
	h = pair[1]
	var main_street_half_len := settlement_radius * 0.85
	var main_angle: float = pair[0] * PI

	var cos_a := cos(main_angle)
	var sin_a := sin(main_angle)

	var streets: Array[Dictionary] = []

	var main_street := {
		"name": street_names[0] if street_names.size() > 0 else "Main Street",
		"start": Vector3(
			settlement_position.x - cos_a * main_street_half_len,
			0.0,
			settlement_position.z - sin_a * main_street_half_len),
		"end": Vector3(
			settlement_position.x + cos_a * main_street_half_len,
			0.0,
			settlement_position.z + sin_a * main_street_half_len),
	}
	streets.append(main_street)

	# Side streets perpendicular to main street
	var side_street_count := maxi(1, lot_count / 8)
	var perp_cos := cos(main_angle + PI / 2.0)
	var perp_sin := sin(main_angle + PI / 2.0)

	for s in range(side_street_count):
		var t := float(s + 1) / (side_street_count + 1)
		var origin: Vector3 = main_street["start"].lerp(main_street["end"], t)

		pair = _seeded_random(h)
		h = pair[1]
		var side_len: float = settlement_radius * (0.3 + float(pair[0]) * 0.3)

		pair = _seeded_random(h)
		h = pair[1]
		var sign_x: float = 1.0 if pair[0] > 0.5 else -1.0

		pair = _seeded_random(h)
		h = pair[1]
		var sign_z: float = 1.0 if pair[0] > 0.5 else -1.0

		var side := {
			"name": street_names[s + 1] if s + 1 < street_names.size() else "Side Street %d" % (s + 1),
			"start": origin,
			"end": Vector3(
				origin.x + perp_cos * side_len * sign_x,
				0.0,
				origin.z + perp_sin * side_len * sign_z),
		}
		streets.append(side)

	# --- Place lots along streets ---
	var lot_offset := 8.0
	var lot_spacing := 14.0
	var placed_count := 0
	var house_num := 1
	var lots: Array[Dictionary] = []

	for si in range(streets.size()):
		if placed_count >= lot_count:
			break
		var street: Dictionary = streets[si]
		var dir: Vector3 = street["end"] - street["start"]
		var street_len := dir.length()
		if street_len < 1.0:
			continue

		var dir_n := dir / street_len
		var perp_n := Vector3(-dir_n.z, 0.0, dir_n.x)

		var lots_per_side := maxi(1, floori(street_len / lot_spacing))

		for side_idx in [-1, 1]:
			for li in range(lots_per_side):
				if placed_count >= lot_count:
					break
				var tt := (li + 0.5) / lots_per_side
				var along: Vector3 = (street["start"] as Vector3).lerp(street["end"], tt)
				var pos: Vector3 = along + perp_n * (lot_offset * side_idx)

				pos.x = clampf(pos.x, -half, half)
				pos.z = clampf(pos.z, -half, half)

				lots.append({
					"position": pos,
					"facing_angle": atan2(perp_n.z * -side_idx, perp_n.x * -side_idx),
					"house_number": house_num,
					"street_name": street["name"],
					"is_corner": (li == 0 or li == lots_per_side - 1),
				})
				house_num += 1
				placed_count += 1

	# Fill remaining with scattered lots
	if placed_count < lot_count:
		var remaining := lot_count - placed_count
		for i in range(remaining):
			pair = _seeded_random(h)
			h = pair[1]
			var angle: float = pair[0] * 2.0 * PI

			pair = _seeded_random(h)
			h = pair[1]
			var r: float = (pair[0] * 0.5 + 0.5) * settlement_radius

			lots.append({
				"position": Vector3(
					clampf(settlement_position.x + cos(angle) * r, -half, half),
					0.0,
					clampf(settlement_position.z + sin(angle) * r, -half, half)),
				"facing_angle": angle + PI,
				"house_number": house_num,
				"street_name": "Outskirts",
				"is_corner": false,
			})
			house_num += 1

	# Sort lots so commercial-friendly positions come first
	if biz_count > 0:
		lots.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			# Corners first
			if a["is_corner"] != b["is_corner"]:
				return a["is_corner"]
			# Then by proximity to settlement center
			var dist_a: float = (a["position"] as Vector3).distance_to(settlement_position)
			var dist_b: float = (b["position"] as Vector3).distance_to(settlement_position)
			return dist_a < dist_b
		)

	return {"streets": streets, "lots": lots}

# ---------------------------------------------------------------------------
# Legacy settlement distribution (flat vectors)
# ---------------------------------------------------------------------------

## Distribute settlements within territory bounds, using 25% margin and
## center-placement for single settlements.
static func distribute_settlements(
	bounds_min: Vector3, bounds_max: Vector3, bounds_center: Vector3,
	settlement_count: int, radii: Array[float], world_seed: int
) -> Array[Vector3]:
	var positions: Array[Vector3] = []
	if settlement_count <= 0:
		return positions

	var bounds_w := bounds_max.x - bounds_min.x
	var bounds_h := bounds_max.z - bounds_min.z

	var margin := minf(bounds_w, bounds_h) * 0.25
	var safe_min_x := bounds_min.x + margin
	var safe_max_x := bounds_max.x - margin
	var safe_min_z := bounds_min.z + margin
	var safe_max_z := bounds_max.z - margin

	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed

	for index in range(settlement_count):
		var radius: float = radii[index] if index < radii.size() else 20.0
		var position: Vector3

		if settlement_count == 1:
			position = bounds_center
		else:
			var attempts := 0
			var max_attempts := 50
			var placed := false
			position = Vector3.ZERO

			while attempts < max_attempts:
				var x := safe_min_x + rng.randf() * maxf(safe_max_x - safe_min_x, 1.0)
				var z := safe_min_z + rng.randf() * maxf(safe_max_z - safe_min_z, 1.0)
				position = Vector3(x, 0.0, z)

				var too_close := false
				for j in range(positions.size()):
					var d := position.distance_to(positions[j])
					var other_radius: float = radii[j] if j < radii.size() else 20.0
					if d < (radius + other_radius + 10.0):
						too_close = true
						break

				if not too_close:
					placed = true
					break
				attempts += 1

			if not placed:
				var cols := ceili(sqrt(float(settlement_count)))
				var row := index / cols
				var col := index % cols

				var cell_width := (safe_max_x - safe_min_x) / cols
				var cell_height := (safe_max_z - safe_min_z) / ceili(float(settlement_count) / cols)

				position = Vector3(
					safe_min_x + col * cell_width + cell_width / 2.0,
					0.0,
					safe_min_z + row * cell_height + cell_height / 2.0
				)

		positions.append(position)

	return positions

# ---------------------------------------------------------------------------
# World sizing
# ---------------------------------------------------------------------------

## Calculate recommended world size based on entity counts.
## Minimum 1024 so that a single town's server-generated street grid
## (mapSize 500-1000) fits comfortably within the world with margin.
static func calculate_optimal_world_size(country_count: int, state_count: int, settlement_count: int) -> int:
	var max_entities := maxf(country_count, maxf(state_count / 2.0, settlement_count / 5.0))
	if max_entities <= 4.0: return 1024
	if max_entities <= 9.0: return 1536
	if max_entities <= 16.0: return 2048
	if max_entities <= 25.0: return 2560
	return 3072
