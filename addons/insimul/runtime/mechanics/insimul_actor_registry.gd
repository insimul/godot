class_name InsimulActorRegistry
extends RefCounted
## Which body is `nessa`, and where is `forge_gate` — tasklist 147, US-1.
##
## Core names an actor with an atom or a CURIE and a location with a place atom;
## a raycast needs a `Vector3` and a walk needs a `Node3D`. Nothing in this plugin
## held that mapping before the mechanic modules arrived, and all three geometry
## probes plus the locomotion host need it, so it is here rather than copied into
## each of them.
##
## IT IS A LOOKUP, NOT A MODEL. It stores no health, no stamina, no stance and no
## state of any kind: every one of those is core's, and a registry that started
## caching them would be the beginning of a second world model. What it holds is
## an id, a node and — for a place — a position.
##
## [codeblock]
## registry.bind_actor("nessa", $Player)
## registry.bind_place("forge_gate", $Places/ForgeGate)
##
## var probe := GodotGeometryProbes.new(registry, get_world_3d())
## [/codeblock]
##
## Nodes are held WEAKLY. A despawned NPC leaves the registry answering "unknown"
## rather than a freed instance, which is what lets a probe report "no reading"
## for a target that left the scene between a decision and a frame.

var _actors := {}
var _places := {}


## Bind an actor atom (or CURIE) to the node that IS that actor.
func bind_actor(actor_id: String, node: Node3D) -> void:
	if actor_id.is_empty() or node == null:
		return
	_actors[actor_id] = weakref(node)


## Bind a location atom to a node whose global position IS that place. A marker,
## a spawn point, a door, the centre of a room — the scene's business entirely.
func bind_place(place_id: String, node: Node3D) -> void:
	if place_id.is_empty() or node == null:
		return
	_places[place_id] = weakref(node)


## Bind a location atom to a fixed point, for a place with no node of its own.
func bind_place_position(place_id: String, position: Vector3) -> void:
	if place_id.is_empty():
		return
	_places[place_id] = position


func unbind_actor(actor_id: String) -> void:
	_actors.erase(actor_id)


func unbind_place(place_id: String) -> void:
	_places.erase(place_id)


func clear() -> void:
	_actors.clear()
	_places.clear()


## The node for an actor atom, or null when it was never bound or has been freed.
func actor(actor_id: String) -> Node3D:
	return _resolve_node(_actors, actor_id)


## Every actor atom currently bound to a live node.
func actor_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for actor_id in _actors.keys():
		if actor(String(actor_id)) != null:
			out.append(String(actor_id))
	out.sort()
	return out


## The node for a place atom, or null. A place bound as a bare position has none.
func place(place_id: String) -> Node3D:
	return _resolve_node(_places, place_id)


## Where an actor is, in scene units. Returns `fallback` when unknown — callers
## treat that as "no reading", never as the origin.
func actor_position(actor_id: String, fallback: Vector3 = Vector3.INF) -> Vector3:
	var node := actor(actor_id)
	return node.global_position if node != null else fallback


## Where a place is, in scene units, whether it was bound as a node or a point.
func place_position(place_id: String, fallback: Vector3 = Vector3.INF) -> Vector3:
	if not _places.has(place_id):
		return fallback
	var bound: Variant = _places[place_id]
	if bound is Vector3:
		return bound
	var node := place(place_id)
	return node.global_position if node != null else fallback


## Whether both ends of a query are known. A probe that cannot find one of them
## must report "no reading" rather than guessing — the whole reason this returns
## a boolean instead of two origins.
func knows(actor_id: String) -> bool:
	return actor(actor_id) != null


func _resolve_node(table: Dictionary, id: String) -> Node3D:
	if not table.has(id):
		return null
	var bound: Variant = table[id]
	if not (bound is WeakRef):
		return null
	var node: Variant = (bound as WeakRef).get_ref()
	if node == null or not is_instance_valid(node):
		table.erase(id)
		return null
	return node as Node3D
