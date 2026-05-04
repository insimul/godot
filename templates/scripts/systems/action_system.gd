extends Node
## Action System -- autoloaded singleton.
## Manages available actions and their execution with item/gold effect support.

signal gold_effect(amount: int)
signal item_effect(item_id: String, quantity: int)

var actions: Array[Dictionary] = []
## Per-action cooldown and usage tracking: { action_id: { last_used, cooldown_remaining, times_used } }
var _action_states: Dictionary = {}

func load_from_data(world_data: Dictionary) -> void:
	var systems: Dictionary = world_data.get("systems", {})
	actions.append_array(systems.get("actions", []))
	actions.append_array(systems.get("baseActions", []))
	print("[Insimul] ActionSystem loaded %d actions" % actions.size())

func get_action(action_id: String) -> Dictionary:
	for a in actions:
		if a.get("id", "") == action_id:
			return a
	return {}

## Get all action IDs matching a category (social, combat, mental, etc.).
func get_actions_by_category(category: String) -> Array[String]:
	var result: Array[String] = []
	for a in actions:
		if a.get("actionType", "") == category:
			result.append(a.get("id", ""))
	return result

## Check whether an action can be performed given current context.
## Returns { can_perform: bool, reason: String }.
func can_perform_action(action_id: String, context: Dictionary = {}) -> Dictionary:
	var action := get_action(action_id)
	if action.is_empty():
		return {"can_perform": false, "reason": "Action not found"}

	if not action.get("isActive", true):
		return {"can_perform": false, "reason": "Action not available"}

	# Check cooldown
	if _action_states.has(action_id):
		var state: Dictionary = _action_states[action_id]
		if state.get("cooldown_remaining", 0.0) > 0:
			return {"can_perform": false, "reason": "On cooldown (%.1fs remaining)" % state["cooldown_remaining"]}

	# Check energy
	var energy_cost: float = action.get("energyCost", 0)
	var player_energy: float = context.get("player_energy", 100.0)
	if energy_cost > 0 and energy_cost > player_energy:
		return {"can_perform": false, "reason": "Not enough energy (need %d)" % int(energy_cost)}

	# Check target requirement
	if action.get("requiresTarget", false) and not context.has("target"):
		return {"can_perform": false, "reason": "Requires a target"}

	return {"can_perform": true, "reason": ""}

## Tick cooldowns -- call once per frame with delta seconds.
func update_cooldowns(delta: float) -> void:
	for action_id in _action_states:
		var state: Dictionary = _action_states[action_id]
		if state.get("cooldown_remaining", 0.0) > 0:
			state["cooldown_remaining"] = maxf(0.0, state["cooldown_remaining"] - delta)

## Get remaining cooldown for an action (0 if ready).
func get_cooldown(action_id: String) -> float:
	if _action_states.has(action_id):
		return _action_states[action_id].get("cooldown_remaining", 0.0)
	return 0.0

## Standard personality affinities for common action types.
## Maps actionType -> { trait -> weight }.
const STANDARD_ACTION_AFFINITIES: Dictionary = {
	# Social actions
	"greet": {"extroversion": 0.4, "agreeableness": 0.3},
	"compliment": {"agreeableness": 0.5, "extroversion": 0.2},
	"gossip": {"extroversion": 0.3, "agreeableness": -0.3, "openness": 0.1},
	"argue": {"extroversion": 0.2, "agreeableness": -0.5, "neuroticism": 0.3},
	"comfort": {"agreeableness": 0.6, "extroversion": 0.1},
	"apologize": {"agreeableness": 0.4, "conscientiousness": 0.3},
	# Physical actions
	"fight": {"agreeableness": -0.5, "extroversion": 0.3, "neuroticism": 0.2},
	"flee": {"neuroticism": 0.5, "agreeableness": 0.2},
	"explore": {"openness": 0.6, "extroversion": 0.2},
	"rest": {"conscientiousness": -0.2, "neuroticism": 0.1},
	# Economic actions
	"trade": {"conscientiousness": 0.4, "agreeableness": 0.1},
	"steal": {"agreeableness": -0.6, "conscientiousness": -0.4, "neuroticism": 0.2},
	"craft": {"conscientiousness": 0.5, "openness": 0.3},
	"work": {"conscientiousness": 0.6},
	# Romance actions
	"flirt": {"extroversion": 0.4, "openness": 0.3, "agreeableness": 0.1},
	"express_love": {"agreeableness": 0.4, "extroversion": 0.2, "openness": 0.3},
	# Mental actions
	"study": {"openness": 0.5, "conscientiousness": 0.4},
	"meditate": {"openness": 0.4, "neuroticism": -0.3},
	"plan": {"conscientiousness": 0.6, "openness": 0.2},
}

## Get contextual actions ranked by personality match using softmax probability.
## personality: Dictionary with keys openness, conscientiousness, extroversion, agreeableness, neuroticism (each -1 to 1).
## Returns Array[Dictionary] with keys: action (Dictionary), probability (float), sorted descending.
## If personality is empty, returns uniform probability.
func get_contextual_actions_ranked(context: Dictionary = {}, personality: Dictionary = {}) -> Array[Dictionary]:
	var player_energy: float = context.get("player_energy", 100.0)
	var has_target: bool = context.has("target")

	# Gather contextual actions
	var contextual: Array[Dictionary] = []
	for a in actions:
		if not a.get("isActive", true):
			continue
		var aid: String = a.get("id", "")
		if _action_states.has(aid):
			if _action_states[aid].get("cooldown_remaining", 0.0) > 0:
				continue
		var energy_cost: float = a.get("energyCost", 0)
		if energy_cost > 0 and energy_cost > player_energy:
			continue
		if a.get("requiresTarget", false) and not has_target:
			continue
		contextual.append(a)

	if contextual.is_empty():
		return []

	# Uniform fallback if no personality provided
	if personality.is_empty():
		var uniform: float = 1.0 / contextual.size()
		var uniform_result: Array[Dictionary] = []
		for a in contextual:
			uniform_result.append({"action": a, "probability": uniform})
		return uniform_result

	# Compute raw scores via dot product of personality traits with action affinities
	var scores: Array[float] = []
	for a in contextual:
		var score: float = 0.5 # base weight
		var action_type: String = a.get("actionType", "")
		if STANDARD_ACTION_AFFINITIES.has(action_type):
			var affinities: Dictionary = STANDARD_ACTION_AFFINITIES[action_type]
			for trait_key in affinities:
				score += personality.get(trait_key, 0.0) * affinities[trait_key]
		scores.append(score)

	# Softmax with temperature
	var temperature: float = 1.0
	var max_score: float = scores[0]
	for s in scores:
		max_score = maxf(max_score, s)

	var exps: Array[float] = []
	var sum_exp: float = 0.0
	for s in scores:
		var e: float = exp((s - max_score) / maxf(0.01, temperature))
		exps.append(e)
		sum_exp += e

	if sum_exp <= 0.0:
		sum_exp = 1.0

	var result: Array[Dictionary] = []
	for i in range(contextual.size()):
		result.append({"action": contextual[i], "probability": exps[i] / sum_exp})

	# Sort descending by probability
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["probability"] > b["probability"])
	return result

## Execute an action and return a result dictionary.
## Result: {success: bool, message: String, energy_used: int, effects: Array[Dictionary], narrative_text: String, animation: Dictionary}
## animation (optional): {clip: String, clip_alt: String, library: String, loop: bool, speed: float, blend_in: float}
func execute_action(action_id: String, source: Node, target: Node = null) -> Dictionary:
	var action := get_action(action_id)

	# Validate via can_perform_action
	var context := {}
	if target:
		context["target"] = target
	var check := can_perform_action(action_id, context)
	if not check["can_perform"]:
		return {"success": false, "message": check["reason"], "energy_used": 0, "effects": [], "narrative_text": "", "animation": {}}

	var effects: Array[Dictionary] = []

	# Process effects from action definition
	for effect in action.get("effects", []):
		var category: String = effect.get("category", "")
		var effect_data := {
			"type": category,
			"target": "player" if effect.get("first", "") == "initiator" else (target.name if target else ""),
			"value": effect.get("value", 0),
			"description": "%s %s %s" % [effect.get("type", ""), effect.get("operator", ""), str(effect.get("value", 0))]
		}

		if category == "item":
			effect_data["item_id"] = effect.get("type", "")
			effect_data["quantity"] = int(effect.get("value", 1))
			item_effect.emit(effect_data["item_id"], effect_data["quantity"])
		elif category == "gold":
			gold_effect.emit(int(effect.get("value", 0)))

		effects.append(effect_data)

	# Generate narrative text
	var target_name: String = str(target.name) if target else "someone"
	var narrative_text: String = _generate_narrative_text(action, "You", target_name)

	# Update action state and start cooldown
	if not _action_states.has(action_id):
		_action_states[action_id] = {"action_id": action_id, "last_used": 0.0, "cooldown_remaining": 0.0, "times_used": 0}
	var state: Dictionary = _action_states[action_id]
	state["last_used"] = Time.get_ticks_msec() / 1000.0
	state["times_used"] = state.get("times_used", 0) + 1
	var cooldown: float = action.get("cooldown", 0)
	if cooldown > 0:
		state["cooldown_remaining"] = cooldown

	# Extract animation data from custom_data if present
	var animation := {}
	var custom_data: Dictionary = action.get("custom_data", {})
	if custom_data.has("animation"):
		var anim_src: Dictionary = custom_data["animation"]
		animation = {
			"clip": anim_src.get("clip", ""),
			"clip_alt": anim_src.get("clipAlt", ""),
			"library": anim_src.get("library", "UAL1"),
			"loop": anim_src.get("loop", false),
			"speed": anim_src.get("speed", 1.0),
			"blend_in": anim_src.get("blendIn", 0.0)
		}

	var action_name: String = action.get("name", action_id)
	print("[Insimul] Executing action: %s (%d effects)" % [action_name, effects.size()])
	return {"success": true, "message": "%s performed successfully" % action_name, "energy_used": action.get("energyCost", 0), "effects": effects, "narrative_text": narrative_text, "animation": animation}

## Generate narrative text from an action's narrativeTemplates array.
func _generate_narrative_text(action: Dictionary, actor_name: String, target_name: String) -> String:
	var templates: Array = action.get("narrativeTemplates", [])
	if templates.size() > 0:
		var template: String = templates[randi() % templates.size()]
		return template.replace("{actor}", actor_name).replace("{target}", target_name)
	# Fallback
	var verb: String = action.get("verbPast", action.get("name", "acted").to_lower())
	return "You %s." % verb

## Maps quest objective types to the action names that can satisfy them.
const OBJECTIVE_TO_ACTION: Dictionary = {
	"visit_location": ["travel_to_location", "enter_building"],
	"discover_location": ["travel_to_location"],
	"talk_to_npc": ["talk_to_npc"],
	"complete_conversation": ["talk_to_npc"],
	"collect_item": ["collect_item"],
	"deliver_item": ["give_gift"],
	"craft_item": ["craft_item", "craft", "cook"],
	"defeat_enemies": ["attack_enemy"],
	"build_friendship": ["talk_to_npc", "compliment_npc", "give_gift"],
	"give_gift": ["give_gift"],
	"examine_object": ["examine_object"],
	"read_sign": ["read_sign"],
	"listen_and_repeat": ["listen_and_repeat"],
	"point_and_name": ["point_and_name"],
	"read_text": ["read_book"],
	"comprehension_quiz": ["answer_question"],
	"photograph_subject": ["take_photo"],
	"photograph_activity": ["take_photo"],
}

## Find actions that can satisfy a given quest objective type.
func find_action_for_objective(objective_type: String) -> Array[Dictionary]:
	if not OBJECTIVE_TO_ACTION.has(objective_type):
		return []
	var names: Array = OBJECTIVE_TO_ACTION[objective_type]
	var result: Array[Dictionary] = []
	for a in actions:
		if names.has(a.get("name", "")):
			result.append(a)
	return result

## Look up an action by its name (e.g., "fish", "cook", "attack_enemy").
func get_action_by_name(action_name: String) -> Dictionary:
	for a in actions:
		if a.get("name", "") == action_name:
			return a
	return {}
