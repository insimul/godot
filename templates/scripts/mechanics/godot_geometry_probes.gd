extends Node
## The three questions core asks a GODOT scene — `ITrajectoryProbe`,
## `IPerceptionProbe` and `ITraversalProbe` (tasklist 147, US-1).
##
## All three are the same shape: core names two atoms, the engine answers in its
## own geometry, and core alone decides what follows. Nothing here computes a
## damage number, a suspicion level or a traversal cost — a probe that answered
## "perfectly visible, line clear, gap jumpable" to everything still cannot change
## one number of any resolution, and `gdextension/test/test_mechanic_bridge.cpp`
## pins that from the other side.
##
## They live in one file because they share the two things that are actually hard:
## resolving an atom to a body ([InsimulActorRegistry]) and getting a
## `PhysicsDirectSpaceState3D` to cast against.
##
## WIRING
## [codeblock]
## var probes := GodotGeometryProbes.new()          # add as a child of anything in the tree
## probes.registry = actor_registry
## probes.obstruction_mask = 1                       # world geometry layer
##
## var session := InsimulMechanicSession.open("combat", args, {
##     "ICombatSystem": combat_host,
##     "ITrajectoryProbe": probes.trajectory(),
## })
## [/codeblock]
##
## CADENCE. Every one of these is asked on a DECISION path — once per ranged
## attack, once per (observer, target) per detection tick, once per attempted
## movement — and never per frame. A game that calls them from `_process` has
## moved the boundary, not the plugin.

## Atom -> body. Without one every probe reports "no reading", which is each
## interface's documented fallback and never a made-up answer.
var registry: InsimulActorRegistry = null

## Collision layers a line of fire or a line of sight is blocked by. Defaults to
## everything; a game narrows it to its world geometry.
@export_flags_3d_physics var obstruction_mask := 0xFFFFFFF

## How far sight reaches before `visibility` decays to zero, in scene units.
## AUTHORED-ADJACENT but not authored: it is a property of the engine's scale, not
## of the world's balance, which is why it is an export here and not a field core
## reads. What darkness and distance are WORTH is `WorldIR.perception`.
@export var sight_range := 40.0

## Ambient light level reported when no sun is found, 0-100. Godot has no runtime
## per-point lightmap read, so `light` is an approximation either way — see
## `_light_level_at`.
@export var ambient_light := 45.0

## The `DirectionalLight3D` that counts as the sun for the light probe. Resolved
## from the tree on first use when left empty.
@export var sun_path: NodePath

var _sun: DirectionalLight3D = null
var _sun_resolved := false


## The `ITrajectoryProbe` for a combat session.
func trajectory() -> InsimulMechanicHosts.TrajectoryProbe:
	return _TrajectoryProbe.new(self)


## The `IPerceptionProbe` for a perception session.
func perception() -> InsimulMechanicHosts.PerceptionProbe:
	return _PerceptionProbe.new(self)


## The `ITraversalProbe` for a traversal session.
func traversal() -> InsimulMechanicHosts.TraversalProbe:
	return _TraversalProbe.new(self)


# ── the answers ──────────────────────────────────────────────────────────────

## Is the line from `attacker` to `target` clear, and how far apart are they.
##
## `blockedBy` is the name of whatever the ray hit, for display. Core carries it
## as a reason string and never reads it as a decision.
func query_trajectory(query: Dictionary) -> Dictionary:
	var from_id := String(query.get("attacker", ""))
	var to_id := String(query.get("target", ""))
	var origin := _eye_position(from_id)
	var destination := _eye_position(to_id)
	if origin == Vector3.INF or destination == Vector3.INF:
		# One of the two is not in this scene. "Clear" is the documented fallback
		# for a world with no geometry, and an unknown body is that world.
		return {"clear": true}

	var separation := origin.distance_to(destination)
	var hit := _raycast(origin, destination, [_body_rid(from_id), _body_rid(to_id)])
	if hit.is_empty():
		return {"clear": true, "separation": separation}
	return {
		"clear": false,
		"separation": separation,
		"blockedBy": _name_of(hit.get("collider")),
	}


## What `observer`'s senses reach of `target` right now: scalars, no geometry.
func sense_perception(query: Dictionary) -> Dictionary:
	var observer_id := String(query.get("observer", ""))
	var target_id := String(query.get("target", ""))
	var eye := _eye_position(observer_id)
	var mark := _eye_position(target_id)
	if eye == Vector3.INF or mark == Vector3.INF:
		return {}

	var distance := eye.distance_to(mark)
	var hit := _raycast(eye, mark, [_body_rid(observer_id), _body_rid(target_id)])
	var occluded := not hit.is_empty()
	# Distance attenuation and the occlusion test folded into ONE number in
	# [0, 1], which is exactly what `PerceptionReading.visibility` is. The curve
	# is linear because anything cleverer would be this engine deciding how much
	# distance hides, and that is authored.
	var reach := clampf(1.0 - distance / maxf(sight_range, 0.001), 0.0, 1.0)
	var reading := {
		"visibility": 0.0 if occluded else reach,
		"cover": 1.0 if occluded else 0.0,
		# Sound is not blocked by the same things sight is, so audibility keeps
		# the distance term and drops the occlusion one.
		"audibility": reach,
		"light": _light_level_at(mark),
	}
	var stance := _stance_of(target_id)
	if not stance.is_empty():
		reading["stance"] = stance
	return reading


## Could `actor` get from `from` to `to` by `mode`, from where they are standing.
##
## The navigation map answers for a walk; a jump, a climb or a swim is a straight
## reachability question the navmesh cannot answer, so those fall back to a ray
## against the world and a distance the game can bound.
func query_traversal(query: Dictionary) -> Dictionary:
	var actor_id := String(query.get("actor", ""))
	var to_id := String(query.get("to", ""))
	var mode := String(query.get("mode", "walk"))
	var origin := _ground_position(actor_id)
	var destination := registry.place_position(to_id) if registry != null else Vector3.INF
	if origin == Vector3.INF or destination == Vector3.INF:
		return {"passable": true}

	var distance := origin.distance_to(destination)
	if mode == "walk" or mode == "ride":
		var world := _world()
		if world == null:
			return {"passable": true, "distance": distance}
		var map := world.navigation_map
		var path := NavigationServer3D.map_get_path(map, origin, destination, true)
		# A path that stops short is the crowd agent telling us it cannot get
		# there. `passable: false` is an ANSWER; core decides what it means.
		if path.size() < 2 or path[path.size() - 1].distance_to(destination) > 1.5:
			return {"passable": false, "distance": distance, "blockedBy": "no_path"}
		return {"passable": true, "distance": distance}

	var hit := _raycast(origin + Vector3.UP, destination + Vector3.UP, [_body_rid(actor_id)])
	if hit.is_empty():
		return {"passable": true, "distance": distance}
	return {"passable": false, "distance": distance, "blockedBy": _name_of(hit.get("collider"))}


# ── the engine underneath ────────────────────────────────────────────────────

## The 3D world this node sits in. `get_world_3d()` is a `Node3D` member and this
## is a plain `Node`, deliberately — a probe has no transform of its own — so the
## world comes from the viewport.
func _world() -> World3D:
	var viewport := get_viewport()
	return viewport.find_world_3d() if viewport != null else null


func _raycast(from: Vector3, to: Vector3, exclude: Array) -> Dictionary:
	var world := _world()
	if world == null:
		return {}
	var space := world.direct_space_state
	if space == null:
		return {}
	var params := PhysicsRayQueryParameters3D.create(from, to, obstruction_mask)
	var excluded: Array[RID] = []
	for rid in exclude:
		if rid is RID:
			excluded.append(rid)
	params.exclude = excluded
	return space.intersect_ray(params)


func _eye_position(actor_id: String) -> Vector3:
	if registry == null:
		return Vector3.INF
	var node := registry.actor(actor_id)
	if node == null:
		# A place can be an endpoint too — core asks about `forge_gate` as
		# readily as about `nessa`.
		return registry.place_position(actor_id)
	# Roughly chest height, so a ray between two characters does not start inside
	# the floor. A game with its own eye markers overrides by binding those.
	return node.global_position + Vector3.UP * 1.5


func _ground_position(actor_id: String) -> Vector3:
	if registry == null:
		return Vector3.INF
	var node := registry.actor(actor_id)
	return node.global_position if node != null else registry.place_position(actor_id)


func _body_rid(actor_id: String) -> Variant:
	if registry == null:
		return null
	var node := registry.actor(actor_id)
	if node is CollisionObject3D:
		return (node as CollisionObject3D).get_rid()
	return null


func _name_of(collider: Variant) -> String:
	if collider is Node:
		return (collider as Node).name
	return "geometry"


## `light_level/2` where the target is, 0-100.
##
## AN APPROXIMATION, and labelled as one. Godot exposes no runtime per-point
## lightmap or light-probe read, so this is the ambient floor plus a linecast at
## the sun: in shadow, ambient; in sunlight, ambient plus the sun's energy scaled
## into the remaining range. It is a MEASUREMENT either way — what darkness is
## worth is authored in `WorldIR.perception` and decided in core, so an
## imprecise reading changes how hidden a character is, never the rules of hiding.
func _light_level_at(point: Vector3) -> float:
	var sun := _resolve_sun()
	if sun == null:
		return ambient_light
	var toward_sun := -sun.global_transform.basis.z.normalized()
	var hit := _raycast(point, point + toward_sun * sight_range, [])
	if not hit.is_empty():
		return ambient_light
	var lit := clampf(sun.light_energy, 0.0, 4.0) / 4.0
	return clampf(ambient_light + (100.0 - ambient_light) * lit, 0.0, 100.0)


func _resolve_sun() -> DirectionalLight3D:
	if _sun_resolved:
		return _sun
	_sun_resolved = true
	if not sun_path.is_empty():
		_sun = get_node_or_null(sun_path) as DirectionalLight3D
	if _sun == null:
		for node in get_tree().get_nodes_in_group("insimul_sun"):
			if node is DirectionalLight3D:
				_sun = node
				break
	return _sun


## What the target's body is doing, in `MovementStance`'s own vocabulary —
## `standing`, `crouching`, `prone`. Deliberately core's spelling rather than a
## second one: this is the host REPORTING the carriage core asks for in a
## locomotion order.
##
## Read from a `stance` property or an `insimul_stance` group membership, and
## empty when the scene says nothing — an absent field is not `standing`.
func _stance_of(actor_id: String) -> String:
	if registry == null:
		return ""
	var node := registry.actor(actor_id)
	if node == null:
		return ""
	if node.has_method("insimul_stance"):
		return String(node.call("insimul_stance"))
	var stance: Variant = node.get("stance")
	return String(stance) if stance != null else ""


# ── the three adapters ───────────────────────────────────────────────────────
# Thin, because the interfaces are: each one forwards its single method to the
# node above, which is where the scene actually lives.

class _TrajectoryProbe extends InsimulMechanicHosts.TrajectoryProbe:
	var _probes: Node = null

	func _init(probes: Node) -> void:
		_probes = probes

	func query(q: Dictionary) -> Dictionary:
		return _probes.query_trajectory(q)


class _PerceptionProbe extends InsimulMechanicHosts.PerceptionProbe:
	var _probes: Node = null

	func _init(probes: Node) -> void:
		_probes = probes

	func sense(q: Dictionary) -> Dictionary:
		return _probes.sense_perception(q)


class _TraversalProbe extends InsimulMechanicHosts.TraversalProbe:
	var _probes: Node = null

	func _init(probes: Node) -> void:
		_probes = probes

	func query(q: Dictionary) -> Dictionary:
		return _probes.query_traversal(q)
