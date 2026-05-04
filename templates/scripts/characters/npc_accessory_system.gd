extends Node
## NPC Accessory System — attaches accessories for visual variety.
## Matches shared/game-engine/rendering/NPCAccessorySystem.ts and NPCAppearanceGenerator.ts.

## Accessory categories with occupation affinities
const ACCESSORY_POOLS := {
	"hats": {
		"guard": ["helmet_iron", "helmet_chain"],
		"merchant": ["hat_feathered", "hat_beret"],
		"blacksmith": ["hat_bandana"],
		"farmer": ["hat_straw", "hat_wide"],
		"noble": ["hat_crown", "hat_tricorn"],
		"civilian": ["hat_cap", "hat_hood"],
	},
	"glasses": ["spectacles_round", "spectacles_square", "monocle"],
	"jewelry": {
		"noble": ["necklace_gold", "ring_gemstone", "brooch_silver"],
		"merchant": ["necklace_silver", "ring_simple"],
		"civilian": ["ring_simple"],
	},
	"weapons": {
		"guard": ["sword_iron", "shield_round", "spear_basic"],
		"blacksmith": ["hammer_smithing"],
		"civilian": ["dagger_small"],
	},
	"tools": {
		"blacksmith": ["tongs_forge", "apron_leather"],
		"merchant": ["pouch_coin", "scale_balance"],
		"farmer": ["pitchfork", "sickle"],
	},
}

const BONE_ATTACHMENTS := {
	"hats": "Head",
	"glasses": "Head",
	"jewelry": "Neck",
	"weapons": "RightHand",
	"tools": "LeftHand",
}

func generate_accessories(npc_root: Node3D, character_data: Dictionary) -> void:
	var char_id: String = character_data.get("characterId", "")
	var role: String = character_data.get("role", "civilian")
	var social_status: String = character_data.get("socialStatus", "common")

	var rng := RandomNumberGenerator.new()
	rng.seed = char_id.hash()

	# Determine which accessory slots to fill based on social status
	var max_accessories: int = 1
	match social_status:
		"wealthy", "noble":
			max_accessories = 3
		"middle":
			max_accessories = 2
		_:
			max_accessories = 1

	var slots_filled := 0
	for category in ["hats", "weapons", "tools", "jewelry", "glasses"]:
		if slots_filled >= max_accessories:
			break
		if rng.randf() < _get_slot_chance(category, role):
			var accessory_id := _pick_accessory(category, role, rng)
			if accessory_id != "":
				_attach_accessory(npc_root, category, accessory_id)
				slots_filled += 1

func _get_slot_chance(category: String, role: String) -> float:
	match category:
		"hats":
			return 0.4 if role in ["guard", "farmer", "noble"] else 0.15
		"weapons":
			return 0.8 if role == "guard" else 0.1
		"tools":
			return 0.6 if role in ["blacksmith", "farmer", "merchant"] else 0.05
		"jewelry":
			return 0.5 if role == "noble" else 0.1
		"glasses":
			return 0.08
	return 0.05

func _pick_accessory(category: String, role: String, rng: RandomNumberGenerator) -> String:
	var pool = ACCESSORY_POOLS.get(category, {})
	var items: Array = []

	if pool is Dictionary:
		items = pool.get(role, pool.get("civilian", []))
	elif pool is Array:
		items = pool

	if items.is_empty():
		return ""
	return items[rng.randi() % items.size()]

func _attach_accessory(npc_root: Node3D, category: String, accessory_id: String) -> void:
	var bone_name: String = BONE_ATTACHMENTS.get(category, "")
	var model_path := "res://assets/accessories/%s/%s.glb" % [category, accessory_id]

	if not ResourceLoader.exists(model_path):
		return

	var scene: PackedScene = load(model_path) as PackedScene
	if not scene:
		return

	var instance := scene.instantiate() as Node3D
	if not instance:
		return

	# Try attaching to skeleton bone, fall back to position-based
	var skeleton := _find_skeleton(npc_root)
	if skeleton and bone_name != "":
		var attachment := BoneAttachment3D.new()
		attachment.bone_name = bone_name
		skeleton.add_child(attachment)
		attachment.add_child(instance)
	else:
		# Positional fallback
		match category:
			"hats":
				instance.position.y = 1.75
			"weapons":
				instance.position = Vector3(0.4, 1.0, 0)
			"tools":
				instance.position = Vector3(-0.4, 1.0, 0)
		npc_root.add_child(instance)

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found:
			return found
	return null
