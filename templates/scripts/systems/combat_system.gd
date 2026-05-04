extends Node
## Combat System — autoloaded singleton.

@export var combat_style := "{{COMBAT_STYLE}}"
@export var base_damage := {{COMBAT_BASE_DAMAGE}}
@export var critical_chance := {{COMBAT_CRITICAL_CHANCE}}
@export var critical_multiplier := {{COMBAT_CRITICAL_MULTIPLIER}}
@export var block_reduction := {{COMBAT_BLOCK_REDUCTION}}
@export var dodge_chance := {{COMBAT_DODGE_CHANCE}}
@export var attack_cooldown := {{COMBAT_ATTACK_COOLDOWN}}

var _last_attack_time := -999.0

func load_from_data(world_data: Dictionary) -> void:
	var combat: Dictionary = world_data.get("combat", {})
	combat_style = combat.get("style", combat_style)
	var settings: Dictionary = combat.get("settings", {})
	if not settings.is_empty():
		base_damage = settings.get("baseDamage", base_damage)
		critical_chance = settings.get("criticalChance", critical_chance)
		critical_multiplier = settings.get("criticalMultiplier", critical_multiplier)
		block_reduction = settings.get("blockReduction", block_reduction)
		dodge_chance = settings.get("dodgeChance", dodge_chance)
		attack_cooldown = settings.get("attackCooldown", attack_cooldown * 1000.0) / 1000.0
	print("[Insimul] CombatSystem loaded — style: %s, baseDamage: %.1f" % [combat_style, base_damage])

func calculate_damage(base_dmg: float, is_critical: bool) -> float:
	var dmg := base_dmg
	if is_critical:
		dmg *= critical_multiplier
	var variance := randf_range(-base_damage * 0.2, base_damage * 0.2)
	return maxf(1.0, dmg + variance)

func can_attack() -> bool:
	return Time.get_ticks_msec() / 1000.0 - _last_attack_time >= attack_cooldown

func register_attack() -> void:
	_last_attack_time = Time.get_ticks_msec() / 1000.0
