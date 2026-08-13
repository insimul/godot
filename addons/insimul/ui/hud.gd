class_name InsimulHud
extends Control
## The heads-up display — a COMPOSITE, mounted through the registry (US-GU2).
##
## The HUD owns no content of its own. Its children are declared in the panel
## manifest (`children` on the HUD's entry) and mounted through
## [InsimulUiRegistry], which means every one of them passes the band-111 module
## gate on the way in: a world with no `map` module gets a HUD without a minimap,
## and nothing anywhere had to ask whether the world has a map.
##
## This file spells no panel key for the same reason the registry does not — the
## HUD's layout is data. [method mount] takes the key the host resolved it under,
## so even its OWN key is not written here.
##
## [codeblock]
## var ui := InsimulUiRegistry.shipped()
## ui.bind_activation(activation)
## var hud := ui.instantiate(key) as InsimulHud
## add_child(hud)
## hud.mount(ui, key)          # children come from the manifest, gated
## [/codeblock]

## Panel key -> the mounted Control, for the children that passed the gate.
var _mounted: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = InsimulUiTokens.build_theme()


## Instantiate every child the manifest declares for `layout_key`, through
## `registry`. A child the module gate blocks is simply absent — the registry has
## already recorded WHY in its diagnostics. Returns the keys that were mounted.
func mount(registry: InsimulUiRegistry, layout_key: String) -> PackedStringArray:
	var mounted := PackedStringArray()
	for key in registry.children(layout_key):
		var child := registry.instantiate(String(key))
		if child == null:
			continue
		add_child(child)
		_mounted[String(key)] = child
		mounted.append(String(key))
	return mounted


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
