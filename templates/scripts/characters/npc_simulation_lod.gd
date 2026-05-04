extends Node
## NPC Simulation LOD — scales NPC detail based on distance from player.
## Matches shared/game-engine/rendering/NPCSimulationLOD.ts.

const MAX_FULL_SIM_NPCS := 8
const FULL_SIM_DISTANCE := 30.0
const MID_SIM_DISTANCE := 60.0
const FAR_DISTANCE := 100.0

enum LODLevel { FULL, MEDIUM, HIDDEN }

var _player: Node3D = null
var _npc_lods: Dictionary = {}  # npc_node_path -> LODLevel
var _frame_counter := 0
var _update_interval := 10  # Evaluate LOD every N frames

func _ready() -> void:
	await get_tree().process_frame
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		_player = players[0] as Node3D

func register_npc(npc: Node3D) -> void:
	_npc_lods[npc.get_path()] = LODLevel.FULL

func unregister_npc(npc: Node3D) -> void:
	_npc_lods.erase(npc.get_path())

func _process(_delta: float) -> void:
	_frame_counter += 1
	if _frame_counter < _update_interval:
		return
	_frame_counter = 0
	_update_lod_levels()

func _update_lod_levels() -> void:
	if not _player:
		return

	var player_pos := _player.global_position

	# Collect distances for all registered NPCs
	var npc_distances: Array[Dictionary] = []
	for npc_path in _npc_lods:
		var npc: Node3D = get_node_or_null(npc_path) as Node3D
		if not npc:
			continue
		var dist := player_pos.distance_to(npc.global_position)
		npc_distances.append({"path": npc_path, "node": npc, "distance": dist})

	# Sort by distance (closest first)
	npc_distances.sort_custom(func(a, b): return a["distance"] < b["distance"])

	var full_count := 0
	for entry in npc_distances:
		var npc: Node3D = entry["node"]
		var dist: float = entry["distance"]
		var npc_path = entry["path"]
		var new_lod: LODLevel

		if dist > FAR_DISTANCE:
			new_lod = LODLevel.HIDDEN
		elif dist > MID_SIM_DISTANCE or full_count >= MAX_FULL_SIM_NPCS:
			new_lod = LODLevel.MEDIUM
		else:
			new_lod = LODLevel.FULL
			full_count += 1

		var old_lod: LODLevel = _npc_lods.get(npc_path, LODLevel.FULL)
		if new_lod != old_lod:
			_apply_lod(npc, new_lod)
			_npc_lods[npc_path] = new_lod

func _apply_lod(npc: Node3D, lod: LODLevel) -> void:
	match lod:
		LODLevel.FULL:
			npc.visible = true
			npc.process_mode = Node.PROCESS_MODE_INHERIT
		LODLevel.MEDIUM:
			npc.visible = true
			# Reduced update frequency handled by frame counter in npc_controller
			npc.process_mode = Node.PROCESS_MODE_INHERIT
		LODLevel.HIDDEN:
			npc.visible = false
			npc.process_mode = Node.PROCESS_MODE_DISABLED

func get_lod_level(npc: Node3D) -> LODLevel:
	return _npc_lods.get(npc.get_path(), LODLevel.FULL)

func get_full_sim_count() -> int:
	var count := 0
	for lod in _npc_lods.values():
		if lod == LODLevel.FULL:
			count += 1
	return count
