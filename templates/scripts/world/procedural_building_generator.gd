extends Node3D
class_name ProceduralBuildingGenerator

@export var base_color := Color({{BASE_COLOR_R}}, {{BASE_COLOR_G}}, {{BASE_COLOR_B}})
@export var roof_color := Color({{ROOF_COLOR_R}}, {{ROOF_COLOR_G}}, {{ROOF_COLOR_B}})
@export var lod_cull_distance := 150.0

var _material_cache := {}

## Runtime procedural configuration set via set_procedural_config().
var _procedural_config: Dictionary = {}

## Role-based model prototypes registered via register_role_model.
var _role_model_prototypes: Dictionary = {}

## Pre-computed scale hints per role (converts native model units to meters).
var _role_scale_hints: Dictionary = {}

## Optional wall texture override for procedural buildings.
var _wall_texture: Texture2D = null

## Optional roof texture override for procedural buildings.
var _roof_texture: Texture2D = null

## Per-preset textures keyed by asset ID.
var _preset_textures: Dictionary = {}

## Style presets matching the Babylon.js source engine.
const STYLE_PRESETS := {
	"medieval_wood": {
		"name": "Medieval Wood",
		"base_color": Color(0.55, 0.35, 0.2),
		"roof_color": Color(0.3, 0.2, 0.15),
		"window_color": Color(0.9, 0.9, 0.7),
		"door_color": Color(0.4, 0.25, 0.15),
		"material_type": "wood",
		"architecture_style": "medieval",
		"roof_style": "gable",
		"has_ironwork_balcony": false,
		"has_porch": false,
		"porch_depth": 3.0,
		"porch_steps": 3,
		"has_shutters": false,
		"shutter_color": Color(0.3, 0.2, 0.1)
	},
	"medieval_stone": {
		"name": "Medieval Stone",
		"base_color": Color(0.6, 0.6, 0.55),
		"roof_color": Color(0.35, 0.2, 0.15),
		"window_color": Color(0.7, 0.8, 0.9),
		"door_color": Color(0.3, 0.2, 0.1),
		"material_type": "stone",
		"architecture_style": "medieval",
		"roof_style": "gable",
		"has_ironwork_balcony": false,
		"has_porch": false,
		"porch_depth": 3.0,
		"porch_steps": 3,
		"has_shutters": false,
		"shutter_color": Color(0.3, 0.3, 0.3)
	},
	"modern_concrete": {
		"name": "Modern Concrete",
		"base_color": Color(0.7, 0.7, 0.7),
		"roof_color": Color(0.3, 0.3, 0.3),
		"window_color": Color(0.6, 0.7, 0.8),
		"door_color": Color(0.5, 0.5, 0.5),
		"material_type": "brick",
		"architecture_style": "modern",
		"roof_style": "flat",
		"has_ironwork_balcony": false,
		"has_porch": false,
		"porch_depth": 3.0,
		"porch_steps": 3,
		"has_shutters": false,
		"shutter_color": Color(0.5, 0.5, 0.5)
	},
	"futuristic_metal": {
		"name": "Futuristic Metal",
		"base_color": Color(0.6, 0.65, 0.7),
		"roof_color": Color(0.2, 0.25, 0.3),
		"window_color": Color(0.5, 0.7, 0.9),
		"door_color": Color(0.3, 0.4, 0.5),
		"material_type": "metal",
		"architecture_style": "futuristic",
		"roof_style": "flat",
		"has_ironwork_balcony": false,
		"has_porch": false,
		"porch_depth": 3.0,
		"porch_steps": 3,
		"has_shutters": false,
		"shutter_color": Color(0.3, 0.4, 0.5)
	},
	"rustic_cottage": {
		"name": "Rustic Cottage",
		"base_color": Color(0.7, 0.5, 0.3),
		"roof_color": Color(0.5, 0.35, 0.2),
		"window_color": Color(0.8, 0.85, 0.7),
		"door_color": Color(0.5, 0.3, 0.2),
		"material_type": "wood",
		"architecture_style": "rustic",
		"roof_style": "gable",
		"has_ironwork_balcony": false,
		"has_porch": true,
		"porch_depth": 3.0,
		"porch_steps": 3,
		"has_shutters": true,
		"shutter_color": Color(0.3, 0.4, 0.25)
	},
	"colonial_stucco": {
		"name": "Colonial Stucco",
		"base_color": Color(0.9, 0.85, 0.75),
		"roof_color": Color(0.35, 0.25, 0.2),
		"window_color": Color(0.7, 0.8, 0.9),
		"door_color": Color(0.3, 0.2, 0.1),
		"material_type": "stucco",
		"architecture_style": "colonial",
		"roof_style": "side_gable",
		"has_ironwork_balcony": false,
		"has_porch": true,
		"porch_depth": 3.5,
		"porch_steps": 4,
		"has_shutters": true,
		"shutter_color": Color(0.15, 0.3, 0.15)
	},
	"creole_townhouse": {
		"name": "Creole Townhouse",
		"base_color": Color(0.85, 0.8, 0.65),
		"roof_color": Color(0.3, 0.3, 0.3),
		"window_color": Color(0.7, 0.75, 0.85),
		"door_color": Color(0.25, 0.15, 0.1),
		"material_type": "stucco",
		"architecture_style": "creole",
		"roof_style": "hipped_dormers",
		"has_ironwork_balcony": true,
		"has_porch": false,
		"porch_depth": 3.0,
		"porch_steps": 3,
		"has_shutters": true,
		"shutter_color": Color(0.15, 0.35, 0.2)
	}
}

## Zone-based scale multipliers for building dimensions.
## Commercial buildings are taller and wider; residential is the baseline.
const ZONE_SCALE := {
	"commercial":  { "floors": 1.3, "width": 1.15, "depth": 1.1 },
	"residential": { "floors": 1.0, "width": 1.0,  "depth": 1.0 }
}

## Fallback defaults when type is unknown.
const DEFAULT_BUILDING_DIMENSIONS := { "floors": 2, "width": 10, "depth": 10, "has_chimney": false, "has_balcony": false, "has_porch": false }

## Default building dimensions indexed by business type.
## Matches shared/game-engine/building-defaults.ts.
const BUILDING_TYPES := {
	# ── Commercial: Food & Drink ──
	"Bakery":           { "floors": 2, "width": 12, "depth": 10, "has_chimney": true,  "has_balcony": false, "has_porch": false },
	"Restaurant":       { "floors": 2, "width": 15, "depth": 12, "has_chimney": false, "has_balcony": false, "has_porch": false },
	"Bar":              { "floors": 2, "width": 12, "depth": 10, "has_chimney": false, "has_balcony": false, "has_porch": false },
	"Brewery":          { "floors": 2, "width": 14, "depth": 12, "has_chimney": true,  "has_balcony": false, "has_porch": false },

	# ── Commercial: Retail ──
	"Shop":             { "floors": 2, "width": 10, "depth": 8,  "has_chimney": false, "has_balcony": false, "has_porch": false },
	"GroceryStore":     { "floors": 2, "width": 14, "depth": 12, "has_chimney": false, "has_balcony": false, "has_porch": false },
	"JewelryStore":     { "floors": 2, "width": 10, "depth": 8,  "has_chimney": false, "has_balcony": false, "has_porch": false },
	"BookStore":        { "floors": 2, "width": 10, "depth": 10, "has_chimney": false, "has_balcony": false, "has_porch": false },
	"PawnShop":         { "floors": 2, "width": 10, "depth": 8,  "has_chimney": false, "has_balcony": false, "has_porch": false },
	"HerbShop":         { "floors": 1, "width": 8,  "depth": 8,  "has_chimney": false, "has_balcony": false, "has_porch": false },

	# ── Commercial: Services ──
	"Bank":             { "floors": 2, "width": 14, "depth": 12, "has_chimney": false, "has_balcony": false, "has_porch": false },
	"Hotel":            { "floors": 3, "width": 16, "depth": 14, "has_chimney": false, "has_balcony": true,  "has_porch": false },
	"Barbershop":       { "floors": 1, "width": 8,  "depth": 8,  "has_chimney": false, "has_balcony": false, "has_porch": false },
	"Tailor":           { "floors": 2, "width": 10, "depth": 8,  "has_chimney": false, "has_balcony": false, "has_porch": false },
	"Bathhouse":        { "floors": 1, "width": 14, "depth": 12, "has_chimney": false, "has_balcony": false, "has_porch": false },
	"DentalOffice":     { "floors": 2, "width": 10, "depth": 10, "has_chimney": false, "has_balcony": false, "has_porch": false },
	"OptometryOffice":  { "floors": 2, "width": 10, "depth": 10, "has_chimney": false, "has_balcony": false, "has_porch": false },
	"Pharmacy":         { "floors": 2, "width": 10, "depth": 10, "has_chimney": false, "has_balcony": false, "has_porch": false },
	"LawFirm":          { "floors": 3, "width": 12, "depth": 10, "has_chimney": false, "has_balcony": false, "has_porch": false },
	"InsuranceOffice":  { "floors": 2, "width": 10, "depth": 10, "has_chimney": false, "has_balcony": false, "has_porch": false },
	"RealEstateOffice": { "floors": 2, "width": 10, "depth": 10, "has_chimney": false, "has_balcony": false, "has_porch": false },
	"TattoParlor":      { "floors": 1, "width": 8,  "depth": 8,  "has_chimney": false, "has_balcony": false, "has_porch": false },

	# ── Civic ──
	"Church":           { "floors": 1, "width": 16, "depth": 24, "has_chimney": false, "has_balcony": false, "has_porch": false },
	"TownHall":         { "floors": 2, "width": 18, "depth": 16, "has_chimney": false, "has_balcony": false, "has_porch": false },
	"School":           { "floors": 2, "width": 18, "depth": 16, "has_chimney": false, "has_balcony": false, "has_porch": false },
	"University":       { "floors": 3, "width": 20, "depth": 18, "has_chimney": false, "has_balcony": false, "has_porch": false },
	"Hospital":         { "floors": 3, "width": 20, "depth": 18, "has_chimney": false, "has_balcony": false, "has_porch": false },
	"PoliceStation":    { "floors": 2, "width": 14, "depth": 12, "has_chimney": false, "has_balcony": false, "has_porch": false },
	"FireStation":      { "floors": 2, "width": 14, "depth": 14, "has_chimney": false, "has_balcony": false, "has_porch": false },
	"Daycare":          { "floors": 1, "width": 12, "depth": 10, "has_chimney": false, "has_balcony": false, "has_porch": false },
	"Mortuary":         { "floors": 1, "width": 12, "depth": 10, "has_chimney": false, "has_balcony": false, "has_porch": false },

	# ── Industrial ──
	"Factory":          { "floors": 2, "width": 20, "depth": 16, "has_chimney": true,  "has_balcony": false, "has_porch": false },
	"Farm":             { "floors": 1, "width": 14, "depth": 12, "has_chimney": false, "has_balcony": false, "has_porch": false },
	"Warehouse":        { "floors": 1, "width": 18, "depth": 14, "has_chimney": false, "has_balcony": false, "has_porch": false },
	"Blacksmith":       { "floors": 1, "width": 12, "depth": 10, "has_chimney": true,  "has_balcony": false, "has_porch": false },
	"Carpenter":        { "floors": 1, "width": 12, "depth": 10, "has_chimney": false, "has_balcony": false, "has_porch": false },
	"Butcher":          { "floors": 1, "width": 10, "depth": 8,  "has_chimney": false, "has_balcony": false, "has_porch": false },

	# ── Maritime ──
	"Harbor":           { "floors": 1, "width": 16, "depth": 12, "has_chimney": false, "has_balcony": false, "has_porch": false },
	"Boatyard":         { "floors": 1, "width": 18, "depth": 14, "has_chimney": false, "has_balcony": false, "has_porch": false },
	"FishMarket":       { "floors": 1, "width": 14, "depth": 10, "has_chimney": false, "has_balcony": false, "has_porch": false },
	"CustomsHouse":     { "floors": 2, "width": 14, "depth": 12, "has_chimney": false, "has_balcony": false, "has_porch": false },
	"Lighthouse":       { "floors": 3, "width": 8,  "depth": 8,  "has_chimney": false, "has_balcony": false, "has_porch": false },

	# ── Residential ──
	"house":            { "floors": 2, "width": 10, "depth": 10, "has_chimney": true,  "has_balcony": false, "has_porch": false },
	"apartment":        { "floors": 3, "width": 14, "depth": 12, "has_chimney": false, "has_balcony": false, "has_porch": false },
	"mansion":          { "floors": 3, "width": 20, "depth": 18, "has_chimney": true,  "has_balcony": true,  "has_porch": false },
	"cottage":          { "floors": 1, "width": 8,  "depth": 8,  "has_chimney": true,  "has_balcony": false, "has_porch": false },
	"townhouse":        { "floors": 2, "width": 8,  "depth": 12, "has_chimney": false, "has_balcony": false, "has_porch": false },
	"mobile_home":      { "floors": 1, "width": 6,  "depth": 10, "has_chimney": false, "has_balcony": false, "has_porch": false },

	# ── Other/legacy ──
	"Tavern":           { "floors": 2, "width": 14, "depth": 14, "has_chimney": false, "has_balcony": true,  "has_porch": false },
	"Inn":              { "floors": 3, "width": 16, "depth": 14, "has_chimney": false, "has_balcony": true,  "has_porch": false },
	"Market":           { "floors": 1, "width": 20, "depth": 15, "has_chimney": false, "has_balcony": false, "has_porch": false },
	"Theater":          { "floors": 2, "width": 18, "depth": 20, "has_chimney": false, "has_balcony": false, "has_porch": false },
	"Library":          { "floors": 3, "width": 16, "depth": 14, "has_chimney": false, "has_balcony": false, "has_porch": false },
	"ApartmentComplex": { "floors": 5, "width": 18, "depth": 16, "has_chimney": false, "has_balcony": true,  "has_porch": false },
	"Windmill":         { "floors": 3, "width": 10, "depth": 10, "has_chimney": false, "has_balcony": false, "has_porch": false },
	"Watermill":        { "floors": 2, "width": 14, "depth": 12, "has_chimney": false, "has_balcony": false, "has_porch": false },
	"Lumbermill":       { "floors": 1, "width": 16, "depth": 12, "has_chimney": true,  "has_balcony": false, "has_porch": false },
	"Barracks":         { "floors": 2, "width": 18, "depth": 14, "has_chimney": false, "has_balcony": false, "has_porch": false },
	"Mine":             { "floors": 1, "width": 12, "depth": 10, "has_chimney": false, "has_balcony": false, "has_porch": false },
	"Clinic":           { "floors": 2, "width": 12, "depth": 10, "has_chimney": false, "has_balcony": false, "has_porch": false },
	"Stables":          { "floors": 1, "width": 14, "depth": 12, "has_chimney": false, "has_balcony": false, "has_porch": false },

	# ── Legacy residence keys ──
	"residence_small":   { "floors": 1, "width": 8,  "depth": 8,  "has_chimney": false, "has_balcony": false, "has_porch": false },
	"residence_medium":  { "floors": 2, "width": 10, "depth": 10, "has_chimney": true,  "has_balcony": false, "has_porch": false },
	"residence_large":   { "floors": 2, "width": 14, "depth": 12, "has_chimney": true,  "has_balcony": true,  "has_porch": false },
	"residence_mansion": { "floors": 3, "width": 20, "depth": 18, "has_chimney": true,  "has_balcony": true,  "has_porch": false }
}


## Register a prefab scene for a building role. Matching roles instance this
## scene instead of generating procedural geometry.
## scale_hint is a pre-computed factor that converts the model's native units
## to real-world meters at its intended size. Pass 0 to use floor-based estimation.
func register_role_model(role: String, scene: PackedScene, scale_hint: float = 0.0) -> void:
	if role.is_empty() or scene == null:
		return
	_role_model_prototypes[role] = scene
	if scale_hint > 0.0:
		_role_scale_hints[role] = scale_hint
	print("[Insimul] Registered role model: %s (scale_hint=%.4f)" % [role, scale_hint])


## Override wall texture for procedural buildings.
func set_wall_texture(texture: Texture2D) -> void:
	_wall_texture = texture


## Override roof texture for procedural buildings.
func set_roof_texture(texture: Texture2D) -> void:
	_roof_texture = texture


## Register a texture by asset ID for use by style presets.
func register_preset_texture(asset_id: String, texture: Texture2D) -> void:
	_preset_textures[asset_id] = texture


## Return an appropriate style preset key for the given world type and terrain.
static func get_style_for_world(world_type: String, terrain: String) -> Dictionary:
	var wt := world_type.to_lower()
	var tr := terrain.to_lower()

	if wt.contains("creole"):
		return STYLE_PRESETS["creole_townhouse"]
	if wt.contains("colonial"):
		return STYLE_PRESETS["colonial_stucco"]
	if wt.contains("medieval") or wt.contains("fantasy"):
		if tr.contains("forest") or tr.contains("rural"):
			return STYLE_PRESETS["medieval_wood"]
		return STYLE_PRESETS["medieval_stone"]
	if wt.contains("cyberpunk") or wt.contains("sci-fi") or wt.contains("futuristic"):
		return STYLE_PRESETS["futuristic_metal"]
	if wt.contains("modern"):
		return STYLE_PRESETS["modern_concrete"]
	if tr.contains("rural") or tr.contains("village"):
		return STYLE_PRESETS["rustic_cottage"]

	return STYLE_PRESETS["medieval_wood"]


func _get_shared_material(key: String, color: Color, material_type: String = "") -> StandardMaterial3D:
	var cache_key := key if material_type.is_empty() else "%s_%s" % [key, material_type]
	if _material_cache.has(cache_key):
		return _material_cache[cache_key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	match material_type:
		"stucco":
			mat.roughness = 0.95
			mat.metallic = 0.0
			mat.metallic_specular = 0.1
		"metal":
			mat.roughness = 0.3
			mat.metallic = 0.8
			mat.metallic_specular = 0.7
		"stone":
			mat.roughness = 0.85
			mat.metallic = 0.0
			mat.metallic_specular = 0.2
		"wood":
			mat.roughness = 0.75
			mat.metallic = 0.0
			mat.metallic_specular = 0.15
	_material_cache[cache_key] = mat
	return mat


func generate_building(pos: Vector3, rotation_y: float, floors: int,
		width: float, depth: float, role: String,
		foundation: Dictionary = {}) -> void:

	# Create terrain-adaptive foundation: raise building to sit on highest corner
	var fnd_type: String = foundation.get("type", "flat")
	var fnd_height: float = foundation.get("foundation_height", 0.0)
	if fnd_type != "flat" and fnd_height > 0.0:
		var base_elev: float = foundation.get("base_elevation", 0.0)
		var top_y := base_elev + fnd_height
		pos.y = top_y
		print("[Insimul] Foundation type=%s height=%.1f, raised to Y=%.1f" % [fnd_type, fnd_height, top_y])

	# Check for a registered role model first.
	# Uses full scene instantiation (not MultiMesh) for RTT/minimap compatibility.
	if _role_model_prototypes.has(role):
		var scene: PackedScene = _role_model_prototypes[role]
		if scene != null:
			var instance := scene.instantiate()
			instance.name = "Building_%s" % role
			instance.position = pos
			instance.rotation.y = rotation_y
			# Apply stored scale_hint if available; converts native model units to meters.
			if _role_scale_hints.has(role):
				var s: float = _role_scale_hints[role]
				instance.scale = Vector3(s, s, s)
			add_child(instance)
			print("[Insimul] Placed role model for %s" % role)
			return

	# Procedural fallback
	var floor_height := 3.0
	var total_height := floors * floor_height

	# Resolve style for material and architecture info
	var style := get_style_for_world("", "")
	if _procedural_config.has("style"):
		style = _procedural_config["style"]
	style = apply_subtype_override(style, role)
	var arch_style: String = style.get("architecture_style", "medieval")
	var mat_type: String = style.get("material_type", "")
	var roof_style_str: String = style.get("roof_style", "")
	var has_porch: bool = style.get("has_porch", false)
	var porch_depth_val: float = style.get("porch_depth", 3.0)
	var porch_steps_val: int = style.get("porch_steps", 3)
	var has_shutters: bool = style.get("has_shutters", false)
	var shutter_color: Color = style.get("shutter_color", Color(0.3, 0.3, 0.3))
	var has_ironwork_balcony: bool = style.get("has_ironwork_balcony", false)

	# Default roof_style from architecture_style if not explicit
	if roof_style_str.is_empty():
		match arch_style:
			"colonial", "creole":
				roof_style_str = "side_gable"
			"modern", "futuristic":
				roof_style_str = "flat"
			_:
				roof_style_str = "gable"

	# Calculate porch elevation offset
	var porch_elevation: float = 0.0
	if has_porch:
		var step_height := 0.2
		porch_elevation = porch_steps_val * step_height

	# Base building
	var building := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(width, total_height, depth)
	building.mesh = box
	building.name = "Building_%s" % role
	building.position = pos + Vector3.UP * (total_height / 2.0 + porch_elevation)
	building.rotation.y = rotation_y

	# Resolve wall texture: prefer per-preset texture, fall back to global, then solid color
	var resolved_wall_tex: Texture2D = null
	var wall_tex_id: String = style.get("wallTextureId", "")
	if wall_tex_id != "" and _preset_textures.has(wall_tex_id):
		resolved_wall_tex = _preset_textures[wall_tex_id]
	if resolved_wall_tex == null:
		resolved_wall_tex = _wall_texture

	# Alternate between textured and solid-color buildings using building ID hash.
	# ~2/3 get the texture, ~1/3 get solid color for visual variety.
	var use_texture := resolved_wall_tex != null
	var building_id: String = role  # Use role as proxy for building ID in procedural context
	if resolved_wall_tex != null and building_id != "":
		var id_hash := building_id.hash()
		use_texture = (absi(id_hash) % 3) != 0  # ~2/3 textured, ~1/3 solid color

	var wall_tex_key := ("global" if wall_tex_id == "" else wall_tex_id) if use_texture else "notex"
	if use_texture and resolved_wall_tex != null:
		# Tint base color toward white by 0.7 lerp when textured
		var tinted_color := base_color.lerp(Color.WHITE, 0.7)
		var wall_mat := _get_shared_material("wall_%s_%s_%s" % [style.get("name", ""), mat_type, wall_tex_key], tinted_color, mat_type)
		wall_mat.albedo_texture = resolved_wall_tex
		building.material_override = wall_mat
	else:
		building.material_override = _get_shared_material("wall", base_color, mat_type)
	add_child(building)

	# Collision
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box.size
	col.shape = shape
	body.add_child(col)
	building.add_child(body)

	# Porch
	if has_porch:
		var has_balcony: bool = style.get("has_ironwork_balcony", false) or style.get("has_balcony", false)
		var porch_spec := {
			"width": width,
			"depth": porch_depth_val,
			"elevation": porch_elevation,
			"steps": porch_steps_val,
			"total_height": total_height,
			"front_z": depth / 2.0,
			"mat_type": mat_type,
			"porch_texture_id": style.get("porch_texture_id", ""),
			"floors": floors,
			"has_balcony": has_balcony
		}
		_create_porch(building, porch_spec)

		# Porch setback: push all geometry back in local -Z so the porch + stairs
		# don't cover the sidewalk. Shift by 3/4 of the total porch extension.
		var step_depth_val := 0.4
		var porch_extension := porch_depth_val + porch_steps_val * step_depth_val
		var setback := porch_extension * 0.75
		for child in building.get_children():
			child.position.z -= setback
		print("[Insimul] Porch setback=%.2f applied" % setback)

	# Determine style-aware roof height based on roof_style
	var peaked_roof_height := 3.0
	var actual_roof_height: float
	match roof_style_str:
		"flat":
			actual_roof_height = 0.5
		"hip", "hipped_dormers", "gable", "side_gable":
			actual_roof_height = peaked_roof_height
		_:
			actual_roof_height = peaked_roof_height

	# Roof — proper vertex geometry for gable/hip, box for flat
	var roof := MeshInstance3D.new()
	roof.name = "Roof"
	var overhang := 0.6
	var rw: float = width + overhang * 2.0
	var rd: float = depth + overhang * 2.0
	match roof_style_str:
		"gable", "side_gable":
			roof.mesh = _create_gable_roof(rw, rd, actual_roof_height, roof_style_str == "side_gable")
		"hip", "hipped_dormers":
			roof.mesh = _create_hip_roof(rw, rd, actual_roof_height)
		_:  # flat
			var flat_box := BoxMesh.new()
			flat_box.size = Vector3(rw, 0.5, rd)
			roof.mesh = flat_box
	roof.position = Vector3(0, total_height / 2.0, 0)

	# Resolve roof texture and material
	var resolved_roof_tex: Texture2D = null
	var roof_tex_id: String = style.get("roofTextureId", "")
	if roof_tex_id != "" and _preset_textures.has(roof_tex_id):
		resolved_roof_tex = _preset_textures[roof_tex_id]
	if resolved_roof_tex == null:
		resolved_roof_tex = _roof_texture

	var roof_tex_key := roof_tex_id if roof_tex_id != "" else ("global" if resolved_roof_tex != null else "notex")
	if resolved_roof_tex != null:
		var roof_mat := _get_shared_material("roof_%s_%s" % [style.get("name", ""), roof_tex_key], Color.WHITE)
		roof_mat.albedo_texture = resolved_roof_tex
		roof_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		roof.material_override = roof_mat
	else:
		var roof_solid_mat := _get_shared_material("roof", roof_color)
		roof_solid_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		roof.material_override = roof_solid_mat
	building.add_child(roof)

	# Windows with optional shutters
	_add_windows(building, width, depth, floors, total_height, style)

	# Balcony — ironwork style on every upper floor if enabled
	if has_ironwork_balcony and floors > 1:
		_add_ironwork_balconies(building, width, depth, floors, total_height, style)

	# Door with frame, panel, and handle
	_add_door(building, width, depth, floors, total_height)

	# Chimney (if building type specifies one)
	var type_defaults: Dictionary = BUILDING_TYPE_DEFAULTS.get(role, DEFAULT_BUILDING_DIMENSIONS)
	var has_chimney: bool = type_defaults.get("has_chimney", false)
	if has_chimney:
		_add_chimney(building, width, depth, total_height)

	# LOD: add VisibilityNotifier to cull at distance
	var notifier := VisibleOnScreenNotifier3D.new()
	notifier.aabb = AABB(Vector3(-width / 2, 0, -depth / 2), Vector3(width, total_height + 1.0, depth))
	building.add_child(notifier)

	# Filter out child MeshInstance3D nodes with no vertices (e.g. empty placeholder
	# nodes). Mirrors the Babylon.js validMeshes filter that skips getTotalVertices() == 0.
	for child in building.get_children():
		if child is MeshInstance3D:
			var vertex_count := 0
			if child.mesh != null:
				for si in range(child.mesh.get_surface_count()):
					var arrays = child.mesh.surface_get_arrays(si)
					if arrays.size() > 0 and arrays[Mesh.ARRAY_VERTEX] != null:
						vertex_count += arrays[Mesh.ARRAY_VERTEX].size()
			if vertex_count == 0:
				child.queue_free()

	# Propagate LOD cull distance to all child meshes so unmerged children
	# (e.g. door, roof) don't remain visible when the parent building is LOD-hidden.
	for child in building.get_children():
		if child is MeshInstance3D and child.visibility_range_end <= 0.0:
			child.visibility_range_end = lod_cull_distance

	# Merge child meshes by material to reduce draw calls.
	# Groups children sharing the same material and merges them into single meshes.
	_merge_building_meshes(building)

	# Freeze transforms — buildings are static geometry
	building.set_notify_transform(false)


## Add door with frame, panel, and handle to a building.
func _add_door(building: MeshInstance3D, width: float, depth: float,
		floors: int, total_height: float) -> void:
	var door_width := 1.2
	var door_height := 2.2
	var door_depth := 0.15
	var frame_thickness := 0.12
	var frame_depth := 0.18
	var front_z := depth / 2.0
	# Ground level in building's local space (building is centered vertically)
	var ground_y := -total_height / 2.0

	# Door frame material (darker than door color)
	var style := get_style_for_world("", "")
	var frame_color: Color = style.get("door_color", Color(0.4, 0.25, 0.15)) * 0.5
	var frame_mat := _get_shared_material("doorframe", frame_color)

	# Left frame post
	var left_post := MeshInstance3D.new()
	var left_box := BoxMesh.new()
	left_box.size = Vector3(frame_thickness, door_height + frame_thickness, frame_depth)
	left_post.mesh = left_box
	left_post.name = "DoorFrame_L"
	left_post.position = Vector3(-door_width / 2.0 - frame_thickness / 2.0,
		ground_y + (door_height + frame_thickness) / 2.0, front_z + frame_depth / 2.0)
	left_post.material_override = frame_mat
	building.add_child(left_post)

	# Right frame post
	var right_post := MeshInstance3D.new()
	var right_box := BoxMesh.new()
	right_box.size = Vector3(frame_thickness, door_height + frame_thickness, frame_depth)
	right_post.mesh = right_box
	right_post.name = "DoorFrame_R"
	right_post.position = Vector3(door_width / 2.0 + frame_thickness / 2.0,
		ground_y + (door_height + frame_thickness) / 2.0, front_z + frame_depth / 2.0)
	right_post.material_override = frame_mat
	building.add_child(right_post)

	# Top frame (lintel)
	var lintel := MeshInstance3D.new()
	var lintel_box := BoxMesh.new()
	lintel_box.size = Vector3(door_width + frame_thickness * 2.0, frame_thickness, frame_depth)
	lintel.mesh = lintel_box
	lintel.name = "DoorFrame_T"
	lintel.position = Vector3(0, ground_y + door_height + frame_thickness / 2.0,
		front_z + frame_depth / 2.0)
	lintel.material_override = frame_mat
	building.add_child(lintel)

	# Door panel
	var door_color: Color = style.get("door_color", Color(0.4, 0.25, 0.15))
	var door_mat := _get_shared_material("door", door_color)
	var door := MeshInstance3D.new()
	var door_box := BoxMesh.new()
	door_box.size = Vector3(door_width, door_height, door_depth)
	door.mesh = door_box
	door.name = "Door"
	door.position = Vector3(0, ground_y + door_height / 2.0, front_z + door_depth / 2.0)
	door.material_override = door_mat
	building.add_child(door)

	# Door handle (metallic brass)
	var handle_mat := _get_shared_material("door_handle", Color(0.7, 0.65, 0.4))
	var handle := MeshInstance3D.new()
	var handle_box := BoxMesh.new()
	handle_box.size = Vector3(0.06, 0.2, 0.06)
	handle.mesh = handle_box
	handle.name = "DoorHandle"
	handle.position = Vector3(door_width / 2.0 - 0.2, ground_y + 1.0,
		front_z + door_depth + 0.03)
	handle.material_override = handle_mat
	building.add_child(handle)


## Create a porch with foundation deck and steps on the front of a building.
func _create_porch(building: MeshInstance3D, spec: Dictionary) -> void:
	var porch_width: float = spec.get("width", 10.0)
	var porch_depth: float = spec.get("depth", 3.0)
	var elevation: float = spec.get("elevation", 0.6)
	var steps: int = spec.get("steps", 3)
	var total_height: float = spec.get("total_height", 6.0)
	var front_z: float = spec.get("front_z", 5.0)
	var mat_type_str: String = spec.get("mat_type", "wood")
	var porch_tex_id: String = spec.get("porch_texture_id", "")
	var floors: int = spec.get("floors", 1)
	var has_balcony: bool = spec.get("has_balcony", false)
	var ground_y := -total_height / 2.0

	# Dynamic porch post height: match the first-floor ceiling
	var floor_height := 4.0
	var has_balcony_above := has_balcony and floors > 1
	var porch_ceiling_y := floor_height + elevation
	var post_height := porch_ceiling_y - elevation

	# Porch deck material: prefer texture, fall back to color
	var porch_deck_mat: StandardMaterial3D
	if porch_tex_id != "" and _preset_textures.has(porch_tex_id):
		porch_deck_mat = _get_shared_material("porch_deck_tex", Color.WHITE, mat_type_str)
		porch_deck_mat.albedo_texture = _preset_textures[porch_tex_id]
	else:
		porch_deck_mat = _get_shared_material("porch_deck", Color(0.45, 0.3, 0.2), mat_type_str)

	# Porch deck
	var deck_thickness := 0.15
	var deck := MeshInstance3D.new()
	var deck_box := BoxMesh.new()
	deck_box.size = Vector3(porch_width + 0.5, deck_thickness, porch_depth)
	deck.mesh = deck_box
	deck.name = "PorchDeck"
	deck.position = Vector3(0, ground_y - elevation / 2.0, front_z + porch_depth / 2.0)
	deck.material_override = porch_deck_mat
	building.add_child(deck)

	# Porch foundation/support
	var foundation := MeshInstance3D.new()
	var fnd_box := BoxMesh.new()
	fnd_box.size = Vector3(porch_width + 0.5, elevation, 0.3)
	foundation.mesh = fnd_box
	foundation.name = "PorchFoundation"
	foundation.position = Vector3(0, ground_y - elevation / 2.0, front_z + porch_depth)
	foundation.material_override = _get_shared_material("porch_fnd", Color(0.5, 0.5, 0.45))
	building.add_child(foundation)

	# Steps
	if steps > 0:
		var step_height := elevation / float(steps)
		var step_depth := 0.35
		var step_mat := _get_shared_material("porch_step", Color(0.5, 0.35, 0.25), mat_type_str)
		for i in range(steps):
			var step := MeshInstance3D.new()
			var step_box := BoxMesh.new()
			step_box.size = Vector3(porch_width * 0.5, step_height, step_depth)
			step.mesh = step_box
			step.name = "PorchStep_%d" % i
			var sy := ground_y - elevation + step_height * (float(i) + 0.5)
			var sz := front_z + porch_depth + step_depth * (steps - i - 0.5)
			step.position = Vector3(0, sy, sz)
			step.material_override = step_mat
			building.add_child(step)

	# Porch posts
	var post_count := maxi(2, floori(porch_width / 4.0))
	var post_mat := _get_shared_material("porch_post", Color(0.45, 0.3, 0.2), mat_type_str)
	for pi in range(post_count):
		var post := MeshInstance3D.new()
		var post_box := BoxMesh.new()
		post_box.size = Vector3(0.15, post_height, 0.15)
		post.mesh = post_box
		post.name = "PorchPost_%d" % pi
		var px := -porch_width / 2.0 + (porch_width / float(post_count - 1)) * pi if post_count > 1 else 0.0
		post.position = Vector3(px, ground_y - elevation + post_height / 2.0, front_z + porch_depth)
		post.material_override = post_mat
		building.add_child(post)

	# Thin overhang when upper floor exists but no balcony covers the porch
	if floors > 1 and not has_balcony_above:
		var overhang := MeshInstance3D.new()
		var overhang_box := BoxMesh.new()
		overhang_box.size = Vector3(porch_width + 0.5, 0.15, porch_depth + 0.3)
		overhang.mesh = overhang_box
		overhang.name = "PorchOverhang"
		overhang.position = Vector3(0, ground_y - elevation + porch_ceiling_y, front_z + porch_depth / 2.0)
		overhang.material_override = _get_shared_material("porch_overhang", Color(0.4, 0.28, 0.18), mat_type_str)
		building.add_child(overhang)


## Add windows to each floor, with optional shutters from style.
func _add_windows(building: MeshInstance3D, width: float, depth: float,
		floors: int, total_height: float, style: Dictionary) -> void:
	var floor_height := 3.0
	var ground_y := -total_height / 2.0
	var front_z := depth / 2.0
	var window_width := 1.0
	var window_height := 1.2
	var window_depth := 0.08
	var window_color: Color = style.get("window_color", Color(0.7, 0.8, 0.9))

	# Window material with glass-like specular, metallic, and transparency
	var window_mat := StandardMaterial3D.new()
	window_mat.albedo_color = window_color
	window_mat.metallic_specular = 0.5
	window_mat.metallic = 0.2
	window_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	window_mat.albedo_color.a = 0.7
	window_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	# Dark backing material for behind window glass
	var backing_mat := StandardMaterial3D.new()
	backing_mat.albedo_color = Color(0.05, 0.05, 0.08)
	backing_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var do_shutters: bool = style.get("has_shutters", false)
	var shutter_col: Color = style.get("shutter_color", Color(0.3, 0.3, 0.3))
	var shutter_tex_id: String = style.get("shutter_texture_id", "")
	var shutter_mat: StandardMaterial3D = null
	if do_shutters:
		if shutter_tex_id != "" and _preset_textures.has(shutter_tex_id):
			shutter_mat = _get_shared_material("shutter_tex", Color.WHITE)
			shutter_mat.albedo_texture = _preset_textures[shutter_tex_id]
		else:
			shutter_mat = _get_shared_material("shutter", shutter_col)

	# Place windows on front AND back faces, evenly spaced
	var num_windows := maxi(1, int(width / 3.0))
	var spacing := width / float(num_windows + 1)
	var back_z := -depth / 2.0

	for face in ["front", "back"]:
		var shutter_z: float = front_z + 0.04 if face == "front" else back_z - 0.04
		var z_sign: float = 1.0 if face == "front" else -1.0

		for floor_i in range(floors):
			var wy := ground_y + floor_height * floor_i + floor_height * 0.6
			for wi in range(num_windows):
				var wx := -width / 2.0 + spacing * (wi + 1)

				# Skip ground-floor front windows that overlap the door (centered at x=0)
				if face == "front" and floor_i == 0 and absf(wx) < 1.2:
					continue

				# Window Z offset: glass pane sits at depth/2 + 0.12
				var win_z: float = z_sign * (depth / 2.0 + 0.12)

				# Dark interior backing behind the glass at depth/2 + 0.02
				var backing := MeshInstance3D.new()
				var backing_box := BoxMesh.new()
				backing_box.size = Vector3(window_width, window_height, 0.02)
				backing.mesh = backing_box
				backing.name = "WindowBack_%s_F%d_%d" % [face, floor_i, wi]
				backing.position = Vector3(wx, wy, z_sign * (depth / 2.0 + 0.02))
				backing.material_override = backing_mat
				building.add_child(backing)

				# Glass pane
				var win := MeshInstance3D.new()
				var win_box := BoxMesh.new()
				win_box.size = Vector3(window_width, window_height, window_depth)
				win.mesh = win_box
				win.name = "Window_%s_F%d_%d" % [face, floor_i, wi]
				win.position = Vector3(wx, wy, win_z)
				win.material_override = window_mat
				building.add_child(win)

				# Shutters (left and right of window)
				if do_shutters and shutter_mat != null:
					var shutter_w := 0.15
					var shutter_h := window_height + 0.1
					for side in [-1, 1]:
						var shutter := MeshInstance3D.new()
						var sb := BoxMesh.new()
						sb.size = Vector3(shutter_w, shutter_h, 0.06)
						shutter.mesh = sb
						shutter.name = "Shutter_%s_F%d_%d_%s" % [face, floor_i, wi, "L" if side == -1 else "R"]
						shutter.position = Vector3(
							wx + side * (window_width / 2.0 + shutter_w / 2.0),
							wy,
							shutter_z
						)
						shutter.material_override = shutter_mat
						building.add_child(shutter)


## Add ironwork balconies on every upper floor (creole / New Orleans style).
func _add_ironwork_balconies(building: MeshInstance3D, width: float, depth: float,
		floors: int, total_height: float, style: Dictionary = {}) -> void:
	var floor_height := 3.0
	var ground_y := -total_height / 2.0
	var front_z := depth / 2.0
	var balcony_depth := 1.5
	var rail_height := 1.0
	var iron_color := Color(0.12, 0.12, 0.12)
	var ironwork_tex_id: String = style.get("ironwork_texture_id", "")
	var iron_mat: StandardMaterial3D
	if ironwork_tex_id != "" and _preset_textures.has(ironwork_tex_id):
		iron_mat = _get_shared_material("ironwork_tex", Color.WHITE, "metal")
		iron_mat.albedo_texture = _preset_textures[ironwork_tex_id]
	else:
		iron_mat = _get_shared_material("ironwork", iron_color, "metal")

	for floor_i in range(1, floors):
		var floor_y := ground_y + floor_height * floor_i

		# Balcony floor/platform
		var platform := MeshInstance3D.new()
		var plat_box := BoxMesh.new()
		plat_box.size = Vector3(width + 0.4, 0.08, balcony_depth)
		platform.mesh = plat_box
		platform.name = "Balcony_Floor_%d" % floor_i
		platform.position = Vector3(0, floor_y, front_z + balcony_depth / 2.0)
		platform.material_override = iron_mat
		building.add_child(platform)

		# Railing — front bar
		var front_rail := MeshInstance3D.new()
		var fr_box := BoxMesh.new()
		fr_box.size = Vector3(width + 0.4, rail_height, 0.05)
		front_rail.mesh = fr_box
		front_rail.name = "Balcony_Rail_%d" % floor_i
		front_rail.position = Vector3(0, floor_y + rail_height / 2.0, front_z + balcony_depth)
		front_rail.material_override = iron_mat
		building.add_child(front_rail)

		# Balusters
		var num_balusters := maxi(2, int(width / 0.8))
		var bal_spacing := (width + 0.4) / float(num_balusters + 1)
		for bi in range(num_balusters):
			var baluster := MeshInstance3D.new()
			var bb := BoxMesh.new()
			bb.size = Vector3(0.03, rail_height, 0.03)
			baluster.mesh = bb
			baluster.name = "Baluster_%d_%d" % [floor_i, bi]
			baluster.position = Vector3(
				-(width + 0.4) / 2.0 + bal_spacing * (bi + 1),
				floor_y + rail_height / 2.0,
				front_z + balcony_depth
			)
			baluster.material_override = iron_mat
			building.add_child(baluster)


## Apply runtime procedural configuration (style overrides, etc.).
func set_procedural_config(config: Dictionary) -> void:
	_procedural_config = config
	if config.has("style_preset"):
		var preset_key: String = config["style_preset"]
		if STYLE_PRESETS.has(preset_key):
			_procedural_config["style"] = STYLE_PRESETS[preset_key]
	print("[Insimul] ProceduralBuildingGenerator config updated: %d keys" % config.size())


## Convert a style preset dictionary and seed into a building spec dictionary.
## Useful for generating varied buildings from the same preset.
static func preset_to_building_style(preset: Dictionary, seed_val: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val

	var result := preset.duplicate(true)
	# Slight color variation based on seed
	var variation := 0.05
	var bc: Color = result.get("base_color", Color.WHITE)
	result["base_color"] = Color(
		clampf(bc.r + rng.randf_range(-variation, variation), 0.0, 1.0),
		clampf(bc.g + rng.randf_range(-variation, variation), 0.0, 1.0),
		clampf(bc.b + rng.randf_range(-variation, variation), 0.0, 1.0)
	)

	# Randomize floor count slightly
	var base_floors: int = result.get("floors", 2)
	result["floors"] = maxi(1, base_floors + rng.randi_range(-1, 1))

	return result


## Subtype-specific style hints: role -> override dictionary.
## Mirrors shared/game-engine/building-style-presets.ts SUBTYPE_STYLE_OVERRIDES.
const SUBTYPE_HINTS := {
	# ── Commercial: Food & Drink ──
	"Bakery":     { "tint": Color(1.15, 1.0, 0.85), "material": "brick", "has_shutters": true },
	"Restaurant": { "tint": Color(1.1, 0.95, 0.85), "material": "brick", "has_porch": true, "porch_depth": 2.0, "porch_steps": 2, "has_shutters": true },
	"Bar":        { "tint": Color(0.8, 0.75, 0.7), "material": "wood", "has_porch": false, "has_shutters": false },
	"Brewery":    { "tint": Color(0.9, 0.85, 0.75), "material": "brick" },
	# ── Commercial: Retail ──
	"Shop":          { "tint": Color(1.05, 1.05, 1.0), "material": "wood", "has_porch": true, "porch_depth": 1.5, "porch_steps": 1 },
	"GroceryStore":  { "tint": Color(1.0, 1.1, 0.95), "material": "brick", "has_porch": true, "porch_depth": 2.0, "porch_steps": 1 },
	"JewelryStore":  { "tint": Color(0.95, 0.95, 1.1), "material": "stone", "has_shutters": true },
	"BookStore":     { "tint": Color(1.0, 0.95, 0.85), "material": "wood", "has_shutters": true },
	"PawnShop":      { "tint": Color(0.9, 0.85, 0.8), "material": "wood" },
	"HerbShop":      { "tint": Color(0.9, 1.1, 0.85), "material": "wood", "has_porch": true, "porch_depth": 1.5, "porch_steps": 1 },
	# ── Commercial: Services ──
	"Bank":          { "tint": Color(0.95, 0.95, 0.95), "material": "stone", "has_porch": true, "porch_depth": 3.0, "porch_steps": 4, "has_shutters": false },
	"Hotel":         { "tint": Color(1.05, 1.0, 0.95), "material": "brick", "has_shutters": true, "has_ironwork_balcony": true },
	"Barbershop":    { "tint": Color(1.0, 1.0, 1.05), "material": "brick" },
	"Tailor":        { "tint": Color(1.05, 0.95, 1.05), "material": "wood", "has_shutters": true },
	"Bathhouse":     { "tint": Color(0.95, 1.0, 1.1), "material": "stone" },
	"Pharmacy":      { "tint": Color(1.0, 1.05, 1.05), "material": "brick", "has_shutters": true },
	"LawFirm":       { "tint": Color(0.9, 0.9, 0.9), "material": "stone", "has_porch": true, "porch_depth": 2.0, "porch_steps": 3 },
	# ── Civic ──
	"Church":        { "material": "stone", "has_porch": true, "porch_depth": 3.0, "porch_steps": 5 },
	"TownHall":      { "material": "stone", "has_porch": true, "porch_depth": 3.0, "porch_steps": 4, "has_ironwork_balcony": true },
	"School":        { "tint": Color(1.0, 0.95, 0.9), "material": "brick", "has_porch": true, "porch_depth": 2.0, "porch_steps": 3 },
	"University":    { "material": "stone", "has_porch": true, "porch_depth": 3.0, "porch_steps": 5 },
	"Hospital":      { "tint": Color(1.15, 1.15, 1.15), "material": "stucco", "has_porch": true, "porch_depth": 3.0, "porch_steps": 2 },
	"PoliceStation": { "tint": Color(0.85, 0.85, 0.9), "material": "brick", "has_porch": true, "porch_depth": 2.0, "porch_steps": 3 },
	"FireStation":   { "tint": Color(1.1, 0.85, 0.8), "material": "brick" },
	# ── Industrial ──
	"Factory":    { "tint": Color(0.85, 0.8, 0.75), "material": "metal" },
	"Farm":       { "tint": Color(1.1, 1.0, 0.85), "material": "wood", "has_porch": true, "porch_depth": 2.0, "porch_steps": 2 },
	"Warehouse":  { "tint": Color(0.8, 0.8, 0.8), "material": "metal" },
	"Blacksmith": { "tint": Color(0.75, 0.7, 0.65), "material": "stone" },
	"Carpenter":  { "tint": Color(1.05, 0.95, 0.8), "material": "wood" },
	"Butcher":    { "tint": Color(1.0, 0.9, 0.85), "material": "brick" },
	# ── Maritime ──
	"Harbor":       { "tint": Color(0.9, 0.95, 1.0), "material": "wood" },
	"Boatyard":     { "tint": Color(0.85, 0.9, 0.95), "material": "wood" },
	"FishMarket":   { "tint": Color(0.95, 1.0, 1.05), "material": "wood", "has_porch": true, "porch_depth": 2.0, "porch_steps": 1 },
	"CustomsHouse": { "tint": Color(0.95, 0.95, 0.95), "material": "stone" },
	"Lighthouse":   { "tint": Color(1.1, 1.1, 1.1), "material": "stone" },
	# ── Residential ──
	"house":       { "material": "wood", "has_porch": true, "porch_depth": 2.0, "porch_steps": 2, "has_shutters": true },
	"apartment":   { "material": "brick", "has_ironwork_balcony": true },
	"mansion":     { "material": "stone", "has_porch": true, "porch_depth": 3.0, "porch_steps": 4, "has_shutters": true, "has_ironwork_balcony": true },
	"cottage":     { "tint": Color(1.1, 1.05, 0.95), "material": "wood", "has_porch": true, "porch_depth": 1.5, "porch_steps": 1, "has_shutters": true },
	"townhouse":   { "material": "brick", "has_shutters": true },
	"mobile_home": { "material": "metal" },
	# ── Other/Legacy ──
	"Tavern":  { "tint": Color(1.0, 0.9, 0.8), "material": "wood", "has_ironwork_balcony": true, "has_porch": true, "porch_depth": 2.0, "porch_steps": 2 },
	"Inn":     { "tint": Color(1.05, 1.0, 0.9), "material": "wood", "has_ironwork_balcony": true, "has_porch": true, "porch_depth": 2.0, "porch_steps": 3, "has_shutters": true },
	"Library": { "material": "stone", "has_porch": true, "porch_depth": 2.0, "porch_steps": 4 },
}


## Apply subtype-specific overrides on top of a base style dictionary.
static func apply_subtype_override(base_style: Dictionary, role: String) -> Dictionary:
	if not SUBTYPE_HINTS.has(role):
		return base_style
	var hint: Dictionary = SUBTYPE_HINTS[role]
	var result := base_style.duplicate(true)

	# Color tint
	if hint.has("tint"):
		var tint: Color = hint["tint"]
		var bc: Color = result.get("base_color", Color.WHITE)
		result["base_color"] = Color(
			minf(1.0, bc.r * tint.r),
			minf(1.0, bc.g * tint.g),
			minf(1.0, bc.b * tint.b))

	# Material preference
	if hint.has("material") and result.get("material_type", "") != hint["material"]:
		result["material_type"] = hint["material"]

	# Feature flags
	for key in ["has_porch", "porch_depth", "porch_steps", "has_shutters", "has_ironwork_balcony"]:
		if hint.has(key):
			result[key] = hint[key]

	return result

## Merge child MeshInstance3D nodes sharing the same material into combined meshes.
## Skips interactive meshes (Door) and non-BoxMesh children (roofs with ArrayMesh).
func _merge_building_meshes(building: MeshInstance3D) -> void:
	# Group children by material resource
	var groups: Dictionary = {}  # material_rid → Array[MeshInstance3D]
	for child in building.get_children():
		if not (child is MeshInstance3D):
			continue
		if child.name == "Door" or child.name == "Roof" or child.name == "Chimney":
			continue  # Skip interactive/special meshes
		if child.mesh == null or not (child.mesh is BoxMesh):
			continue  # Only merge box meshes (not ArrayMesh roofs)
		var mat: Material = child.material_override
		if mat == null:
			continue
		var key: int = mat.get_rid().get_id()
		if not groups.has(key):
			groups[key] = []
		groups[key].append(child)

	# Merge groups with 2+ meshes
	for key in groups:
		var meshes: Array = groups[key]
		if meshes.size() < 2:
			continue

		# Collect all vertices from child BoxMeshes, transforming to building-local space
		var all_vertices := PackedVector3Array()
		var all_normals := PackedVector3Array()
		var all_uvs := PackedVector2Array()
		var all_indices := PackedInt32Array()
		var mat: Material = meshes[0].material_override
		var vertex_offset := 0

		for mi in meshes:
			var box: BoxMesh = mi.mesh as BoxMesh
			if box == null:
				continue
			# Generate box arrays
			var box_arrays := box.get_mesh_arrays()
			if box_arrays.size() == 0:
				continue
			# Get arrays from first surface
			var temp_mesh := ArrayMesh.new()
			temp_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, box.surface_get_arrays(0))
			var arrays := temp_mesh.surface_get_arrays(0)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var uv_arr: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]

			# Transform vertices to building-local space
			var xform: Transform3D = Transform3D(Basis(), mi.position)
			xform = xform.scaled_local(mi.scale)
			for v in verts:
				all_vertices.append(xform * v)
			all_normals.append_array(norms)
			if uv_arr.size() > 0:
				all_uvs.append_array(uv_arr)
			else:
				for _i in range(verts.size()):
					all_uvs.append(Vector2.ZERO)
			for i_val in idx:
				all_indices.append(i_val + vertex_offset)
			vertex_offset += verts.size()

		if all_vertices.size() == 0:
			continue

		# Create merged mesh
		var merged_arrays := []
		merged_arrays.resize(Mesh.ARRAY_MAX)
		merged_arrays[Mesh.ARRAY_VERTEX] = all_vertices
		merged_arrays[Mesh.ARRAY_NORMAL] = all_normals
		merged_arrays[Mesh.ARRAY_TEX_UV] = all_uvs
		merged_arrays[Mesh.ARRAY_INDEX] = all_indices
		var merged_mesh := ArrayMesh.new()
		merged_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, merged_arrays)

		var merged_inst := MeshInstance3D.new()
		merged_inst.mesh = merged_mesh
		merged_inst.material_override = mat
		merged_inst.name = "Merged_%d" % key
		building.add_child(merged_inst)

		# Remove original children
		for mi in meshes:
			mi.queue_free()

## Create a gable roof mesh with custom vertex geometry.
## Ridge runs along X (front-to-back) for standard gable, along Z for side_gable.
func _create_gable_roof(w: float, d: float, h: float, side: bool) -> ArrayMesh:
	var hw: float = w / 2.0
	var hd: float = d / 2.0
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	if side:
		# Ridge runs left-right (Z axis), slopes on front/back
		# 6 vertices: 4 base corners + 2 ridge points
		vertices.append(Vector3(-hw, 0, -hd))  # 0: front-left base
		vertices.append(Vector3(hw, 0, -hd))   # 1: front-right base
		vertices.append(Vector3(hw, 0, hd))    # 2: back-right base
		vertices.append(Vector3(-hw, 0, hd))   # 3: back-left base
		vertices.append(Vector3(-hw, h, 0))    # 4: left ridge
		vertices.append(Vector3(hw, h, 0))     # 5: right ridge
	else:
		# Ridge runs front-back (X axis), slopes on left/right
		vertices.append(Vector3(-hw, 0, -hd))  # 0: front-left base
		vertices.append(Vector3(hw, 0, -hd))   # 1: front-right base
		vertices.append(Vector3(hw, 0, hd))    # 2: back-right base
		vertices.append(Vector3(-hw, 0, hd))   # 3: back-left base
		vertices.append(Vector3(0, h, -hd))    # 4: front ridge
		vertices.append(Vector3(0, h, hd))     # 5: back ridge

	for _i in range(6):
		normals.append(Vector3.UP)
		uvs.append(Vector2(0, 0))

	if side:
		# Front slope: 0, 1, 5, 4
		indices.append_array(PackedInt32Array([0, 4, 1, 1, 4, 5]))
		# Back slope: 2, 3, 4, 5
		indices.append_array(PackedInt32Array([2, 5, 3, 3, 5, 4]))
		# Left triangle: 0, 3, 4
		indices.append_array(PackedInt32Array([0, 3, 4]))
		# Right triangle: 1, 5, 2
		indices.append_array(PackedInt32Array([1, 5, 2]))
	else:
		# Left slope: 0, 3, 5, 4
		indices.append_array(PackedInt32Array([0, 4, 3, 3, 4, 5]))
		# Right slope: 1, 5, 2  (and 1, 4, 5)
		indices.append_array(PackedInt32Array([1, 5, 4, 1, 2, 5]))
		# Front triangle: 0, 4, 1
		indices.append_array(PackedInt32Array([0, 4, 1]))
		# Back triangle: 3, 5, 2
		indices.append_array(PackedInt32Array([3, 5, 2]))

	# Compute proper face normals
	_compute_normals(vertices, indices, normals)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

## Create a hip roof mesh — all four sides slope inward to a central ridge.
func _create_hip_roof(w: float, d: float, h: float) -> ArrayMesh:
	var hw: float = w / 2.0
	var hd: float = d / 2.0
	var ridge_inset: float = minf(hw, hd) * 0.4  # Ridge is shorter than base
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	# 6 vertices: 4 base corners + 2 ridge endpoints
	vertices.append(Vector3(-hw, 0, -hd))         # 0: front-left
	vertices.append(Vector3(hw, 0, -hd))           # 1: front-right
	vertices.append(Vector3(hw, 0, hd))            # 2: back-right
	vertices.append(Vector3(-hw, 0, hd))           # 3: back-left
	vertices.append(Vector3(-hw + ridge_inset, h, 0))  # 4: left ridge
	vertices.append(Vector3(hw - ridge_inset, h, 0))   # 5: right ridge

	for _i in range(6):
		normals.append(Vector3.UP)
		uvs.append(Vector2(0, 0))

	# Front slope: 0, 1, 5, 4
	indices.append_array(PackedInt32Array([0, 4, 1, 1, 4, 5]))
	# Back slope: 2, 3, 4, 5
	indices.append_array(PackedInt32Array([2, 5, 3, 3, 5, 4]))
	# Left triangle: 0, 3, 4
	indices.append_array(PackedInt32Array([0, 3, 4]))
	# Right triangle: 1, 5, 2
	indices.append_array(PackedInt32Array([1, 5, 2]))

	_compute_normals(vertices, indices, normals)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

## Compute face normals and accumulate to vertices for smooth shading.
func _compute_normals(vertices: PackedVector3Array, indices: PackedInt32Array, normals: PackedVector3Array) -> void:
	for i in range(normals.size()):
		normals[i] = Vector3.ZERO
	for i in range(0, indices.size(), 3):
		var i0: int = indices[i]
		var i1: int = indices[i + 1]
		var i2: int = indices[i + 2]
		var face_normal := (vertices[i1] - vertices[i0]).cross(vertices[i2] - vertices[i0]).normalized()
		normals[i0] += face_normal
		normals[i1] += face_normal
		normals[i2] += face_normal
	for i in range(normals.size()):
		if normals[i].length_squared() > 0.001:
			normals[i] = normals[i].normalized()
		else:
			normals[i] = Vector3.UP

## Add a chimney to the side of a building.
func _add_chimney(building: MeshInstance3D, width: float, depth: float,
		total_height: float) -> void:
	var chimney_w := 1.0
	var chimney_d := 1.0
	var chimney_h := 5.0
	var chimney := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(chimney_w, chimney_h, chimney_d)
	chimney.mesh = box
	chimney.name = "Chimney"
	chimney.position = Vector3(
		width / 2.0 - chimney_w / 2.0,
		total_height / 2.0 + chimney_h / 2.0 - 1.0,
		-depth * 0.15
	)
	var chimney_mat := _get_shared_material("chimney", Color(0.45, 0.3, 0.2))
	chimney.material_override = chimney_mat
	building.add_child(chimney)
