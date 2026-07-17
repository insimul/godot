# binding_dock_test.gd — the Godot headless leg of the Binding Editor dock gate
# (US-GB3), exercising the LOGIC LAYER (InsimulBindingDockModel).
#
# The dock UI (insimul_binding_dock.gd) needs a running editor, so it is only
# structurally checked; the model is UI-free and fully testable here. When a
# `godot` binary is on PATH this drives taxonomy-tree construction, bound/unbound
# status, suggestion ranking, bind / bind-descendants, and pack import/export
# round-trip. When NO binary is present the runner SKIPs (the structural lint
# covers the .gd on a bare box).
#
#   godot --headless -s addons/insimul/editor/dock/binding_dock_test.gd
extends SceneTree

var _pass := 0
var _fail := 0


func _initialize() -> void:
	_test_bound_unbound()
	_test_taxonomy_tree()
	_test_suggestions()
	_test_bind_descendants()
	_test_pack_roundtrip()
	_finish()


func _finish() -> void:
	print("-----------------------------------------------------------")
	print("[insimul-dock] %d passed, %d failed" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)


func _archetypes() -> Array:
	return [
		"building.residential", "building.commercial", "building.downtown",
		"prop.tree", "prop.lamp", "road.street",
	]


func _test_bound_unbound() -> void:
	var table := InsimulBindingTable.new()
	table.set_binding("building.residential", {"scene": "res://a.tscn"})
	var model := InsimulBindingDockModel.new(table)
	var bound := model.bound_keys(_archetypes())
	var unbound := model.unbound_keys(_archetypes())
	_report("residential is bound", bound.has("building.residential"), "")
	_report("commercial is unbound", unbound.has("building.commercial"), "")
	_report("bound + unbound partition the set", bound.size() + unbound.size() == _archetypes().size(),
		"%d + %d" % [bound.size(), unbound.size()])


func _test_taxonomy_tree() -> void:
	var table := InsimulBindingTable.new()
	# Binding the parent 'building' covers all building.* via descendant match.
	table.set_binding("building", {"scene": "res://generic_building.tscn"})
	var model := InsimulBindingDockModel.new(table)
	var tree := model.build_taxonomy_tree(_archetypes())
	var building: Dictionary = tree.get("children", {}).get("building", {})
	_report("taxonomy tree has building node", not building.is_empty(), "")
	var residential: Dictionary = building.get("children", {}).get("residential", {})
	_report("building.residential bound via descendant match", bool(residential.get("bound", false)), "")


func _test_suggestions() -> void:
	var model := InsimulBindingDockModel.new()
	var assets := [
		{"path": "res://art/residential_house.tscn", "name": "residential_house", "tags": ["building"]},
		{"path": "res://art/oak_tree.tscn", "name": "oak_tree", "tags": ["prop", "nature"]},
		{"path": "res://art/unrelated.tscn", "name": "unrelated", "tags": []},
	]
	var suggestions := model.suggest_bindings("building.residential", assets)
	_report("top suggestion is the residential building",
		suggestions.size() > 0 and String(suggestions[0].get("path", "")) == "res://art/residential_house.tscn",
		"%s" % suggestions)
	_report("unrelated asset excluded", not _has_path(suggestions, "res://art/unrelated.tscn"), "")


func _test_bind_descendants() -> void:
	var model := InsimulBindingDockModel.new()
	model.bind_descendants("prop", "res://generic_prop.tscn")
	_report("prop.tree bound after bind_descendants('prop')", model.is_bound("prop.tree"), "")
	_report("prop.lamp bound after bind_descendants('prop')", model.is_bound("prop.lamp"), "")
	_report("building unaffected by prop descendant bind", not model.is_bound("building.commercial"), "")


func _test_pack_roundtrip() -> void:
	var model := InsimulBindingDockModel.new()
	model.bind("building.residential", "res://house.tscn")
	model.bind("prop.tree", "res://tree.tscn")
	var json := model.export_pack_json()

	var reloaded := InsimulBindingDockModel.new()
	var ok := reloaded.import_pack_json(json)
	_report("pack imports", ok, "")
	_report("round-trip preserves residential binding", reloaded.is_bound("building.residential"), "")
	_report("round-trip export is byte-stable", reloaded.export_pack_json() == json, "")


# ── helpers ──────────────────────────────────────────────────────────────────
func _has_path(suggestions: Array, path: String) -> bool:
	for s in suggestions:
		if String(s.get("path", "")) == path:
			return true
	return false


func _report(name: String, ok: bool, detail: String) -> void:
	print("  %s  %s%s" % ["PASS" if ok else "FAIL", name, ("" if detail.is_empty() else "  " + detail)])
	if ok:
		_pass += 1
	else:
		_fail += 1
