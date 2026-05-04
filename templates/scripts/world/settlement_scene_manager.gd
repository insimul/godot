extends Node3D
## Settlement scene manager — controls visibility of settlements based on
## player distance, matching SettlementSceneManager.ts.
## Manages up to MAX_SETTLEMENTS_3D visible settlements.

const MAX_SETTLEMENTS_3D := 16
const VISIBILITY_DISTANCE := 300.0
const EXIT_BUFFER := 20.0

var _zones: Array[Dictionary] = []
## Maps settlement ID → Array of registered Node3D meshes.
var _settlement_meshes: Dictionary = {}
var _overworld_meshes: Array[Node3D] = []
var _global_meshes: Array[Node3D] = []
var _active_zone_id: String = ""
var _player: Node3D = null

func _ready() -> void:
	add_to_group("world_generator")

func generate_from_data(world_data: Dictionary) -> void:
	var settlements: Array = world_data.get("geography", {}).get("settlements", [])
	if settlements.is_empty():
		var sd: Array = world_data.get("settlements", [])
		settlements = sd

	for s in settlements:
		var pos_dict: Dictionary = s.get("position", {})
		register_zone({
			"id": s.get("id", ""),
			"name": s.get("name", ""),
			"center": Vector3(pos_dict.get("x", 0), pos_dict.get("y", 0), pos_dict.get("z", 0)),
			"radius": s.get("radius", 50.0),
			"type": s.get("settlementType", "town"),
		})

func register_zone(zone: Dictionary) -> void:
	_zones.append(zone)
	if not _settlement_meshes.has(zone["id"]):
		_settlement_meshes[zone["id"]] = []

func register_settlement_mesh(settlement_id: String, mesh: Node3D) -> void:
	if not _settlement_meshes.has(settlement_id):
		_settlement_meshes[settlement_id] = []
	(_settlement_meshes[settlement_id] as Array).append(mesh)

func register_overworld_mesh(mesh: Node3D) -> void:
	_overworld_meshes.append(mesh)

func register_global_mesh(mesh: Node3D) -> void:
	_global_meshes.append(mesh)

func _process(_delta: float) -> void:
	if _player == null:
		_player = _find_player()
		if _player == null:
			return

	_check_player_zone()
	_update_settlement_visibility()

func _check_player_zone() -> void:
	var player_pos := _player.global_position

	# If already in a zone, check if we've exited (with hysteresis buffer)
	if _active_zone_id != "":
		var zone := _find_zone(_active_zone_id)
		if zone.is_empty():
			_active_zone_id = ""
		else:
			var dist: float = player_pos.distance_to(zone["center"])
			if dist > zone["radius"] + EXIT_BUFFER:
				_exit_settlement()

	# Check if we've entered a new zone
	if _active_zone_id == "":
		for zone in _zones:
			var dist: float = player_pos.distance_to(zone["center"])
			if dist < zone["radius"]:
				_enter_settlement(zone["id"])
				break

func _update_settlement_visibility() -> void:
	if _player == null:
		return

	var player_pos := _player.global_position
	var visible_count := 0

	for zone in _zones:
		var dist: float = player_pos.distance_to(zone["center"])
		var should_show := dist < VISIBILITY_DISTANCE and visible_count < MAX_SETTLEMENTS_3D
		var meshes: Array = _settlement_meshes.get(zone["id"], [])

		for mesh in meshes:
			if mesh is Node3D and is_instance_valid(mesh):
				mesh.visible = should_show

		if should_show:
			visible_count += 1

func _enter_settlement(zone_id: String) -> void:
	_active_zone_id = zone_id

	# Show settlement meshes, hide overworld meshes
	for mesh in _overworld_meshes:
		if is_instance_valid(mesh):
			mesh.visible = false

	var meshes: Array = _settlement_meshes.get(zone_id, [])
	for mesh in meshes:
		if mesh is Node3D and is_instance_valid(mesh):
			mesh.visible = true

func _exit_settlement() -> void:
	_active_zone_id = ""

	# Show overworld meshes
	for mesh in _overworld_meshes:
		if is_instance_valid(mesh):
			mesh.visible = true

func get_active_zone() -> Dictionary:
	if _active_zone_id == "":
		return {}
	return _find_zone(_active_zone_id)

func is_in_settlement() -> bool:
	return _active_zone_id != ""

func get_nearest_settlement(pos: Vector3) -> Dictionary:
	var nearest: Dictionary = {}
	var nearest_dist: float = INF
	for zone in _zones:
		var dist: float = pos.distance_to(zone["center"])
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = zone
	return nearest

func _find_zone(zone_id: String) -> Dictionary:
	for zone in _zones:
		if zone["id"] == zone_id:
			return zone
	return {}

func _find_player() -> Node3D:
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		return players[0] as Node3D
	return null
