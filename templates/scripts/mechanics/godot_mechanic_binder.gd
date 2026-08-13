extends Node
## Activates the mechanic modules THIS WORLD selected, and nothing else —
## tasklist 147, US-3.
##
## Drop this node into the scene once. On `_ready()` it reads the genre out of
## the exported world IR, asks core which modules that genre's bundle selects,
## and opens a session for each one it can drive — wiring only the host
## interfaces those modules declare.
##
## ## Why there is no list of mechanics in this file
##
## Because there is no list of mechanics anywhere in the plugin. The set comes
## from `meta.genreConfig.id` in `world_ir.json` through
## [InsimulModuleActivation]; adding a module to a genre bundle upstream changes
## what this node opens with no code change here and none in the addon. The one
## thing a game must still supply is each module's CREATE arguments — a roster, a
## seed, an action table — because those are the world's, not the module's. Fill
## them in a listener:
##
## [codeblock]
## func _ready() -> void:
##     var binder := $InsimulMechanicBinder
##     binder.creating_module.connect(_on_creating_module)
##
## func _on_creating_module(module_id: String, args: Dictionary) -> void:
##     if module_id == "combat":
##         args["combatants"] = _roster()
##         args["actions"] = DataLoader.load_combat_actions()
## [/codeblock]
##
## ## What an inactive module gets
##
## Nothing at all: no consulted rule pack (its vocabulary is not in the KB these
## sessions open with), no session, and no wired host — the implementations below
## are offered to the activator as a table, and a module that does not declare an
## interface never receives it.

## A session is about to be created. Fill `args` with this module's create
## arguments, in core's own field names (see the row table in
## `gdextension/corebridge/js/entry.js`). `kb` is supplied by the activator and
## is overwritten if you set it.
signal creating_module(module_id: String, args: Dictionary)
## Every session this world activated is open.
signal modules_activated(opened: PackedStringArray, unreachable: Dictionary)

## The world's own Prolog facts, consulted after the active rule packs.
@export_multiline var world_facts := ""
## Print the activation and the sessions at startup. A creator should be told
## which mechanics are live rather than left to infer it from a component.
@export var log_activation := true

## Optional: the host components. Left empty, the binder looks for them among
## its own children, which is how the sample scene wires them.
@export var combat_host_path: NodePath
@export var geometry_probes_path: NodePath
@export var locomotion_host_path: NodePath
@export var skill_sink_path: NodePath
@export var survival_host_path: NodePath

var _activation: InsimulModuleActivation = null
var _live: InsimulMechanicActivator = null


func _ready() -> void:
	activate()


func _exit_tree() -> void:
	if _live != null:
		_live.dispose_all()


## Resolve and activate. Called on `_ready()`; call it again after loading a
## different world.
func activate() -> void:
	if _live != null:
		_live.dispose_all()
	_activation = _resolve()
	var args_by_module := {}
	for module_id in _activation.module_ids():
		var args := {}
		creating_module.emit(module_id, args)
		args_by_module[module_id] = args
	_live = InsimulMechanicActivator.activate(_activation, world_facts, args_by_module, _hosts())
	if log_activation:
		for line in _activation.report():
			print(line)
		for line in _live.report():
			print(line)
	modules_activated.emit(_live.opened(), _live.unreachable())


## What this world selected.
func activation() -> InsimulModuleActivation:
	return _activation


## The open session for a module, or null. Never assume: a genre that does not
## select the module, and a build with no rows for it, both answer null.
func session(module_id: String) -> InsimulMechanicSession:
	return _live.session(module_id) if _live != null else null


## Whether this world selected the module AND a session is open for it.
func is_live(module_id: String) -> bool:
	return _live != null and _live.session(module_id) != null


# ── the world's genre ────────────────────────────────────────────────────────

func _resolve() -> InsimulModuleActivation:
	# The genre rides in the exported world IR. A game with no world data at all
	# resolves UNDECLARED — every pack, nothing activated — which the report says
	# out loud rather than pretending to be a genre.
	var loader := get_node_or_null("/root/DataLoader")
	if loader != null and loader.has_method("load_world_data"):
		var ir: Variant = loader.call("load_world_data")
		if ir is Dictionary:
			return InsimulModuleActivation.for_world(ir)
	return InsimulModuleActivation.undeclared()


# ── the host table ───────────────────────────────────────────────────────────

## Interface name -> implementation, from whichever host components this scene
## carries. The activator hands each session only the interfaces its own module
## declares, so a table with more in it than the world needs is harmless — and a
## table with less means those interfaces fall back to the addon's documented
## defaults rather than to nothing.
func _hosts() -> Dictionary:
	var hosts := {}
	var combat := _component(combat_host_path, "combat_system")
	if combat != null:
		hosts["ICombatSystem"] = combat.combat_system()
		hosts["ICombatStatSink"] = combat.stat_sink()
	var probes := _component(geometry_probes_path, "trajectory")
	if probes != null:
		hosts["ITrajectoryProbe"] = probes.trajectory()
		hosts["IPerceptionProbe"] = probes.perception()
		hosts["ITraversalProbe"] = probes.traversal()
	var locomotion := _component(locomotion_host_path, "host")
	if locomotion != null:
		hosts["ILocomotionHost"] = locomotion.host()
	var skills := _component(skill_sink_path, "sink")
	if skills != null:
		hosts["ISkillModifierSink"] = skills.sink()
	var survival := _component(survival_host_path, "survival_system")
	if survival != null:
		hosts["ISurvivalSystem"] = survival.survival_system()
	return hosts


## The node at `path`, or the first child that answers `method` — so the sample
## scene can wire by parenting and a real game can wire by NodePath.
func _component(path: NodePath, method: String) -> Node:
	if not path.is_empty():
		var node := get_node_or_null(path)
		if node != null and node.has_method(method):
			return node
	for child in get_children():
		if child is Node and (child as Node).has_method(method):
			return child
	return null
