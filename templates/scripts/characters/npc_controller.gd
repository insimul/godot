extends CharacterBody3D
## NPC controller with navigation, state machine, and schedule-driven behavior.
## Requires a NavigationAgent3D child node.

enum NPCState { IDLE, PATROL, TALKING, FLEEING, PURSUING, ALERT, SCHEDULE_MOVE }

@export var character_id := ""
@export var role := ""
@export var home_position := Vector3.ZERO
@export var patrol_radius := 20.0
@export var disposition := 50.0
@export var settlement_id := ""

var quest_ids: Array[String] = []
var current_state: NPCState = NPCState.IDLE

## Schedule fields
var has_schedule: bool = false
var current_block_index: int = -1
var _schedule_blocks: Array = []
var _schedule_home_building_id := ""
var _schedule_work_building_id := ""
var _schedule_friend_building_ids: Array[String] = []

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D if has_node("NavigationAgent3D") else null

var _patrol_timer := 0.0
var _patrol_interval := 5.0
var _anim_controller: Node = null
var _schedule_eval_timer := 0.0
var _schedule_eval_interval := 2.0

func init_from_data(data: Dictionary) -> void:
	character_id = data.get("characterId", "")
	role = data.get("role", "")
	var pos: Dictionary = data.get("homePosition", {})
	home_position = Vector3(pos.get("x", 0), pos.get("y", 0), pos.get("z", 0))
	patrol_radius = data.get("patrolRadius", 20.0)
	disposition = data.get("disposition", 50.0)
	settlement_id = data.get("settlementId", "")
	quest_ids.assign(data.get("questIds", []))
	global_position = home_position
	_anim_controller = _find_anim_controller()
	_load_schedule(data)
	print("[Insimul] NPC %s initialized at %s (role: %s, schedule: %s)" % [character_id, home_position, role, has_schedule])

func _load_schedule(data: Dictionary) -> void:
	var schedule = data.get("schedule", null)
	if schedule == null or not (schedule is Dictionary):
		return
	_schedule_blocks = schedule.get("blocks", [])
	if _schedule_blocks.is_empty():
		return
	_schedule_home_building_id = schedule.get("homeBuildingId", "")
	_schedule_work_building_id = schedule.get("workBuildingId", "")
	var friends = schedule.get("friendBuildingIds", [])
	for f in friends:
		_schedule_friend_building_ids.append(str(f))
	has_schedule = true

func _find_anim_controller() -> Node:
	for child in get_children():
		if child.has_method("set_speed"):
			return child
	return null

func _physics_process(delta: float) -> void:
	if has_schedule and current_state != NPCState.TALKING:
		_schedule_eval_timer += delta
		if _schedule_eval_timer >= _schedule_eval_interval:
			_schedule_eval_timer = 0.0
			_evaluate_schedule()

	match current_state:
		NPCState.IDLE:
			_update_idle(delta)
		NPCState.PATROL:
			_update_patrol(delta)
		NPCState.SCHEDULE_MOVE:
			_update_schedule_move(delta)
		NPCState.TALKING:
			pass
		NPCState.FLEEING:
			pass
		NPCState.PURSUING:
			pass
		NPCState.ALERT:
			pass

func _evaluate_schedule() -> void:
	var hour: float = GameClock.current_hour
	var block_idx := _find_block_for_hour(hour)
	if block_idx < 0 or block_idx == current_block_index:
		return
	current_block_index = block_idx
	var block: Dictionary = _schedule_blocks[block_idx]
	var activity: String = block.get("activity", "idle_at_home")

	if activity == "wander":
		current_state = NPCState.PATROL
		_start_patrol_from_current()
		return

	var building_id: String = _resolve_activity_building(activity, block)
	if building_id == "":
		current_state = NPCState.IDLE
		return

	var target := _resolve_building_position(building_id)
	if target == Vector3.ZERO and building_id != "":
		current_state = NPCState.IDLE
		return

	if nav_agent:
		nav_agent.target_position = target
		current_state = NPCState.SCHEDULE_MOVE

func _find_block_for_hour(hour: float) -> int:
	for i in range(_schedule_blocks.size()):
		var b: Dictionary = _schedule_blocks[i]
		var start: float = b.get("startHour", 0.0)
		var end: float = b.get("endHour", 0.0)
		if start <= end:
			if hour >= start and hour < end:
				return i
		else:
			# Midnight-wrapping block (e.g. 22:00–06:30)
			if hour >= start or hour < end:
				return i
	return -1

func _resolve_activity_building(activity: String, block: Dictionary) -> String:
	var block_building: String = block.get("buildingId", "")
	if block_building != "":
		return block_building
	match activity:
		"sleep", "idle_at_home", "eat":
			return _schedule_home_building_id
		"work":
			return _schedule_work_building_id
		"visit_friend":
			if not _schedule_friend_building_ids.is_empty():
				return _schedule_friend_building_ids[randi() % _schedule_friend_building_ids.size()]
		"socialize", "shop":
			return _schedule_work_building_id
	return ""

func _resolve_building_position(building_id: String) -> Vector3:
	var buildings: Array = DataLoader.load_buildings()
	for bld in buildings:
		if bld.get("id", "") == building_id:
			var pos: Dictionary = bld.get("position", {})
			return Vector3(pos.get("x", 0), pos.get("y", 0), pos.get("z", 0))
	return Vector3.ZERO

func _start_patrol_from_current() -> void:
	var random_offset := Vector3(
		randf_range(-patrol_radius, patrol_radius),
		0,
		randf_range(-patrol_radius, patrol_radius)
	)
	var target := global_position + random_offset
	if nav_agent:
		nav_agent.target_position = target

func _update_idle(delta: float) -> void:
	if _anim_controller:
		_anim_controller.set_speed(0.0)
	if has_schedule:
		return
	_patrol_timer += delta
	if _patrol_timer >= _patrol_interval:
		_patrol_timer = 0.0
		current_state = NPCState.PATROL
		var random_offset := Vector3(
			randf_range(-patrol_radius, patrol_radius),
			0,
			randf_range(-patrol_radius, patrol_radius)
		)
		var target := home_position + random_offset
		if nav_agent:
			nav_agent.target_position = target

func _update_patrol(_delta: float) -> void:
	if nav_agent == null:
		current_state = NPCState.IDLE
		return
	if nav_agent.is_navigation_finished():
		current_state = NPCState.IDLE
		return
	var next_pos := nav_agent.get_next_path_position()
	var direction := (next_pos - global_position).normalized()
	velocity = direction * 2.0
	if _anim_controller:
		_anim_controller.set_speed(velocity.length())
	move_and_slide()

func _update_schedule_move(_delta: float) -> void:
	if nav_agent == null:
		current_state = NPCState.IDLE
		return
	if nav_agent.is_navigation_finished():
		current_state = NPCState.IDLE
		return
	var next_pos := nav_agent.get_next_path_position()
	var direction := (next_pos - global_position).normalized()
	velocity = direction * 2.0
	move_and_slide()

func start_dialogue(initiator: Node3D) -> void:
	current_state = NPCState.TALKING
	velocity = Vector3.ZERO
	look_at(initiator.global_position, Vector3.UP)
	if _anim_controller:
		_anim_controller.set_talking(true)
	print("[Insimul] NPC %s starting dialogue" % character_id)

func end_dialogue() -> void:
	if _anim_controller:
		_anim_controller.set_talking(false)
	current_block_index = -1
	current_state = NPCState.IDLE
