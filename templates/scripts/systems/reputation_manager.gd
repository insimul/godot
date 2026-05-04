extends Node
## Reputation Manager — tracks player reputation and NPC relationships.
## Matches shared/game-engine/rendering/ReputationManager.ts, logic/RelationshipManager.ts.

signal reputation_changed(faction_id: String, old_value: float, new_value: float)
signal relationship_changed(npc_id: String, old_value: float, new_value: float)
signal relationship_level_changed(npc_id: String, level: String)

const RELATIONSHIP_LEVELS := {
	-100: "hostile",
	-50: "unfriendly",
	-10: "cold",
	0: "neutral",
	25: "warm",
	50: "friendly",
	75: "close",
	90: "devoted",
}

## Per-settlement/faction reputation: { id: float }
var reputations: Dictionary = {}
## Per-NPC relationship: { npc_id: { friendship: float, trust: float, romance: float } }
var relationships: Dictionary = {}

func get_reputation(faction_id: String) -> float:
	return reputations.get(faction_id, 0.0)

func modify_reputation(faction_id: String, delta: float) -> void:
	var old_val: float = reputations.get(faction_id, 0.0)
	var new_val: float = clampf(old_val + delta, -100.0, 100.0)
	reputations[faction_id] = new_val
	reputation_changed.emit(faction_id, old_val, new_val)

func get_price_multiplier(faction_id: String) -> float:
	var rep: float = get_reputation(faction_id)
	# -100 rep = 1.5x prices, 0 = 1.0x, +100 = 0.7x
	return clampf(1.0 - (rep / 333.0), 0.7, 1.5)

func is_quest_available(faction_id: String, min_rep: float) -> bool:
	return get_reputation(faction_id) >= min_rep

func get_relationship(npc_id: String) -> Dictionary:
	if not relationships.has(npc_id):
		relationships[npc_id] = {"friendship": 0.0, "trust": 0.0, "romance": 0.0}
	return relationships[npc_id]

func modify_relationship(npc_id: String, dimension: String, delta: float) -> void:
	var rel := get_relationship(npc_id)
	var old_val: float = rel.get(dimension, 0.0)
	var new_val: float = clampf(old_val + delta, -100.0, 100.0)
	rel[dimension] = new_val
	relationships[npc_id] = rel
	relationship_changed.emit(npc_id, old_val, new_val)

	# Check for level change
	var old_level := _get_level(old_val)
	var new_level := _get_level(new_val)
	if old_level != new_level:
		relationship_level_changed.emit(npc_id, new_level)

func get_dialogue_tone(npc_id: String) -> String:
	var rel := get_relationship(npc_id)
	var friendship: float = rel.get("friendship", 0.0)
	return _get_level(friendship)

func _get_level(value: float) -> String:
	var result := "neutral"
	for threshold in RELATIONSHIP_LEVELS:
		if value >= threshold:
			result = RELATIONSHIP_LEVELS[threshold]
	return result

func on_quest_completed(npc_id: String, settlement_id: String) -> void:
	modify_relationship(npc_id, "friendship", 10.0)
	modify_relationship(npc_id, "trust", 5.0)
	modify_reputation(settlement_id, 5.0)

func on_dialogue_positive(npc_id: String) -> void:
	modify_relationship(npc_id, "friendship", 2.0)

func on_dialogue_negative(npc_id: String) -> void:
	modify_relationship(npc_id, "friendship", -3.0)
	modify_relationship(npc_id, "trust", -2.0)

func save_data() -> Dictionary:
	return {"reputations": reputations, "relationships": relationships}

func load_data(data: Dictionary) -> void:
	reputations = data.get("reputations", {})
	relationships = data.get("relationships", {})
