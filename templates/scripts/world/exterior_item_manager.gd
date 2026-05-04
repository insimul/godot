extends Node3D
## Exterior item manager — spawns collectible items, readable books/documents,
## and interactive objects in the exterior world.
## Matches ExteriorItemManager.ts and BookSpawnManager.ts.

signal item_collected(item_id: String, item_data: Dictionary)
signal book_read(book_id: String, content: String)

## Item type → color mapping for procedural fallback meshes.
const ITEM_TYPE_COLORS := {
	"food": Color(0.7, 0.4, 0.1),
	"drink": Color(0.2, 0.4, 0.7),
	"weapon": Color(0.5, 0.5, 0.55),
	"armor": Color(0.4, 0.4, 0.45),
	"tool": Color(0.5, 0.4, 0.3),
	"material": Color(0.6, 0.55, 0.45),
	"consumable": Color(0.3, 0.6, 0.3),
	"collectible": Color(0.7, 0.6, 0.2),
	"key": Color(0.8, 0.7, 0.2),
	"quest": Color(0.8, 0.3, 0.8),
	"book": Color(0.5, 0.35, 0.18),
}

## Item type → scale for procedural meshes.
const ITEM_TYPE_SCALES := {
	"food": Vector3(0.2, 0.15, 0.2),
	"drink": Vector3(0.1, 0.25, 0.1),
	"weapon": Vector3(0.15, 0.6, 0.1),
	"armor": Vector3(0.3, 0.3, 0.15),
	"tool": Vector3(0.15, 0.4, 0.1),
	"material": Vector3(0.25, 0.25, 0.25),
	"consumable": Vector3(0.15, 0.15, 0.15),
	"collectible": Vector3(0.15, 0.15, 0.15),
	"key": Vector3(0.1, 0.05, 0.2),
	"quest": Vector3(0.2, 0.2, 0.2),
	"book": Vector3(0.2, 0.03, 0.15),
}

var _items: Dictionary = {}  # item_id → Dictionary
var _books: Dictionary = {}  # book_id → Dictionary
var _bob_items: Array[Node3D] = []  # Items that bob/spin (quest items)
var _bob_time := 0.0

func _ready() -> void:
	add_to_group("world_generator")

func generate_from_data(world_data: Dictionary) -> void:
	var entities: Dictionary = world_data.get("entities", {})

	# Spawn items from IR
	var items: Array = entities.get("items", [])
	if items.is_empty():
		items = world_data.get("items", [])

	for item in items:
		var pos: Variant = item.get("position", null)
		if pos == null or not (pos is Dictionary):
			continue
		_spawn_item(item)

	# Spawn books from texts IR
	var texts: Array = world_data.get("systems", {}).get("texts", [])
	if texts.is_empty():
		texts = world_data.get("texts", [])

	for text in texts:
		var pos: Variant = text.get("position", null)
		if pos == null or not (pos is Dictionary):
			continue
		_spawn_book(text)

	print("[Insimul] ExteriorItemManager: %d items, %d books spawned" % [_items.size(), _books.size()])

func _spawn_item(data: Dictionary) -> void:
	var pos_dict: Dictionary = data.get("position", {})
	var pos := Vector3(pos_dict.get("x", 0), pos_dict.get("y", 0), pos_dict.get("z", 0))
	var item_id: String = data.get("id", "item_%d" % _items.size())
	var item_type: String = data.get("itemType", data.get("type", "collectible"))
	var model_key: String = data.get("modelAssetKey", "")

	var node: Node3D

	# Try to load asset model
	if model_key != "":
		var scene := load("res://" + model_key) as PackedScene
		if scene != null:
			node = scene.instantiate()
		else:
			node = _create_procedural_item(item_type)
	else:
		node = _create_procedural_item(item_type)

	node.name = "Item_%s" % item_id
	node.position = pos

	# Snap to terrain height
	var terrain := _find_terrain()
	if terrain != null and terrain.has_method("sample_height"):
		node.position.y = terrain.sample_height(pos.x, pos.z) + 0.3

	# Interaction area
	var area := Area3D.new()
	area.name = "PickupArea"
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 1.5
	col.shape = shape
	area.add_child(col)
	area.body_entered.connect(_on_item_body_entered.bind(item_id))
	node.add_child(area)

	_items[item_id] = {
		"node": node,
		"data": data,
		"collected": false,
	}

	# Quest items get bobbing animation
	if item_type == "quest" or data.get("objectRole", "") == "quest":
		_bob_items.append(node)

	add_child(node)

func _spawn_book(data: Dictionary) -> void:
	var pos_dict: Dictionary = data.get("position", {})
	var pos := Vector3(pos_dict.get("x", 0), pos_dict.get("y", 0), pos_dict.get("z", 0))
	var book_id: String = data.get("id", "book_%d" % _books.size())
	var content: String = data.get("content", data.get("text", ""))

	var node := Node3D.new()
	node.name = "Book_%s" % book_id
	node.position = pos

	# Book mesh
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	(mesh.mesh as BoxMesh).size = Vector3(0.2, 0.03, 0.15)
	mesh.position.y = 0.3
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.35, 0.18)
	mesh.material_override = mat
	mesh.name = "BookMesh"
	node.add_child(mesh)

	# Snap to terrain
	var terrain := _find_terrain()
	if terrain != null and terrain.has_method("sample_height"):
		node.position.y = terrain.sample_height(pos.x, pos.z) + 0.3

	# Label showing title
	var title: String = data.get("title", data.get("name", "Book"))
	var label := Label3D.new()
	label.text = title
	label.font_size = 16
	label.position.y = 0.5
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.name = "BookLabel"
	node.add_child(label)

	# Interaction area
	var area := Area3D.new()
	area.name = "ReadArea"
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 1.5
	col.shape = shape
	area.add_child(col)
	area.body_entered.connect(_on_book_body_entered.bind(book_id, content))
	node.add_child(area)

	_books[book_id] = {
		"node": node,
		"content": content,
		"data": data,
		"read": false,
	}

	add_child(node)

func _create_procedural_item(item_type: String) -> Node3D:
	var node := Node3D.new()
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()

	var item_scale: Vector3 = ITEM_TYPE_SCALES.get(item_type, Vector3(0.2, 0.2, 0.2))
	(mesh.mesh as BoxMesh).size = item_scale
	mesh.position.y = item_scale.y / 2.0 + 0.1

	var mat := StandardMaterial3D.new()
	mat.albedo_color = ITEM_TYPE_COLORS.get(item_type, Color(0.5, 0.5, 0.5))
	mesh.material_override = mat
	mesh.name = "ItemMesh"
	node.add_child(mesh)

	return node

func _process(delta: float) -> void:
	if _bob_items.is_empty():
		return

	_bob_time += delta
	for item in _bob_items:
		if is_instance_valid(item):
			# Gentle bobbing and spinning
			item.position.y += sin(_bob_time * 2.0) * delta * 0.3
			item.rotation.y += delta * 1.5

func _on_item_body_entered(body: Node3D, item_id: String) -> void:
	if not body.is_in_group("player"):
		return

	var item: Dictionary = _items.get(item_id, {})
	if item.is_empty() or item.get("collected", false):
		return

	item["collected"] = true
	item_collected.emit(item_id, item.get("data", {}))

	var node: Node3D = item.get("node")
	if is_instance_valid(node):
		node.visible = false
		_bob_items.erase(node)

func _on_book_body_entered(body: Node3D, book_id: String, content: String) -> void:
	if not body.is_in_group("player"):
		return

	var book: Dictionary = _books.get(book_id, {})
	if book.is_empty():
		return

	book["read"] = true
	book_read.emit(book_id, content)

func _find_terrain() -> Node:
	for gen in get_tree().get_nodes_in_group("world_generator"):
		if gen.has_method("sample_height"):
			return gen
	return null
