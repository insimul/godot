class_name InsimulGameMenu
extends Control
## The in-game menu SHELL — a composite, mounted through the registry (US-3).
##
## One overlay a game puts on the tree once and forgets: it mounts the panels its
## manifest entry declares as `children` (the tabbed pause menu, the notification
## centre) and forwards open/close/toggle to whichever of them is a menu. Like the
## HUD, it owns no content and spells no panel key — the layout is manifest data,
## and every child goes through [method InsimulUiRegistry.instantiate], so each
## still meets the band-111 module gate on the way in.
##
## Which child is "the menu" is DUCK-TYPED (it answers `toggle`/`open_menu`), for
## the same reason [method InsimulUiRegistry.bind_activation] is: naming the class
## would be naming the panel, and a creator who overrides the menu key with their
## own scene must keep working.
##
## [codeblock]
## var ui := InsimulUiRegistry.shipped()
## ui.bind_activation(activation)
## var shell := ui.instantiate(key) as InsimulGameMenu
## add_child(shell)
## shell.mount(ui, key)                 # children come from the manifest, gated
## shell.configure(bundle.module_ids()) # tab visibility, forwarded to the menu
## [/codeblock]

signal opened
signal closed

## Panel key -> the mounted Control, for the children that passed the gate.
var _mounted: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	theme = InsimulUiTokens.build_theme()


## Instantiate every child the manifest declares for `layout_key`, through
## `registry`, and hand the registry on to whichever child resolves tab bodies with
## it. A child the module gate blocks is simply absent — the registry has already
## recorded WHY. Returns the keys that were mounted.
func mount(registry: InsimulUiRegistry, layout_key: String) -> PackedStringArray:
	var mounted := PackedStringArray()
	for key in registry.children(layout_key):
		var child := registry.instantiate(String(key))
		if child == null:
			continue
		add_child(child)
		if child.has_method("bind_registry"):
			child.call("bind_registry", registry)
		_mounted[String(key)] = child
		mounted.append(String(key))
	return mounted


## Forward the active genre bundle's enabled feature modules to the menu child.
func configure(enabled_modules: Array) -> void:
	var menu := menu_panel()
	if menu != null and menu.has_method("configure"):
		menu.call("configure", enabled_modules)


## The mounted child that behaves like a menu (duck-typed), or null.
func menu_panel() -> Node:
	for key in _mounted.keys():
		var child: Node = _mounted[key]
		if is_instance_valid(child) and child.has_method("toggle") and child.has_method("open_menu"):
			return child
	return null


func toggle() -> void:
	var menu := menu_panel()
	if menu == null:
		return
	menu.call("toggle")
	_emit_state(menu)


func open_menu(tab: String = "") -> void:
	var menu := menu_panel()
	if menu == null:
		return
	menu.call("open_menu", tab)
	_emit_state(menu)


func close_menu() -> void:
	var menu := menu_panel()
	if menu == null:
		return
	menu.call("close_menu")
	_emit_state(menu)


func is_open() -> bool:
	var menu := menu_panel()
	return menu != null and menu.has_method("is_open") and bool(menu.call("is_open"))


## The mounted child for `key`, or null when the gate blocked it.
func child_panel(key: String) -> Node:
	return _mounted.get(key, null)


func mounted_keys() -> Array:
	var out := _mounted.keys()
	out.sort()
	return out


## Drop every mounted child (a genre change, a new world).
func unmount() -> void:
	for key in _mounted.keys():
		var child: Node = _mounted[key]
		if is_instance_valid(child):
			remove_child(child)
			child.queue_free()
	_mounted.clear()


func _emit_state(menu: Node) -> void:
	if menu.has_method("is_open") and bool(menu.call("is_open")):
		opened.emit()
	else:
		closed.emit()
