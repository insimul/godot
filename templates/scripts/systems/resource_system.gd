extends Node
## Resource System — autoloaded singleton.
## Manages gatherable resource nodes: spawning visuals, gather mechanic with
## progress, depletion, respawn timers, and tool requirements.
## Mirrors the Unity ResourceSystem.cs and Babylon.js ResourceSystem.

signal gather_complete(resource_type: String, node_id: String)
signal node_respawned(node_id: String)

## How close the player must be to interact (metres).
const INTERACTION_RADIUS := 2.0

## Tool requirements by resource type. null = no tool needed.
const TOOL_REQUIREMENTS: Dictionary = {
	"wood": "axe",
	"stone": "pickaxe",
	"iron": "pickaxe",
	"gold": "pickaxe",
	"crystal": "pickaxe",
}

var definitions: Array[Dictionary] = []

## Keyed by node id → Dictionary with runtime state.
var _nodes: Dictionary = {}

## Currently targeted node id (nearest non-depleted within range), or "".
var _active_node_id: String = ""

## Gathering state.
var _is_gathering: bool = false
var _gather_progress: float = 0.0

## Root Node3D that holds all spawned node visuals.
var _nodes_root: Node3D = null

func load_from_data(world_data: Dictionary) -> void:
	var resources: Dictionary = world_data.get("resources", {})
	definitions.assign(resources.get("definitions", []))

	var gathering_nodes: Array = resources.get("gatheringNodes", [])
	_nodes_root = Node3D.new()
	_nodes_root.name = "ResourceNodes"
	add_child(_nodes_root)

	for node_data in gathering_nodes:
		_spawn_node(node_data)

	print("[Insimul] ResourceSystem loaded %d types, %d nodes" % [definitions.size(), _nodes.size()])

# ---------------------------------------------------------------------------
# Node spawning
# ---------------------------------------------------------------------------

func _spawn_node(data: Dictionary) -> void:
	var node_id: String = data.get("id", "")
	var resource_type: String = data.get("resourceType", "")
	var pos: Dictionary = data.get("position", {})
	var max_amount: int = data.get("maxAmount", 3)
	var respawn_time: float = data.get("respawnTime", 60000.0) / 1000.0
	var node_scale: float = data.get("scale", 1.0)

	var def: Dictionary = _get_definition(resource_type)

	# Create visual
	var visual: Node3D = _create_node_visual(resource_type, def)
	visual.name = node_id
	visual.position = Vector3(pos.get("x", 0.0), pos.get("y", 0.0), pos.get("z", 0.0))
	visual.scale = Vector3.ONE * node_scale
	_nodes_root.add_child(visual)

	_nodes[node_id] = {
		"id": node_id,
		"resource_type": resource_type,
		"visual": visual,
		"max_amount": max_amount,
		"current_amount": max_amount,
		"respawn_time": respawn_time,
		"respawn_timer": 0.0,
		"scale": node_scale,
		"depleted": false,
		"original_color": _color_from_def(def),
	}

func _create_node_visual(resource_type: String, def: Dictionary) -> Node3D:
	var mesh_instance := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _color_from_def(def)

	match resource_type:
		"wood":
			# Tree stump — short cylinder
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = 0.3
			cylinder.bottom_radius = 0.4
			cylinder.height = 0.6
			mesh_instance.mesh = cylinder
		"stone":
			# Rock pile — cube
			var box := BoxMesh.new()
			box.size = Vector3(0.8, 0.5, 0.8)
			mesh_instance.mesh = box
		"iron", "crystal":
			# Ore vein — vertically stretched sphere
			var sphere := SphereMesh.new()
			sphere.radius = 0.35
			sphere.height = 0.9
			mesh_instance.mesh = sphere
			if resource_type == "iron":
				mat.metallic = 0.8
				mat.roughness = 0.4
		"fiber", "food":
			# Bush — flattened sphere
			var sphere := SphereMesh.new()
			sphere.radius = 0.5
			sphere.height = 0.6
			mesh_instance.mesh = sphere
		"water":
			# Water pool — very flat cylinder
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = 0.6
			cylinder.bottom_radius = 0.6
			cylinder.height = 0.1
			mesh_instance.mesh = cylinder
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.albedo_color.a = 0.7
		_:
			var sphere := SphereMesh.new()
			sphere.radius = 0.4
			mesh_instance.mesh = sphere

	mesh_instance.material_override = mat
	return mesh_instance

func _color_from_def(def: Dictionary) -> Color:
	var c: Dictionary = def.get("color", {})
	return Color(c.get("r", 0.5), c.get("g", 0.5), c.get("b", 0.5))

# ---------------------------------------------------------------------------
# Frame update — proximity check, gather input, respawn timers
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	_tick_respawns(delta)

	if _is_gathering:
		_update_gathering(delta)
		return

	_update_nearest_node()

	if not _active_node_id.is_empty() and Input.is_action_just_pressed("interact"):
		_try_start_gathering()

func _tick_respawns(delta: float) -> void:
	for node_id in _nodes:
		var node: Dictionary = _nodes[node_id]
		if not node.get("depleted", false):
			continue
		node["respawn_timer"] = node.get("respawn_timer", 0.0) - delta
		if node["respawn_timer"] <= 0.0:
			_respawn_node(node_id)

func _update_nearest_node() -> void:
	_active_node_id = ""
	var player: Node3D = _find_player()
	if player == null:
		return

	var best_dist: float = INTERACTION_RADIUS
	for node_id in _nodes:
		var node: Dictionary = _nodes[node_id]
		if node.get("depleted", false):
			continue
		var visual: Node3D = node.get("visual")
		if visual == null:
			continue
		var dist: float = player.global_position.distance_to(visual.global_position)
		if dist < best_dist:
			best_dist = dist
			_active_node_id = node_id

# ---------------------------------------------------------------------------
# Gathering
# ---------------------------------------------------------------------------

func _try_start_gathering() -> void:
	var node: Dictionary = _nodes.get(_active_node_id, {})
	var resource_type: String = node.get("resource_type", "")

	if not _check_tool_requirement(resource_type):
		var required: String = TOOL_REQUIREMENTS.get(resource_type, "")
		print("[Insimul] Need %s to gather %s" % [required, resource_type])
		return

	_is_gathering = true
	_gather_progress = 0.0

func _update_gathering(delta: float) -> void:
	if _active_node_id.is_empty():
		cancel_gathering()
		return

	var node: Dictionary = _nodes.get(_active_node_id, {})
	if node.is_empty() or node.get("depleted", false):
		cancel_gathering()
		return

	# Cancel if player moved out of range
	var player: Node3D = _find_player()
	var visual: Node3D = node.get("visual")
	if player == null or visual == null:
		cancel_gathering()
		return
	if player.global_position.distance_to(visual.global_position) > INTERACTION_RADIUS:
		cancel_gathering()
		return

	# Advance progress
	var def: Dictionary = _get_definition(node.get("resource_type", ""))
	var gather_time: float = def.get("gatherTime", 2000.0) / 1000.0
	_gather_progress += delta / gather_time

	if _gather_progress >= 1.0:
		_complete_gathering()

func _complete_gathering() -> void:
	var node: Dictionary = _nodes.get(_active_node_id, {})
	var resource_type: String = node.get("resource_type", "")
	var def: Dictionary = _get_definition(resource_type)

	# Add to inventory
	InventorySystem.add_item({
		"id": resource_type,
		"name": def.get("name", resource_type),
		"type": "material",
		"quantity": 1,
	})

	node["current_amount"] = node.get("current_amount", 0) - 1
	print("[Insimul] Gathered %s (%d/%d remaining)" % [
		resource_type,
		node.get("current_amount", 0),
		node.get("max_amount", 0),
	])

	gather_complete.emit(resource_type, _active_node_id)

	if node.get("current_amount", 0) <= 0:
		_deplete_node(_active_node_id)

	_is_gathering = false
	_gather_progress = 0.0

func cancel_gathering() -> void:
	_is_gathering = false
	_gather_progress = 0.0

# ---------------------------------------------------------------------------
# Tool requirement
# ---------------------------------------------------------------------------

func _check_tool_requirement(resource_type: String) -> bool:
	if not TOOL_REQUIREMENTS.has(resource_type):
		return true
	var required_tool: String = TOOL_REQUIREMENTS[resource_type]
	return InventorySystem.has_item(required_tool)

# ---------------------------------------------------------------------------
# Depletion & respawn
# ---------------------------------------------------------------------------

func _deplete_node(node_id: String) -> void:
	var node: Dictionary = _nodes.get(node_id, {})
	node["depleted"] = true
	node["respawn_timer"] = node.get("respawn_time", 60.0)

	var visual: Node3D = node.get("visual")
	if visual is MeshInstance3D:
		var mat: StandardMaterial3D = (visual as MeshInstance3D).material_override
		if mat:
			var depleted_mat := mat.duplicate() as StandardMaterial3D
			depleted_mat.albedo_color = Color(0.4, 0.4, 0.4, 0.5)
			depleted_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			(visual as MeshInstance3D).material_override = depleted_mat
	if visual:
		visual.scale = Vector3.ONE * node.get("scale", 1.0) * 0.5

func _respawn_node(node_id: String) -> void:
	var node: Dictionary = _nodes.get(node_id, {})
	node["depleted"] = false
	node["current_amount"] = node.get("max_amount", 3)
	node["respawn_timer"] = 0.0

	var visual: Node3D = node.get("visual")
	if visual is MeshInstance3D:
		var original_color: Color = node.get("original_color", Color.WHITE)
		var mat: StandardMaterial3D = (visual as MeshInstance3D).material_override
		if mat:
			var restored_mat := mat.duplicate() as StandardMaterial3D
			restored_mat.albedo_color = original_color
			if node.get("resource_type", "") != "water":
				restored_mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
			(visual as MeshInstance3D).material_override = restored_mat
	if visual:
		visual.scale = Vector3.ONE * node.get("scale", 1.0)

	node_respawned.emit(node_id)
	print("[Insimul] Resource node %s respawned" % node_id)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _get_definition(resource_type: String) -> Dictionary:
	for def in definitions:
		if def.get("id", "") == resource_type:
			return def
	return {}

func _find_player() -> Node3D:
	var tree := get_tree()
	if tree == null:
		return null
	var players := tree.get_nodes_in_group("player")
	if players.size() > 0:
		return players[0] as Node3D
	return null

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func is_gathering() -> bool:
	return _is_gathering

func get_gather_progress() -> float:
	return _gather_progress

func get_active_node_id() -> String:
	return _active_node_id

func get_node_state(node_id: String) -> Dictionary:
	return _nodes.get(node_id, {})

func get_all_node_ids() -> Array:
	return _nodes.keys()

func get_resource_count(resource_type: String) -> int:
	return InventorySystem.get_item_count(resource_type)

func has_enough(resource_type: String, amount: int) -> bool:
	return get_resource_count(resource_type) >= amount

func dispose() -> void:
	_nodes.clear()
	_active_node_id = ""
	_is_gathering = false
	_gather_progress = 0.0
	if _nodes_root and is_instance_valid(_nodes_root):
		_nodes_root.queue_free()
		_nodes_root = null
	print("[Insimul] ResourceSystem disposed")
