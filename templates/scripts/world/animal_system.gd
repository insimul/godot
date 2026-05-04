extends Node3D
## Ambient Animal System — spawns cats, dogs, and birds with wander/sit/fly behaviors.
## Add to the "world_generator" group.

const ANIMAL_COUNT := 12  # Total animals to spawn
const SPAWN_RADIUS := 80.0
const WANDER_SPEED := 1.5
const BIRD_FLY_SPEED := 4.0
const BIRD_HEIGHT := 15.0
const WANDER_INTERVAL_MIN := 3.0
const WANDER_INTERVAL_MAX := 8.0

var _animals: Array[Dictionary] = []  # [{node, type, state, timer, target, base_y}]

func _ready() -> void:
	add_to_group("world_generator")

func generate_from_data(_world_data: Dictionary) -> void:
	for i in range(ANIMAL_COUNT):
		var animal_type: int = i % 3  # 0=cat, 1=dog, 2=bird
		var pos := Vector3(
			randf_range(-SPAWN_RADIUS, SPAWN_RADIUS),
			0.0,
			randf_range(-SPAWN_RADIUS, SPAWN_RADIUS)
		)
		var color_variant: int = i % 4
		var node: Node3D
		match animal_type:
			0: node = _create_cat(color_variant)
			1: node = _create_dog(color_variant)
			2:
				node = _create_bird(color_variant)
				pos.y = BIRD_HEIGHT + randf_range(-3, 3)
		node.position = pos
		node.name = "Animal_%d" % i
		add_child(node)
		_animals.append({
			"node": node,
			"type": animal_type,
			"state": "wander",  # wander, sit, fly
			"timer": randf_range(0, WANDER_INTERVAL_MAX),
			"target": pos,
			"base_y": pos.y,
		})
	print("[Insimul] AnimalSystem: spawned %d ambient animals" % ANIMAL_COUNT)

func _process(delta: float) -> void:
	for entry in _animals:
		if not is_instance_valid(entry["node"]):
			continue
		match entry["type"]:
			0, 1: _update_ground_animal(entry, delta)
			2: _update_bird(entry, delta)

# ─────────────────────────────────────────────
# Ground animal behavior (cats, dogs)
# ─────────────────────────────────────────────

func _update_ground_animal(entry: Dictionary, delta: float) -> void:
	entry["timer"] -= delta
	var node: Node3D = entry["node"]

	if entry["state"] == "sit":
		if entry["timer"] <= 0:
			entry["state"] = "wander"
			entry["timer"] = randf_range(WANDER_INTERVAL_MIN, WANDER_INTERVAL_MAX)
			entry["target"] = node.position + Vector3(
				randf_range(-8, 8), 0, randf_range(-8, 8)
			)
		return

	# Wander toward target
	var target: Vector3 = entry["target"]
	var dir := (target - node.position)
	dir.y = 0
	if dir.length() < 0.5:
		# Arrived — sit for a while
		entry["state"] = "sit"
		entry["timer"] = randf_range(2.0, 6.0)
		return

	dir = dir.normalized()
	node.position += dir * WANDER_SPEED * delta
	node.rotation.y = atan2(dir.x, dir.z)

	if entry["timer"] <= 0:
		# Pick new target
		entry["timer"] = randf_range(WANDER_INTERVAL_MIN, WANDER_INTERVAL_MAX)
		entry["target"] = node.position + Vector3(
			randf_range(-10, 10), 0, randf_range(-10, 10)
		)

# ─────────────────────────────────────────────
# Bird behavior (circular flying)
# ─────────────────────────────────────────────

func _update_bird(entry: Dictionary, delta: float) -> void:
	var node: Node3D = entry["node"]
	entry["timer"] += delta
	# Circular flight pattern
	var radius := 15.0 + float(entry["node"].get_index()) * 3.0
	var speed := BIRD_FLY_SPEED / radius
	var angle: float = entry["timer"] * speed
	var base: Vector3 = entry["target"]  # orbit center
	node.position = Vector3(
		base.x + cos(angle) * radius,
		entry["base_y"] + sin(entry["timer"] * 0.5) * 2.0,
		base.z + sin(angle) * radius
	)
	node.rotation.y = angle + PI / 2.0

# ─────────────────────────────────────────────
# Procedural animal geometry
# ─────────────────────────────────────────────

const CAT_COLORS := [
	Color(0.3, 0.28, 0.25),   # Dark gray
	Color(0.8, 0.55, 0.25),   # Orange tabby
	Color(0.15, 0.14, 0.13),  # Black
	Color(0.85, 0.82, 0.78),  # White
]

const DOG_COLORS := [
	Color(0.5, 0.35, 0.2),    # Brown
	Color(0.25, 0.22, 0.18),  # Dark brown
	Color(0.8, 0.75, 0.65),   # Golden
	Color(0.6, 0.58, 0.55),   # Gray
]

const BIRD_COLORS := [
	Color(0.3, 0.3, 0.35),    # Dark gray
	Color(0.6, 0.25, 0.2),    # Robin red
	Color(0.2, 0.35, 0.5),    # Blue
	Color(0.5, 0.45, 0.3),    # Sparrow brown
]

func _create_cat(variant: int) -> Node3D:
	var root := Node3D.new()
	var color: Color = CAT_COLORS[variant % CAT_COLORS.size()]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color

	# Body (ellipsoid)
	var body := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.2
	sphere.height = 0.4
	body.mesh = sphere
	body.scale = Vector3(1.0, 0.8, 1.6)
	body.position.y = 0.2
	body.material_override = mat
	root.add_child(body)

	# Head
	var head := MeshInstance3D.new()
	var head_sphere := SphereMesh.new()
	head_sphere.radius = 0.12
	head_sphere.height = 0.24
	head.mesh = head_sphere
	head.position = Vector3(0, 0.28, 0.25)
	head.material_override = mat
	root.add_child(head)

	# Ears (two small cones)
	for side in [-1.0, 1.0]:
		var ear := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.04
		cone.height = 0.08
		cone.radial_segments = 4
		ear.mesh = cone
		ear.position = Vector3(side * 0.06, 0.38, 0.22)
		ear.material_override = mat
		root.add_child(ear)

	# Tail (cylinder)
	var tail := MeshInstance3D.new()
	var tail_cyl := CylinderMesh.new()
	tail_cyl.top_radius = 0.015
	tail_cyl.bottom_radius = 0.025
	tail_cyl.height = 0.3
	tail_cyl.radial_segments = 4
	tail.mesh = tail_cyl
	tail.position = Vector3(0, 0.3, -0.3)
	tail.rotation.x = -PI / 4.0
	tail.material_override = mat
	root.add_child(tail)

	root.scale = Vector3(0.8, 0.8, 0.8)
	return root

func _create_dog(variant: int) -> Node3D:
	var root := Node3D.new()
	var color: Color = DOG_COLORS[variant % DOG_COLORS.size()]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color

	# Body (box)
	var body := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.3, 0.25, 0.5)
	body.mesh = box
	body.position.y = 0.3
	body.material_override = mat
	root.add_child(body)

	# Head (box with snout)
	var head := MeshInstance3D.new()
	var head_box := BoxMesh.new()
	head_box.size = Vector3(0.2, 0.2, 0.2)
	head.mesh = head_box
	head.position = Vector3(0, 0.38, 0.3)
	head.material_override = mat
	root.add_child(head)

	# Snout
	var snout := MeshInstance3D.new()
	var snout_box := BoxMesh.new()
	snout_box.size = Vector3(0.1, 0.08, 0.12)
	snout.mesh = snout_box
	snout.position = Vector3(0, 0.32, 0.4)
	snout.material_override = mat
	root.add_child(snout)

	# Legs (4 cylinders)
	for lx in [-0.1, 0.1]:
		for lz in [-0.15, 0.15]:
			var leg := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.035
			cyl.bottom_radius = 0.035
			cyl.height = 0.2
			cyl.radial_segments = 4
			leg.mesh = cyl
			leg.position = Vector3(lx, 0.1, lz)
			leg.material_override = mat
			root.add_child(leg)

	return root

func _create_bird(variant: int) -> Node3D:
	var root := Node3D.new()
	var color: Color = BIRD_COLORS[variant % BIRD_COLORS.size()]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color

	# Body
	var body := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.08
	sphere.height = 0.16
	body.mesh = sphere
	body.scale = Vector3(0.8, 0.8, 1.4)
	body.material_override = mat
	root.add_child(body)

	# Wings (two flat boxes)
	for side in [-1.0, 1.0]:
		var wing := MeshInstance3D.new()
		var wing_box := BoxMesh.new()
		wing_box.size = Vector3(0.2, 0.02, 0.1)
		wing.mesh = wing_box
		wing.position = Vector3(side * 0.12, 0.02, 0)
		wing.rotation.z = side * 0.3
		wing.material_override = mat
		root.add_child(wing)

	return root
