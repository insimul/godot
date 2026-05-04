extends Node
## Turn-Based Combat System — RPG-style with status effects, MP, party management.
## Used when combat_style is "turn_based".

signal turn_started(combatant_id: String, is_player: bool)
signal action_resolved(result: Dictionary)
signal combat_started(allies: Array, enemies: Array)
signal combat_ended(victory: bool)
signal status_applied(target_id: String, effect_type: String, duration: int)
signal status_expired(target_id: String, effect_type: String)

enum CombatPhase { WAITING, PLAYER_TURN, ENEMY_TURN, RESOLVING, VICTORY, DEFEAT }

## Base actions available to all combatants
const BASE_ACTIONS := [
	{"id": "attack", "name": "Attack", "type": "damage", "damage": 20, "mp_cost": 0, "accuracy": 0.9, "target": "single_enemy"},
	{"id": "defend", "name": "Defend", "type": "defend", "damage": 0, "mp_cost": 0, "accuracy": 1.0, "target": "self", "duration": 1},
	{"id": "fire", "name": "Fire", "type": "damage", "damage": 35, "mp_cost": 10, "accuracy": 0.85, "target": "single_enemy", "status": "burn", "status_chance": 0.3, "status_duration": 3, "status_potency": 5},
	{"id": "ice", "name": "Ice", "type": "damage", "damage": 30, "mp_cost": 10, "accuracy": 0.85, "target": "single_enemy", "status": "freeze", "status_chance": 0.2, "status_duration": 1, "status_potency": 0},
	{"id": "heal", "name": "Heal", "type": "heal", "damage": 40, "mp_cost": 15, "accuracy": 1.0, "target": "single_ally"},
	{"id": "group_heal", "name": "Group Heal", "type": "heal", "damage": 25, "mp_cost": 30, "accuracy": 1.0, "target": "all_allies"},
	{"id": "poison_strike", "name": "Poison Strike", "type": "damage", "damage": 15, "mp_cost": 5, "accuracy": 0.9, "target": "single_enemy", "status": "poison", "status_chance": 0.5, "status_duration": 4, "status_potency": 8},
	{"id": "flee", "name": "Flee", "type": "flee", "damage": 0, "mp_cost": 0, "accuracy": 0.5, "target": "self"},
]

## Status effect types
const STATUS_TYPES := {
	"poison": {"dot": true, "stat_mod": ""},
	"burn": {"dot": true, "stat_mod": ""},
	"freeze": {"dot": false, "stat_mod": "skip_turn"},
	"stun": {"dot": false, "stat_mod": "skip_turn"},
	"heal_over_time": {"dot": false, "heal": true, "stat_mod": ""},
	"shield": {"dot": false, "stat_mod": "damage_reduction"},
	"attack_up": {"dot": false, "stat_mod": "attack_mult"},
	"defense_up": {"dot": false, "stat_mod": "defense_mult"},
	"attack_down": {"dot": false, "stat_mod": "attack_mult_neg"},
	"defense_down": {"dot": false, "stat_mod": "defense_mult_neg"},
}

var phase: CombatPhase = CombatPhase.WAITING
var _combatants: Dictionary = {}  # id → combatant data
var _turn_order: Array[String] = []
var _current_turn_index := 0
var _combat_log: Array[String] = []

func start_combat(allies: Array, enemies: Array) -> void:
	_combatants.clear()
	_combat_log.clear()
	for ally in allies:
		_combatants[ally["id"]] = _make_combatant(ally, true)
	for enemy in enemies:
		_combatants[enemy["id"]] = _make_combatant(enemy, false)
	_calculate_turn_order()
	_current_turn_index = 0
	phase = CombatPhase.PLAYER_TURN if _combatants[_turn_order[0]]["is_ally"] else CombatPhase.ENEMY_TURN
	combat_started.emit(allies, enemies)
	_log("Combat begins!")
	_start_next_turn()

func _make_combatant(data: Dictionary, is_ally: bool) -> Dictionary:
	return {
		"id": data.get("id", ""),
		"name": data.get("name", "Unknown"),
		"health": data.get("health", 100.0),
		"max_health": data.get("max_health", 100.0),
		"mp": data.get("mp", 50.0),
		"max_mp": data.get("max_mp", 50.0),
		"speed": data.get("speed", 10),
		"attack": data.get("attack", 10),
		"defense": data.get("defense", 5),
		"is_ally": is_ally,
		"is_defending": false,
		"status_effects": [],  # [{type, duration, potency}]
		"actions": data.get("actions", BASE_ACTIONS).duplicate(true),
		"is_alive": true,
	}

func _calculate_turn_order() -> void:
	_turn_order.clear()
	var sorted: Array = _combatants.values().filter(func(c: Dictionary) -> bool: return c["is_alive"])
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["speed"] > b["speed"])
	for c in sorted:
		_turn_order.append(c["id"])

func _start_next_turn() -> void:
	# Process status effects at turn start
	if _current_turn_index == 0:
		_process_round_start()

	if _current_turn_index >= _turn_order.size():
		_current_turn_index = 0
		_calculate_turn_order()
		if _check_combat_end():
			return
		_start_next_turn()
		return

	var combatant_id: String = _turn_order[_current_turn_index]
	if not _combatants.has(combatant_id) or not _combatants[combatant_id]["is_alive"]:
		_current_turn_index += 1
		_start_next_turn()
		return

	var combatant: Dictionary = _combatants[combatant_id]

	# Check for skip-turn status (freeze/stun)
	for effect in combatant["status_effects"]:
		var effect_info: Dictionary = STATUS_TYPES.get(effect["type"], {})
		if effect_info.get("stat_mod", "") == "skip_turn":
			_log("%s is %s and cannot act!" % [combatant["name"], effect["type"]])
			_current_turn_index += 1
			_start_next_turn()
			return

	combatant["is_defending"] = false
	var is_player: bool = combatant["is_ally"]
	phase = CombatPhase.PLAYER_TURN if is_player else CombatPhase.ENEMY_TURN
	turn_started.emit(combatant_id, is_player)

	if not is_player:
		# AI decides action
		call_deferred("_ai_decide", combatant_id)

## Player selects an action
func execute_action(actor_id: String, action_id: String, target_id: String) -> void:
	if phase != CombatPhase.PLAYER_TURN and phase != CombatPhase.ENEMY_TURN:
		return
	phase = CombatPhase.RESOLVING
	var actor: Dictionary = _combatants.get(actor_id, {})
	var action: Dictionary = {}
	for a in actor.get("actions", BASE_ACTIONS):
		if a["id"] == action_id:
			action = a
			break
	if action.is_empty():
		return

	# MP check
	var mp_cost: int = action.get("mp_cost", 0)
	if mp_cost > 0:
		if actor["mp"] < mp_cost:
			_log("Not enough MP!")
			return
		actor["mp"] -= mp_cost

	var result := _resolve_action(actor, action, target_id)
	action_resolved.emit(result)

	if _check_combat_end():
		return

	_current_turn_index += 1
	call_deferred("_start_next_turn")

func _resolve_action(actor: Dictionary, action: Dictionary, target_id: String) -> Dictionary:
	var result := {"actor": actor["name"], "action": action["name"], "targets": []}
	var action_type: String = action.get("type", "damage")

	match action_type:
		"damage":
			var targets: Array = _get_targets(action, target_id, false)
			for target in targets:
				# Accuracy roll
				if randf() > action.get("accuracy", 0.9):
					_log("%s's %s missed %s!" % [actor["name"], action["name"], target["name"]])
					result["targets"].append({"name": target["name"], "damage": 0, "miss": true})
					continue

				var raw_damage: float = action.get("damage", 10)
				# Attack modifiers
				var atk_mult := 1.0
				for eff in actor["status_effects"]:
					if STATUS_TYPES.get(eff["type"], {}).get("stat_mod", "") == "attack_mult":
						atk_mult += eff["potency"] / 100.0

				# Defense modifiers
				var def_mult := 1.0
				if target["is_defending"]:
					def_mult = 0.5
				for eff in target["status_effects"]:
					var sm: String = STATUS_TYPES.get(eff["type"], {}).get("stat_mod", "")
					if sm == "defense_mult":
						def_mult -= eff["potency"] / 100.0
					elif sm == "damage_reduction":
						def_mult -= eff["potency"] / 100.0

				var final_damage: float = maxf(1.0, raw_damage * atk_mult * def_mult)
				target["health"] = maxf(0.0, target["health"] - final_damage)
				if target["health"] <= 0:
					target["is_alive"] = false
				_log("%s deals %d damage to %s!" % [actor["name"], int(final_damage), target["name"]])
				result["targets"].append({"name": target["name"], "damage": int(final_damage)})

				# Status effect chance
				if action.has("status") and randf() < action.get("status_chance", 0):
					_apply_status(target, action["status"], action.get("status_duration", 3), action.get("status_potency", 5))

				EventBus.emit_event({
					"type": "combat_action",
					"action_type": action["id"],
					"damage": int(final_damage),
					"target_name": target["name"],
					"target_id": target["id"],
					"target_health": target["health"],
					"target_max_health": target["max_health"],
				})

		"heal":
			var targets: Array = _get_targets(action, target_id, true)
			for target in targets:
				var heal_amount: float = action.get("damage", 20)
				target["health"] = minf(target["max_health"], target["health"] + heal_amount)
				_log("%s heals %s for %d HP!" % [actor["name"], target["name"], int(heal_amount)])
				result["targets"].append({"name": target["name"], "heal": int(heal_amount)})

		"defend":
			actor["is_defending"] = true
			_log("%s takes a defensive stance!" % actor["name"])

		"flee":
			if randf() < action.get("accuracy", 0.5):
				_log("%s fled from battle!" % actor["name"])
				combat_ended.emit(false)
			else:
				_log("%s tried to flee but failed!" % actor["name"])

	return result

func _get_targets(action: Dictionary, target_id: String, allies: bool) -> Array:
	var target_type: String = action.get("target", "single_enemy")
	match target_type:
		"single_enemy", "single_ally":
			if _combatants.has(target_id):
				return [_combatants[target_id]]
			return []
		"all_enemies":
			return _combatants.values().filter(func(c: Dictionary) -> bool: return c["is_alive"] and not c["is_ally"])
		"all_allies":
			return _combatants.values().filter(func(c: Dictionary) -> bool: return c["is_alive"] and c["is_ally"])
		"self":
			return []
	return []

func _apply_status(target: Dictionary, effect_type: String, duration: int, potency: float) -> void:
	target["status_effects"].append({"type": effect_type, "duration": duration, "potency": potency})
	_log("%s is afflicted with %s!" % [target["name"], effect_type])
	status_applied.emit(target["id"], effect_type, duration)

func _process_round_start() -> void:
	for c_id in _combatants:
		var c: Dictionary = _combatants[c_id]
		if not c["is_alive"]:
			continue
		var expired: Array[int] = []
		for i in range(c["status_effects"].size()):
			var eff: Dictionary = c["status_effects"][i]
			var eff_type: Dictionary = STATUS_TYPES.get(eff["type"], {})
			# DoT damage
			if eff_type.get("dot", false):
				var dot_dmg: float = eff["potency"]
				c["health"] = maxf(0.0, c["health"] - dot_dmg)
				_log("%s takes %d %s damage!" % [c["name"], int(dot_dmg), eff["type"]])
				if c["health"] <= 0:
					c["is_alive"] = false
			# HoT
			if eff_type.get("heal", false):
				c["health"] = minf(c["max_health"], c["health"] + eff["potency"])
			# Reduce duration
			eff["duration"] -= 1
			if eff["duration"] <= 0:
				expired.append(i)
				status_expired.emit(c["id"], eff["type"])
		# Remove expired (reverse order)
		for i in range(expired.size() - 1, -1, -1):
			c["status_effects"].remove_at(expired[i])

func _check_combat_end() -> bool:
	var allies_alive: bool = _combatants.values().any(func(c: Dictionary) -> bool: return c["is_ally"] and c["is_alive"])
	var enemies_alive: bool = _combatants.values().any(func(c: Dictionary) -> bool: return not c["is_ally"] and c["is_alive"])
	if not enemies_alive:
		phase = CombatPhase.VICTORY
		combat_ended.emit(true)
		_log("Victory!")
		return true
	if not allies_alive:
		phase = CombatPhase.DEFEAT
		combat_ended.emit(false)
		_log("Defeat...")
		return true
	return false

## Enemy AI decision
func _ai_decide(combatant_id: String) -> void:
	var combatant: Dictionary = _combatants.get(combatant_id, {})
	if combatant.is_empty() or not combatant["is_alive"]:
		return

	var health_pct: float = combatant["health"] / combatant["max_health"]
	var action_id := "attack"
	var target_id := ""

	# Low health → try to heal or defend
	if health_pct < 0.3:
		if combatant["mp"] >= 15:
			action_id = "heal"
			target_id = combatant_id
		else:
			action_id = "defend"
			target_id = combatant_id
	else:
		# Pick strongest affordable attack
		var best_damage := 0.0
		for a in combatant.get("actions", BASE_ACTIONS):
			if a["type"] == "damage" and a.get("mp_cost", 0) <= combatant["mp"] and a.get("damage", 0) > best_damage:
				best_damage = a["damage"]
				action_id = a["id"]

		# Target lowest HP ally
		var lowest_hp := INF
		for c in _combatants.values():
			if c["is_ally"] and c["is_alive"] and c["health"] < lowest_hp:
				lowest_hp = c["health"]
				target_id = c["id"]

	execute_action(combatant_id, action_id, target_id)

func get_combatant(c_id: String) -> Dictionary:
	return _combatants.get(c_id, {})

func get_combat_log() -> Array[String]:
	return _combat_log

func _log(text: String) -> void:
	_combat_log.append(text)
	print("[Combat] %s" % text)
