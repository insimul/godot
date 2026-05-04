extends Node3D
## Spatial partitioning chunk manager — divides world into grid cells and
## toggles visibility/processing based on player position.
## Matches ChunkManager.ts for performance optimization.

@export var world_size := 512
@export var chunk_size := 64
@export var render_radius := 2
@export var dispose_radius := 5

var _chunks: Dictionary = {}  # Vector2i → Array[Node3D]
var _active_chunks: Dictionary = {}  # Vector2i → bool
var _player: Node3D = null
var _last_chunk := Vector2i(-9999, -9999)
var _grid_cols: int = 0
var _grid_rows: int = 0

func _ready() -> void:
	add_to_group("world_generator")

func generate_from_data(world_data: Dictionary) -> void:
	var geo: Dictionary = world_data.get("geography", {})
	world_size = geo.get("terrainSize", world_size)
	_grid_cols = ceili(float(world_size) / chunk_size)
	_grid_rows = _grid_cols
	print("[Insimul] ChunkManager: %dx%d grid, chunk_size=%d, render_radius=%d" % [_grid_cols, _grid_rows, chunk_size, render_radius])

## Register a mesh/node into the appropriate chunk based on its world position.
func register_mesh(mesh: Node3D) -> void:
	var chunk_key := _world_to_chunk(mesh.global_position)
	if not _chunks.has(chunk_key):
		_chunks[chunk_key] = []
	(_chunks[chunk_key] as Array).append(mesh)

## Register multiple meshes at once.
func register_meshes(meshes: Array[Node3D]) -> void:
	for mesh in meshes:
		register_mesh(mesh)

func _process(_delta: float) -> void:
	if _player == null:
		_player = _find_player()
		if _player == null:
			return

	var current_chunk := _world_to_chunk(_player.global_position)
	if current_chunk == _last_chunk:
		return

	_last_chunk = current_chunk
	_update_chunks(current_chunk)

func _update_chunks(center: Vector2i) -> void:
	var new_active: Dictionary = {}

	for dx in range(-render_radius, render_radius + 1):
		for dz in range(-render_radius, render_radius + 1):
			var key := Vector2i(center.x + dx, center.y + dz)
			new_active[key] = true

			if not _active_chunks.has(key):
				_enable_chunk(key)

	# Disable chunks that are no longer active
	for key: Vector2i in _active_chunks:
		if not new_active.has(key):
			var dist := _chunk_distance(center, key)
			if dist > dispose_radius:
				_dispose_chunk(key)
			else:
				_disable_chunk(key)

	_active_chunks = new_active

func _enable_chunk(key: Vector2i) -> void:
	var meshes: Array = _chunks.get(key, [])
	for mesh in meshes:
		if mesh is Node3D and is_instance_valid(mesh):
			mesh.visible = true
			mesh.process_mode = Node.PROCESS_MODE_INHERIT

func _disable_chunk(key: Vector2i) -> void:
	var meshes: Array = _chunks.get(key, [])
	for mesh in meshes:
		if mesh is Node3D and is_instance_valid(mesh):
			mesh.visible = false
			mesh.process_mode = Node.PROCESS_MODE_DISABLED

func _dispose_chunk(key: Vector2i) -> void:
	_disable_chunk(key)

func _world_to_chunk(world_pos: Vector3) -> Vector2i:
	var half := float(world_size) / 2.0
	var col := floori((world_pos.x + half) / chunk_size)
	var row := floori((world_pos.z + half) / chunk_size)
	return Vector2i(
		clampi(col, 0, _grid_cols - 1),
		clampi(row, 0, _grid_rows - 1)
	)

func _chunk_distance(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))

func get_chunk_count() -> int:
	return _chunks.size()

func get_active_chunk_count() -> int:
	return _active_chunks.size()

func _find_player() -> Node3D:
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		return players[0] as Node3D
	return null
