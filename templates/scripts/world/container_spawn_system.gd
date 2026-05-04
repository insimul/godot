extends Node3D
## Container spawn system — spawns interactive containers (chests, barrels,
## crates) with loot tables and quest objects.
## Matches ContainerSpawnSystem.ts, ProceduralQuestObjects.ts, QuestObjectManager.ts.

signal container_opened(container_id: String, items: Array)
signal quest_object_interacted(quest_id: String, object_id: String)

const CONTAINER_TYPES := {
	"chest": {"item_min": 4, "item_max": 8, "width": 0.8, "height": 0.5, "depth": 0.5},
	"barrel": {"item_min": 3, "item_max": 5, "width": 0.6, "height": 0.8, "depth": 0.6},
	"crate": {"item_min": 3, "item_max": 6, "width": 0.6, "height": 0.6, "depth": 0.6},
}

## Business-type loot context for contextual item generation.
const BUSINESS_LOOT := {
	"tavern": ["ale", "bread", "meat", "cheese", "mug", "wine"],
	"bakery": ["bread", "cake", "flour", "sugar", "rolling_pin"],
	"library": ["book", "scroll", "ink", "quill", "map"],
	"church": ["candle", "holy_water", "incense", "prayer_book"],
	"farm": ["seeds", "wheat", "corn", "egg", "milk"],
	"blacksmith": ["iron_ore", "steel_ingot", "hammer", "tongs", "coal"],
	"shop": ["cloth", "thread", "dye", "gemstone", "trinket"],
	"warehouse": ["crate_goods", "rope", "lumber", "nails", "tools"],
	"residence": ["gold_coin", "letter", "key", "trinket", "food"],
}

var _containers: Dictionary = {}  # container_id → Dictionary
var _quest_objects: Dictionary = {}  # object_id → Dictionary

func _ready() -> void:
	add_to_group("world_generator")

func generate_from_data(world_data: Dictionary) -> void:
	var entities: Dictionary = world_data.get("entities", {})

	# Spawn containers from IR data
	var containers: Array = entities.get("containers", [])
	for container in containers:
		_spawn_container(container)

	# Spawn quest objects
	var quest_objects: Array = entities.get("questObjects", [])
	for qobj in quest_objects:
		_spawn_quest_object(qobj)

	# Generate containers near buildings if no IR containers
	if containers.is_empty():
		_generate_building_containers(world_data)

	print("[Insimul] ContainerSpawnSystem: %d containers, %d quest objects" % [_containers.size(), _quest_objects.size()])

func _spawn_container(data: Dictionary) -> void:
	var container_type: String = data.get("type", "chest")
	var pos_dict: Dictionary = data.get("position", {})
	var pos := Vector3(pos_dict.get("x", 0), pos_dict.get("y", 0), pos_dict.get("z", 0))
	var container_id: String = data.get("id", "container_%d" % _containers.size())

	var node := _create_container_mesh(container_type)
	node.position = pos
	node.name = "Container_%s" % container_id

	# Area3D for interaction
	var area := Area3D.new()
	area.name = "InteractArea"
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 2.0
	col.shape = shape
	area.add_child(col)
	area.body_entered.connect(_on_container_body_entered.bind(container_id))
	node.add_child(area)

	# Generate loot
	var loot := _generate_loot(container_id, container_type, data.get("context", ""))
	_containers[container_id] = {
		"node": node,
		"type": container_type,
		"items": loot,
		"opened": false,
		"data": data,
	}

	add_child(node)

func _generate_building_containers(world_data: Dictionary) -> void:
	var buildings: Array = world_data.get("entities", {}).get("buildings", [])
	var rng := RandomNumberGenerator.new()
	rng.seed = world_data.get("meta", {}).get("seed", "world").hash()

	for bld in buildings:
		# ~30% chance of having a container
		if rng.randf() > 0.3:
			continue

		var pos_dict: Dictionary = bld.get("position", {})
		var pos := Vector3(pos_dict.get("x", 0), pos_dict.get("y", 0), pos_dict.get("z", 0))
		var role: String = bld.get("spec", {}).get("buildingRole", "residential")
		var bld_id: String = bld.get("id", "")

		# Place container near building entrance
		var offset := Vector3(rng.randf_range(-3, 3), 0, rng.randf_range(2, 5))
		var container_pos := pos + offset

		var types := ["chest", "barrel", "crate"]
		var ctype: String = types[rng.randi() % types.size()]

		_spawn_container({
			"id": "bld_container_%s" % bld_id,
			"type": ctype,
			"position": {"x": container_pos.x, "y": container_pos.y, "z": container_pos.z},
			"context": role,
		})

func _spawn_quest_object(data: Dictionary) -> void:
	var pos_dict: Dictionary = data.get("position", {})
	var pos := Vector3(pos_dict.get("x", 0), pos_dict.get("y", 0), pos_dict.get("z", 0))
	var object_id: String = data.get("id", "qobj_%d" % _quest_objects.size())
	var quest_id: String = data.get("questId", "")

	var node := Node3D.new()
	node.name = "QuestObject_%s" % object_id
	node.position = pos

	# Glowing marker mesh
	var mesh := MeshInstance3D.new()
	mesh.mesh = SphereMesh.new()
	(mesh.mesh as SphereMesh).radius = 0.3
	mesh.position.y = 0.5
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.85, 0.2)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.85, 0.2)
	mat.emission_energy_multiplier = 2.0
	mesh.material_override = mat
	mesh.name = "Marker"
	node.add_child(mesh)

	# Point light for visibility
	var light := OmniLight3D.new()
	light.position.y = 0.5
	light.light_color = Color(1.0, 0.85, 0.3)
	light.light_energy = 0.8
	light.omni_range = 4.0
	light.name = "QuestGlow"
	node.add_child(light)

	# Interaction area
	var area := Area3D.new()
	area.name = "InteractArea"
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 2.5
	col.shape = shape
	area.add_child(col)
	area.body_entered.connect(_on_quest_object_body_entered.bind(quest_id, object_id))
	node.add_child(area)

	_quest_objects[object_id] = {
		"node": node,
		"quest_id": quest_id,
		"data": data,
		"collected": false,
	}

	add_child(node)

func _create_container_mesh(container_type: String) -> Node3D:
	var node := Node3D.new()
	var spec: Dictionary = CONTAINER_TYPES.get(container_type, CONTAINER_TYPES["chest"])

	var mesh := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()

	match container_type:
		"chest":
			mesh.mesh = BoxMesh.new()
			(mesh.mesh as BoxMesh).size = Vector3(spec["width"], spec["height"], spec["depth"])
			mesh.position.y = spec["height"] / 2.0
			mat.albedo_color = Color(0.4, 0.25, 0.1)
		"barrel":
			mesh.mesh = CylinderMesh.new()
			(mesh.mesh as CylinderMesh).top_radius = spec["width"] / 2.0
			(mesh.mesh as CylinderMesh).bottom_radius = spec["width"] / 2.0 + 0.05
			(mesh.mesh as CylinderMesh).height = spec["height"]
			mesh.position.y = spec["height"] / 2.0
			mat.albedo_color = Color(0.5, 0.35, 0.2)
		"crate":
			mesh.mesh = BoxMesh.new()
			(mesh.mesh as BoxMesh).size = Vector3(spec["width"], spec["height"], spec["depth"])
			mesh.position.y = spec["height"] / 2.0
			mat.albedo_color = Color(0.55, 0.4, 0.22)

	mesh.material_override = mat
	mesh.name = "ContainerMesh"
	node.add_child(mesh)

	# Collision
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(spec["width"], spec["height"], spec["depth"])
	col.shape = shape
	body.position.y = spec["height"] / 2.0
	body.add_child(col)
	node.add_child(body)

	return node

func _generate_loot(container_id: String, container_type: String, context: String) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = container_id.hash()

	var spec: Dictionary = CONTAINER_TYPES.get(container_type, CONTAINER_TYPES["chest"])
	var item_count := rng.randi_range(spec["item_min"], spec["item_max"])

	var context_items: Array = BUSINESS_LOOT.get(context, ["gold_coin", "trinket", "food", "cloth"])
	var items: Array[Dictionary] = []

	for i in range(item_count):
		var item_name: String = context_items[rng.randi() % context_items.size()]
		items.append({
			"name": item_name,
			"type": "consumable",
			"rarity": "common",
			"quantity": rng.randi_range(1, 3),
		})

	return items

func _on_container_body_entered(body: Node3D, container_id: String) -> void:
	if not body.is_in_group("player"):
		return

	var container: Dictionary = _containers.get(container_id, {})
	if container.is_empty() or container.get("opened", false):
		return

	container["opened"] = true
	container_opened.emit(container_id, container.get("items", []))

func _on_quest_object_body_entered(body: Node3D, quest_id: String, object_id: String) -> void:
	if not body.is_in_group("player"):
		return

	var qobj: Dictionary = _quest_objects.get(object_id, {})
	if qobj.is_empty() or qobj.get("collected", false):
		return

	qobj["collected"] = true
	quest_object_interacted.emit(quest_id, object_id)

	# Hide the quest object
	var node: Node3D = qobj.get("node")
	if is_instance_valid(node):
		node.visible = false

func get_container_items(container_id: String) -> Array:
	var container: Dictionary = _containers.get(container_id, {})
	return container.get("items", [])

func is_container_opened(container_id: String) -> bool:
	var container: Dictionary = _containers.get(container_id, {})
	return container.get("opened", false)
