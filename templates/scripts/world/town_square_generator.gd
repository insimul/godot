extends Node3D
## Town square generator — creates decorated central gathering areas for
## settlements matching TownSquareGenerator.ts.

const SQUARE_SIZE := 20.0
const BENCH_OFFSET := 7.0
const LAMP_OFFSET := 9.0

var _world_type: String = "medieval-fantasy"

func _ready() -> void:
	add_to_group("world_generator")

func generate_from_data(world_data: Dictionary) -> void:
	_world_type = world_data.get("meta", {}).get("worldType", "medieval-fantasy")
	var settlements: Array = world_data.get("geography", {}).get("settlements", [])
	if settlements.is_empty():
		settlements = world_data.get("settlements", [])

	var count := 0
	for s in settlements:
		var pos_dict: Dictionary = s.get("position", {})
		var pos := Vector3(pos_dict.get("x", 0), pos_dict.get("y", 0), pos_dict.get("z", 0))
		var sname: String = s.get("name", "Town")
		_generate_town_square(pos, sname, s.get("id", ""))
		count += 1

	if count > 0:
		print("[Insimul] TownSquareGenerator: %d town squares created" % count)

func _generate_town_square(center: Vector3, settlement_name: String, settlement_id: String) -> void:
	var container := Node3D.new()
	container.name = "TownSquare_%s" % settlement_id
	container.position = center

	# Ground plane with paved material
	var ground := MeshInstance3D.new()
	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(SQUARE_SIZE, SQUARE_SIZE)
	ground.mesh = ground_mesh
	ground.position.y = 0.02  # Slightly above terrain to avoid z-fighting
	ground.name = "SquareGround"

	var ground_mat := StandardMaterial3D.new()
	ground_mat.albedo_color = _get_ground_color()
	ground.material_override = ground_mat
	container.add_child(ground)

	# Central feature (fountain/well/flagpole based on world type)
	_add_central_feature(container)

	# Benches at cardinal directions
	var bench_dirs := [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]
	for i in range(bench_dirs.size()):
		var dir: Vector3 = bench_dirs[i]
		_add_bench(container, dir * BENCH_OFFSET, dir)

	# Lamp posts at diagonal positions
	var lamp_dirs := [
		Vector3(-1, 0, -1).normalized(),
		Vector3(1, 0, -1).normalized(),
		Vector3(-1, 0, 1).normalized(),
		Vector3(1, 0, 1).normalized(),
	]
	for dir in lamp_dirs:
		_add_lamp_post(container, dir * LAMP_OFFSET)

	# Notice board
	_add_notice_board(container, Vector3(SQUARE_SIZE / 2.0 - 1.0, 0, 0))

	add_child(container)

func _add_central_feature(parent: Node3D) -> void:
	var feature := Node3D.new()
	feature.name = "CentralFeature"

	match _world_type:
		"cyberpunk", "sci-fi-space":
			# Terminal/hologram pedestal
			var base := MeshInstance3D.new()
			base.mesh = CylinderMesh.new()
			(base.mesh as CylinderMesh).top_radius = 0.8
			(base.mesh as CylinderMesh).bottom_radius = 1.0
			(base.mesh as CylinderMesh).height = 1.2
			base.position.y = 0.6
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.3, 0.35, 0.4)
			base.material_override = mat
			base.name = "Pedestal"
			feature.add_child(base)
		"modern", "contemporary":
			# Modern fountain
			_add_fountain(feature, Color(0.6, 0.6, 0.65))
		_:
			# Medieval/fantasy fountain or well
			_add_fountain(feature, Color(0.5, 0.48, 0.43))

	parent.add_child(feature)

func _add_fountain(parent: Node3D, color: Color) -> void:
	# Basin
	var basin := MeshInstance3D.new()
	basin.mesh = CylinderMesh.new()
	(basin.mesh as CylinderMesh).top_radius = 2.0
	(basin.mesh as CylinderMesh).bottom_radius = 2.2
	(basin.mesh as CylinderMesh).height = 0.8
	basin.position.y = 0.4
	var basin_mat := StandardMaterial3D.new()
	basin_mat.albedo_color = color
	basin.material_override = basin_mat
	basin.name = "Basin"
	parent.add_child(basin)

	# Water surface
	var water := MeshInstance3D.new()
	water.mesh = CylinderMesh.new()
	(water.mesh as CylinderMesh).top_radius = 1.8
	(water.mesh as CylinderMesh).bottom_radius = 1.8
	(water.mesh as CylinderMesh).height = 0.05
	water.position.y = 0.75
	var water_mat := StandardMaterial3D.new()
	water_mat.albedo_color = Color(0.2, 0.5, 0.7, 0.7)
	water_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water.material_override = water_mat
	water.name = "FountainWater"
	parent.add_child(water)

	# Central pillar
	var pillar := MeshInstance3D.new()
	pillar.mesh = CylinderMesh.new()
	(pillar.mesh as CylinderMesh).top_radius = 0.2
	(pillar.mesh as CylinderMesh).bottom_radius = 0.3
	(pillar.mesh as CylinderMesh).height = 2.0
	pillar.position.y = 1.0
	pillar.material_override = basin_mat
	pillar.name = "Pillar"
	parent.add_child(pillar)

func _add_bench(parent: Node3D, pos: Vector3, facing: Vector3) -> void:
	var bench := Node3D.new()
	bench.name = "Bench"
	bench.position = pos
	bench.look_at_from_position(pos, pos - facing, Vector3.UP)

	var seat := MeshInstance3D.new()
	seat.mesh = BoxMesh.new()
	(seat.mesh as BoxMesh).size = Vector3(2.0, 0.1, 0.5)
	seat.position.y = 0.45
	var wood_mat := StandardMaterial3D.new()
	wood_mat.albedo_color = Color(0.45, 0.3, 0.15)
	seat.material_override = wood_mat
	seat.name = "Seat"
	bench.add_child(seat)

	# Legs
	for lx in [-0.8, 0.8]:
		var leg := MeshInstance3D.new()
		leg.mesh = BoxMesh.new()
		(leg.mesh as BoxMesh).size = Vector3(0.08, 0.45, 0.4)
		leg.position = Vector3(lx, 0.225, 0)
		leg.material_override = wood_mat
		leg.name = "Leg"
		bench.add_child(leg)

	# Backrest
	var back := MeshInstance3D.new()
	back.mesh = BoxMesh.new()
	(back.mesh as BoxMesh).size = Vector3(2.0, 0.4, 0.08)
	back.position = Vector3(0, 0.7, -0.2)
	back.material_override = wood_mat
	back.name = "Backrest"
	bench.add_child(back)

	parent.add_child(bench)

func _add_lamp_post(parent: Node3D, pos: Vector3) -> void:
	var lamp := Node3D.new()
	lamp.name = "LampPost"
	lamp.position = pos

	var pole := MeshInstance3D.new()
	pole.mesh = CylinderMesh.new()
	(pole.mesh as CylinderMesh).top_radius = 0.05
	(pole.mesh as CylinderMesh).bottom_radius = 0.08
	(pole.mesh as CylinderMesh).height = 3.0
	pole.position.y = 1.5
	var metal_mat := StandardMaterial3D.new()
	metal_mat.albedo_color = Color(0.2, 0.2, 0.22)
	pole.material_override = metal_mat
	pole.name = "Pole"
	lamp.add_child(pole)

	# Lantern
	var lantern := MeshInstance3D.new()
	lantern.mesh = BoxMesh.new()
	(lantern.mesh as BoxMesh).size = Vector3(0.3, 0.4, 0.3)
	lantern.position.y = 3.2
	var lantern_mat := StandardMaterial3D.new()
	lantern_mat.albedo_color = Color(0.9, 0.8, 0.5)
	lantern_mat.emission_enabled = true
	lantern_mat.emission = Color(0.9, 0.7, 0.3)
	lantern_mat.emission_energy_multiplier = 2.0
	lantern.material_override = lantern_mat
	lantern.name = "Lantern"
	lamp.add_child(lantern)

	# Point light
	var light := OmniLight3D.new()
	light.position.y = 3.2
	light.light_color = Color(0.9, 0.7, 0.4)
	light.light_energy = 1.5
	light.omni_range = 10.0
	light.shadow_enabled = false
	light.name = "LampLight"
	lamp.add_child(light)

	parent.add_child(lamp)

func _add_notice_board(parent: Node3D, pos: Vector3) -> void:
	var board := Node3D.new()
	board.name = "NoticeBoard"
	board.position = pos

	# Posts
	var wood_mat := StandardMaterial3D.new()
	wood_mat.albedo_color = Color(0.4, 0.28, 0.12)

	for px in [-0.5, 0.5]:
		var post := MeshInstance3D.new()
		post.mesh = BoxMesh.new()
		(post.mesh as BoxMesh).size = Vector3(0.1, 2.0, 0.1)
		post.position = Vector3(px, 1.0, 0)
		post.material_override = wood_mat
		post.name = "Post"
		board.add_child(post)

	# Board face
	var face := MeshInstance3D.new()
	face.mesh = BoxMesh.new()
	(face.mesh as BoxMesh).size = Vector3(1.2, 0.8, 0.05)
	face.position = Vector3(0, 1.4, 0)
	var board_mat := StandardMaterial3D.new()
	board_mat.albedo_color = Color(0.55, 0.42, 0.22)
	face.material_override = board_mat
	face.name = "BoardFace"
	board.add_child(face)

	# Header label
	var label := Label3D.new()
	label.text = "Notice Board"
	label.position = Vector3(0, 1.85, 0.03)
	label.font_size = 24
	label.modulate = Color(0.2, 0.15, 0.08)
	label.name = "HeaderLabel"
	board.add_child(label)

	parent.add_child(board)

func _get_ground_color() -> Color:
	match _world_type:
		"cyberpunk", "sci-fi-space":
			return Color(0.35, 0.38, 0.42)
		"modern", "contemporary":
			return Color(0.55, 0.55, 0.58)
		_:
			return Color(0.5, 0.45, 0.38)
