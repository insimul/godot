class_name InsimulMechanicHosts
extends RefCounted
## The EIGHT host interfaces the band-120 mechanic modules declare, as Godot
## base classes — tasklist 147, US-1.
##
## Core's `module-contract.ts` says a module is six parts, and part 4 is *the
## host interface that executes its decisions*. Seven modules (combat, stamina,
## perception, traversal, skill, equipment, routine) name eight distinct
## interfaces between them, and this file is all eight, in one place, with the
## fallback each one documents implemented ONCE.
##
## ## Why base classes rather than a convention
##
## GDScript has no `interface`, so the alternative was a documented set of method
## names a game is expected to spell correctly. That is how a plugin's P/Invoke
## table rots. Extending these gets a class the default behaviour core documents
## for a MISSING host, which is never "nothing happens":
##
## | interface | no host means | so the default here is |
## | --- | --- | --- |
## | `ITrajectoryProbe` | a world with no geometry resolves on reach and accuracy | `clear` |
## | `IPerceptionProbe` | the caller hands readings to `observe` directly | no reading |
## | `ITraversalProbe` | a geometric link with no answer is usable | `passable` |
## | `ILocomotionHost` | world state moves, nothing is animated | `arrived` |
## | `ISkillModifierSink` | every effect core owns still applies | ignored |
## | `ICombatStatSink` | equipment is tracked, stats are not applied | no base stats |
## | `ICombatSystem` | decisions are made, nothing is executed | recorded, not drawn |
## | `ISurvivalSystem` | the meter moves in core only | recorded, not drawn |
##
## Those are core's own words, not this plugin's policy, and implementing them
## here rather than in each of four engines is the point: a fallback guessed
## independently four times is four different games.
##
## ## What an implementation may and may not do
##
## A probe ANSWERS a question about this engine's geometry. A sink is TOLD a
## number core already decided. Neither may recompute a mechanic: a host that
## rolls its own damage, prices its own action or invents its own suspicion level
## has forked the module, and the same save then means two things
## (`docs/module-contract.md` §3). `gdextension/test/test_mechanic_bridge.cpp`
## pins the boundary from the other side — a host that answered `clear` to every
## shot cannot change one number of a resolution.
##
## ## Where the engine-specific ones live
##
## `templates/scripts/mechanics/` — the exported GAME, because a raycast needs a
## `PhysicsDirectSpaceState3D` and a walk needs a `NavigationAgent3D`, and the SDK
## addon has neither. What lives here is the contract and the fallback; what
## lives there is Godot.


## `ICombatSystem` — the `combat` module's host interface.
##
## Core calls exactly three of these members (`CombatResolver`): `register_entity`
## when a combatant joins, `unregister_entity` when one dies or leaves, and
## `apply_damage` with a number it resolved deterministically from (attacker,
## defender, action, tuning, separation, seed, tick). The rest are the host's own
## surface, for a game's UI and its own code.
##
## AN ADAPTER MUST NOT ROLL ITS OWN DAMAGE. `execute_attack()` exists because
## engines have always had it; core never calls it, and the default below refuses
## rather than rolling, because a second damage pipeline is exactly the drift the
## whole unification program exists to stop.
class CombatSystem extends RefCounted:
	## Register an entity that can participate in combat.
	## `entity` is core's `CombatEntityData`: { id, name, health, maxHealth, damage? }.
	func register_entity(_entity: Dictionary) -> void:
		pass

	## Unregister an entity (death, despawn, scene change).
	func unregister_entity(_entity_id: String) -> void:
		pass

	## Apply damage CORE computed. No mitigation, no rounding, no second roll.
	func apply_damage(_entity_id: String, _damage: float) -> void:
		pass

	## Deliberately unimplemented, and loudly. Core never calls it; a host that
	## drove its own attacks would be deciding. Returns {} rather than a plausible
	## damage result so a caller cannot mistake silence for a swing.
	func execute_attack(attacker_id: String, target_id: String) -> Dictionary:
		push_warning(
			"[Insimul] CombatSystem.execute_attack(%s -> %s) is not implemented: attacks are resolved by core's CombatResolver (combat.attack). See addons/insimul/runtime/mechanics/insimul_mechanic_hosts.gd."
			% [attacker_id, target_id]
		)
		return {}

	func is_combat_enabled() -> bool:
		return true

	func get_health(_entity_id: String) -> float:
		return 0.0

	func heal(_entity_id: String, _amount: float) -> void:
		pass

	func dispose() -> void:
		pass


## `ICombatStatSink` — the `equipment` module's host interface, and the only one
## that runs in BOTH directions: core reads an entity's unmodified stats once,
## then writes equipment-adjusted totals back whenever the loadout changes.
##
## The totals are ABSOLUTE, not deltas, and re-applying the same ones twice must
## be a no-op.
class CombatStatSink extends RefCounted:
	## { attackPower, defense, dodgeChance }, or {} when the entity is not in combat.
	func get_base_stats(_entity_id: String) -> Dictionary:
		return {}

	func apply_stats(_entity_id: String, _stats: Dictionary) -> void:
		pass


## `ISurvivalSystem` — the `stamina` module's host interface.
##
## Core decides what an action costs (`action/4`'s `EnergyCost`), whether the
## actor can pay and which band that leaves them in, then hands the AMOUNT here.
## An adapter must not price actions itself.
##
## The needs CLOCK stays entirely the host's: `update()` is the game ticking its
## own system, never core requiring a per-frame call.
class SurvivalSystem extends RefCounted:
	func update(_delta: float) -> void:
		pass

	func restore_need(_need_type: String, _amount: float) -> void:
		pass

	## Spend stamina core already decided was affordable. Returns whether the
	## host's own meter covered it.
	func consume_stamina(_amount: float) -> bool:
		return true

	func recover_stamina(_amount: float) -> void:
		pass

	func set_temperature(_value: float) -> void:
		pass

	func add_modifier(_modifier: Dictionary) -> void:
		pass

	func remove_modifier(_modifier_id: String) -> void:
		pass

	## { needType, value, maxValue, ... } or {} when the need is not tracked.
	func get_need(_need_type: String) -> Dictionary:
		return {}

	func get_all_needs() -> Array:
		return []

	func get_need_percent(_need_type: String) -> float:
		return 0.0

	func is_any_critical() -> bool:
		return false

	func is_any_warning() -> bool:
		return false

	func set_enabled(_enabled: bool) -> void:
		pass

	func is_enabled() -> bool:
		return true

	## The three callbacks the interface declares are the GAME's, not core's: core
	## never registers one, and a Godot game would rather have a signal. They are
	## here because the contract has them and a member core declares that this
	## plugin does not is how a binding table rots — a concrete host wires them to
	## its own signals, or ignores them.
	func set_on_need_changed(_callback: Callable) -> void:
		pass

	func set_on_survival_event(_callback: Callable) -> void:
		pass

	func set_on_damage_from_need(_callback: Callable) -> void:
		pass

	func dispose() -> void:
		pass


## `ITrajectoryProbe` — the `combat` module's second host interface, and the ONLY
## thing an engine must supply for ranged combat: **is the line to that target
## clear, and how far away is it.**
##
## Asked once per ranged attack, on the decision path, never on a frame path.
## What the shot costs, whether it is permitted, whether it is in reach and what
## it does on arrival all stay in core.
class TrajectoryProbe extends RefCounted:
	## `query`: { attacker, target, action, range? }
	## returns: { clear: bool, separation?: float, blockedBy?: String }
	func query(_query: Dictionary) -> Dictionary:
		# A world with no geometry — a turn-based fight, a headless simulation —
		# resolves a ranged attack on reach and accuracy alone. Core's documented
		# fallback, and the reason a missing probe does not block every shot.
		return {"clear": true}


## `IPerceptionProbe` — the `perception` module's host interface: **what can this
## observer's senses reach of that target, right now.**
##
## A detection tick is NOT a frame: core asks when it is deciding, at whatever
## cadence the host drives `perception.observe`. What a reading is WORTH — how
## much darkness hides, what crouching buys, how fast suspicion builds — is
## authored in `WorldIR.perception` and decided in core.
class PerceptionProbe extends RefCounted:
	## `query`: { observer, target, tick }
	## returns: { visibility, cover?, audibility?, light?, stance?, noise? } or {}
	func sense(_query: Dictionary) -> Dictionary:
		# Empty is "sensed nothing", which is a real answer and not an error. A
		# host's geometry failing must not stop the rules layer from ticking.
		return {}


## `ITraversalProbe` — the `traversal` module's first host interface: **could this
## actor actually get across that, from where they are standing.**
##
## Asked only for links a world marked `geometric` — a gap that may not be
## jumpable from here, a door whose state the scene owns. The rest of the authored
## graph is settled in core without the host being disturbed.
class TraversalProbe extends RefCounted:
	## `query`: { actor, from, to, mode, link }
	## returns: { passable: bool, distance?: float, blockedBy?: String }
	func query(_query: Dictionary) -> Dictionary:
		# A geometric link with no answer is passable — what a turn-based world, a
		# headless simulation and the conformance corpus all rely on.
		return {"passable": true}


## `ILocomotionHost` — the `traversal` module's second host interface and the
## `routine` module's only one. It runs the other way from a probe: core has
## already decided the movement is afforded, permitted and paid for, and this
## carries it out.
##
## THE ASYMMETRY IS THE POINT. Locomotion is the most per-frame thing in a game —
## a path, a character controller, a root-motion animation, a crowd agent — and
## none of it crosses the boundary. What crosses is one order in and one arrival
## out, and the arrival's `location` is a location atom, never a coordinate.
##
## `arrived == false` is an ANSWER, not an error: a `NavigationAgent3D` that could
## not reach the target, a ledge that gave way, a door that closed between the
## decision and the frame. Core counts it and eventually re-plans against it.
class LocomotionHost extends RefCounted:
	## `order`: { actor, from, to, mode, link, cost, action, urgency, stance, vehicle? }
	## returns: { arrived: bool, location?: String, reason?: String }
	func travel(_order: Dictionary) -> Dictionary:
		# No host means world state moves and nothing is animated — core's own
		# no-host behaviour.
		return {"arrived": true}


## `ISkillModifierSink` — the `skill` module's host interface, and the narrowest
## one in this file on purpose.
##
## Drawing a skill tree is NOT an interface: what a host renders from is the VALUE
## core returns. What is left over is one thing — a `modifies(Param, Amount)`
## effect whose parameter names a quantity only the engine holds (how fast a body
## moves, how far it reaches, how much it can carry).
##
## Told, never asked. Absolute totals, never deltas. Once per change to an actor's
## taken nodes, never on a frame. A parameter the host does not recognise is
## IGNORED — the parameter set is open and most of what arrives belongs to
## somebody else.
class SkillModifierSink extends RefCounted:
	## `modifiers`: { "<authored param atom>": <number>, ... } — the whole set.
	func apply_modifiers(_actor_id: String, _modifiers: Dictionary) -> void:
		pass


## `IAgentActionHost` — the `agentAi` module's host interface.
##
## NOT a band-120 module and NOT adopted by this tasklist: no `agent.*` row exists
## in `gdextension/corebridge/js/entry.js`, so nothing in this plugin can call it
## yet. It is declared here because the adapter carries the matching shim and a
## contract stated in one place is what stops the ninth interface being invented
## differently when `AgentPlanner` is adopted.
class AgentActionHost extends RefCounted:
	## `order`: { agent, action, target, tick, animation, utility, goal?, step? }
	func perform(_order: Dictionary) -> void:
		pass


## Every interface name, in the spelling core's manifest uses. The gate
## (`tools/verify-mechanics/check-mechanics.mjs`) reads this list, so a class
## added here without a manifest entry — or a manifest entry with no class — is a
## red gate rather than a silent gap.
const INTERFACES := [
	"ICombatSystem",
	"ICombatStatSink",
	"ISurvivalSystem",
	"ITrajectoryProbe",
	"IPerceptionProbe",
	"ITraversalProbe",
	"ILocomotionHost",
	"ISkillModifierSink",
	"IAgentActionHost",
]


## The Godot class implementing one interface, or null. One lookup rather than a
## match statement in every caller.
static func default_host(interface_name: String) -> RefCounted:
	match interface_name:
		"ICombatSystem":
			return CombatSystem.new()
		"ICombatStatSink":
			return CombatStatSink.new()
		"ISurvivalSystem":
			return SurvivalSystem.new()
		"ITrajectoryProbe":
			return TrajectoryProbe.new()
		"IPerceptionProbe":
			return PerceptionProbe.new()
		"ITraversalProbe":
			return TraversalProbe.new()
		"ILocomotionHost":
			return LocomotionHost.new()
		"ISkillModifierSink":
			return SkillModifierSink.new()
		"IAgentActionHost":
			return AgentActionHost.new()
	return null
