class_name InsimulUiRegistry
extends RefCounted
## Default-runtime UI panel registry — the ONE place a panel is resolved.
##
## Maps a stable panel KEY (e.g. "quest_journal", "inventory", "dialogue") to a
## Godot scene, with a creator OVERRIDE layer that always wins over the shipped
## default, plus missing-panel diagnostics. This is the Godot mirror of the
## engine-neutral registry contract; the behavior (default lookup, override
## precedence, missing diagnostics) is pinned by the shared cases in
## conformance/ui/registry-cases.json, which the Unreal and Unity ports run too.
##
## ## Nothing here spells a panel or a module
##
## The shipped panel set lives in [constant MANIFEST_PATH] — panel key, the scene
## that serves it, and the Insimul modules (band 111) it needs. That is the same
## discipline [InsimulModuleActivation] works by, for the same reason: a creator
## adds, swaps or gates a panel by editing DATA, and no engine code changes.
## `tools/verify-ui/check-ui.mjs` greps this file for every panel key in the
## shared corpus and every module id in the activation table and fails on a hit.
##
## ## Two resolution levels, on purpose
##
##   - scene_ref(key) -> String : the opaque scene reference (a res:// path here).
##     Pure data, no disk access — this is what the shared cases exercise.
##   - instantiate(key) -> Node : loads + instantiates the PackedScene at runtime.
##     Only this touches the filesystem, so the registry stays unit-testable.
##
## ## Three layers, applied in order (later wins)
##
##   1. the shipped manifest,
##   2. project setting `insimul/ui/panel_overrides` — a Dictionary { key: path },
##   3. explicit register(key, ref) calls.
##
## ## The module gate
##
## A panel whose module the world does not activate does not resolve AT ALL: it
## answers "" and records a `module_inactive` diagnostic, so a creator is told
## why the panel is blank rather than shipping a button onto a system that is not
## there. Gating is OFF until an activation is bound ([method bind_activation] /
## [method set_active_modules]) — a registry nobody told about the world shows
## everything, which is what an editor session and the shared cases both want.
##
## [codeblock]
## var ui := InsimulUiRegistry.shipped()
## ui.bind_activation(InsimulModuleActivation.for_world(world_ir))
## var panel := ui.instantiate("merchant")   # null when the world has no trade
## for note in ui.diagnostics():
##     push_warning(note["message"])
## [/codeblock]

## Project-settings key holding a { panel_key: scene_path } override Dictionary.
const OVERRIDES_SETTING := "insimul/ui/panel_overrides"

## The shipped panel manifest — the default map and the module gates, as data.
const MANIFEST_PATH := "res://addons/insimul/ui/panels.json"

var _defaults: Dictionary = {}
var _requires: Dictionary = {}
var _children: Dictionary = {}
var _overrides: Dictionary = {}
var _diagnostics: Array = []
var _active_modules: PackedStringArray = PackedStringArray()
var _gated := false


## The registry a game runs on: the shipped manifest plus any creator override
## declared in project settings. Bind an activation to it to turn the module gate
## on.
static func shipped() -> InsimulUiRegistry:
	var registry := InsimulUiRegistry.new()
	registry.load_manifest(MANIFEST_PATH)
	registry.load_project_overrides()
	return registry


## Construct a bare registry. Pass a default map (key -> opaque scene id) and an
## optional requirement map (key -> Array of module ids) to run the shared cases
## against pure data; use [method shipped] for the real panel set.
func _init(defaults: Dictionary = {}, requirements: Dictionary = {}) -> void:
	_defaults = defaults.duplicate(true)
	for key in requirements.keys():
		_requires[String(key)] = _strings(requirements[key])


## Read a panel manifest ({ panels: { key: { scene, requires? } } }). Records a
## `bad_manifest` diagnostic and changes nothing when the file is missing or
## malformed — a broken install must still be diagnosable, not silently empty.
func load_manifest(path: String) -> bool:
	if not FileAccess.file_exists(path):
		_record("bad_manifest", "", "panel manifest not found: %s" % path)
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary) or not ((parsed as Dictionary).get("panels", null) is Dictionary):
		_record("bad_manifest", "", "panel manifest is not { panels: {...} }: %s" % path)
		return false
	var panels: Dictionary = (parsed as Dictionary)["panels"]
	for key in panels.keys():
		var entry: Variant = panels[key]
		if not (entry is Dictionary):
			_record("bad_manifest", String(key), "panel entry is not an object")
			continue
		_defaults[String(key)] = String((entry as Dictionary).get("scene", ""))
		_requires[String(key)] = _strings((entry as Dictionary).get("requires", []))
		_children[String(key)] = _strings((entry as Dictionary).get("children", []))
	return true


## Load creator overrides from the project setting, if present. Silently ignores a
## missing/mistyped setting (the defaults still resolve).
func load_project_overrides() -> void:
	if not ProjectSettings.has_setting(OVERRIDES_SETTING):
		return
	var raw: Variant = ProjectSettings.get_setting(OVERRIDES_SETTING)
	if raw is Dictionary:
		apply_overrides(raw)


## Apply an override map directly (key -> scene ref). Later calls win.
func apply_overrides(overrides: Dictionary) -> void:
	for key in overrides.keys():
		_overrides[String(key)] = String(overrides[key])


## Register / override a single panel's scene ref.
func register(key: String, scene_ref: String) -> void:
	_overrides[key] = scene_ref


# ── the module gate ──────────────────────────────────────────────────────────


## Gate every panel on what this world activates. Takes an
## [InsimulModuleActivation] — or anything answering `module_ids()` and `genre()`,
## which is what keeps the default UI compilable without the GDExtension the real
## activation reader needs.
##
## An activation that declared no genre runs every panel: see
## [InsimulModuleActivation]'s class doc for why "undeclared" is not "nothing is
## active".
func bind_activation(activation: Variant) -> void:
	if not (activation is Object) or not (activation as Object).has_method("module_ids"):
		clear_gating()
		return
	if (activation as Object).has_method("genre") and String(activation.genre()).is_empty():
		clear_gating()
		return
	set_active_modules(activation.module_ids())


## Gate on an explicit module-id set. Turns the gate ON, including for an empty
## set — a world that activates nothing offers only the ungated panels.
func set_active_modules(ids: Variant) -> void:
	_active_modules = _strings(ids)
	_gated = true


## Turn the gate off: every registered panel resolves again.
func clear_gating() -> void:
	_active_modules = PackedStringArray()
	_gated = false


## Whether a module gate is in force.
func is_gated() -> bool:
	return _gated


## The module ids `key` needs before it is offered. Empty for an ungated panel.
func requirements(key: String) -> PackedStringArray:
	return _strings(_requires.get(key, []))


## The panel keys a COMPOSITE panel mounts inside itself, in manifest order. Empty
## for a leaf panel. This is how a composite (the HUD) stays free of the keys it
## contains: its layout is manifest data like everything else, and each child still
## goes through [method instantiate], so each still meets the module gate.
func children(key: String) -> PackedStringArray:
	return _strings(_children.get(key, []))


## The required modules this world does NOT activate — why the panel is hidden.
## Empty when the gate is off or the panel is satisfied.
func missing_modules(key: String) -> PackedStringArray:
	var out := PackedStringArray()
	if not _gated:
		return out
	for module_id in requirements(key):
		if not _active_modules.has(module_id):
			out.append(module_id)
	return out


## True if `key` is registered AND its modules are active. This is the question a
## menu asks before it draws a button.
func is_available(key: String) -> bool:
	return has(key) and missing_modules(key).is_empty()


## Every key that is registered and passes the module gate, sorted.
func available_keys() -> Array:
	var out := []
	for key in keys():
		if is_available(String(key)):
			out.append(key)
	return out


# ── resolution ───────────────────────────────────────────────────────────────


## True if `key` resolves to a default or an override, module gate aside.
func has(key: String) -> bool:
	return _overrides.has(key) or _defaults.has(key)


## True if `key` is currently served by a creator override rather than the default.
func is_overridden(key: String) -> bool:
	return _overrides.has(key)


## The scene reference for `key` (override wins over default). Returns "" and
## records a diagnostic when the key is unknown, or when the world does not
## activate the modules the panel needs.
func scene_ref(key: String) -> String:
	if not has(key):
		_record("missing_panel", key, "no panel registered for key '%s'" % key)
		return ""
	var missing := missing_modules(key)
	if not missing.is_empty():
		_record(
			"module_inactive",
			key,
			"panel '%s' needs module(s) %s, which this world does not activate" % [key, ", ".join(missing)]
		)
		return ""
	if _overrides.has(key):
		return String(_overrides[key])
	return String(_defaults[key])


## Instantiate the panel scene for `key`, or null if unknown / gated off /
## unloadable. Records a diagnostic on any failure so a creator sees exactly which
## panel is broken.
func instantiate(key: String) -> Node:
	var ref := scene_ref(key)
	if ref == "":
		return null
	if not ResourceLoader.exists(ref):
		_record("missing_scene", key, "scene not found: %s" % ref)
		return null
	var packed: Variant = load(ref)
	if packed == null or not (packed is PackedScene):
		_record("bad_scene", key, "not a PackedScene: %s" % ref)
		return null
	return (packed as PackedScene).instantiate()


## All panel keys currently registered (defaults + overrides), sorted. Ignores the
## module gate — [method available_keys] is the gated answer.
func keys() -> Array:
	var merged := {}
	for k in _defaults.keys():
		merged[k] = true
	for k in _overrides.keys():
		merged[k] = true
	var out := merged.keys()
	out.sort()
	return out


## Diagnostics accumulated by scene_ref()/instantiate()/load_manifest() — array of
## { kind, key, message }. A creator-facing "why is this panel blank" log.
func diagnostics() -> Array:
	return _diagnostics.duplicate(true)


func has_diagnostics() -> bool:
	return not _diagnostics.is_empty()


func clear_diagnostics() -> void:
	_diagnostics.clear()


func _record(kind: String, key: String, message: String) -> void:
	_diagnostics.append({"kind": kind, "key": key, "message": message})


func _strings(value: Variant) -> PackedStringArray:
	var out := PackedStringArray()
	if value is PackedStringArray:
		return (value as PackedStringArray).duplicate()
	if value is Array:
		for item in (value as Array):
			out.append(String(item))
	return out
