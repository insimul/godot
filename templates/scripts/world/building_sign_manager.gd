extends Node3D
## Building sign manager — generates and places business signs on building
## facades matching BuildingSignManager.ts.
## Signs display business names using Label3D with backing geometry.

const SIGN_HEIGHT := 3.5
const SIGN_WIDTH := 2.5
const SIGN_DEPTH := 0.1
const SIGN_BOARD_PADDING := 0.2

var _signs: Array[Node3D] = []
var _businesses: Dictionary = {}  # businessId → Dictionary

func _ready() -> void:
	add_to_group("world_generator")

func generate_from_data(world_data: Dictionary) -> void:
	# Build business lookup
	var biz_list: Array = world_data.get("entities", {}).get("businesses", [])
	if biz_list.is_empty():
		biz_list = world_data.get("businesses", [])
	for biz in biz_list:
		_businesses[biz.get("id", "")] = biz

	var buildings: Array = world_data.get("entities", {}).get("buildings", [])
	if buildings.is_empty():
		buildings = world_data.get("buildings", [])

	var count := 0
	for bld in buildings:
		var biz_id: String = bld.get("businessId", "")
		if biz_id == "" or not _businesses.has(biz_id):
			continue

		var biz: Dictionary = _businesses[biz_id]
		if biz.get("isOutOfBusiness", false):
			continue

		var pos_dict: Dictionary = bld.get("position", {})
		var pos := Vector3(pos_dict.get("x", 0), pos_dict.get("y", 0), pos_dict.get("z", 0))
		var rot: float = bld.get("rotation", 0.0)
		var spec: Dictionary = bld.get("spec", {})
		var width: float = spec.get("width", 10.0)
		var depth: float = spec.get("depth", 10.0)

		var sign_node := _create_sign(
			biz.get("name", "Shop"),
			biz.get("businessType", "shop"),
			pos, rot, width, depth
		)
		add_child(sign_node)
		_signs.append(sign_node)
		count += 1

	if count > 0:
		print("[Insimul] BuildingSignManager: %d business signs placed" % count)

func _create_sign(biz_name: String, biz_type: String, building_pos: Vector3,
		building_rot: float, building_width: float, building_depth: float) -> Node3D:
	var container := Node3D.new()
	container.name = "Sign_%s" % biz_name.replace(" ", "_").substr(0, 20)

	# Position sign on building front face
	var rot_rad := deg_to_rad(building_rot)
	var front_offset := building_depth / 2.0 + 0.15
	var sign_pos := Vector3(
		building_pos.x + sin(rot_rad) * front_offset,
		building_pos.y + SIGN_HEIGHT,
		building_pos.z + cos(rot_rad) * front_offset
	)
	container.position = sign_pos
	container.rotation.y = rot_rad

	# Sign board backing
	var board := MeshInstance3D.new()
	board.mesh = BoxMesh.new()
	var sign_w := minf(SIGN_WIDTH, building_width * 0.6)
	(board.mesh as BoxMesh).size = Vector3(sign_w + SIGN_BOARD_PADDING * 2, 0.8, SIGN_DEPTH)
	board.name = "SignBoard"

	var board_mat := StandardMaterial3D.new()
	board_mat.albedo_color = _get_sign_color(biz_type)
	board.material_override = board_mat
	container.add_child(board)

	# Border frame
	var frame := MeshInstance3D.new()
	frame.mesh = BoxMesh.new()
	(frame.mesh as BoxMesh).size = Vector3(sign_w + SIGN_BOARD_PADDING * 2 + 0.1, 0.9, SIGN_DEPTH * 0.5)
	frame.position.z = -SIGN_DEPTH * 0.5
	frame.name = "SignFrame"

	var frame_mat := StandardMaterial3D.new()
	frame_mat.albedo_color = _get_frame_color(biz_type)
	frame.material_override = frame_mat
	container.add_child(frame)

	# Business name text
	var label := Label3D.new()
	label.text = biz_name
	label.font_size = 28
	label.position.z = SIGN_DEPTH / 2.0 + 0.01
	label.modulate = _get_text_color(biz_type)
	label.outline_modulate = Color(0, 0, 0, 0.5)
	label.outline_size = 2
	label.name = "SignText"
	container.add_child(label)

	# Mounting brackets
	for bx in [-sign_w / 2.0 - 0.1, sign_w / 2.0 + 0.1]:
		var bracket := MeshInstance3D.new()
		bracket.mesh = BoxMesh.new()
		(bracket.mesh as BoxMesh).size = Vector3(0.05, 0.3, 0.2)
		bracket.position = Vector3(bx, -0.3, -SIGN_DEPTH)
		bracket.material_override = frame_mat
		bracket.name = "Bracket"
		container.add_child(bracket)

	return container

func _get_sign_color(biz_type: String) -> Color:
	match biz_type:
		"tavern", "inn", "bar":
			return Color(0.35, 0.2, 0.1)
		"shop", "general_store", "merchant":
			return Color(0.15, 0.3, 0.15)
		"blacksmith", "forge":
			return Color(0.25, 0.22, 0.2)
		"bakery", "restaurant", "cafe":
			return Color(0.45, 0.3, 0.15)
		"church", "temple":
			return Color(0.3, 0.28, 0.4)
		"bank", "office":
			return Color(0.2, 0.22, 0.35)
		"hospital", "clinic", "apothecary":
			return Color(0.8, 0.8, 0.82)
		_:
			return Color(0.3, 0.25, 0.2)

func _get_frame_color(biz_type: String) -> Color:
	match biz_type:
		"tavern", "inn", "bar":
			return Color(0.5, 0.35, 0.15)
		"blacksmith", "forge":
			return Color(0.3, 0.3, 0.3)
		"hospital", "clinic", "apothecary":
			return Color(0.6, 0.6, 0.62)
		_:
			return Color(0.4, 0.35, 0.25)

func _get_text_color(biz_type: String) -> Color:
	match biz_type:
		"hospital", "clinic", "apothecary":
			return Color(0.8, 0.15, 0.15)
		_:
			return Color(0.95, 0.9, 0.8)
