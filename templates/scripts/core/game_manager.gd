extends Node
## Central game manager — autoloaded singleton.
## Orchestrates data loading and world spawning.

signal world_loaded
signal world_spawned

var world_data: Dictionary = {}
var is_data_loaded := false

var _has_spawned := false

func _ready() -> void:
	load_world_data()
	# Don't spawn here — the main scene hasn't loaded yet (we're on the menu).
	# Wait for the scene tree to change to the game scene.
	get_tree().tree_changed.connect(_on_tree_changed)

func _on_tree_changed() -> void:
	if _has_spawned or not is_data_loaded:
		return
	var generators := get_tree().get_nodes_in_group("world_generator")
	if generators.size() > 0:
		_has_spawned = true
		get_tree().tree_changed.disconnect(_on_tree_changed)
		# Wait one more frame so all generators finish _ready()
		get_tree().process_frame.connect(_deferred_spawn, CONNECT_ONE_SHOT)

func _deferred_spawn() -> void:
	spawn_world()

func load_world_data() -> void:
	world_data = DataLoader.load_world_data()
	if world_data.is_empty():
		push_error("[Insimul] Failed to load world data")
		return
	is_data_loaded = true
	var meta: Dictionary = world_data.get("meta", {})
	print("[Insimul] Loaded world: %s (type: %s)" % [meta.get("worldName", "?"), meta.get("worldType", "?")])
	world_loaded.emit()

func spawn_world() -> void:
	print("[Insimul] Spawning world entities...")
	# Generators are expected as children of the main scene or found via groups
	for gen in get_tree().get_nodes_in_group("world_generator"):
		if gen.has_method("generate_from_data"):
			gen.generate_from_data(world_data)

	# Initialize systems
	ActionSystem.load_from_data(world_data)
	QuestSystem.load_from_data(world_data)
	CombatSystem.load_from_data(world_data)
	RuleEnforcer.load_from_data(world_data)
	InventorySystem.initialize()

	# Initialize survival system (conditionally loaded)
	var survival_system: Node = get_node_or_null("/root/SurvivalSystem")
	if survival_system and survival_system.has_method("load_from_data"):
		survival_system.load_from_data(world_data)

	# Register buildings with entry system
	var entry_system: Node = get_node_or_null("/root/BuildingEntrySystem")
	if entry_system and entry_system.has_method("register_buildings"):
		entry_system.register_buildings(world_data)

	print("[Insimul] World spawning complete.")
	world_spawned.emit()
