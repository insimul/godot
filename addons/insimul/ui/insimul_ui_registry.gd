class_name InsimulUiRegistry
extends RefCounted
## Default-runtime UI panel registry (US-GU1).
##
## Maps a stable panel KEY (e.g. "quest_journal", "inventory", "dialogue") to a
## Godot scene, with a creator OVERRIDE layer that always wins over the shipped
## default, plus missing-panel diagnostics. This is the Godot mirror of the
## engine-neutral registry contract; the behavior (default lookup, override
## precedence, missing diagnostics) is pinned by the shared cases in
## packages/core/conformance/ui/registry-cases.json.
##
## Two resolution levels, on purpose:
##   - scene_ref(key) -> String : the opaque scene reference (a res:// path here).
##     Pure data, no disk access — this is what the shared cases exercise.
##   - instantiate(key) -> Node : loads + instantiates the PackedScene at runtime.
##     Only this touches the filesystem, so the registry stays unit-testable.
##
## Creator overrides come from two sources, applied in order (later wins):
##   1. Project setting `insimul/ui/panel_overrides` — a Dictionary { key: path }.
##   2. Explicit register(key, ref) calls.

## Project-settings key holding a { panel_key: scene_path } override Dictionary.
const OVERRIDES_SETTING := "insimul/ui/panel_overrides"

## The canonical default panel map. Keys mirror
## packages/core/conformance/ui/registry-cases.json → `panel_keys`. Scenes live
## under res://addons/insimul/ui/scenes/ in an exported game; a creator overrides
## any of them via the project setting or register().
const DEFAULT_PANELS := {
	"loading_screen": "res://addons/insimul/ui/scenes/loading_screen.tscn",
	"notifications": "res://addons/insimul/ui/scenes/notification_center.tscn",
	"hud": "res://addons/insimul/ui/scenes/hud.tscn",
	"main_menu": "res://addons/insimul/ui/scenes/main_menu.tscn",
	"game_menu": "res://addons/insimul/ui/scenes/game_menu.tscn",
	"quest_journal": "res://addons/insimul/ui/scenes/quest_journal.tscn",
	"quest_tracker": "res://addons/insimul/ui/scenes/quest_tracker.tscn",
	"quest_offer": "res://addons/insimul/ui/scenes/quest_offer.tscn",
	"inventory": "res://addons/insimul/ui/scenes/inventory.tscn",
	"container": "res://addons/insimul/ui/scenes/container.tscn",
	"merchant": "res://addons/insimul/ui/scenes/merchant.tscn",
	"dialogue": "res://addons/insimul/ui/scenes/dialogue.tscn",
	"pause_menu": "res://addons/insimul/ui/scenes/pause_menu.tscn",
	"save_load": "res://addons/insimul/ui/scenes/save_load.tscn",
}

var _defaults: Dictionary = {}
var _overrides: Dictionary = {}
var _diagnostics: Array = []


## Seed with the shipped defaults. Pass a custom default map (opaque scene ids)
## to run the shared registry cases; omit for the real default-UI panel set.
func _init(defaults: Dictionary = DEFAULT_PANELS) -> void:
	_defaults = defaults.duplicate(true)


## Load creator overrides from the project setting, if present. Silently ignores a
## missing/mistyped setting (the defaults still resolve).
func load_project_overrides() -> void:
	if not ProjectSettings.has_setting(OVERRIDES_SETTING):
		return
	var raw = ProjectSettings.get_setting(OVERRIDES_SETTING)
	if raw is Dictionary:
		for key in raw.keys():
			_overrides[String(key)] = String(raw[key])


## Apply an override map directly (key -> scene ref). Later calls win.
func apply_overrides(overrides: Dictionary) -> void:
	for key in overrides.keys():
		_overrides[String(key)] = String(overrides[key])


## Register / override a single panel's scene ref.
func register(key: String, scene_ref: String) -> void:
	_overrides[key] = scene_ref


## True if `key` resolves to a default or an override.
func has(key: String) -> bool:
	return _overrides.has(key) or _defaults.has(key)


## True if `key` is currently served by a creator override rather than the default.
func is_overridden(key: String) -> bool:
	return _overrides.has(key)


## The scene reference for `key` (override wins over default). Returns "" and
## records a diagnostic when the key is unknown.
func scene_ref(key: String) -> String:
	if _overrides.has(key):
		return String(_overrides[key])
	if _defaults.has(key):
		return String(_defaults[key])
	_record_missing(key)
	return ""


## Instantiate the panel scene for `key`, or null if unknown / unloadable. Records
## a diagnostic on any failure so a creator sees exactly which panel is broken.
func instantiate(key: String) -> Node:
	var ref := scene_ref(key)
	if ref == "":
		return null
	if not ResourceLoader.exists(ref):
		_record("missing_scene", key, "scene not found: %s" % ref)
		return null
	var packed = load(ref)
	if packed == null or not (packed is PackedScene):
		_record("bad_scene", key, "not a PackedScene: %s" % ref)
		return null
	return (packed as PackedScene).instantiate()


## All panel keys currently resolvable (defaults + overrides), sorted.
func keys() -> Array:
	var merged := {}
	for k in _defaults.keys():
		merged[k] = true
	for k in _overrides.keys():
		merged[k] = true
	var out := merged.keys()
	out.sort()
	return out


## Diagnostics accumulated by scene_ref()/instantiate() — array of
## { kind, key, message }. A creator-facing "why is this panel blank" log.
func diagnostics() -> Array:
	return _diagnostics.duplicate(true)


func has_diagnostics() -> bool:
	return not _diagnostics.is_empty()


func clear_diagnostics() -> void:
	_diagnostics.clear()


func _record_missing(key: String) -> void:
	_record("missing_panel", key, "no panel registered for key '%s'" % key)


func _record(kind: String, key: String, message: String) -> void:
	_diagnostics.append({"kind": kind, "key": key, "message": message})
