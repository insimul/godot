# reimport_test.gd — the Godot headless leg of the re-import diff policy gate
# (US-GB3).
#
# When a `godot` binary is on PATH this drives InsimulReimport end-to-end against
# the SHARED old/new manifests (editor/reimport/fixtures/{old,new}-manifest.json):
# it computes the diff and asserts every id lands in the bucket the committed
# golden (golden-diff-report.json) pins — the exact contract the host C++ gate
# (gdextension/test/run_reimport_tests.sh) proves on a bare box. It then builds
# two live scene trees, applies the reconciliation, and asserts the mutated tree
# honors the policy (hand edits untouched, dropped generated nodes deprecated,
# new nodes added).
#
#   godot --headless -s addons/insimul/editor/reimport/reimport_test.gd
#   godot --headless -s .../reimport_test.gd -- --fixtures /abs/fixtures
#
# The host C++ gate is the authority on the plain Ralph box; this SceneTree test
# is the editor-side twin that runs when a real Godot binary is available.
extends SceneTree

var _pass := 0
var _fail := 0


func _initialize() -> void:
	var fixtures_dir := _resolve_fixtures_dir()
	print("[insimul-reimport] fixtures: %s" % fixtures_dir)

	var old_m = _read_json(fixtures_dir + "/old-manifest.json")
	var new_m = _read_json(fixtures_dir + "/new-manifest.json")
	var golden = _read_json(fixtures_dir + "/golden-diff-report.json")
	if not (old_m is Dictionary and new_m is Dictionary and golden is Dictionary):
		_report("load fixtures", false, "one of old/new/golden failed to parse")
		_finish()
		return

	_test_diff_matches_golden(old_m, new_m, golden)
	_test_apply_reconciles_tree(old_m, new_m)

	_finish()


func _finish() -> void:
	print("-----------------------------------------------------------")
	print("[insimul-reimport] %d passed, %d failed" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)


func _test_diff_matches_golden(old_m: Dictionary, new_m: Dictionary, golden: Dictionary) -> void:
	var report := InsimulReimport.compute_diff(old_m.get("nodes", []), new_m.get("nodes", []))
	for bucket in ["added", "updated", "unchanged", "skipped", "deprecated"]:
		var got: Array = report.get(bucket, [])
		var want: Array = golden.get(bucket, [])
		_report("bucket %s matches golden" % bucket, JSON.stringify(got) == JSON.stringify(want),
			"%s vs %s" % [got, want])
	# No-op re-import: same manifest in and out touches nothing.
	var noop := InsimulReimport.compute_diff(new_m.get("nodes", []), new_m.get("nodes", []))
	var clean := noop["added"].is_empty() and noop["updated"].is_empty() and noop["deprecated"].is_empty()
	_report("no-op re-import touches nothing", clean, "")


func _test_apply_reconciles_tree(old_m: Dictionary, new_m: Dictionary) -> void:
	var existing := _tree_from_manifest(old_m)
	var fresh := _tree_from_manifest(new_m)
	var report := InsimulReimport.apply_reimport(existing, fresh)

	# Hand edits (prop.d, prop.f) must still be present, untouched, generated=false.
	var handedit := _find_child(existing, "prop.d")
	_report("hand edit prop.d preserved", handedit != null and not bool(handedit.get_meta("insimul_generated", true)), "")
	# The absent hand edit prop.f survives in place (never auto-removed).
	_report("absent hand edit prop.f preserved", _find_child(existing, "prop.f") != null, "")
	# Added node prop.c is now in the existing tree.
	_report("added prop.c materialized", _find_child(existing, "prop.c") != null, "")
	# Deprecated generated node prop.e moved under the Deprecated group.
	var group := _find_named(existing, InsimulReimport.DEPRECATED_GROUP)
	var deprecated_node = null if group == null else _find_child(group, "prop.e")
	_report("deprecated prop.e under Deprecated group",
		deprecated_node != null and deprecated_node.is_in_group("insimul_deprecated"), "")
	# Updated node building.b took the fresh transform (x = 22).
	var updated := _find_child(existing, "building.b")
	_report("updated building.b took fresh transform",
		updated != null and absf((updated as Node3D).position.x - 22.0) < 0.001, "")

	existing.free()
	# fresh's added child was reparented into existing (already freed); free the rest.
	if is_instance_valid(fresh):
		fresh.free()

	_report("diff report returned by apply", report.has("counts"), "")


# ── tree construction from a manifest ─────────────────────────────────────────
func _tree_from_manifest(manifest: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "World"
	for n in manifest.get("nodes", []):
		var node := Node3D.new()
		node.name = String(n.get("entityId", ""))
		var pos: Dictionary = n.get("position", {})
		node.position = Vector3(float(pos.get("x", 0.0)), float(pos.get("y", 0.0)), float(pos.get("z", 0.0)))
		node.rotation = Vector3(0.0, float(n.get("rotationY", 0.0)), 0.0)
		var scl: Dictionary = n.get("scale", {})
		node.scale = Vector3(float(scl.get("x", 1.0)), float(scl.get("y", 1.0)), float(scl.get("z", 1.0)))
		node.set_meta("insimul_entity_id", String(n.get("entityId", "")))
		node.set_meta("insimul_kind", String(n.get("kind", "")))
		node.set_meta("insimul_archetype", String(n.get("archetype", "")))
		node.set_meta("insimul_scene", String(n.get("scene", "")))
		node.set_meta("insimul_binding_source", String(n.get("bindingSource", "")))
		node.set_meta("insimul_generated", bool(n.get("generated", false)))
		root.add_child(node)
	return root


func _find_child(root: Node, entity_id: String) -> Node:
	for child in root.get_children():
		if child.has_meta("insimul_entity_id") and String(child.get_meta("insimul_entity_id")) == entity_id:
			return child
	return null


func _find_named(root: Node, node_name: String) -> Node:
	for child in root.get_children():
		if child.name == node_name:
			return child
	return null


# ── helpers ──────────────────────────────────────────────────────────────────
func _report(name: String, ok: bool, detail: String) -> void:
	print("  %s  %s%s" % ["PASS" if ok else "FAIL", name, ("" if detail.is_empty() else "  " + detail)])
	if ok:
		_pass += 1
	else:
		_fail += 1


func _read_text(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var text := f.get_as_text()
	f.close()
	return text


func _read_json(path: String):
	return JSON.parse_string(_read_text(path))


func _resolve_fixtures_dir() -> String:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--fixtures" and i + 1 < args.size():
			return args[i + 1]
	return "res://addons/insimul/editor/reimport/fixtures"
