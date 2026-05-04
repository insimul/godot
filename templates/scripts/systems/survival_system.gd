extends Node
## Survival System — manages hunger, thirst, temperature, stamina, and sleep needs.
## Needs decay over time and must be replenished through actions.

var needs: Array[Dictionary] = []
var damage_enabled: bool = true
var global_damage_multiplier: float = 1.0

# Temperature config
var temperature_enabled: bool = false
var temperature_comfort_min: float = 20.0
var temperature_comfort_max: float = 80.0
var temperature_critical_both_extremes: bool = true
var environment_temperature: float = 50.0

# Stamina config
var stamina_action_driven: bool = true
var stamina_recovery_rate: float = 2.0

# Modifier system
var modifier_presets: Dictionary = {}  # presetId -> {needType, rateMultiplier, duration, source}
var active_modifiers: Array[Dictionary] = []  # [{presetId, needType, rateMultiplier, remainingDuration, isPermanent}]

signal need_warning(need_id: String, value: float)
signal need_critical(need_id: String, value: float)
signal need_restored(need_id: String, value: float)
signal damage_from_need(need_id: String, damage: float)
signal need_changed(need_id: String, value: float, max_value: float)
signal modifier_applied(preset_id: String, need_type: String)
signal modifier_expired(preset_id: String, need_type: String)

func load_from_data(world_data: Dictionary) -> void:
	var survival: Dictionary = world_data.get("survival", {})
	if survival.is_empty():
		return

	# Load needs
	var need_defs: Array = survival.get("needs", [])
	for nd in need_defs:
		needs.append({
			"id": nd.get("id", ""),
			"name": nd.get("name", ""),
			"value": nd.get("startValue", 100.0),
			"max_value": nd.get("maxValue", 100.0),
			"decay_rate": nd.get("decayRate", 0.0),
			"critical_threshold": nd.get("criticalThreshold", 20.0),
			"warning_threshold": nd.get("warningThreshold", 30.0),
			"damage_rate": nd.get("damageRate", 0.0),
			"was_critical": false,
			"was_warning": false,
		})

	# Damage config
	var dmg_config: Dictionary = survival.get("damageConfig", {})
	damage_enabled = dmg_config.get("enabled", true)
	global_damage_multiplier = dmg_config.get("globalDamageMultiplier", 1.0)

	# Temperature config
	var temp_config: Dictionary = survival.get("temperatureConfig", {})
	temperature_enabled = temp_config.get("environmentDriven", false)
	var comfort: Dictionary = temp_config.get("comfortZone", {})
	temperature_comfort_min = comfort.get("min", 20.0)
	temperature_comfort_max = comfort.get("max", 80.0)
	temperature_critical_both_extremes = temp_config.get("criticalAtBothExtremes", true)

	# Stamina config
	var stam_config: Dictionary = survival.get("staminaConfig", {})
	stamina_action_driven = stam_config.get("actionDriven", true)
	stamina_recovery_rate = stam_config.get("recoveryRate", 2.0)

	# Modifier presets
	var presets: Array = survival.get("modifierPresets", [])
	for preset in presets:
		var pid: String = preset.get("id", "")
		if pid != "":
			modifier_presets[pid] = {
				"needType": preset.get("needType", ""),
				"rateMultiplier": preset.get("rateMultiplier", 1.0),
				"duration": preset.get("duration", 0.0),
				"source": preset.get("source", ""),
			}

	print("[Insimul] SurvivalSystem loaded %d needs, %d modifier presets" % [needs.size(), modifier_presets.size()])

func _process(delta: float) -> void:
	_update_modifiers(delta)

	for need in needs:
		var nid: String = need.get("id", "")

		# Temperature is environment-driven
		if nid == "temperature" and temperature_enabled:
			_update_temperature_need(need, delta)
			continue

		# Stamina recovers passively when action-driven
		if nid == "stamina" and stamina_action_driven:
			_update_stamina_need(need, delta)
			continue

		# Standard decay
		var effective_rate: float = _get_effective_decay_rate(nid, need.get("decay_rate", 0.0))
		if effective_rate > 0:
			need["value"] = clampf(need.get("value", 0.0) - effective_rate * delta, 0.0, need.get("max_value", 100.0))

		_check_thresholds(need, delta)

func _update_temperature_need(need: Dictionary, delta: float) -> void:
	# Map environment temperature to need value using comfort zone
	# Below comfort_min -> low need value (cold), above comfort_max -> low need value (hot)
	# Inside comfort zone -> value near 50 (comfortable)
	var target: float = 50.0
	if environment_temperature < temperature_comfort_min:
		target = lerpf(0.0, 50.0, clampf(
			inverse_lerp(0.0, temperature_comfort_min, environment_temperature), 0.0, 1.0))
	elif environment_temperature > temperature_comfort_max:
		target = lerpf(50.0, 0.0, clampf(
			inverse_lerp(temperature_comfort_max, 100.0, environment_temperature), 0.0, 1.0))

	# Smooth transition
	need["value"] = move_toward(need.get("value", 50.0), target, 10.0 * delta)

	# Temperature critical at both extremes
	var val: float = need.get("value", 50.0)
	var crit: float = need.get("critical_threshold", 10.0)
	var warn: float = need.get("warning_threshold", 20.0)
	var max_val: float = need.get("max_value", 100.0)

	var is_critical: bool
	var is_warning: bool
	if temperature_critical_both_extremes:
		is_critical = val <= crit or val >= (max_val - crit)
		is_warning = (val <= warn or val >= (max_val - warn)) and not is_critical
	else:
		is_critical = val <= crit
		is_warning = val <= warn and not is_critical

	_emit_threshold_signals(need, is_critical, is_warning)
	need["was_critical"] = is_critical
	need["was_warning"] = is_warning

	# Damage when critical
	if damage_enabled and is_critical:
		var dmg_rate: float = need.get("damage_rate", 0.0)
		if dmg_rate > 0.0:
			var damage: float = dmg_rate * global_damage_multiplier * delta
			damage_from_need.emit(need.get("id", ""), damage)

	need_changed.emit(need.get("id", ""), need.get("value", 0.0), need.get("max_value", 100.0))

func _update_stamina_need(need: Dictionary, delta: float) -> void:
	# Passive recovery when action-driven
	var val: float = need.get("value", 0.0)
	var max_val: float = need.get("max_value", 100.0)
	var effective_recovery: float = _get_effective_recovery_rate("stamina", stamina_recovery_rate)
	if val < max_val and effective_recovery > 0:
		need["value"] = clampf(val + effective_recovery * delta, 0.0, max_val)

	_check_thresholds(need, delta)

func _check_thresholds(need: Dictionary, delta: float) -> void:
	var val: float = need.get("value", 0.0)
	var crit: float = need.get("critical_threshold", 20.0)
	var warn: float = need.get("warning_threshold", 30.0)
	var is_critical: bool = val <= crit
	var is_warning: bool = val <= warn and not is_critical

	_emit_threshold_signals(need, is_critical, is_warning)
	need["was_critical"] = is_critical
	need["was_warning"] = is_warning

	# Damage when need is depleted
	if damage_enabled and val <= 0.0:
		var dmg_rate: float = need.get("damage_rate", 0.0)
		if dmg_rate > 0.0:
			var damage: float = dmg_rate * global_damage_multiplier * delta
			damage_from_need.emit(need.get("id", ""), damage)

	need_changed.emit(need.get("id", ""), val, need.get("max_value", 100.0))

func _emit_threshold_signals(need: Dictionary, is_critical: bool, is_warning: bool) -> void:
	var nid: String = need.get("id", "")
	var val: float = need.get("value", 0.0)
	var was_critical: bool = need.get("was_critical", false)
	var was_warning: bool = need.get("was_warning", false)

	if is_critical and not was_critical:
		need_critical.emit(nid, val)
	elif is_warning and not was_warning:
		need_warning.emit(nid, val)

	# Restored: was critical or warning, now neither
	if (was_critical or was_warning) and not is_critical and not is_warning:
		need_restored.emit(nid, val)

func _get_effective_decay_rate(need_id: String, base_rate: float) -> float:
	var rate: float = base_rate
	for mod in active_modifiers:
		if mod.get("needType", "") == need_id:
			rate *= mod.get("rateMultiplier", 1.0)
	return rate

func _get_effective_recovery_rate(need_id: String, base_rate: float) -> float:
	# Modifiers with rateMultiplier 0 = full recovery, >1 = slower recovery
	var multiplier: float = 1.0
	for mod in active_modifiers:
		if mod.get("needType", "") == need_id:
			if mod.get("rateMultiplier", 1.0) == 0.0:
				return base_rate * 2.0  # Boosted recovery (e.g., resting)
			multiplier *= mod.get("rateMultiplier", 1.0)
	# Inverse: higher decay multiplier = slower recovery
	if multiplier > 0:
		return base_rate / multiplier
	return base_rate

func _update_modifiers(delta: float) -> void:
	var expired: Array[int] = []
	for i in range(active_modifiers.size()):
		var mod: Dictionary = active_modifiers[i]
		if mod.get("isPermanent", false):
			continue
		mod["remainingDuration"] = mod.get("remainingDuration", 0.0) - delta
		if mod.get("remainingDuration", 0.0) <= 0.0:
			expired.append(i)

	# Remove expired (reverse order)
	for i in range(expired.size() - 1, -1, -1):
		var mod: Dictionary = active_modifiers[expired[i]]
		modifier_expired.emit(mod.get("presetId", ""), mod.get("needType", ""))
		active_modifiers.remove_at(expired[i])

# ─── Public API ───

func get_need_value(need_id: String) -> float:
	for need in needs:
		if need.get("id", "") == need_id:
			return need.get("value", 0.0)
	return 0.0

func get_need_percent(need_id: String) -> float:
	for need in needs:
		if need.get("id", "") == need_id:
			var max_val: float = need.get("max_value", 100.0)
			if max_val <= 0:
				return 0.0
			return need.get("value", 0.0) / max_val
	return 0.0

func get_all_needs() -> Array[Dictionary]:
	return needs

func modify_need(need_id: String, delta_val: float) -> void:
	for need in needs:
		if need.get("id", "") == need_id:
			var was_critical: bool = need.get("was_critical", false)
			var was_warning: bool = need.get("was_warning", false)
			need["value"] = clampf(need.get("value", 0.0) + delta_val, 0.0, need.get("max_value", 100.0))
			var val: float = need.get("value", 0.0)
			var crit: float = need.get("critical_threshold", 20.0)
			var warn: float = need.get("warning_threshold", 30.0)
			var is_critical: bool = val <= crit
			var is_warning: bool = val <= warn and not is_critical
			if (was_critical or was_warning) and not is_critical and not is_warning:
				need_restored.emit(need_id, val)
			need["was_critical"] = is_critical
			need["was_warning"] = is_warning
			need_changed.emit(need_id, val, need.get("max_value", 100.0))
			return

func restore_need(need_id: String, amount: float) -> void:
	modify_need(need_id, amount)

func eat(item_id: String, restore_amount: float = 30.0) -> void:
	restore_need("hunger", restore_amount)

func drink(item_id: String, restore_amount: float = 25.0) -> void:
	restore_need("thirst", restore_amount)

func sleep_rest(duration: float, sleep_restore: float = 50.0, stamina_restore: float = 30.0) -> void:
	restore_need("sleep", sleep_restore)
	restore_need("stamina", stamina_restore)

func set_environment_temperature(temperature: float) -> void:
	environment_temperature = clampf(temperature, 0.0, 100.0)

func get_environment_temperature() -> float:
	return environment_temperature

func consume_stamina(amount: float) -> bool:
	var val: float = get_need_value("stamina")
	if val < amount:
		return false
	modify_need("stamina", -amount)
	return true

func has_stamina(amount: float) -> bool:
	return get_need_value("stamina") >= amount

func apply_modifier(preset_id: String) -> void:
	if not modifier_presets.has(preset_id):
		return
	var preset: Dictionary = modifier_presets[preset_id]

	# Refresh if already active
	for mod in active_modifiers:
		if mod.get("presetId", "") == preset_id:
			var dur: float = preset.get("duration", 0.0) / 1000.0
			mod["remainingDuration"] = dur
			return

	var dur: float = preset.get("duration", 0.0) / 1000.0
	active_modifiers.append({
		"presetId": preset_id,
		"needType": preset.get("needType", ""),
		"rateMultiplier": preset.get("rateMultiplier", 1.0),
		"remainingDuration": dur,
		"isPermanent": dur <= 0.0,
	})
	modifier_applied.emit(preset_id, preset.get("needType", ""))

func remove_modifier(preset_id: String) -> void:
	for i in range(active_modifiers.size()):
		if active_modifiers[i].get("presetId", "") == preset_id:
			var mod: Dictionary = active_modifiers[i]
			modifier_expired.emit(preset_id, mod.get("needType", ""))
			active_modifiers.remove_at(i)
			return

func get_active_modifiers() -> Array[Dictionary]:
	return active_modifiers
