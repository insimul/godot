extends Node
## NPC Movement Controller — NavigationAgent3D pathfinding for NPCs.
## Matches shared/game-engine/rendering/NPCMovementController.ts, PathfindingSystem.ts.

signal destination_reached(npc: Node3D)
signal path_failed(npc: Node3D)

@export var walk_speed := 2.0
@export var run_speed := 5.0
@export var wander_radius := 15.0
@export var avoidance_enabled := true

var _npc: CharacterBody3D = null
var _nav_agent: NavigationAgent3D = null
var _anim_controller: Node = null
var _current_speed: float = 2.0
var _is_moving := false

func setup(npc: CharacterBody3D) -> void:
	_npc = npc
	_nav_agent = _find_nav_agent(npc)
	_anim_controller = _find_anim_controller(npc)
	if _nav_agent:
		_nav_agent.avoidance_enabled = avoidance_enabled
		_nav_agent.navigation_finished.connect(_on_nav_finished)

func move_to(target: Vector3, speed: float = -1.0) -> void:
	if not _nav_agent or not _npc:
		return
	_current_speed = speed if speed > 0 else walk_speed
	_nav_agent.target_position = target
	_is_moving = true

func move_to_building(building_id: String) -> void:
	var buildings: Array = DataLoader.load_buildings()
	for bld in buildings:
		if bld.get("id", "") == building_id:
			var pos: Dictionary = bld.get("position", {})
			move_to(Vector3(pos.get("x", 0), pos.get("y", 0), pos.get("z", 0)))
			return
	path_failed.emit(_npc)

func wander() -> void:
	if not _nav_agent or not _npc:
		return
	var random_offset := Vector3(
		randf_range(-wander_radius, wander_radius),
		0,
		randf_range(-wander_radius, wander_radius)
	)
	move_to(_npc.global_position + random_offset)

func follow_road(waypoints: Array) -> void:
	if waypoints.is_empty() or not _nav_agent:
		return
	# Navigate to first waypoint; road following is sequential
	var wp: Dictionary = waypoints[0] if waypoints[0] is Dictionary else {}
	var target := Vector3(wp.get("x", 0), wp.get("y", 0), wp.get("z", 0))
	move_to(target)

func stop() -> void:
	_is_moving = false
	if _npc:
		_npc.velocity = Vector3.ZERO
	if _anim_controller and _anim_controller.has_method("set_speed"):
		_anim_controller.set_speed(0.0)

func is_moving() -> bool:
	return _is_moving

func update(delta: float) -> void:
	if not _is_moving or not _nav_agent or not _npc:
		return

	if _nav_agent.is_navigation_finished():
		_on_nav_finished()
		return

	var next_pos := _nav_agent.get_next_path_position()
	var direction := (next_pos - _npc.global_position).normalized()
	_npc.velocity = direction * _current_speed

	# Face movement direction
	if direction.length() > 0.1:
		var target_rot := atan2(direction.x, direction.z)
		_npc.rotation.y = lerp_angle(_npc.rotation.y, target_rot, 8.0 * delta)

	_npc.move_and_slide()

	if _anim_controller and _anim_controller.has_method("set_speed"):
		_anim_controller.set_speed(_current_speed)

func _on_nav_finished() -> void:
	_is_moving = false
	if _anim_controller and _anim_controller.has_method("set_speed"):
		_anim_controller.set_speed(0.0)
	destination_reached.emit(_npc)

func _find_nav_agent(node: Node) -> NavigationAgent3D:
	for child in node.get_children():
		if child is NavigationAgent3D:
			return child
	return null

func _find_anim_controller(node: Node) -> Node:
	for child in node.get_children():
		if child.has_method("set_speed"):
			return child
	return null
