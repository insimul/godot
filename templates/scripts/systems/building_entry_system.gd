extends Node
## Building Entry System — autoloaded singleton.
## Detects when the player is near a building door and handles entry/exit
## with fade transitions. Generates a simple placeholder interior room.

signal entered_building(building_id: String)
signal exited_building

const ENTRY_DISTANCE := 3.0
const FADE_DURATION := 0.5

var is_inside := false
var current_building_id := ""
var _player: Node3D = null
var _buildings: Array[Dictionary] = []  # [{position, rotation, id, spec, node}]
var _interior_root: Node3D = null
var _exterior_root: Node3D = null
var _saved_player_pos := Vector3.ZERO
var _fade_overlay: ColorRect = null
var _fade_tween: Tween = null
var _prompt_label: Label = null

func _ready() -> void:
	call_deferred("_setup")

func _setup() -> void:
	_create_fade_overlay()
	_create_prompt_label()

func _process(_delta: float) -> void:
	if is_inside:
		_update_exit_prompt()
		return
	if _player == null:
		_player = _find_player()
		if _player == null:
			return
	_update_entry_prompt()

func register_buildings(world_data: Dictionary) -> void:
	var entities: Dictionary = world_data.get("entities", {})
	var buildings: Array = entities.get("buildings", [])
	for bld in buildings:
		var pos_dict: Dictionary = bld.get("position", {})
		_buildings.append({
			"position": Vector3(pos_dict.get("x", 0.0), pos_dict.get("y", 0.0), pos_dict.get("z", 0.0)),
			"rotation": bld.get("rotation", 0.0),
			"id": bld.get("id", ""),
			"spec": bld.get("spec", {}),
		})

# ─────────────────────────────────────────────
# Proximity detection
# ─────────────────────────────────────────────

func _update_entry_prompt() -> void:
	var nearest := _find_nearest_building_door()
	if nearest.is_empty():
		_prompt_label.visible = false
		return

	var dist: float = nearest["distance"]
	if dist < ENTRY_DISTANCE:
		_prompt_label.text = "Press E to enter %s" % nearest.get("role", "building")
		_prompt_label.visible = true
		if Input.is_action_just_pressed("interact"):
			_enter_building(nearest)
	else:
		_prompt_label.visible = false

func _update_exit_prompt() -> void:
	_prompt_label.text = "Press E to exit"
	_prompt_label.visible = true
	if Input.is_action_just_pressed("interact"):
		_exit_building()

func _find_nearest_building_door() -> Dictionary:
	if _player == null:
		return {}
	var player_pos := _player.global_position
	var best_dist := INF
	var best := {}
	for bld in _buildings:
		var bpos: Vector3 = bld["position"]
		# Door is at front center of building
		var rot: float = deg_to_rad(bld.get("rotation", 0.0))
		var spec: Dictionary = bld.get("spec", {})
		var depth: float = spec.get("depth", 10.0)
		var door_offset := Vector3(sin(rot) * depth / 2.0, 0, cos(rot) * depth / 2.0)
		var door_pos := bpos + door_offset
		var dist: float = player_pos.distance_to(door_pos)
		if dist < best_dist:
			best_dist = dist
			best = bld.duplicate()
			best["distance"] = dist
			best["door_pos"] = door_pos
			best["role"] = spec.get("buildingRole", "building")
	return best

# ─────────────────────────────────────────────
# Entry / Exit transitions
# ─────────────────────────────────────────────

func _enter_building(building: Dictionary) -> void:
	if is_inside:
		return
	current_building_id = building.get("id", "")
	_saved_player_pos = _player.global_position

	# Fade out
	_fade_to_black(func():
		# Hide exterior world
		_hide_exterior()
		# Generate interior
		_generate_interior(building)
		# Move player inside
		_player.global_position = Vector3(0, 0.5, 0)
		is_inside = true
		entered_building.emit(current_building_id)
		# Fade in
		_fade_from_black()
	)

func _exit_building() -> void:
	if not is_inside:
		return

	_fade_to_black(func():
		# Clean up interior
		if _interior_root and is_instance_valid(_interior_root):
			_interior_root.queue_free()
			_interior_root = null
		# Show exterior
		_show_exterior()
		# Restore player position
		_player.global_position = _saved_player_pos + Vector3(0, 0, 2)
		is_inside = false
		current_building_id = ""
		exited_building.emit()
		_fade_from_black()
	)

# ─────────────────────────────────────────────
# Interior generation (simple placeholder room)
# ─────────────────────────────────────────────

func _generate_interior(building: Dictionary) -> void:
	_interior_root = Node3D.new()
	_interior_root.name = "Interior_%s" % building.get("id", "")
	get_tree().root.add_child(_interior_root)

	var spec: Dictionary = building.get("spec", {})
	var width: float = spec.get("width", 10.0)
	var depth: float = spec.get("depth", 10.0)
	var floor_height := 3.0

	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.85, 0.82, 0.75)
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.5, 0.35, 0.22)

	# Floor
	var floor_mesh := MeshInstance3D.new()
	var floor_box := BoxMesh.new()
	floor_box.size = Vector3(width, 0.1, depth)
	floor_mesh.mesh = floor_box
	floor_mesh.material_override = floor_mat
	floor_mesh.position.y = -0.05
	_interior_root.add_child(floor_mesh)

	# Floor collision
	var floor_body := StaticBody3D.new()
	var floor_col := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(width, 0.1, depth)
	floor_col.shape = floor_shape
	floor_col.position.y = -0.05
	floor_body.add_child(floor_col)
	_interior_root.add_child(floor_body)

	# 4 walls
	var wall_thickness := 0.2
	var walls := [
		{"size": Vector3(width, floor_height, wall_thickness), "pos": Vector3(0, floor_height/2.0, -depth/2.0)},
		{"size": Vector3(width, floor_height, wall_thickness), "pos": Vector3(0, floor_height/2.0, depth/2.0)},
		{"size": Vector3(wall_thickness, floor_height, depth), "pos": Vector3(-width/2.0, floor_height/2.0, 0)},
		{"size": Vector3(wall_thickness, floor_height, depth), "pos": Vector3(width/2.0, floor_height/2.0, 0)},
	]
	for w in walls:
		var wall := MeshInstance3D.new()
		var wall_box := BoxMesh.new()
		wall_box.size = w["size"]
		wall.mesh = wall_box
		wall.position = w["pos"]
		wall.material_override = wall_mat
		_interior_root.add_child(wall)

	# Interior light
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.95, 0.85)
	light.light_energy = 1.2
	light.omni_range = maxf(width, depth) * 0.8
	light.position = Vector3(0, floor_height - 0.5, 0)
	_interior_root.add_child(light)

	# Furniture placement based on building role
	var role: String = spec.get("buildingRole", "residential")
	_place_furniture(_interior_root, role, width, depth)

	# Spawn interior NPCs (shopkeeper/resident)
	_populate_interior(_interior_root, building, role, width, depth)

# ─────────────────────────────────────────────
# Exterior visibility toggle
# ─────────────────────────────────────────────

func _hide_exterior() -> void:
	if _exterior_root == null:
		# Find the Main scene node
		for child in get_tree().root.get_children():
			if child.name == "Main":
				_exterior_root = child
				break
	if _exterior_root:
		for child in _exterior_root.get_children():
			if child is Node3D and child.name != "Player" and child != _interior_root:
				child.visible = false

func _show_exterior() -> void:
	if _exterior_root:
		for child in _exterior_root.get_children():
			if child is Node3D:
				child.visible = true

# ─────────────────────────────────────────────
# Fade transitions
# ─────────────────────────────────────────────

func _fade_to_black(on_complete: Callable) -> void:
	if _fade_overlay == null:
		on_complete.call()
		return
	_fade_overlay.visible = true
	_fade_overlay.color = Color(0, 0, 0, 0)
	if _fade_tween and _fade_tween.is_running():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(_fade_overlay, "color", Color(0, 0, 0, 1), FADE_DURATION)
	_fade_tween.tween_callback(on_complete)

func _fade_from_black() -> void:
	if _fade_overlay == null:
		return
	if _fade_tween and _fade_tween.is_running():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(_fade_overlay, "color", Color(0, 0, 0, 0), FADE_DURATION)
	_fade_tween.tween_callback(func(): _fade_overlay.visible = false)

# ─────────────────────────────────────────────
# UI setup
# ─────────────────────────────────────────────

func _create_fade_overlay() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 100
	add_child(canvas)
	_fade_overlay = ColorRect.new()
	_fade_overlay.color = Color(0, 0, 0, 0)
	_fade_overlay.anchor_right = 1.0
	_fade_overlay.anchor_bottom = 1.0
	_fade_overlay.visible = false
	_fade_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(_fade_overlay)

func _create_prompt_label() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 10
	add_child(canvas)
	_prompt_label = Label.new()
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.anchor_left = 0.3
	_prompt_label.anchor_right = 0.7
	_prompt_label.anchor_top = 0.75
	_prompt_label.anchor_bottom = 0.8
	_prompt_label.add_theme_font_size_override("font_size", 20)
	_prompt_label.add_theme_color_override("font_color", Color.WHITE)
	_prompt_label.visible = false
	canvas.add_child(_prompt_label)

func _find_player() -> Node3D:
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		return players[0] as Node3D
	return null

# ─────────────────────────────────────────────
# Furniture placement
# ─────────────────────────────────────────────

const WOOD_COLOR := Color(0.45, 0.30, 0.18)
const DARK_WOOD_COLOR := Color(0.30, 0.20, 0.12)
const FABRIC_COLOR := Color(0.55, 0.35, 0.25)
const METAL_COLOR := Color(0.35, 0.35, 0.38)

func _place_furniture(root: Node3D, role: String, width: float, depth: float) -> void:
	var hw: float = width / 2.0 - 0.5
	var hd: float = depth / 2.0 - 0.5

	match role:
		"Tavern", "Bar", "Restaurant", "Inn":
			_add_counter(root, Vector3(0, 0, -hd + 0.5), width * 0.6)
			_add_table(root, Vector3(-hw * 0.4, 0, hd * 0.3))
			_add_table(root, Vector3(hw * 0.4, 0, hd * 0.3))
			_add_chair(root, Vector3(-hw * 0.4 - 0.8, 0, hd * 0.3))
			_add_chair(root, Vector3(-hw * 0.4 + 0.8, 0, hd * 0.3))
			_add_chair(root, Vector3(hw * 0.4 - 0.8, 0, hd * 0.3))
			_add_chair(root, Vector3(hw * 0.4 + 0.8, 0, hd * 0.3))
		"Shop", "GroceryStore", "Bakery", "BookStore", "HerbShop", "JewelryStore":
			_add_counter(root, Vector3(0, 0, -hd + 0.5), width * 0.5)
			_add_shelf(root, Vector3(-hw + 0.3, 0, 0), depth * 0.6)
			_add_shelf(root, Vector3(hw - 0.3, 0, 0), depth * 0.6)
		"Blacksmith", "Carpenter":
			_add_box(root, "Anvil", Vector3(-hw * 0.3, 0.4, -hd * 0.3), Vector3(0.8, 0.8, 0.6), METAL_COLOR)
			_add_box(root, "Workbench", Vector3(hw * 0.3, 0.4, 0), Vector3(2.0, 0.8, 0.8), WOOD_COLOR)
		"Church":
			for i in range(4):
				_add_box(root, "Pew", Vector3(-hw * 0.3, 0.25, -hd * 0.5 + float(i) * 1.8 + 1.5), Vector3(2.5, 0.5, 0.5), DARK_WOOD_COLOR)
				_add_box(root, "Pew", Vector3(hw * 0.3, 0.25, -hd * 0.5 + float(i) * 1.8 + 1.5), Vector3(2.5, 0.5, 0.5), DARK_WOOD_COLOR)
		"Library", "School", "University":
			_add_shelf(root, Vector3(-hw + 0.3, 0, 0), depth * 0.8)
			_add_shelf(root, Vector3(hw - 0.3, 0, 0), depth * 0.8)
			_add_table(root, Vector3(0, 0, 0))
			_add_chair(root, Vector3(-0.8, 0, 0))
			_add_chair(root, Vector3(0.8, 0, 0))
		"Hospital", "Clinic", "Pharmacy":
			_add_box(root, "Bed", Vector3(-hw * 0.4, 0.3, 0), Vector3(1.0, 0.6, 2.0), Color(0.8, 0.8, 0.85))
			_add_box(root, "Bed", Vector3(hw * 0.4, 0.3, 0), Vector3(1.0, 0.6, 2.0), Color(0.8, 0.8, 0.85))
			_add_shelf(root, Vector3(0, 0, -hd + 0.3), width * 0.4)
		_:
			# Default residential: table, chairs, bed
			_add_table(root, Vector3(0, 0, hd * 0.3))
			_add_chair(root, Vector3(-0.8, 0, hd * 0.3))
			_add_chair(root, Vector3(0.8, 0, hd * 0.3))
			_add_box(root, "Bed", Vector3(-hw + 1.0, 0.3, -hd + 1.0), Vector3(1.2, 0.6, 2.0), FABRIC_COLOR)
			_add_shelf(root, Vector3(hw - 0.3, 0, -hd * 0.3), depth * 0.3)

func _add_table(root: Node3D, pos: Vector3) -> void:
	# Tabletop
	var top := MeshInstance3D.new()
	var top_box := BoxMesh.new()
	top_box.size = Vector3(1.4, 0.08, 0.8)
	top.mesh = top_box
	top.position = pos + Vector3(0, 0.75, 0)
	top.material_override = _furniture_mat(WOOD_COLOR)
	root.add_child(top)
	# Legs
	for lx in [-0.6, 0.6]:
		for lz in [-0.3, 0.3]:
			var leg := MeshInstance3D.new()
			var leg_box := BoxMesh.new()
			leg_box.size = Vector3(0.06, 0.75, 0.06)
			leg.mesh = leg_box
			leg.position = pos + Vector3(lx, 0.375, lz)
			leg.material_override = _furniture_mat(DARK_WOOD_COLOR)
			root.add_child(leg)

func _add_chair(root: Node3D, pos: Vector3) -> void:
	# Seat
	var seat := MeshInstance3D.new()
	var seat_box := BoxMesh.new()
	seat_box.size = Vector3(0.45, 0.06, 0.45)
	seat.mesh = seat_box
	seat.position = pos + Vector3(0, 0.45, 0)
	seat.material_override = _furniture_mat(WOOD_COLOR)
	root.add_child(seat)
	# Back
	var back := MeshInstance3D.new()
	var back_box := BoxMesh.new()
	back_box.size = Vector3(0.45, 0.45, 0.06)
	back.mesh = back_box
	back.position = pos + Vector3(0, 0.7, -0.2)
	back.material_override = _furniture_mat(WOOD_COLOR)
	root.add_child(back)

func _add_counter(root: Node3D, pos: Vector3, counter_width: float) -> void:
	var counter := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(counter_width, 1.0, 0.6)
	counter.mesh = box
	counter.position = pos + Vector3(0, 0.5, 0)
	counter.material_override = _furniture_mat(DARK_WOOD_COLOR)
	root.add_child(counter)

func _add_shelf(root: Node3D, pos: Vector3, shelf_length: float) -> void:
	for i in range(3):
		var shelf := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.3, 0.06, shelf_length)
		shelf.mesh = box
		shelf.position = pos + Vector3(0, 0.8 + float(i) * 0.6, 0)
		shelf.material_override = _furniture_mat(WOOD_COLOR)
		root.add_child(shelf)

func _add_box(root: Node3D, obj_name: String, pos: Vector3, size: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.name = obj_name
	mi.position = pos
	mi.material_override = _furniture_mat(color)
	root.add_child(mi)

# ─────────────────────────────────────────────
# Interior NPC population
# ─────────────────────────────────────────────

const NPC_ROLE_LABELS := {
	"Tavern": "Innkeeper", "Bar": "Bartender", "Restaurant": "Host",
	"Shop": "Shopkeeper", "GroceryStore": "Grocer", "Bakery": "Baker",
	"Blacksmith": "Blacksmith", "Carpenter": "Carpenter",
	"BookStore": "Bookseller", "JewelryStore": "Jeweler",
	"HerbShop": "Herbalist", "Pharmacy": "Pharmacist",
	"Bank": "Banker", "Library": "Librarian",
	"Church": "Priest", "Hospital": "Doctor", "Clinic": "Doctor",
	"School": "Teacher", "TownHall": "Clerk",
	"Inn": "Innkeeper", "Hotel": "Concierge",
}

func _populate_interior(root: Node3D, building: Dictionary, role: String, width: float, depth: float) -> void:
	var npc_label: String = NPC_ROLE_LABELS.get(role, "")
	if npc_label.is_empty():
		# Residential — spawn a resident
		npc_label = "Resident"

	var building_id: String = building.get("id", "")

	# Find the NPC assigned to this building from world data
	var npc_data: Dictionary = _find_npc_for_building(building_id)
	var npc_name: String = npc_data.get("name", npc_label)
	var char_id: String = npc_data.get("characterId", building_id + "_npc")

	# Create NPC body
	var npc := _create_interior_npc(char_id, npc_name, npc_label)
	# Position behind counter for commercial, center for residential
	var hw: float = width / 2.0 - 1.0
	var hd: float = depth / 2.0 - 1.0
	match role:
		"Tavern", "Bar", "Restaurant", "Shop", "GroceryStore", "Bakery", \
		"BookStore", "JewelryStore", "HerbShop", "Pharmacy", "Bank", "Inn", "Hotel":
			npc.position = Vector3(0, 0, -hd + 1.2)  # Behind counter
		"Church":
			npc.position = Vector3(0, 0, -hd + 1.0)  # At altar
		_:
			npc.position = Vector3(hw * 0.3, 0, hd * 0.3)  # Living area
	root.add_child(npc)

func _find_npc_for_building(building_id: String) -> Dictionary:
	# Search world data for NPCs assigned to this building
	if not GameManager.world_data.is_empty():
		var entities: Dictionary = GameManager.world_data.get("entities", {})
		var npcs: Array = entities.get("npcs", [])
		for npc in npcs:
			var schedule: Array = npc.get("schedule", [])
			for block in schedule:
				if block.get("buildingId", "") == building_id:
					return npc
			if npc.get("homeBuildingId", "") == building_id:
				return npc
			if npc.get("workBuildingId", "") == building_id:
				return npc
	return {}

func _create_interior_npc(char_id: String, npc_name: String, role_label: String) -> Node3D:
	var root := Node3D.new()
	root.name = "InteriorNPC_%s" % char_id

	# Deterministic appearance from character ID
	var seed_val: int = char_id.hash()
	var skin_idx: int = absi(seed_val) % 8
	var clothing_idx: int = absi(seed_val >> 4) % 12

	var skin_tones := [
		Color(0.96, 0.87, 0.78), Color(0.92, 0.80, 0.68),
		Color(0.85, 0.72, 0.58), Color(0.76, 0.60, 0.44),
		Color(0.65, 0.48, 0.35), Color(0.55, 0.38, 0.26),
		Color(0.45, 0.30, 0.20), Color(0.82, 0.67, 0.52),
	]
	var clothing_colors := [
		Color(0.40, 0.28, 0.18), Color(0.20, 0.38, 0.22),
		Color(0.15, 0.18, 0.35), Color(0.45, 0.15, 0.18),
		Color(0.65, 0.58, 0.42), Color(0.25, 0.25, 0.28),
		Color(0.70, 0.60, 0.45), Color(0.40, 0.22, 0.35),
		Color(0.55, 0.30, 0.18), Color(0.18, 0.40, 0.38),
		Color(0.88, 0.85, 0.78), Color(0.50, 0.28, 0.15),
	]

	var skin_color: Color = skin_tones[skin_idx]
	var cloth_color: Color = clothing_colors[clothing_idx]

	var skin_mat := StandardMaterial3D.new()
	skin_mat.albedo_color = skin_color
	var cloth_mat := StandardMaterial3D.new()
	cloth_mat.albedo_color = cloth_color

	# Head
	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.18
	head_mesh.height = 0.36
	head.mesh = head_mesh
	head.position.y = 1.65
	head.material_override = skin_mat
	root.add_child(head)

	# Torso
	var torso := MeshInstance3D.new()
	var torso_box := BoxMesh.new()
	torso_box.size = Vector3(0.40, 0.55, 0.22)
	torso.mesh = torso_box
	torso.position.y = 1.2
	torso.material_override = cloth_mat
	root.add_child(torso)

	# Arms
	for side in [-1.0, 1.0]:
		var arm := MeshInstance3D.new()
		var arm_cyl := CylinderMesh.new()
		arm_cyl.top_radius = 0.05
		arm_cyl.bottom_radius = 0.05
		arm_cyl.height = 0.55
		arm.mesh = arm_cyl
		arm.position = Vector3(side * 0.26, 1.1, 0)
		arm.material_override = cloth_mat
		root.add_child(arm)

	# Legs
	for side in [-1.0, 1.0]:
		var leg := MeshInstance3D.new()
		var leg_cyl := CylinderMesh.new()
		leg_cyl.top_radius = 0.07
		leg_cyl.bottom_radius = 0.07
		leg_cyl.height = 0.7
		leg.mesh = leg_cyl
		leg.position = Vector3(side * 0.1, 0.5, 0)
		leg.material_override = cloth_mat
		root.add_child(leg)

	# Name label (floating text above head)
	var label_3d := Label3D.new()
	label_3d.text = "%s\n%s" % [npc_name, role_label]
	label_3d.font_size = 48
	label_3d.position.y = 2.0
	label_3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label_3d.no_depth_test = true
	label_3d.modulate = Color(1, 1, 1, 0.9)
	root.add_child(label_3d)

	# Store metadata for interaction
	root.set_meta("character_id", char_id)
	root.set_meta("npc_name", npc_name)
	root.set_meta("npc_role", role_label)
	root.set_meta("is_interior_npc", true)

	return root

var _furniture_mat_cache := {}
func _furniture_mat(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if _furniture_mat_cache.has(key):
		return _furniture_mat_cache[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	_furniture_mat_cache[key] = mat
	return mat
