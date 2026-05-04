extends Node3D
## Animal NPC System — ambient wildlife with navigation.
## Matches shared/game-engine/rendering/AnimalNPCSystem.ts, AmbientLifeBehaviorSystem.ts.

signal animal_interacted(animal_id: String, interaction: String)

const ANIMAL_TYPES := {
	"cat": {"speed": 2.5, "wander_radius": 10.0, "flee_distance": 8.0, "behavior": "pet"},
	"dog": {"speed": 3.0, "wander_radius": 15.0, "flee_distance": 0.0, "behavior": "pet"},
	"bird": {"speed": 4.0, "wander_radius": 20.0, "flee_distance": 5.0, "behavior": "wild"},
	"horse": {"speed": 6.0, "wander_radius": 25.0, "flee_distance": 0.0, "behavior": "rideable"},
	"chicken": {"speed": 1.5, "wander_radius": 8.0, "flee_distance": 4.0, "behavior": "wild"},
	"cow": {"speed": 1.0, "wander_radius": 12.0, "flee_distance": 0.0, "behavior": "domestic"},
}

var _animals: Array[Dictionary] = []
var _player: Node3D = null
var _mounted_animal: CharacterBody3D = null

func _ready() -> void:
	add_to_group("world_generator")
	await get_tree().process_frame
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		_player = players[0] as Node3D

func generate_from_data(world_data: Dictionary) -> void:
	var entities: Dictionary = world_data.get("entities", {})
	var animals: Array = entities.get("animals", [])
	for animal_data in animals:
		_spawn_animal(animal_data)
	print("[Insimul] AnimalSystem: spawned %d animals" % animals.size())

func _spawn_animal(data: Dictionary) -> void:
	var animal_type: String = data.get("type", "cat")
	var config: Dictionary = ANIMAL_TYPES.get(animal_type, ANIMAL_TYPES["cat"])

	var body := CharacterBody3D.new()
	body.name = "Animal_%s_%s" % [animal_type, data.get("id", str(randi()))]

	# Simple mesh representation
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	var scale_factor: float = 0.5 if animal_type in ["cat", "chicken", "bird"] else 1.0
	box.size = Vector3(0.4 * scale_factor, 0.3 * scale_factor, 0.6 * scale_factor)
	mesh.mesh = box
	mesh.position.y = box.size.y / 2.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _get_animal_color(animal_type)
	mesh.material_override = mat
	body.add_child(mesh)

	var col := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.2 * scale_factor
	capsule.height = 0.5 * scale_factor
	col.shape = capsule
	col.position.y = capsule.height / 2.0
	body.add_child(col)

	var nav := NavigationAgent3D.new()
	nav.avoidance_enabled = true
	body.add_child(nav)

	# Interaction area for rideable animals
	if config["behavior"] == "rideable":
		var area := Area3D.new()
		var area_col := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = 2.0
		area_col.shape = sphere
		area.add_child(area_col)
		area.collision_layer = 0
		area.collision_mask = 1
		area.body_entered.connect(func(b): _on_mount_proximity(b, body, animal_type))
		body.add_child(area)

	add_child(body)

	var pos: Dictionary = data.get("position", {})
	body.global_position = Vector3(pos.get("x", 0), pos.get("y", 0), pos.get("z", 0))

	_animals.append({
		"node": body,
		"type": animal_type,
		"config": config,
		"wander_timer": randf() * 5.0,
		"home": body.global_position,
	})

func _physics_process(delta: float) -> void:
	for animal in _animals:
		_update_animal(animal, delta)

func _update_animal(animal: Dictionary, delta: float) -> void:
	var node: CharacterBody3D = animal["node"]
	if not is_instance_valid(node):
		return
	var config: Dictionary = animal["config"]
	var behavior: String = config["behavior"]

	# Flee behavior
	if _player and behavior == "wild":
		var dist := _player.global_position.distance_to(node.global_position)
		var flee_dist: float = config["flee_distance"]
		if flee_dist > 0 and dist < flee_dist:
			var away := (node.global_position - _player.global_position).normalized()
			node.velocity = away * config["speed"] * 1.5
			node.move_and_slide()
			return

	# Pet follow behavior
	if _player and behavior == "pet":
		var dist := _player.global_position.distance_to(node.global_position)
		if dist > 3.0 and dist < 20.0:
			var to_player := (_player.global_position - node.global_position).normalized()
			node.velocity = to_player * config["speed"]
			node.move_and_slide()
			return

	# Wander
	animal["wander_timer"] -= delta
	if animal["wander_timer"] <= 0:
		animal["wander_timer"] = randf_range(3.0, 8.0)
		var nav: NavigationAgent3D = node.get_node_or_null("NavigationAgent3D")
		if nav:
			var wander_r: float = config["wander_radius"]
			var home: Vector3 = animal["home"]
			nav.target_position = home + Vector3(randf_range(-wander_r, wander_r), 0, randf_range(-wander_r, wander_r))

	var nav: NavigationAgent3D = node.get_node_or_null("NavigationAgent3D")
	if nav and not nav.is_navigation_finished():
		var next := nav.get_next_path_position()
		var dir := (next - node.global_position).normalized()
		node.velocity = dir * config["speed"]
		node.move_and_slide()
	else:
		node.velocity = Vector3.ZERO

func _on_mount_proximity(body: Node3D, animal: CharacterBody3D, animal_type: String) -> void:
	if body.is_in_group("player"):
		animal_interacted.emit(animal.name, "mount_available")

func _get_animal_color(animal_type: String) -> Color:
	match animal_type:
		"cat": return Color(0.6, 0.4, 0.2)
		"dog": return Color(0.5, 0.35, 0.2)
		"bird": return Color(0.3, 0.5, 0.7)
		"horse": return Color(0.45, 0.3, 0.15)
		"chicken": return Color(0.9, 0.85, 0.7)
		"cow": return Color(0.85, 0.85, 0.8)
	return Color(0.5, 0.5, 0.5)
