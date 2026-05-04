extends Node3D
## Spawns NPCs from world data with procedural body assembly.
## Add to the "world_generator" group so GameManager calls generate_from_data().
##
## Three-tier visual system:
## 1. Bundled glTF model from asset manifest (best quality)
## 2. Procedural body assembly with skin tones, clothing colors, role tinting
## 3. Capsule fallback (last resort)

var _npc_scene: PackedScene = null

# ─────────────────────────────────────────────
# Skin tones (8 variants)
# ─────────────────────────────────────────────
const SKIN_TONES := [
	Color(0.96, 0.87, 0.78),  # Fair
	Color(0.92, 0.80, 0.68),  # Light
	Color(0.85, 0.72, 0.58),  # Medium-light
	Color(0.76, 0.60, 0.44),  # Medium
	Color(0.65, 0.48, 0.35),  # Medium-dark
	Color(0.55, 0.38, 0.26),  # Dark
	Color(0.45, 0.30, 0.20),  # Deep
	Color(0.82, 0.67, 0.52),  # Olive
]

# ─────────────────────────────────────────────
# Clothing colors (12 muted naturals)
# ─────────────────────────────────────────────
const CLOTHING_COLORS := [
	Color(0.40, 0.28, 0.18),  # Brown
	Color(0.20, 0.38, 0.22),  # Forest Green
	Color(0.15, 0.18, 0.35),  # Navy
	Color(0.45, 0.15, 0.18),  # Burgundy
	Color(0.65, 0.58, 0.42),  # Khaki
	Color(0.25, 0.25, 0.28),  # Charcoal
	Color(0.70, 0.60, 0.45),  # Tan
	Color(0.40, 0.22, 0.35),  # Plum
	Color(0.55, 0.30, 0.18),  # Russet
	Color(0.18, 0.40, 0.38),  # Teal
	Color(0.88, 0.85, 0.78),  # Cream
	Color(0.50, 0.28, 0.15),  # Sienna
]

# ─────────────────────────────────────────────
# Hair colors (10 options)
# ─────────────────────────────────────────────
const HAIR_COLORS := [
	Color(0.08, 0.06, 0.05),  # Black
	Color(0.22, 0.15, 0.10),  # Dark Brown
	Color(0.38, 0.28, 0.18),  # Medium Brown
	Color(0.55, 0.42, 0.28),  # Light Brown
	Color(0.65, 0.55, 0.38),  # Dirty Blonde
	Color(0.82, 0.72, 0.50),  # Blonde
	Color(0.50, 0.22, 0.12),  # Auburn
	Color(0.60, 0.18, 0.10),  # Red
	Color(0.55, 0.55, 0.55),  # Grey
	Color(0.85, 0.85, 0.85),  # White
]

# ─────────────────────────────────────────────
# Role tinting
# ─────────────────────────────────────────────
const ROLE_TINTS := {
	"guard":      Color(0.85, 0.50, 0.45),
	"merchant":   Color(0.85, 0.75, 0.45),
	"quest_giver": Color(0.50, 0.65, 0.90),
	"civilian":   Color(0.70, 0.70, 0.70),
}

var _material_cache := {}

func _ready() -> void:
	add_to_group("world_generator")
	_load_npc_scene_from_manifest()

func _load_npc_scene_from_manifest() -> void:
	var manifest_path := "res://data/asset-manifest.json"
	if not FileAccess.file_exists(manifest_path):
		return
	var file := FileAccess.open(manifest_path, FileAccess.READ)
	if not file:
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return
	var manifest: Dictionary = json.data if json.data is Dictionary else {}
	var assets: Array = manifest.get("assets", [])
	for entry in assets:
		if entry.get("category", "") != "character":
			continue
		var role: String = entry.get("role", "")
		if role == "player_default" or role == "player_texture":
			continue
		var export_path: String = entry.get("exportPath", "")
		if export_path == "":
			continue
		var scene: PackedScene = load("res://" + export_path) as PackedScene
		if scene:
			_npc_scene = scene
			print("[Insimul] NPCSpawner: loaded NPC model — %s" % export_path)
			return

func generate_from_data(world_data: Dictionary) -> void:
	var entities: Dictionary = world_data.get("entities", {})
	var npcs: Array = entities.get("npcs", [])
	for npc_data in npcs:
		_spawn_npc(npc_data)
	print("[Insimul] NPCSpawner: spawned %d NPCs" % npcs.size())

func _spawn_npc(data: Dictionary) -> void:
	var npc := CharacterBody3D.new()
	var char_id: String = data.get("characterId", "unknown")

	if _npc_scene:
		var model := _npc_scene.instantiate()
		npc.add_child(model)
	else:
		# Procedural body assembly
		var body := _create_procedural_body(char_id, data)
		npc.add_child(body)

	var col := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.8
	col.shape = capsule
	col.position.y = 0.9
	npc.add_child(col)

	var nav := NavigationAgent3D.new()
	npc.add_child(nav)

	var pos: Dictionary = data.get("homePosition", {})
	npc.name = "NPC_%s" % char_id
	add_child(npc)
	npc.global_position = Vector3(pos.get("x", 0), pos.get("y", 0), pos.get("z", 0))

	# Attach animation controller
	var anim_ctrl_script := load("res://scripts/characters/character_animation_controller.gd")
	if anim_ctrl_script:
		var anim_ctrl := Node.new()
		anim_ctrl.set_script(anim_ctrl_script)
		anim_ctrl.name = "AnimationController"
		npc.add_child(anim_ctrl)

	var script := load("res://scripts/characters/npc_controller.gd")
	if script:
		npc.set_script(script)
		npc.init_from_data(data)

# ─────────────────────────────────────────────
# Procedural body assembly
# ─────────────────────────────────────────────

func _create_procedural_body(char_id: String, data: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "ProceduralBody"

	# Deterministic appearance from character ID hash
	var seed_val: int = char_id.hash()
	var skin_idx: int = absi(seed_val) % SKIN_TONES.size()
	var clothing_idx: int = absi(seed_val >> 4) % CLOTHING_COLORS.size()
	var secondary_idx: int = (clothing_idx + 2 + absi(seed_val >> 8) % 4) % CLOTHING_COLORS.size()
	var hair_idx: int = absi(seed_val >> 12) % HAIR_COLORS.size()

	var skin_color: Color = SKIN_TONES[skin_idx]
	var clothing_color: Color = CLOTHING_COLORS[clothing_idx]
	var secondary_color: Color = CLOTHING_COLORS[secondary_idx]
	var hair_color: Color = HAIR_COLORS[hair_idx]

	# Apply role tinting to clothing
	var role: String = data.get("role", "civilian")
	if ROLE_TINTS.has(role):
		var tint: Color = ROLE_TINTS[role]
		var blend: float = 0.15
		clothing_color = clothing_color.lerp(tint, blend)

	# Body type variation (deterministic)
	var body_type: int = absi(seed_val >> 16) % 4  # 0=average, 1=athletic, 2=heavy, 3=slim
	var width_mult: float = [1.0, 1.02, 1.15, 0.92][body_type]
	var height_mult: float = [1.0, 1.04, 0.95, 1.06][body_type]

	var skin_mat := _get_cached_mat("skin_%d" % skin_idx, skin_color)
	var cloth_mat := _get_cached_mat("cloth_%d_%d" % [clothing_idx, seed_val % 100], clothing_color)
	var secondary_mat := _get_cached_mat("cloth2_%d_%d" % [secondary_idx, seed_val % 100], secondary_color)
	var hair_mat := _get_cached_mat("hair_%d" % hair_idx, hair_color)

	# --- Head ---
	var head := _make_sphere(0.36, 6)
	head.position.y = 1.65 * height_mult
	head.material_override = skin_mat
	root.add_child(head)

	# --- Hair (sphere on top of head) ---
	var has_hair: bool = (absi(seed_val >> 20) % 6) > 0  # 5/6 chance of hair
	if has_hair:
		var hair := _make_sphere(0.28, 5)
		hair.position.y = 1.78 * height_mult
		hair.scale = Vector3(1.1, 0.6, 1.1)
		hair.material_override = hair_mat
		root.add_child(hair)

	# --- Torso ---
	var torso_w: float = 0.40 * width_mult
	var torso_h: float = 0.55 * height_mult
	var torso := MeshInstance3D.new()
	var torso_box := BoxMesh.new()
	torso_box.size = Vector3(torso_w, torso_h, 0.22 * width_mult)
	torso.mesh = torso_box
	torso.position.y = 1.2 * height_mult
	torso.material_override = cloth_mat
	root.add_child(torso)

	# --- Arms ---
	var arm_offset_x: float = torso_w / 2.0 + 0.06
	for side in [-1.0, 1.0]:
		# Upper arm (clothing)
		var upper_arm := _make_cylinder(0.06, 0.06, 0.30 * height_mult, 6)
		upper_arm.position = Vector3(side * arm_offset_x, 1.25 * height_mult, 0)
		upper_arm.material_override = cloth_mat
		root.add_child(upper_arm)

		# Lower arm (skin)
		var lower_arm := _make_cylinder(0.054, 0.054, 0.28 * height_mult, 6)
		lower_arm.position = Vector3(side * arm_offset_x, 0.92 * height_mult, 0)
		lower_arm.material_override = skin_mat
		root.add_child(lower_arm)

	# --- Legs ---
	var leg_offset_x: float = torso_w * 0.25
	for side in [-1.0, 1.0]:
		# Upper leg (secondary clothing)
		var upper_leg := _make_cylinder(0.08, 0.08, 0.35 * height_mult, 6)
		upper_leg.position = Vector3(side * leg_offset_x, 0.72 * height_mult, 0)
		upper_leg.material_override = secondary_mat
		root.add_child(upper_leg)

		# Lower leg (secondary clothing)
		var lower_leg := _make_cylinder(0.072, 0.072, 0.35 * height_mult, 6)
		lower_leg.position = Vector3(side * leg_offset_x, 0.35 * height_mult, 0)
		lower_leg.material_override = secondary_mat
		root.add_child(lower_leg)

	return root

# ─────────────────────────────────────────────
# Mesh helpers
# ─────────────────────────────────────────────

func _make_cylinder(top_r: float, bottom_r: float, height: float, segments: int) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = top_r
	m.bottom_radius = bottom_r
	m.height = height
	m.radial_segments = segments
	mi.mesh = m
	return mi

func _make_sphere(diameter: float, segments: int) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := SphereMesh.new()
	m.radius = diameter / 2.0
	m.height = diameter
	m.radial_segments = segments * 2
	m.rings = segments
	mi.mesh = m
	return mi

func _get_cached_mat(key: String, color: Color) -> StandardMaterial3D:
	if _material_cache.has(key):
		return _material_cache[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	_material_cache[key] = mat
	return mat
