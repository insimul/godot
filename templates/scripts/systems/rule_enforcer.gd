extends Node
## Rule Enforcer — autoloaded singleton.
## Evaluates and enforces game rules with item condition support.

signal violation_recorded(violation: Dictionary)
signal restriction_applied(rule_name: String, message: String)

var rules: Array[Dictionary] = []
var _prolog_content: String = ""
var has_prolog_kb: bool = false
var _settlement_zones: Array[Dictionary] = []
var _violations: Array[Dictionary] = []

func load_from_data(world_data: Dictionary) -> void:
	var systems: Dictionary = world_data.get("systems", {})
	rules.append_array(systems.get("rules", []))
	rules.append_array(systems.get("baseRules", []))
	print("[Insimul] RuleEnforcer loaded %d rules" % rules.size())

func evaluate_rules(context: Dictionary) -> Array[String]:
	var violations: Array[String] = []
	for rule in rules:
		if not rule.get("isActive", true):
			continue
		var rule_type: String = rule.get("ruleType", "")
		if rule_type != "trigger" and rule_type != "volition":
			continue
		if _check_rule_conditions(rule, context):
			var restriction := _find_restriction(rule, context.get("actionType", ""))
			if restriction.size() > 0:
				var msg: String = restriction.get("message", "")
				if msg.is_empty():
					msg = "Action violates rule: %s" % rule.get("name", rule.get("id", ""))
				violations.append(msg)
	return violations

## Check if an action is allowed, consulting Prolog KB when available.
## Mirrors RuleEnforcer.canPerformActionAsync from the Babylon.js source.
func can_perform_action(action_id: String, action_type: String, context: Dictionary) -> bool:
	if has_prolog_kb:
		print("[Insimul] Consulting Prolog KB for action %s" % action_id)
	var ctx := context.duplicate()
	ctx["actionId"] = action_id
	ctx["actionType"] = action_type
	var violations := evaluate_rules(ctx)
	return violations.is_empty()

## Attach a Prolog knowledge base string for logic-based rule evaluation.
## The KB content is stored and used for quest condition checks (quest_complete,
## quest_available, quest_cefr_level) via lightweight string search rather than
## requiring a full Prolog interpreter in the export.
func set_prolog_knowledge_base(prolog_content: String) -> void:
	_prolog_content = prolog_content
	has_prolog_kb = not prolog_content.is_empty()
	print("[Insimul] Prolog KB %s (%d chars)" % ["attached" if has_prolog_kb else "cleared", prolog_content.length()])

# --- Settlement zone registration ---

## Register a settlement zone for spatial in-settlement checks.
func register_settlement_zone(settlement_id: String, position: Vector3, radius: float) -> void:
	_settlement_zones.append({
		"settlement_id": settlement_id,
		"position": position,
		"radius": radius
	})
	print("[Insimul] Registered settlement zone '%s' at %s radius %.1f" % [settlement_id, str(position), radius])

## Check if a position is within any registered settlement zone.
## Returns { "in_settlement": bool, "settlement_id": String }
func is_in_settlement(position: Vector3) -> Dictionary:
	for zone in _settlement_zones:
		var distance: float = position.distance_to(zone["position"])
		if distance <= zone["radius"]:
			return { "in_settlement": true, "settlement_id": zone["settlement_id"] }
	return { "in_settlement": false, "settlement_id": "" }

# --- Violation tracking ---

## Record a rule violation.
func record_violation(rule_id: String, rule_name: String, severity: String, message: String) -> void:
	var violation := {
		"rule_id": rule_id,
		"rule_name": rule_name,
		"timestamp": Time.get_ticks_msec() / 1000.0,
		"severity": severity,
		"message": message
	}
	_violations.append(violation)
	print("[Insimul] Violation recorded: %s — %s" % [rule_name, message])
	violation_recorded.emit(violation)

## Get recent violations (up to limit).
func get_violations(limit: int = 10) -> Array[Dictionary]:
	if limit <= 0 or limit >= _violations.size():
		return _violations.duplicate()
	return _violations.slice(_violations.size() - limit)

## Clear all recorded violations.
func clear_violations() -> void:
	_violations.clear()
	print("[Insimul] Violations cleared")

# --- Condition evaluation ---

func _check_rule_conditions(rule: Dictionary, context: Dictionary) -> bool:
	var conditions: Array = rule.get("conditions", [])
	if conditions.is_empty():
		return true
	for cond in conditions:
		if not _evaluate_condition(cond, context):
			return false
	return true

func _evaluate_condition(condition: Dictionary, context: Dictionary) -> bool:
	var type: String = condition.get("type", "")
	match type:
		"location": return _check_location_condition(condition, context)
		"zone": return _check_zone_condition(condition, context)
		"action": return _check_action_condition(condition, context)
		"energy": return _check_energy_condition(condition, context)
		"proximity": return context.get("nearNPC", false)
		"tag": return true
		"has_item": return _check_has_item_condition(condition, context)
		"item_count": return _check_item_count_condition(condition, context)
		"item_type": return _check_item_type_condition(condition, context)
		"quest_complete": return _check_quest_complete_condition(condition, context)
		"quest_available": return _check_quest_available_condition(condition, context)
		"cefr_level": return _check_cefr_level_condition(condition, context)
		_: return true

func _check_location_condition(condition: Dictionary, context: Dictionary) -> bool:
	var loc: String = condition.get("location", "")
	if loc == "settlement":
		return context.get("inSettlement", false)
	if loc == "wilderness":
		return not context.get("inSettlement", false)
	return true

func _check_zone_condition(condition: Dictionary, context: Dictionary) -> bool:
	var zone: String = condition.get("zone", "")
	if zone == "safe" or zone == "settlement":
		return context.get("inSettlement", false)
	if zone == "combat" or zone == "wilderness":
		return not context.get("inSettlement", false)
	return true

func _check_action_condition(condition: Dictionary, context: Dictionary) -> bool:
	var action: String = condition.get("action", "")
	if not action.is_empty():
		return context.get("actionType", "") == action or context.get("actionId", "") == action
	return true

func _check_energy_condition(condition: Dictionary, context: Dictionary) -> bool:
	var energy: float = context.get("playerEnergy", -1.0)
	if energy < 0.0:
		return true
	var op: String = condition.get("operator", ">=")
	var value: float = condition.get("value", 0.0)
	return _compare_value(energy, value, op)

func _check_has_item_condition(condition: Dictionary, context: Dictionary) -> bool:
	var inventory: Array = context.get("playerInventory", [])
	if inventory.is_empty():
		return false
	var item_id: String = condition.get("itemId", "")
	var item_name: String = condition.get("itemName", "")
	for item in inventory:
		if not item_id.is_empty() and item.get("item_id", "") == item_id:
			return true
		if not item_name.is_empty() and item.get("name", "").to_lower() == item_name.to_lower():
			return true
	return false

func _check_item_count_condition(condition: Dictionary, context: Dictionary) -> bool:
	var inventory: Array = context.get("playerInventory", [])
	if inventory.is_empty():
		return false
	var item_id: String = condition.get("itemId", "")
	var item_name: String = condition.get("itemName", "")
	var qty: int = 0
	for item in inventory:
		if (not item_id.is_empty() and item.get("item_id", "") == item_id) or \
		   (not item_name.is_empty() and item.get("name", "").to_lower() == item_name.to_lower()):
			qty = item.get("count", 0)
			break
	var required: int = condition.get("quantity", 1)
	var op: String = condition.get("operator", ">=")
	return _compare_value(float(qty), float(required), op)

func _check_item_type_condition(condition: Dictionary, context: Dictionary) -> bool:
	var inventory: Array = context.get("playerInventory", [])
	var target_type: String = condition.get("itemType", "")
	if inventory.is_empty() or target_type.is_empty():
		return false
	for item in inventory:
		if str(item.get("type", "")).to_lower() == target_type.to_lower():
			return true
	return false

func _check_quest_complete_condition(condition: Dictionary, _context: Dictionary) -> bool:
	if not has_prolog_kb:
		return false
	var quest_id: String = condition.get("questId", "")
	if quest_id.is_empty():
		return false
	# Search the KB for quest_complete(player, "<questId>")
	var pattern := 'quest_complete(player, "%s")' % quest_id
	return _prolog_content.contains(pattern)

func _check_quest_available_condition(condition: Dictionary, _context: Dictionary) -> bool:
	if not has_prolog_kb:
		return false
	var quest_id: String = condition.get("questId", "")
	if quest_id.is_empty():
		return false
	# Search the KB for quest_available(player, "<questId>")
	var pattern := 'quest_available(player, "%s")' % quest_id
	return _prolog_content.contains(pattern)

func _check_cefr_level_condition(condition: Dictionary, _context: Dictionary) -> bool:
	if not has_prolog_kb:
		return false
	var quest_id: String = condition.get("questId", "")
	var cefr_level: String = condition.get("cefrLevel", "")
	if quest_id.is_empty() or cefr_level.is_empty():
		return false
	# Search the KB for quest_cefr_level("<questId>", "<level>")
	var pattern := 'quest_cefr_level("%s", "%s")' % [quest_id, cefr_level]
	return _prolog_content.contains(pattern)

func _compare_value(actual: float, expected: float, op: String) -> bool:
	match op:
		">": return actual > expected
		">=": return actual >= expected
		"<": return actual < expected
		"<=": return actual <= expected
		"==": return is_equal_approx(actual, expected)
		_: return actual >= expected

func _find_restriction(rule: Dictionary, action_type: String) -> Dictionary:
	var effects: Array = rule.get("effects", [])
	for effect in effects:
		var etype: String = effect.get("type", "")
		if etype == "restrict" or etype == "prevent" or etype == "block":
			var eaction: String = effect.get("action", "")
			if eaction.is_empty() or eaction == action_type or eaction == "all":
				return effect
	return {}

# --- Atom helpers (match ir-generator.ts sanitizeAtom / nameAtom) ---

## Convert a display name to the Prolog KB atom format used by the knowledge base.
## The KB uses human-readable atoms (e.g. "john_smith") rather than raw entity IDs.
## Use this to translate entity names when cross-referencing JSON data with KB facts.
static func sanitize_to_atom(name_str: String) -> String:
	if name_str.strip_edges().is_empty():
		return "unknown"
	var result := name_str.to_lower()
	# Replace non-alphanumeric (except underscore) with underscore
	var regex := RegEx.new()
	regex.compile("[^a-z0-9_]")
	result = regex.sub(result, "_", true)
	# Prefix leading digit
	if not result.is_empty() and result[0] >= "0" and result[0] <= "9":
		result = "_" + result
	# Collapse multiple underscores
	var multi := RegEx.new()
	multi.compile("_+")
	result = multi.sub(result, "_", true)
	# Strip leading/trailing underscores
	result = result.strip_edges().trim_prefix("_").trim_suffix("_")
	# May need multiple passes for nested underscores at edges
	while not result.is_empty() and (result.begins_with("_") or result.ends_with("_")):
		result = result.trim_prefix("_").trim_suffix("_")
	return "unknown" if result.is_empty() else result

## Convert an entity display name to a KB atom, stripping accents.
## Falls back to sanitize_to_atom(fallback_id) if name is empty.
static func name_to_atom(name_str: String, fallback_id: String = "unknown") -> String:
	if not name_str.strip_edges().is_empty():
		# Strip combining diacritical marks via NFD decomposition
		var normalized := name_str.unicode_normalize_nfd()
		var clean := ""
		for i in normalized.length():
			var ch: String = normalized[i]
			# Skip combining diacritical marks (U+0300–U+036F)
			var code := ch.unicode_at(0)
			if code < 0x0300 or code > 0x036F:
				clean += ch
		return sanitize_to_atom(clean)
	return sanitize_to_atom("unknown" if fallback_id.is_empty() else fallback_id)
