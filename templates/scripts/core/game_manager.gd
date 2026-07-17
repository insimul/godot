extends Node
## Central game manager — autoloaded singleton.
## Orchestrates data loading and world spawning.
##
## Portable runtime (US-GC4): when the Insimul addon is vendored AND a portable
## worldSnapshot export is present, startup boots the InsimulRuntime orchestrator
## — world source -> save slot -> KB -> systems — and the world source becomes the
## authoritative source of character identity for the spawner. When either is
## absent (the default template state), the legacy DataLoader/SaveSystem/QuestSystem
## autoloads drive startup UNCHANGED (zero behavior delta). See ../../MIGRATION.md.

signal world_loaded
signal world_spawned

const _RUNTIME_SCRIPT := "res://addons/insimul/runtime/runtime_bootstrap.gd"
const _WORLD_SNAPSHOT_PATH := "res://data/world_snapshot.json"

var world_data: Dictionary = {}
var is_data_loaded := false

## The booted portable runtime (InsimulRuntime), or null when the legacy path runs.
var insimul_runtime = null

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
	_boot_insimul_runtime(meta)
	world_loaded.emit()

## Boot the portable runtime core (world source -> save slot -> KB -> systems) when
## the addon + a worldSnapshot export are present. Guarded so a missing addon /
## export / extension degrades to the legacy startup path without error.
func _boot_insimul_runtime(meta: Dictionary) -> void:
	if not FileAccess.file_exists(_WORLD_SNAPSHOT_PATH):
		return  # no portable export — legacy DataLoader path drives startup
	var runtime_script: Variant = load(_RUNTIME_SCRIPT)
	if runtime_script == null:
		return  # addon not vendored — legacy path
	var rt: Object = runtime_script.new()
	if not rt.available():
		push_warning("[Insimul] portable save extension not built — using legacy startup path")
		return
	var snapshot: String = FileAccess.get_file_as_string(_WORLD_SNAPSHOT_PATH)
	var world_id: String = str(meta.get("worldId", meta.get("worldName", "world")))
	var boot: Dictionary = rt.boot(0, snapshot, "playthrough-0", "local", world_id, "New Game")
	if not boot.get("ok", false):
		push_warning("[Insimul] runtime boot failed: %s — using legacy startup path" % rt.last_error())
		return
	insimul_runtime = rt
	print("[Insimul] runtime booted (%s): world source + save slot + KB + quests" % ("resumed save" if boot.get("resumed_save", false) else "new game"))

## The booted world source (InsimulWorldSource), or null when the legacy path runs.
## The npc_spawner reads this as the authoritative source of character identity.
func get_world_source():
	return insimul_runtime.world if insimul_runtime != null else null

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
