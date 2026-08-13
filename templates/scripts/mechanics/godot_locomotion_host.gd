extends Node
## `ILocomotionHost` for Godot — `NavigationAgent3D` driving a `CharacterBody3D`
## (tasklist 147, US-1).
##
## Core has already decided the movement is afforded, permitted and paid for. All
## that is left is the part only an engine can do: the path, the speed, the
## animation, the character controller — none of which crosses the boundary. What
## crosses is one order in and one arrival out, and the arrival names a LOCATION
## ATOM, never a coordinate.
##
## ## The one hard problem, and the answer
##
## `ILocomotionHost.travel` returns an `ArrivalReport` that core reads
## immediately, and a walk takes seconds. Across `insimul_core_call` there is no
## awaiting a host at all, so the answer has to be decided at the moment of the
## call. Unity's probe landed on this first (its RUNTIME_CORE_ADOPTION.md §12.2
## finding 3) and this is the same answer for the same reason:
##
##   * what the host ALREADY KNOWS is reported immediately — a missing body, an
##     unknown destination or a `NavigationServer3D` path that stops short is
##     `arrived: false` right there, with a reason;
##   * anything else dispatches the agent and reports `arrived: true`, so world
##     state moves at the decision moment and the body catches up.
##
## The alternative — reporting `arrived: false` for every movement that takes
## time — would make `LocomotionDirector` count a successful walk as a failure and
## re-plan against a wall that is not there.
##
## A game that wants the strict answer passes the reading in ahead of the call
## instead: `traversal.traverse`'s `arrival` argument is read by core BEFORE the
## order goes out, and a host that already knows the body cannot get there says so
## there (see [method arrival_reading]).

## Atom -> body, and place atom -> where that place is.
var registry: InsimulActorRegistry = null

## How the four `MovementUrgency` rungs become speeds, in scene units per second.
## THIS TABLE IS THE WHOLE OF WHAT AN ENGINE ADDS: core resolves *how pressing*
## the movement is from the goal's own priority and says `hurried`; what a hurried
## walk looks like is this engine's answer and three others disagree, correctly.
@export var speed_idle := 1.2
@export var speed_ordinary := 2.2
@export var speed_hurried := 3.6
@export var speed_urgent := 5.5

## How close counts as arrived, in scene units. Passed to the agent.
@export var arrival_distance := 1.0

## Emitted when an order is dispatched, so a game can drive its own animation
## graph from the intent core supplied. `stance` and `urgency` are atoms out of
## closed vocabularies — never a pose, never a speed.
signal movement_ordered(actor_id: String, destination: String, urgency: String, stance: String)
## Emitted when a body actually reaches where it was sent, which is a FRAME
## concern and therefore this side of the boundary entirely.
signal movement_finished(actor_id: String, destination: String)

## actor atom -> { agent, destination, place }
var _in_flight := {}


## The `ILocomotionHost` to wire into a traversal or routine session.
func host() -> InsimulMechanicHosts.LocomotionHost:
	return _LocomotionHost.new(self)


## Carry out one order. See the class header for what `arrived` means here.
func travel(order: Dictionary) -> Dictionary:
	var actor_id := String(order.get("actor", ""))
	var destination := String(order.get("to", ""))
	var body := registry.actor(actor_id) if registry != null else null
	if body == null:
		return {"arrived": false, "reason": "no body for %s in this scene" % actor_id}

	var target := registry.place_position(destination)
	if target == Vector3.INF:
		return {"arrived": false, "reason": "unknown place %s" % destination}

	var agent := _agent_for(body)
	if agent == null:
		# No navigation in this scene: put the body where core says it is. A world
		# that moves without animating is a legitimate world (a strategy map, a
		# text layer, a test scene), and it is better than refusing to move.
		body.global_position = target
		movement_ordered.emit(actor_id, destination, String(order.get("urgency", "ordinary")), String(order.get("stance", "standing")))
		movement_finished.emit(actor_id, destination)
		return {"arrived": true, "location": destination}

	agent.target_position = target
	agent.target_desired_distance = arrival_distance
	if not agent.navigation_finished.is_connected(_on_navigation_finished):
		agent.navigation_finished.connect(_on_navigation_finished.bind(actor_id))
	if not agent.is_target_reachable():
		return {
			"arrived": false,
			"reason": "no path from %s to %s" % [String(order.get("from", "")), destination],
		}

	_in_flight[actor_id] = {
		"agent": agent,
		"destination": destination,
		"speed": speed_for(String(order.get("urgency", "ordinary"))),
		"vehicle": String(order.get("vehicle", "")),
	}
	movement_ordered.emit(
		actor_id,
		destination,
		String(order.get("urgency", "ordinary")),
		String(order.get("stance", "standing"))
	)
	# The body is on its way; world state moves now. See the class header.
	return {"arrived": true, "location": destination}


## What the host already knows about whether this actor can get to that place,
## in the shape `traversal.traverse` takes as its `arrival` argument.
##
## THIS IS THE STRICT PATH, and it is the one a game should prefer for anything
## that matters: it is read by core BEFORE the movement is ordered, so a body that
## cannot get there never spends the meter. Cheap enough to call per attempted
## movement, and not cheap enough to call per frame.
func arrival_reading(actor_id: String, destination: String) -> Dictionary:
	var body := registry.actor(actor_id) if registry != null else null
	if body == null:
		return {"arrived": false, "reason": "no body for %s in this scene" % actor_id}
	var target := registry.place_position(destination)
	if target == Vector3.INF:
		return {"arrived": false, "reason": "unknown place %s" % destination}
	var agent := _agent_for(body)
	if agent == null:
		return {"arrived": true}
	agent.target_position = target
	return (
		{"arrived": true}
		if agent.is_target_reachable()
		else {"arrived": false, "reason": "no path to %s" % destination}
	)


## The speed one urgency rung means IN THIS ENGINE. Public because a game's own
## controller wants the same answer for its own movement.
func speed_for(urgency: String) -> float:
	match urgency:
		"idle":
			return speed_idle
		"hurried":
			return speed_hurried
		"urgent":
			return speed_urgent
	return speed_ordinary


## Drive whatever is in flight. A game with its own character controller ignores
## this and reads [signal movement_ordered] instead.
##
## THE FRAME LOOP IS ENTIRELY THIS SIDE OF THE BOUNDARY: core is never told a
## frame happened, and nothing below reports anything to it.
func _physics_process(_delta: float) -> void:
	for actor_id in _in_flight.keys():
		var flight: Dictionary = _in_flight[actor_id]
		var agent: NavigationAgent3D = flight["agent"]
		if not is_instance_valid(agent) or agent.is_navigation_finished():
			continue
		var body := agent.get_parent() as CharacterBody3D
		if body == null:
			continue
		var next := agent.get_next_path_position()
		var direction := (next - body.global_position).normalized()
		body.velocity = direction * float(flight["speed"])
		body.move_and_slide()


func _agent_for(body: Node3D) -> NavigationAgent3D:
	for child in body.get_children():
		if child is NavigationAgent3D:
			return child
	return null


func _on_navigation_finished(actor_id: String) -> void:
	if not _in_flight.has(actor_id):
		return
	var destination := String(_in_flight[actor_id]["destination"])
	_in_flight.erase(actor_id)
	movement_finished.emit(actor_id, destination)


class _LocomotionHost extends InsimulMechanicHosts.LocomotionHost:
	var _node: Node = null

	func _init(node: Node) -> void:
		_node = node

	func travel(order: Dictionary) -> Dictionary:
		return _node.travel(order)
