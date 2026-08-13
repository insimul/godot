class_name InsimulMechanicSurface
extends RefCounted
## What THIS BUILD can actually do with the band-120 mechanic modules, asked of
## the binary rather than inferred — tasklist 147, US-1.
##
## ## Why a build must be asked and not trusted
##
## `libinsimulcore` is a vendored artifact with a recorded core commit, and a game
## may be running against a copy older or newer than the plugin it is installed
## beside. A version string cannot answer "can this build resolve an attack" —
## `core.methods` and `mechanic.modules` can, because they are computed from the
## bundle's own method table. Unity's probe landed on the same rule the hard way
## (its RUNTIME_CORE_ADOPTION.md §12.6 item 2) after reporting a mechanic as
## adopted against a binary that carried no row for it.
##
## So a game asks:
##
## [codeblock]
## var surface := InsimulMechanicSurface.new()
## for line in surface.report():
##     print(line)
## if surface.status("combat") != InsimulMechanicSurface.READY:
##     hud.hide_combat_ui()
## [/codeblock]
##
## and the boot log says which mechanics are live rather than leaving a creator
## to infer it from a component that exists.

## Every row the module needs is in this build, and the module can be opened.
const READY := "ready"
## No `InsimulCore` class, or the bridge would not start — this build has no
## libinsimulcore at all.
const BRIDGE_MISSING := "bridge_missing"
## The bridge is here but carries no row for this module. What Unity's probe
## reported for all seven, because its bridge lives in a repository a Unity
## worktree cannot edit; this plugin's bridge is in-tree, so it should now be
## reachable — seeing this means the vendored bundle predates tasklist 147.
const BRIDGE_HAS_NO_ROW := "bridge_has_no_row"
## The build claims rows this plugin does not know how to drive: the bundle is
## NEWER than the addon. Reported rather than ignored, because the difference
## between the two is exactly what a version stamp hides.
const PLUGIN_IS_OLDER := "plugin_is_older"

var _core: InsimulCore = null
var _methods := {}
var _modules := {}
var _error := ""


func _init() -> void:
	_probe()


## Reason the surface could not be measured, or "".
func last_error() -> String:
	return _error


## One of the status constants, for a module name in [constant InsimulMechanicSession.MODULES].
func status(module_name: String) -> String:
	if _core == null:
		return BRIDGE_MISSING
	if not _modules.has(module_name):
		return BRIDGE_HAS_NO_ROW
	var declared: Variant = _modules[module_name].get("rows", [])
	if not (declared is Array):
		return BRIDGE_HAS_NO_ROW
	for row in declared:
		if not _methods.has(String(row)):
			return BRIDGE_HAS_NO_ROW
	if not InsimulMechanicSession.MODULES.has(module_name):
		return PLUGIN_IS_OLDER
	return READY


## The host interfaces one module executes through, as core's manifest names
## them. Empty for a module this build cannot reach.
func host_interfaces(module_name: String) -> PackedStringArray:
	var out := PackedStringArray()
	if not _modules.has(module_name):
		return out
	var declared: Variant = _modules[module_name].get("hostInterfaces", [])
	if declared is Array:
		for name in declared:
			out.append(String(name))
	return out


## Every module the BUILD claims, which is not necessarily every module this
## plugin knows how to drive — the difference is the point.
func modules() -> PackedStringArray:
	var out := PackedStringArray()
	for module_name in _modules.keys():
		out.append(String(module_name))
	out.sort()
	return out


## A boot-log block: one line per module, with its status and its interfaces.
## Printed by the plugin at startup so a creator is TOLD, not left to infer.
func report() -> PackedStringArray:
	var lines := PackedStringArray()
	if _core == null:
		lines.append("[Insimul] mechanics: no core bridge (%s)" % _error)
		return lines
	lines.append("[Insimul] mechanics — %s" % _core.get_version())
	var names := InsimulMechanicSession.MODULES.duplicate()
	for extra in modules():
		if not names.has(extra):
			names.append(extra)
	for module_name in names:
		var state := status(module_name)
		var interfaces := host_interfaces(module_name)
		lines.append(
			"  %-11s %-18s %s"
			% [
				module_name,
				state,
				", ".join(interfaces) if interfaces.size() > 0 else "-",
			]
		)
	return lines


func _probe() -> void:
	if not ClassDB.class_exists("InsimulCore"):
		_error = "InsimulCore is not registered — this build has no libinsimulcore"
		return
	var core := InsimulCore.new()
	if not core.is_available():
		_error = core.last_error()
		return
	_core = core

	var methods: Variant = _parse(core, "core.methods").get("methods", [])
	if methods is Array:
		for method_name in methods:
			_methods[String(method_name)] = true

	# A build older than this file has no `mechanic.modules` at all; that is a
	# missing row like any other, and every module then reads BRIDGE_HAS_NO_ROW.
	var table: Variant = _parse(core, "mechanic.modules").get("modules", {})
	if table is Dictionary:
		_modules = table


func _parse(core: InsimulCore, method: String) -> Dictionary:
	var response := core.call_json(method, "{}")
	if response.is_empty():
		_error = core.last_error()
		return {}
	var parsed: Variant = JSON.parse_string(response)
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}
