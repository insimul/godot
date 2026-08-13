extends Node
## `ICombatSystem` + `ICombatStatSink` for Godot — tasklist 147, US-1.
##
## Two interfaces, one component, because they are two views of ONE thing: the
## roster of who is fighting and what their numbers are. `EquipmentManager` writes
## equipment-adjusted totals into it; `CombatResolver` takes health out of it.
## Splitting them would mean two rosters that have to agree.
##
## ## What this file does NOT do
##
## Resolve an attack. `combat_system.gd` in this template has a
## `calculate_damage()` with its own critical multiplier and its own random
## variance — the pre-adoption combat, kept because existing games call it — and
## this component deliberately does not use it, call it or agree with it. Damage
## arrives already decided, from core's `resolution.ts`, through
## `combat.attack`'s `ICombatSystem.applyDamage` order. A host that recomputed it
## would make the same save mean two things in two engines, which is the drift
## the whole unification program exists to stop
## (`packages/core/src/game-engine/system-contracts.ts`).
##
## The two are not a contradiction, they are a MIGRATION: a game moving to the
## adopted mechanic stops calling `CombatSystem.calculate_damage` and starts
## calling `combat.attack`. Until it does, both exist and only one of them is
## core's.

## Emitted with a number CORE decided, for a health bar, a hit flash, a hit sound.
signal damage_applied(entity_id: String, damage: float, health: float)
## Emitted when core's resolution took an entity out of the fight.
signal entity_unregistered(entity_id: String)
## Emitted when equipment changed what an entity's numbers are.
signal stats_applied(entity_id: String, stats: Dictionary)

## Whether combat is on for this world at all. Read by core through
## `is_combat_enabled()`; a world whose genre bundle does not select the combat
## module never opens a session in the first place (tasklist 147, US-3).
@export var combat_enabled := true

## entity atom -> { name, health, maxHealth, attackPower, defense, dodgeChance }
var _roster := {}


## The `ICombatSystem` to wire into a combat session.
func combat_system() -> InsimulMechanicHosts.CombatSystem:
	return _CombatSystem.new(self)


## The `ICombatStatSink` to wire into an equipment session.
func stat_sink() -> InsimulMechanicHosts.CombatStatSink:
	return _CombatStatSink.new(self)


## Seed an entity's UNMODIFIED numbers — what it is worth before anything is
## worn. This is the one thing the host is authoritative about, and it is why
## `ICombatStatSink` runs in both directions.
func set_base_stats(entity_id: String, attack_power: float, defense: float, dodge_chance: float) -> void:
	var entry: Dictionary = _roster.get(entity_id, {})
	entry["attackPower"] = attack_power
	entry["defense"] = defense
	entry["dodgeChance"] = dodge_chance
	_roster[entity_id] = entry


func register_entity(entity: Dictionary) -> void:
	var entity_id := String(entity.get("id", ""))
	if entity_id.is_empty():
		return
	var entry: Dictionary = _roster.get(entity_id, {})
	entry["name"] = String(entity.get("name", entity_id))
	entry["health"] = float(entity.get("health", 0.0))
	entry["maxHealth"] = float(entity.get("maxHealth", entry.get("health", 0.0)))
	_roster[entity_id] = entry


func unregister_entity(entity_id: String) -> void:
	if not _roster.has(entity_id):
		return
	_roster.erase(entity_id)
	entity_unregistered.emit(entity_id)


## Apply damage CORE resolved. No mitigation, no rounding, no second roll: every
## number that made this what it is happened in core, deterministically, from
## (attacker, defender, action, tuning, separation, seed, tick).
func apply_damage(entity_id: String, damage: float) -> void:
	var entry: Dictionary = _roster.get(entity_id, {})
	var health := maxf(0.0, float(entry.get("health", 0.0)) - damage)
	entry["health"] = health
	_roster[entity_id] = entry
	damage_applied.emit(entity_id, damage, health)


func heal(entity_id: String, amount: float) -> void:
	if not _roster.has(entity_id):
		return
	var entry: Dictionary = _roster[entity_id]
	entry["health"] = minf(float(entry.get("maxHealth", 0.0)), float(entry.get("health", 0.0)) + amount)
	_roster[entity_id] = entry


func get_health(entity_id: String) -> float:
	return float(_roster.get(entity_id, {}).get("health", 0.0))


func is_combat_enabled() -> bool:
	return combat_enabled


## The entity's unmodified stats, or {} when it is not in combat — `undefined` on
## core's side, which `EquipmentManager` reads as "no base stats, so apply none".
func get_base_stats(entity_id: String) -> Dictionary:
	if not _roster.has(entity_id):
		return {}
	var entry: Dictionary = _roster[entity_id]
	if not entry.has("attackPower"):
		return {}
	return {
		"attackPower": float(entry.get("attackPower", 0.0)),
		"defense": float(entry.get("defense", 0.0)),
		"dodgeChance": float(entry.get("dodgeChance", 0.0)),
	}


## Apply equipment-adjusted totals. ABSOLUTE, not a delta: re-applying the same
## totals twice is a no-op, which is what makes a save restore or a replayed
## equip safe.
func apply_stats(entity_id: String, stats: Dictionary) -> void:
	if not _roster.has(entity_id):
		# A no-op for an unknown entity, exactly as core's interface says.
		return
	var entry: Dictionary = _roster[entity_id]
	entry["attackPower"] = float(stats.get("attackPower", entry.get("attackPower", 0.0)))
	entry["defense"] = float(stats.get("defense", entry.get("defense", 0.0)))
	entry["dodgeChance"] = float(stats.get("dodgeChance", entry.get("dodgeChance", 0.0)))
	_roster[entity_id] = entry
	stats_applied.emit(entity_id, entry.duplicate())


## The whole roster, for a HUD. A copy, because nothing outside this component
## may move a number in it.
func roster() -> Dictionary:
	return _roster.duplicate(true)


class _CombatSystem extends InsimulMechanicHosts.CombatSystem:
	var _node: Node = null

	func _init(node: Node) -> void:
		_node = node

	func register_entity(entity: Dictionary) -> void:
		_node.register_entity(entity)

	func unregister_entity(entity_id: String) -> void:
		_node.unregister_entity(entity_id)

	func apply_damage(entity_id: String, damage: float) -> void:
		_node.apply_damage(entity_id, damage)

	func is_combat_enabled() -> bool:
		return _node.is_combat_enabled()

	func get_health(entity_id: String) -> float:
		return _node.get_health(entity_id)

	func heal(entity_id: String, amount: float) -> void:
		_node.heal(entity_id, amount)


class _CombatStatSink extends InsimulMechanicHosts.CombatStatSink:
	var _node: Node = null

	func _init(node: Node) -> void:
		_node = node

	func get_base_stats(entity_id: String) -> Dictionary:
		return _node.get_base_stats(entity_id)

	func apply_stats(entity_id: String, stats: Dictionary) -> void:
		_node.apply_stats(entity_id, stats)
