extends Node
## NPC Modular Assembler — assembles NPC characters from modular Quaternius GLTF parts.
## Matches shared/game-engine/rendering/NPCModularAssembler.ts and QuaterniusNPCLoader.ts.

const BODY_TYPES := ["average", "athletic", "heavy", "slim"]
const GENDERS := ["male", "female"]

## Genre-specific model sets
const GENRE_MODEL_PATHS := {
	"fantasy": "res://assets/characters/fantasy/",
	"scifi": "res://assets/characters/scifi/",
	"modern": "res://assets/characters/modern/",
	"generic": "res://assets/characters/generic/",
}

## Role-specific outfit overrides
const ROLE_OUTFITS := {
	"guard": "armor_guard",
	"merchant": "outfit_merchant",
	"blacksmith": "outfit_blacksmith",
	"innkeeper": "outfit_tavern",
	"farmer": "outfit_farmer",
	"noble": "outfit_noble",
	"priest": "outfit_priest",
}

var _model_cache: Dictionary = {}

func assemble_npc(character_data: Dictionary, parent: Node3D) -> Node3D:
	var root := Node3D.new()
	root.name = "ModularBody"

	var char_id: String = character_data.get("characterId", "")
	var seed_val: int = char_id.hash()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val

	var gender: String = character_data.get("gender", GENDERS[rng.randi() % 2])
	var body_type: String = character_data.get("bodyType", BODY_TYPES[rng.randi() % BODY_TYPES.size()])
	var role: String = character_data.get("role", "civilian")
	var genre: String = character_data.get("genre", "generic")

	# Try to load from bundled GLTF assets with fallback chain
	var body_model := _load_body(genre, gender, body_type, role, rng)
	if body_model:
		root.add_child(body_model)
		_attach_hair(root, genre, gender, rng)
		_attach_outfit(root, genre, gender, role, rng)
	else:
		# Fallback: procedural body from npc_spawner
		push_warning("[NPCModularAssembler] No model found for %s — using fallback" % char_id)

	parent.add_child(root)
	return root

func _load_body(genre: String, gender: String, body_type: String, role: String, rng: RandomNumberGenerator) -> Node3D:
	# Fallback chain: role-specific -> body type -> genre+gender -> generic
	var paths_to_try: Array[String] = []

	var base_path: String = GENRE_MODEL_PATHS.get(genre, GENRE_MODEL_PATHS["generic"])
	if ROLE_OUTFITS.has(role):
		paths_to_try.append(base_path + "body_%s_%s_%s.glb" % [gender, body_type, ROLE_OUTFITS[role]])
	paths_to_try.append(base_path + "body_%s_%s.glb" % [gender, body_type])
	paths_to_try.append(base_path + "body_%s.glb" % gender)
	paths_to_try.append(GENRE_MODEL_PATHS["generic"] + "body_%s.glb" % gender)

	for path in paths_to_try:
		var model := _try_load_model(path)
		if model:
			return model
	return null

func _attach_hair(root: Node3D, genre: String, gender: String, rng: RandomNumberGenerator) -> void:
	var base_path: String = GENRE_MODEL_PATHS.get(genre, GENRE_MODEL_PATHS["generic"])
	var hair_index: int = rng.randi() % 20  # Up to 20 hair styles per gender
	var path := base_path + "hair_%s_%02d.glb" % [gender, hair_index]
	var model := _try_load_model(path)
	if model:
		# Attach at head position
		model.position.y = 1.65
		root.add_child(model)

func _attach_outfit(root: Node3D, genre: String, gender: String, role: String, rng: RandomNumberGenerator) -> void:
	var base_path: String = GENRE_MODEL_PATHS.get(genre, GENRE_MODEL_PATHS["generic"])
	var outfit_name := ""
	if ROLE_OUTFITS.has(role):
		outfit_name = ROLE_OUTFITS[role]
	else:
		outfit_name = "outfit_%02d" % (rng.randi() % 10)
	var path := base_path + "%s_%s.glb" % [outfit_name, gender]
	var model := _try_load_model(path)
	if model:
		root.add_child(model)

func _try_load_model(path: String) -> Node3D:
	if _model_cache.has(path):
		var cached = _model_cache[path]
		if cached == null:
			return null
		return cached.duplicate()

	if not ResourceLoader.exists(path):
		_model_cache[path] = null
		return null

	var scene: PackedScene = load(path) as PackedScene
	if scene:
		var instance := scene.instantiate() as Node3D
		_model_cache[path] = instance
		return instance.duplicate()

	_model_cache[path] = null
	return null
