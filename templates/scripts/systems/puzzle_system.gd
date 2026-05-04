extends Node3D
## Puzzle System — puzzles and procedural dungeon generation.
## Matches shared/game-engine/rendering/PuzzleSystem.ts, ProceduralDungeonGenerator.ts.

signal puzzle_completed(puzzle_id: String)
signal dungeon_entered(dungeon_id: String)

var _puzzle_ui: CanvasLayer = null
var _puzzle_container: VBoxContainer = null
var _current_puzzle: Dictionary = {}

func _ready() -> void:
	add_to_group("world_generator")
	_build_puzzle_ui()

func generate_from_data(world_data: Dictionary) -> void:
	var entities: Dictionary = world_data.get("entities", {})
	var dungeons: Array = entities.get("dungeons", [])
	for dungeon_data in dungeons:
		_generate_dungeon(dungeon_data)
	print("[Insimul] PuzzleSystem: generated %d dungeons" % dungeons.size())

func _generate_dungeon(data: Dictionary) -> void:
	var dungeon_id: String = data.get("id", "")
	var pos_data: Dictionary = data.get("position", {})
	var rooms: Array = data.get("rooms", [])
	var seed_val: int = data.get("seed", dungeon_id.hash())
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val

	var dungeon_root := Node3D.new()
	dungeon_root.name = "Dungeon_%s" % dungeon_id
	add_child(dungeon_root)
	dungeon_root.global_position = Vector3(pos_data.get("x", 0), pos_data.get("y", 0), pos_data.get("z", 0))

	# Generate rooms
	var room_positions: Array[Vector3] = []
	for i in range(max(rooms.size(), 3)):
		var room_pos := Vector3(rng.randf_range(-20, 20), 0, rng.randf_range(-20, 20))
		room_positions.append(room_pos)
		var room := _create_room(rng, room_pos, i)
		dungeon_root.add_child(room)

	# Connect rooms with corridors
	for i in range(room_positions.size() - 1):
		var corridor := _create_corridor(room_positions[i], room_positions[i + 1])
		dungeon_root.add_child(corridor)

	# Entry trigger
	var entry := Area3D.new()
	var col := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 3.0
	col.shape = sphere
	entry.add_child(col)
	entry.collision_layer = 0
	entry.collision_mask = 1
	entry.body_entered.connect(func(body):
		if body.is_in_group("player"):
			dungeon_entered.emit(dungeon_id)
	)
	dungeon_root.add_child(entry)

func _create_room(rng: RandomNumberGenerator, pos: Vector3, index: int) -> Node3D:
	var room := Node3D.new()
	room.name = "Room_%d" % index
	room.position = pos

	var width: float = rng.randf_range(6, 12)
	var depth: float = rng.randf_range(6, 12)
	var height: float = 4.0

	# Floor
	var floor_mesh := MeshInstance3D.new()
	var floor_box := BoxMesh.new()
	floor_box.size = Vector3(width, 0.2, depth)
	floor_mesh.mesh = floor_box
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.3, 0.3, 0.35)
	floor_mesh.material_override = floor_mat
	room.add_child(floor_mesh)

	# Walls (4 sides)
	for side in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var wall := MeshInstance3D.new()
		var wall_box := BoxMesh.new()
		if abs(side.x) > 0:
			wall_box.size = Vector3(0.3, height, depth)
			wall.position = side * (width / 2.0) + Vector3(0, height / 2.0, 0)
		else:
			wall_box.size = Vector3(width, height, 0.3)
			wall.position = side * (depth / 2.0) + Vector3(0, height / 2.0, 0)
		wall.mesh = wall_box
		var wall_mat := StandardMaterial3D.new()
		wall_mat.albedo_color = Color(0.35, 0.32, 0.3)
		wall.material_override = wall_mat
		room.add_child(wall)

	return room

func _create_corridor(from: Vector3, to: Vector3) -> MeshInstance3D:
	var corridor := MeshInstance3D.new()
	var dir := to - from
	var length := dir.length()
	var box := BoxMesh.new()
	box.size = Vector3(2.0, 3.0, length)
	corridor.mesh = box
	corridor.position = (from + to) / 2.0 + Vector3(0, 1.5, 0)
	corridor.look_at_from_position(corridor.position, to + Vector3(0, 1.5, 0), Vector3.UP)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.25, 0.28)
	corridor.material_override = mat
	return corridor

func _build_puzzle_ui() -> void:
	_puzzle_ui = CanvasLayer.new()
	_puzzle_ui.layer = 15
	_puzzle_ui.process_mode = Node.PROCESS_MODE_ALWAYS
	_puzzle_ui.visible = false
	add_child(_puzzle_ui)

	var panel := PanelContainer.new()
	panel.anchors_preset = Control.PRESET_CENTER
	panel.anchor_left = 0.2
	panel.anchor_top = 0.2
	panel.anchor_right = 0.8
	panel.anchor_bottom = 0.8
	_puzzle_ui.add_child(panel)

	_puzzle_container = VBoxContainer.new()
	panel.add_child(_puzzle_container)

func show_puzzle(puzzle_data: Dictionary) -> void:
	_current_puzzle = puzzle_data
	_puzzle_ui.visible = true
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	for child in _puzzle_container.get_children():
		child.queue_free()

	var title := Label.new()
	title.text = puzzle_data.get("title", "Puzzle")
	_puzzle_container.add_child(title)

	var desc := Label.new()
	desc.text = puzzle_data.get("description", "")
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_puzzle_container.add_child(desc)

	var solve_btn := Button.new()
	solve_btn.text = "Attempt Solution"
	solve_btn.pressed.connect(func():
		_puzzle_ui.visible = false
		get_tree().paused = false
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		puzzle_completed.emit(_current_puzzle.get("id", ""))
	)
	_puzzle_container.add_child(solve_btn)
