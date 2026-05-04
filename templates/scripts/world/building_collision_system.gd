extends Node3D
## Building collision system — adds StaticBody3D collision shapes to buildings
## and Area3D entry triggers at doorways.
## Matches BuildingCollisionSystem.ts and BuildingEntrySystem.ts.

const WALL_THICKNESS := 0.5
const FLOOR_HEIGHT := 4.0
const DOOR_WIDTH := 2.5
const DOOR_HEIGHT := 3.0
const ENTRY_TRIGGER_DEPTH := 2.0

signal building_entered(building_id: String, building_data: Dictionary)
signal building_exited(building_id: String)

var _colliders: Dictionary = {}  # building_id → Node3D
var _entry_zones: Dictionary = {}  # building_id → Area3D

func _ready() -> void:
	add_to_group("world_generator")

func generate_from_data(world_data: Dictionary) -> void:
	var buildings: Array = world_data.get("entities", {}).get("buildings", [])
	if buildings.is_empty():
		buildings = world_data.get("buildings", [])

	var count := 0
	for bld in buildings:
		var pos_dict: Dictionary = bld.get("position", {})
		var pos := Vector3(pos_dict.get("x", 0), pos_dict.get("y", 0), pos_dict.get("z", 0))
		var rot: float = bld.get("rotation", 0.0)
		var spec: Dictionary = bld.get("spec", {})
		var width: float = spec.get("width", 10.0)
		var depth: float = spec.get("depth", 10.0)
		var floors: int = spec.get("floors", 2)
		var bld_id: String = bld.get("id", "bld_%d" % count)

		_create_building_collider(bld_id, pos, rot, width, depth, floors, bld)
		count += 1

	print("[Insimul] BuildingCollisionSystem: %d building colliders created" % count)

func _create_building_collider(bld_id: String, pos: Vector3, rot: float,
		width: float, depth: float, floors: int, bld_data: Dictionary) -> void:
	var total_height := floors * FLOOR_HEIGHT
	var container := Node3D.new()
	container.name = "Collider_%s" % bld_id
	container.position = pos
	container.rotation.y = deg_to_rad(rot)

	var hw := width / 2.0
	var hd := depth / 2.0

	# Back wall (full width)
	_add_wall(container, Vector3(0, total_height / 2.0, -hd), Vector3(width, total_height, WALL_THICKNESS))

	# Left wall (full depth)
	_add_wall(container, Vector3(-hw, total_height / 2.0, 0), Vector3(WALL_THICKNESS, total_height, depth))

	# Right wall (full depth)
	_add_wall(container, Vector3(hw, total_height / 2.0, 0), Vector3(WALL_THICKNESS, total_height, depth))

	# Front wall — split around door
	var door_half := DOOR_WIDTH / 2.0
	var left_section_width := hw - door_half
	var right_section_width := hw - door_half

	if left_section_width > 0.1:
		_add_wall(container,
			Vector3(-hw + left_section_width / 2.0, total_height / 2.0, hd),
			Vector3(left_section_width, total_height, WALL_THICKNESS))

	if right_section_width > 0.1:
		_add_wall(container,
			Vector3(hw - right_section_width / 2.0, total_height / 2.0, hd),
			Vector3(right_section_width, total_height, WALL_THICKNESS))

	# Door lintel (above door)
	var lintel_height := total_height - DOOR_HEIGHT
	if lintel_height > 0.1:
		_add_wall(container,
			Vector3(0, DOOR_HEIGHT + lintel_height / 2.0, hd),
			Vector3(DOOR_WIDTH, lintel_height, WALL_THICKNESS))

	_colliders[bld_id] = container
	add_child(container)

	# Entry trigger zone at doorway
	_create_entry_zone(bld_id, container, hd, bld_data)

func _add_wall(parent: Node3D, pos: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = pos

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)

	body.name = "Wall"
	parent.add_child(body)

func _create_entry_zone(bld_id: String, container: Node3D, half_depth: float,
		bld_data: Dictionary) -> void:
	var entry := Area3D.new()
	entry.name = "EntryZone_%s" % bld_id
	entry.position = Vector3(0, DOOR_HEIGHT / 2.0, half_depth + ENTRY_TRIGGER_DEPTH / 2.0)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(DOOR_WIDTH + 1.0, DOOR_HEIGHT, ENTRY_TRIGGER_DEPTH)
	col.shape = shape
	entry.add_child(col)

	entry.set_meta("building_id", bld_id)
	entry.set_meta("building_data", bld_data)

	entry.body_entered.connect(_on_entry_body_entered.bind(bld_id, bld_data))
	entry.body_exited.connect(_on_entry_body_exited.bind(bld_id))

	_entry_zones[bld_id] = entry
	container.add_child(entry)

func _on_entry_body_entered(body: Node3D, bld_id: String, bld_data: Dictionary) -> void:
	if body.is_in_group("player"):
		building_entered.emit(bld_id, bld_data)

func _on_entry_body_exited(body: Node3D, bld_id: String) -> void:
	if body.is_in_group("player"):
		building_exited.emit(bld_id)

func get_entry_zone(building_id: String) -> Area3D:
	return _entry_zones.get(building_id, null)

func get_all_entry_zones() -> Dictionary:
	return _entry_zones
