extends Node
## NPC Schedule System — daily routines driven by game time.
## Matches shared/game-engine/rendering/NPCScheduleSystem.ts, ScheduleExecutor.ts.

signal activity_changed(npc_id: String, activity: String)

## Activity-to-animation mapping
const ACTIVITY_ANIMS := {
	"sleep": "sleep",
	"eat": "eat",
	"work": "work",
	"socialize": "talk",
	"shop": "walk",
	"idle_at_home": "idle",
	"visit_friend": "walk",
	"wander": "walk",
}

var _schedules: Dictionary = {}  # npc_id -> { blocks, homeBuildingId, workBuildingId, ... }
var _current_blocks: Dictionary = {}  # npc_id -> block_index
var _npc_nodes: Dictionary = {}  # npc_id -> CharacterBody3D

func register_npc(npc_id: String, schedule_data: Dictionary, npc_node: CharacterBody3D) -> void:
	_schedules[npc_id] = schedule_data
	_current_blocks[npc_id] = -1
	_npc_nodes[npc_id] = npc_node

func unregister_npc(npc_id: String) -> void:
	_schedules.erase(npc_id)
	_current_blocks.erase(npc_id)
	_npc_nodes.erase(npc_id)

func _process(_delta: float) -> void:
	var hour: float = GameClock.current_hour
	for npc_id in _schedules:
		_evaluate_npc_schedule(npc_id, hour)

func _evaluate_npc_schedule(npc_id: String, hour: float) -> void:
	var schedule: Dictionary = _schedules[npc_id]
	var blocks: Array = schedule.get("blocks", [])
	if blocks.is_empty():
		return

	var block_idx := _find_block_for_hour(blocks, hour)
	if block_idx < 0 or block_idx == _current_blocks.get(npc_id, -1):
		return

	_current_blocks[npc_id] = block_idx
	var block: Dictionary = blocks[block_idx]
	var activity: String = block.get("activity", "idle_at_home")

	# Navigate NPC to appropriate location
	var npc: CharacterBody3D = _npc_nodes.get(npc_id)
	if not npc:
		return

	var target_building := _resolve_building(schedule, activity, block)
	if target_building != "" and npc.has_method("init_from_data"):
		var nav: NavigationAgent3D = npc.get_node_or_null("NavigationAgent3D")
		if nav:
			var pos := _get_building_position(target_building)
			if pos != Vector3.ZERO:
				nav.target_position = pos

	# Set animation state
	var anim_ctrl := _find_anim_controller(npc)
	if anim_ctrl:
		var anim: String = ACTIVITY_ANIMS.get(activity, "idle")
		match anim:
			"sleep":
				if anim_ctrl.has_method("set_sleeping"):
					anim_ctrl.set_sleeping(true)
			"eat":
				if anim_ctrl.has_method("set_eating"):
					anim_ctrl.set_eating(true)
			"work":
				if anim_ctrl.has_method("set_working"):
					anim_ctrl.set_working(true)
			"talk":
				if anim_ctrl.has_method("set_talking"):
					anim_ctrl.set_talking(true)
			_:
				if anim_ctrl.has_method("set_speed"):
					anim_ctrl.set_speed(0.0)

	activity_changed.emit(npc_id, activity)

func _find_block_for_hour(blocks: Array, hour: float) -> int:
	for i in range(blocks.size()):
		var b: Dictionary = blocks[i]
		var start: float = b.get("startHour", 0.0)
		var end: float = b.get("endHour", 0.0)
		if start <= end:
			if hour >= start and hour < end:
				return i
		else:
			if hour >= start or hour < end:
				return i
	return -1

func _resolve_building(schedule: Dictionary, activity: String, block: Dictionary) -> String:
	var block_building: String = block.get("buildingId", "")
	if block_building != "":
		return block_building
	match activity:
		"sleep", "idle_at_home", "eat":
			return schedule.get("homeBuildingId", "")
		"work":
			return schedule.get("workBuildingId", "")
		"visit_friend":
			var friends: Array = schedule.get("friendBuildingIds", [])
			if not friends.is_empty():
				return friends[randi() % friends.size()]
		"socialize", "shop":
			return schedule.get("workBuildingId", "")
	return ""

func _get_building_position(building_id: String) -> Vector3:
	var buildings: Array = DataLoader.load_buildings()
	for bld in buildings:
		if bld.get("id", "") == building_id:
			var pos: Dictionary = bld.get("position", {})
			return Vector3(pos.get("x", 0), pos.get("y", 0), pos.get("z", 0))
	return Vector3.ZERO

func _find_anim_controller(npc: Node) -> Node:
	for child in npc.get_children():
		if child.has_method("set_speed"):
			return child
	return null
