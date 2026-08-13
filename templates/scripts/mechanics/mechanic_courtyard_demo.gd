extends Node3D
## The playable sample scene for the adopted mechanics — tasklist 147, US-3.
##
## A guard on a dark courtyard wall, a wanderer below, one lantern, one crate.
## Two mechanics run end to end in it, and the point of the scene is WHERE each
## line is drawn:
##
## [codeblock]
## the engine measures   a raycast from the guard's eyes to the wanderer, the
##                       light level at the wanderer's feet, the distance
##                       between them. `godot_geometry_probes.gd`.
## core decides          whether that adds up to a detection, how much suspicion
##                       it is worth, whether the shot connects, how much damage
##                       it did. Not one of those numbers is computed in this
##                       file or anywhere else in the template.
## the engine executes   the health bar moves, the guard turns, the hit sound
##                       plays — from the ORDERS the decision came back with.
## [/codeblock]
##
## ## Why the steps are a JSON file and not written out below
##
## Because a scene a human has to open is a scene nothing checks. The steps live
## in `res://insimul/scenarios/dark-courtyard.json`, and
## `gdextension/test/run_activation_tests.sh` replays that same file through the
## same bridge rows on a box with no Godot binary at all. Editing the scenario
## changes both. What it CANNOT check is this file: the raycasts, the lights and
## the bodies are the half that needs an engine, which is why VERIFICATION.md
## still lists a human pass.
##
## Run it: `godot --path templates/project -s scripts/mechanics/mechanic_courtyard_demo.gd`,
## or open the scene and press play.

const SCENARIO_PATH := "res://insimul/scenarios/dark-courtyard.json"

const BINDER_SCRIPT := preload("res://scripts/mechanics/godot_mechanic_binder.gd")
const COMBAT_HOST_SCRIPT := preload("res://scripts/mechanics/godot_combat_host.gd")
const PROBES_SCRIPT := preload("res://scripts/mechanics/godot_geometry_probes.gd")

var _scenario := {}
var _binder: Node = null
var _probes: Node = null
var _combat_host: Node = null
var _failures := 0


func _ready() -> void:
	_scenario = _load_scenario()
	if _scenario.is_empty():
		push_error("[courtyard] no scenario at %s" % SCENARIO_PATH)
		return
	_build_courtyard()
	_build_hosts()
	_binder.creating_module.connect(_on_creating_module)
	_binder.modules_activated.connect(_on_modules_activated)
	add_child(_binder)


# ── the world ────────────────────────────────────────────────────────────────

func _build_courtyard() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_energy = 0.05          # night: the lantern is what matters
	sun.rotation_degrees = Vector3(-70, 30, 0)
	add_child(sun)

	var lantern := OmniLight3D.new()
	lantern.name = "Lantern"
	lantern.position = Vector3(0, 3, 0)
	lantern.omni_range = 8.0
	add_child(lantern)

	add_child(_body("guard", Vector3(0, 0, -6)))
	add_child(_body("wanderer", Vector3(0, 0, 2)))
	add_child(_obstacle("crate", Vector3(0, 0.5, -2), Vector3(1.5, 1.5, 1.5)))
	add_child(_obstacle("wall", Vector3(6, 2, 0), Vector3(0.5, 4, 12)))


func _body(actor_id: String, at: Vector3) -> CharacterBody3D:
	var body := CharacterBody3D.new()
	body.name = actor_id
	body.position = at
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.height = 1.8
	capsule.radius = 0.35
	shape.shape = capsule
	shape.position = Vector3(0, 0.9, 0)
	body.add_child(shape)
	return body


func _obstacle(obstacle_name: String, at: Vector3, extents: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = obstacle_name
	body.position = at
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = extents
	shape.shape = box
	body.add_child(shape)
	return body


func _build_hosts() -> void:
	_binder = Node.new()
	_binder.name = "InsimulMechanicBinder"
	_binder.set_script(BINDER_SCRIPT)
	_binder.world_facts = String(_scenario.get("worldFacts", ""))

	_combat_host = Node.new()
	_combat_host.name = "GodotCombatHost"
	_combat_host.set_script(COMBAT_HOST_SCRIPT)
	_binder.add_child(_combat_host)

	_probes = Node.new()
	_probes.name = "GodotGeometryProbes"
	_probes.set_script(PROBES_SCRIPT)
	_probes.sun_path = NodePath("../../Sun")
	_binder.add_child(_probes)


# ── activation ───────────────────────────────────────────────────────────────

## Each session's create arguments come from the scenario, which is the world's
## data. The binder asked; it did not decide.
func _on_creating_module(module_id: String, args: Dictionary) -> void:
	for entry in _scenario.get("sessions", []):
		if entry is Dictionary and String(entry.get("module", "")) == module_id:
			for key in entry.get("args", {}):
				args[key] = entry["args"][key]


func _on_modules_activated(opened: PackedStringArray, unreachable: Dictionary) -> void:
	print("[courtyard] live: %s" % ", ".join(opened))
	for module_id in unreachable:
		# Selected by the genre and not runnable here. Said out loud, because a
		# skipped mechanic looks exactly like a working one from the outside.
		print("[courtyard] selected but not runnable: %s (%s)" % [module_id, unreachable[module_id]])
	_run_steps()


# ── the steps ────────────────────────────────────────────────────────────────

func _run_steps() -> void:
	var index := 0
	for step in _scenario.get("steps", []):
		if not (step is Dictionary):
			continue
		index += 1
		var module_id := String(step.get("module", ""))
		var session: InsimulMechanicSession = _binder.session(module_id)
		if session == null:
			print("[courtyard] step %d SKIPPED — %s is not live in this world" % [index, module_id])
			continue
		var args: Dictionary = (step.get("args", {}) as Dictionary).duplicate(true)
		_take_readings(module_id, args)
		var report := session.call_row(String(step.get("row", "")), args)
		if report.is_empty() and not session.last_error().is_empty():
			_failures += 1
			print("[courtyard] step %d FAILED — %s" % [index, session.last_error()])
			continue
		print(
			"[courtyard] step %d %s.%s -> %s (%d order(s) carried out)"
			% [index, module_id, step.get("row", ""), JSON.stringify(report), session.last_orders().size()]
		)
	print("[courtyard] %d step(s), %d failure(s)" % [index, _failures])


## Replace the scenario's authored readings with what this engine MEASURES.
##
## The scenario pins what the courtyard is meant to look like so a headless gate
## can replay it; in the running game the raycast and the light probe answer, and
## core sees the engine's numbers. That difference is the whole reason the host
## interfaces are "asked" rather than "told".
func _take_readings(module_id: String, args: Dictionary) -> void:
	if args.has("readings") and args["readings"] is Array:
		var measured := []
		for reading in args["readings"]:
			if not (reading is Dictionary):
				continue
			var sensed: Dictionary = _probes.sense_perception({
				"observer": String(reading.get("observer", "")),
				"target": String(reading.get("target", "")),
			})
			sensed["observer"] = reading.get("observer", "")
			sensed["target"] = reading.get("target", "")
			measured.append(sensed)
		if measured.size() > 0:
			args["readings"] = measured
	if args.has("trajectory"):
		args["trajectory"] = _probes.query_trajectory({
			"attacker": String(args.get("attackerId", "")),
			"target": String(args.get("targetId", "")),
			"action": String(args.get("action", "")),
		})
	if module_id.is_empty():
		return


# ── data ─────────────────────────────────────────────────────────────────────

func _load_scenario() -> Dictionary:
	if not FileAccess.file_exists(SCENARIO_PATH):
		return {}
	var text := FileAccess.get_file_as_string(SCENARIO_PATH)
	var parsed: Variant = JSON.parse_string(text)
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}
