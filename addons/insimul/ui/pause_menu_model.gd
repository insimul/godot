class_name InsimulPauseMenuModel
extends RefCounted
## Pause / ESC-menu tab-gating view-model (US-GU3).
##
## The Godot mirror of the engine-neutral pause-menu contract
## (packages/core/src/ui/pause-menu-model.ts). An ordered set of tabs, each
## optionally GATED by the feature modules the active genre bundle enabled. A tab
## with no "requires" is always shown; a gated tab shows only when EVERY required
## module is enabled. The Control (pause_menu.gd) owns get_tree().paused + input.
##
## Shared cases: packages/core/conformance/ui/pause-menu-cases.json.

## Default tabs. Core tabs are ungated; learning/progression tabs gate on a module.
## Each: { key, label, requires? } where requires is a String or Array of module ids.
const DEFAULT_TABS: Array = [
	{"key": "resume", "label": "Resume"},
	{"key": "journal", "label": "Journal"},
	{"key": "inventory", "label": "Inventory"},
	{"key": "map", "label": "Map"},
	{"key": "character", "label": "Character", "requires": "proficiency"},
	{"key": "vocabulary", "label": "Vocabulary", "requires": "knowledge-acquisition"},
	{"key": "skills", "label": "Skills", "requires": "skill-tree"},
	{"key": "analytics", "label": "Analytics", "requires": "conversation-analytics"},
	{"key": "assessment", "label": "Assessment", "requires": "assessment"},
	{"key": "settings", "label": "Settings"},
	{"key": "save", "label": "Save / Load"},
]

var _tabs: Array = []
var _enabled: Dictionary = {}       # module id -> true (a set)
var _open := false
var _active := ""


func _init(enabled_modules: Array = [], tabs: Array = DEFAULT_TABS) -> void:
	for m in enabled_modules:
		_enabled[String(m)] = true
	_tabs = tabs if not tabs.is_empty() else DEFAULT_TABS


func _required(tab: Dictionary) -> Array:
	if not tab.has("requires"):
		return []
	var req: Variant = tab["requires"]
	return req if req is Array else [req]


func _gated(tab: Dictionary) -> bool:
	for m in _required(tab):
		if not _enabled.has(String(m)):
			return false
	return true


## Tabs visible under the current module set, in declaration order.
func visible_tabs() -> Array:
	var out: Array = []
	for t in _tabs:
		if _gated(t):
			out.append((t as Dictionary).duplicate(true))
	return out


func visible_keys() -> Array:
	var out: Array = []
	for t in _tabs:
		if _gated(t):
			out.append(String(t["key"]))
	return out


func is_visible(key: String) -> bool:
	for t in _tabs:
		if String(t["key"]) == key:
			return _gated(t)
	return false


# ── Open / active-tab state ───────────────────────────────────────────────────

## Open the menu, optionally to a tab (falls back to the first visible tab).
func open_menu(tab: String = "") -> void:
	_open = true
	if tab != "" and is_visible(tab):
		_active = tab
	elif not is_visible(_active):
		var keys := visible_keys()
		_active = String(keys[0]) if not keys.is_empty() else ""


func close_menu() -> void:
	_open = false


func toggle() -> void:
	if _open:
		close_menu()
	else:
		open_menu()


func is_open() -> bool:
	return _open


## Switch tabs. Rejected (returns false) for a hidden/unknown tab.
func set_active(key: String) -> bool:
	if not is_visible(key):
		return false
	_active = key
	return true


func active_tab() -> String:
	return _active
