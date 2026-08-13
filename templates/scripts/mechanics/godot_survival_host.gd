extends Node
## `ISurvivalSystem` for Godot — tasklist 147, US-1.
##
## The `stamina` module's host interface. Core decides what an action costs
## (`action/4`'s `EnergyCost`, authored in `WorldIR.survival.staminaConfig`),
## whether the actor can pay for it and which band that leaves them in
## (`winded/1`, `exhausted/1`), and hands the AMOUNT here. An adapter must not
## price actions itself, for the same reason it must not roll its own damage.
##
## ## It forwards, it does not duplicate
##
## This template already ships `survival_system.gd`, an autoloaded singleton with
## needs, thresholds, modifier presets and its own `_process` clock. That system
## is the game's, it stays the game's, and this component is a thin forwarder onto
## it — because the meter a player SEES and the meter core CHARGES have to be one
## meter or the HUD lies.
##
## ## Two honest edges
##
## 1. `update(delta)` is a NO-OP here. `survival_system.gd` owns the clock and
##    ticks itself from `_process`; ticking it a second time from core's side
##    would decay hunger at twice the rate. Core never calls it — the method
##    exists on the interface because a host that does NOT have its own clock
##    needs somewhere to be driven from.
## 2. `add_modifier` forwards `modifier.id` as an authored PRESET id.
##    `survival_system.gd` applies modifiers by preset, so a modifier core invents
##    at runtime with no authored preset behind it cannot be applied — that case
##    is warned about rather than silently dropped.

## The autoloaded `survival_system.gd`, or any node with the same members.
## Resolved from the `SurvivalSystem` autoload when left empty.
@export var survival_path: NodePath

## Whose meter this is. `ISurvivalSystem` takes no actor argument — it is the
## host's meter for the entity the host owns — so a stamina session forwards only
## this actor's spends (`survivalActorId` in `stamina.create`).
@export var actor_id := "player"

## Emitted with an amount CORE decided, for a stamina bar or an exhaustion
## animation. Never a control input.
signal stamina_consumed(amount: float)
signal stamina_recovered(amount: float)

var _survival: Node = null
var _warned_presets := {}


## The `ISurvivalSystem` to wire into a stamina session.
func survival_system() -> InsimulMechanicHosts.SurvivalSystem:
	return _SurvivalSystem.new(self)


## Deliberately a no-op — see the class header, edge 1.
func update(_delta: float) -> void:
	pass


func restore_need(need_type: String, amount: float) -> void:
	var survival := _resolve()
	if survival != null:
		survival.restore_need(need_type, amount)


## Spend what core decided. The boolean is whether the HOST's own meter covered
## it; core has already decided the spend was affordable against its own, so a
## `false` here means the two have drifted and the game should say so rather than
## quietly refuse.
func consume_stamina(amount: float) -> bool:
	var survival := _resolve()
	stamina_consumed.emit(amount)
	if survival == null:
		return true
	var covered: bool = survival.consume_stamina(amount)
	if not covered:
		push_warning(
			"[Insimul] survival host: core charged %.1f stamina the host's meter could not cover — the two have drifted"
			% amount
		)
	return covered


func recover_stamina(amount: float) -> void:
	var survival := _resolve()
	stamina_recovered.emit(amount)
	if survival != null:
		survival.restore_need("stamina", amount)


func set_temperature(value: float) -> void:
	var survival := _resolve()
	if survival != null:
		survival.set_environment_temperature(value)


## `modifier.id` names an AUTHORED preset. See the class header, edge 2.
func add_modifier(modifier: Dictionary) -> void:
	var survival := _resolve()
	if survival == null:
		return
	var preset_id := String(modifier.get("id", ""))
	var presets: Variant = survival.get("modifier_presets")
	if presets is Dictionary and (presets as Dictionary).has(preset_id):
		survival.apply_modifier(preset_id)
		return
	if not _warned_presets.has(preset_id):
		_warned_presets[preset_id] = true
		push_warning(
			"[Insimul] survival host: no authored modifier preset '%s' — the modifier was NOT applied"
			% preset_id
		)


func remove_modifier(modifier_id: String) -> void:
	var survival := _resolve()
	if survival != null and survival.has_method("remove_modifier"):
		survival.remove_modifier(modifier_id)


func get_need(need_type: String) -> Dictionary:
	var survival := _resolve()
	if survival == null:
		return {}
	return {
		"needType": need_type,
		"value": survival.get_need_value(need_type),
		"percent": survival.get_need_percent(need_type),
	}


func get_all_needs() -> Array:
	var survival := _resolve()
	return survival.get_all_needs() if survival != null else []


func get_need_percent(need_type: String) -> float:
	var survival := _resolve()
	return survival.get_need_percent(need_type) if survival != null else 0.0


func _resolve() -> Node:
	if _survival != null and is_instance_valid(_survival):
		return _survival
	if not survival_path.is_empty():
		_survival = get_node_or_null(survival_path)
	if _survival == null:
		_survival = get_node_or_null("/root/SurvivalSystem")
	return _survival


class _SurvivalSystem extends InsimulMechanicHosts.SurvivalSystem:
	var _node: Node = null

	func _init(node: Node) -> void:
		_node = node

	func update(delta: float) -> void:
		_node.update(delta)

	func restore_need(need_type: String, amount: float) -> void:
		_node.restore_need(need_type, amount)

	func consume_stamina(amount: float) -> bool:
		return _node.consume_stamina(amount)

	func recover_stamina(amount: float) -> void:
		_node.recover_stamina(amount)

	func set_temperature(value: float) -> void:
		_node.set_temperature(value)

	func add_modifier(modifier: Dictionary) -> void:
		_node.add_modifier(modifier)

	func remove_modifier(modifier_id: String) -> void:
		_node.remove_modifier(modifier_id)

	func get_need(need_type: String) -> Dictionary:
		return _node.get_need(need_type)

	func get_all_needs() -> Array:
		return _node.get_all_needs()

	func get_need_percent(need_type: String) -> float:
		return _node.get_need_percent(need_type)
