extends Node3D
## Item & Container world spawner.
## Places items from world_data as 3D objects with type-based colors,
## spawns containers (chests/barrels/crates) near buildings, and adds
## bobbing animation to quest items.
## Add to the "world_generator" group.

## Item type → fallback color mapping (matches Babylon.js ExteriorItemManager).
const ITEM_COLORS := {
	"food":        Color(0.7, 0.5, 0.2),
	"drink":       Color(0.3, 0.4, 0.7),
	"weapon":      Color(0.5, 0.5, 0.55),
	"armor":       Color(0.45, 0.4, 0.35),
	"tool":        Color(0.4, 0.35, 0.3),
	"material":    Color(0.5, 0.45, 0.35),
	"consumable":  Color(0.6, 0.3, 0.3),
	"collectible": Color(0.6, 0.55, 0.3),
	"key":         Color(0.7, 0.65, 0.2),
	"quest":       Color(0.3, 0.6, 0.7),
}
const DEFAULT_ITEM_COLOR := Color(0.5, 0.45, 0.4)

## Container type specs: {color, size}
const CONTAINER_SPECS := {
	"chest":  {"color": Color(0.55, 0.35, 0.12), "size": Vector3(1.2, 0.7, 0.8)},
	"barrel": {"color": Color(0.5, 0.3, 0.12),   "size": Vector3(0.8, 1.2, 0.8)},
	"crate":  {"color": Color(0.4, 0.32, 0.2),   "size": Vector3(0.9, 0.9, 0.9)},
}

## Bobbing animation parameters
const BOB_AMPLITUDE := 0.25
const BOB_SPEED := 3.0  # radians per second
const SPIN_SPEED := 2.0  # radians per second

var _bobbing_items: Array[Dictionary] = []  # [{node, base_y}]
var _material_cache := {}

func _ready() -> void:
	add_to_group("world_generator")

func generate_from_data(world_data: Dictionary) -> void:
	var entities: Dictionary = world_data.get("entities", {})

	# Spawn exterior items
	var items: Array = entities.get("items", [])
	var item_count := 0
	for item in items:
		if _spawn_item(item):
			item_count += 1

	# Spawn containers near buildings
	var buildings: Array = entities.get("buildings", [])
	var container_count := _spawn_containers(buildings)

	print("[Insimul] ItemSpawner: %d items, %d containers" % [item_count, container_count])

func _process(delta: float) -> void:
	# Animate bobbing items
	var time: float = Time.get_ticks_msec() / 1000.0
	for entry in _bobbing_items:
		var node: Node3D = entry["node"]
		if is_instance_valid(node):
			node.position.y = entry["base_y"] + sin(time * BOB_SPEED) * BOB_AMPLITUDE
			node.rotation.y += SPIN_SPEED * delta

# ─────────────────────────────────────────────
# Item spawning
# ─────────────────────────────────────────────

func _spawn_item(item: Dictionary) -> bool:
	var meta: Dictionary = item.get("metadata", {})
	var pos_data: Dictionary = meta.get("position", {})
	if pos_data.is_empty():
		return false

	var x: float = pos_data.get("x", 0.0)
	var z: float = pos_data.get("z", 0.0)
	var y: float = pos_data.get("y", 0.15)

	var item_type: String = item.get("itemType", item.get("type", ""))
	var item_id: String = item.get("id", "")
	var item_name: String = item.get("name", "Item")
	var object_role: String = item.get("objectRole", "")

	# Try asset-based model first
	var node: Node3D = null
	if not object_role.is_empty():
		node = _try_load_model(object_role)

	# Fallback to procedural box
	if node == null:
		node = _create_item_mesh(item_type)

	node.position = Vector3(x, y, z)
	node.name = "Item_%s" % item_id

	# Store metadata for interaction
	node.set_meta("item_id", item_id)
	node.set_meta("item_name", item_name)
	node.set_meta("item_type", item_type)
	node.set_meta("is_world_item", true)

	add_child(node)

	# Quest items get bobbing animation
	if item_type == "quest" or item_type == "collectible" or item_type == "key":
		_bobbing_items.append({"node": node, "base_y": y})

	return true

func _create_item_mesh(item_type: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.35, 0.35, 0.35)
	mi.mesh = box

	var color: Color = ITEM_COLORS.get(item_type, DEFAULT_ITEM_COLOR)
	var mat := _get_mat("item_%s" % item_type, color)
	mi.material_override = mat

	return mi

func _try_load_model(role: String) -> Node3D:
	# Check asset manifest for model path
	var manifest: Dictionary = DataLoader.load_asset_manifest()
	var assets: Array = manifest.get("assets", [])
	for entry in assets:
		if entry.get("role", "") == role and entry.get("category", "") == "prop":
			var path: String = entry.get("exportPath", "")
			if not path.is_empty() and ResourceLoader.exists("res://" + path):
				var scene: PackedScene = load("res://" + path)
				if scene:
					return scene.instantiate()
	return null

# ─────────────────────────────────────────────
# Container spawning
# ─────────────────────────────────────────────

func _spawn_containers(buildings: Array) -> int:
	var count := 0
	for building in buildings:
		var bx: float = building.get("position", {}).get("x", 0.0)
		var bz: float = building.get("position", {}).get("z", 0.0)
		var by: float = building.get("position", {}).get("y", 0.0)
		var rot: float = deg_to_rad(building.get("rotation", 0.0))
		var spec: Dictionary = building.get("spec", {})
		var bw: float = spec.get("width", 10.0)
		var bd: float = spec.get("depth", 10.0)

		# Use building ID as seed for deterministic placement
		var seed_val: int = building.get("id", "").hash()

		# Right side container (50% chance)
		if (seed_val % 100) < 50:
			var local_x: float = bw / 2.0 + 1.5
			var local_z: float = (((seed_val >> 8) % 100) / 100.0 - 0.5) * bd * 0.5
			var container_type: String = "barrel" if (seed_val % 2) == 0 else "crate"
			var wx: float = bx + cos(rot) * local_x - sin(rot) * local_z
			var wz: float = bz + sin(rot) * local_x + cos(rot) * local_z
			_spawn_container(container_type, Vector3(wx, by, wz), rot, building.get("id", ""))
			count += 1

		# Back side container (40% chance)
		if ((seed_val >> 4) % 100) < 40:
			var local_z2: float = -(bd / 2.0 + 1.5)
			var local_x2: float = (((seed_val >> 12) % 100) / 100.0 - 0.5) * bw * 0.4
			var container_type2: String = "crate" if ((seed_val >> 2) % 10) < 7 else "chest"
			var wx2: float = bx + cos(rot) * local_x2 - sin(rot) * local_z2
			var wz2: float = bz + sin(rot) * local_x2 + cos(rot) * local_z2
			_spawn_container(container_type2, Vector3(wx2, by, wz2), rot, building.get("id", "") + "_back")
			count += 1

	return count

func _spawn_container(container_type: String, pos: Vector3, rot: float, container_id: String) -> void:
	var spec: Dictionary = CONTAINER_SPECS.get(container_type, CONTAINER_SPECS["crate"])
	var size: Vector3 = spec["size"]
	var color: Color = spec["color"]

	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = _get_mat("container_%s" % container_type, color)
	mi.position = Vector3(pos.x, pos.y + size.y / 2.0, pos.z)
	mi.rotation.y = rot
	mi.name = "Container_%s" % container_id

	# Collision
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)
	mi.add_child(body)

	# Metadata for interaction
	mi.set_meta("is_container", true)
	mi.set_meta("container_type", container_type)
	mi.set_meta("container_id", container_id)

	add_child(mi)

# ─────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────

func _get_mat(key: String, color: Color) -> StandardMaterial3D:
	if _material_cache.has(key):
		return _material_cache[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	_material_cache[key] = mat
	return mat
