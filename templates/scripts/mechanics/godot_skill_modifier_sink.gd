extends Node
## `ISkillModifierSink` for Godot — tasklist 147, US-1.
##
## The narrowest interface in the band, and the last one core added, because it is
## what was left over after everything else had an owner. A
## `skill_node_effect(N, modifies(Param, Amount))` is applied by whoever owns the
## field it names: core wired every parameter core owns, and what remained were
## the parameters only an ENGINE holds — how fast a body moves, how far it
## reaches, how much it can carry before the animation changes. Those reached
## nobody in any engine before this.
##
## ## Told, never asked
##
## Core hands the whole current set, not a delta, computed as integer sums over
## the nodes an actor has taken. So:
##
##   * applying the same totals twice must be a no-op — and is, because every
##     parameter below is written as `base * (1 + total/100)` or `base + total`
##     against a BASE captured once, never against the current value;
##   * a parameter this engine does not recognise is IGNORED, not an error. The
##     parameter set is open and most of what arrives belongs to somebody else.
##
## ## The one gap, stated where a reader will hit it
##
## `carry_capacity` LANDS NOWHERE. `inventory_system.gd` limits an inventory by
## `max_slots` and has no weight capacity at all, so applying a carry-capacity
## modifier would mean inventing a limit no rule in this template reads. It is
## RECORDED (see [method unapplied]) and announced once, not silently dropped and
## not silently invented. The same gap Unity's probe found, for the same reason:
## the parameter names a quantity the engine is supposed to hold and this engine
## does not hold it yet.

## Parameters this engine can actually apply, and what each one does. The keys are
## the WORLD's spelling — `skill_node_effect(N, modifies(move_speed, 2))` — never
## a GDScript field name, because the host is the thing that knows which of its
## own quantities `move_speed` names.
const APPLIED_PARAMS := ["move_speed", "jump_height", "reach"]

## Parameters that arrive with nowhere to go in this template. Named rather than
## ignored so the gap is visible to whoever adds the field.
const UNAPPLIED_PARAMS := ["carry_capacity"]

## Atom -> body, so `nessa`'s modifiers reach `nessa`'s controller.
var registry: InsimulActorRegistry = null

## Emitted after a set is applied, for a character sheet.
signal modifiers_applied(actor_id: String, modifiers: Dictionary)

## actor -> { param: base value }, captured the first time a parameter is touched
## so re-applying is idempotent.
var _bases := {}
## actor -> { param: amount } for everything that had nowhere to go.
var _unapplied := {}
var _warned := {}


## The `ISkillModifierSink` to wire into a skill session.
func sink() -> InsimulMechanicHosts.SkillModifierSink:
	return _SkillModifierSink.new(self)


## Apply this actor's WHOLE current modifier set.
func apply_modifiers(actor_id: String, modifiers: Dictionary) -> void:
	var body := registry.actor(actor_id) if registry != null else null
	var unapplied := {}
	for key in modifiers.keys():
		var param := String(key)
		var amount := float(modifiers[key])
		if UNAPPLIED_PARAMS.has(param):
			unapplied[param] = amount
			_warn_once(
				param,
				"[Insimul] skill modifier '%s' (%+.0f) has nowhere to land in this template — inventory_system.gd limits by slots, not weight. Recorded, not applied."
				% [param, amount]
			)
			continue
		if not APPLIED_PARAMS.has(param):
			# Not ours. `withSkillModifiers` ignores a parameter that names no
			# field it owns, and so does this — silently, because most of an open
			# parameter set belongs to somebody else.
			continue
		if body == null:
			unapplied[param] = amount
			continue
		var landed := _apply_one(actor_id, body, param, amount)
		if not landed:
			unapplied[param] = amount
	_unapplied[actor_id] = unapplied
	modifiers_applied.emit(actor_id, modifiers.duplicate())


## What arrived for this actor and could not be applied, and why it matters:
## a game showing a skill tree should not show a node as taken-and-active when its
## effect reached nothing.
func unapplied(actor_id: String) -> Dictionary:
	return (_unapplied.get(actor_id, {}) as Dictionary).duplicate()


## True when the parameter actually landed on a field this body has.
func _apply_one(actor_id: String, body: Node3D, param: String, amount: float) -> bool:
	var field := _field_for(param)
	if field.is_empty() or body.get(field) == null:
		return false
	var base := _base_for(actor_id, param, float(body.get(field)))
	# PERCENTAGE, because that is what an authored `modifies(move_speed, 10)`
	# means in every world that ships with core — 10 is "ten percent faster", not
	# "ten metres per second faster", which would be an engine-scale number in
	# authored content. Absolute rather than accumulated: applying twice is the
	# same as applying once.
	body.set(field, base * (1.0 + amount / 100.0))
	return true


func _field_for(param: String) -> String:
	match param:
		"move_speed":
			return "move_speed"
		"jump_height":
			return "jump_height"
		"reach":
			return "interact_range"
	return ""


func _base_for(actor_id: String, param: String, current: float) -> float:
	if not _bases.has(actor_id):
		_bases[actor_id] = {}
	var bases: Dictionary = _bases[actor_id]
	if not bases.has(param):
		bases[param] = current
	return float(bases[param])


func _warn_once(key: String, message: String) -> void:
	if _warned.has(key):
		return
	_warned[key] = true
	push_warning(message)


class _SkillModifierSink extends InsimulMechanicHosts.SkillModifierSink:
	var _node: Node = null

	func _init(node: Node) -> void:
		_node = node

	func apply_modifiers(actor_id: String, modifiers: Dictionary) -> void:
		_node.apply_modifiers(actor_id, modifiers)
