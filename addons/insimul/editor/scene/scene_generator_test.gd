# scene_generator_test.gd — the Godot headless leg of the scene-generation
# pipeline gate (US-GB2).
#
# When a `godot` binary is on PATH this drives the @tool pipeline
# (InsimulSceneGenerator + InsimulPlaceholderPack) end-to-end against the SHARED
# golden IR (editor/scene/fixtures/golden-ir.json): it materializes the scene
# tree, reads the placement manifest back off the generated nodes' metadata, and
# asserts it matches the committed golden (fixtures/golden-placement-manifest.json)
# — the exact contract the host C++ gate (gdextension/test/run_placement_tests.sh)
# proves on a bare box. It also checks placeholder coverage and determinism.
#
#   godot --headless -s addons/insimul/editor/scene/scene_generator_test.gd
#   godot --headless -s .../scene_generator_test.gd -- --fixtures /abs/fixtures
#
# The host C++ gate is the authority on the plain Ralph box; this SceneTree test
# is the editor-side twin that runs when a real Godot binary is available.
extends SceneTree

const EPS := 0.0005

var _pass := 0
var _fail := 0


func _initialize() -> void:
	var fixtures_dir := _resolve_fixtures_dir()
	print("[insimul-scene] fixtures: %s" % fixtures_dir)

	var ir = _read_json(fixtures_dir + "/golden-ir.json")
	var pack = _read_json(fixtures_dir + "/placeholder-pack.json")
	var golden = _read_json(fixtures_dir + "/golden-placement-manifest.json")
	if not (ir is Dictionary and pack is Dictionary and golden is Dictionary):
		_report("load fixtures", false, "one of ir/pack/golden failed to parse")
		_finish()
		return

	var resolver := InsimulBindingResolver.new()
	var table := InsimulBindingTable.new()
	table.from_pack_dict(pack)
	resolver.add_tier(table)
	resolver.sort_tiers()

	var seed_value := String(ir.get("meta", {}).get("seed", ""))

	_test_golden_match(ir, resolver, seed_value, golden)
	_test_placeholder_coverage(pack)
	_test_generator_pack_matches_fixture(pack)
	_test_determinism(ir, resolver, seed_value)

	_finish()


func _finish() -> void:
	print("-----------------------------------------------------------")
	print("[insimul-scene] %d passed, %d failed" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)


func _build_manifest(ir: Dictionary, resolver: InsimulBindingResolver, seed_value: String) -> Dictionary:
	var gen := InsimulSceneGenerator.new()
	var root := gen.generate(ir, resolver)
	var manifest := gen.manifest_from_tree(root, seed_value)
	root.free()
	return manifest


func _test_golden_match(ir: Dictionary, resolver: InsimulBindingResolver, seed_value: String, golden: Dictionary) -> void:
	var manifest := _build_manifest(ir, resolver, seed_value)
	_report("nodeCount matches golden",
		int(manifest.get("nodeCount", -1)) == int(golden.get("nodeCount", -2)),
		"%d vs %d" % [manifest.get("nodeCount", -1), golden.get("nodeCount", -2)])
	_report("seed matches golden", String(manifest.get("seed", "")) == String(golden.get("seed", "")), "")

	var got_nodes: Array = manifest.get("nodes", [])
	var want_nodes: Array = golden.get("nodes", [])
	var all_ok := got_nodes.size() == want_nodes.size()
	for i in min(got_nodes.size(), want_nodes.size()):
		if not _nodes_equal(got_nodes[i], want_nodes[i]):
			all_ok = false
			_report("node[%d] %s matches golden" % [i, want_nodes[i].get("entityId", "?")], false,
				"%s vs %s" % [got_nodes[i], want_nodes[i]])
	_report("all generated nodes match golden manifest", all_ok, "")


func _nodes_equal(a: Dictionary, b: Dictionary) -> bool:
	for key in ["entityId", "kind", "archetype", "scene", "bindingSource"]:
		if String(a.get(key, "")) != String(b.get(key, "")):
			return false
	if bool(a.get("generated", false)) != bool(b.get("generated", false)):
		return false
	if not _vec_equal(a.get("position", {}), b.get("position", {})):
		return false
	if not _vec_equal(a.get("scale", {}), b.get("scale", {})):
		return false
	if absf(float(a.get("rotationY", 0.0)) - float(b.get("rotationY", 0.0))) > EPS:
		return false
	return true


func _vec_equal(a: Dictionary, b: Dictionary) -> bool:
	for axis in ["x", "y", "z"]:
		if absf(float(a.get(axis, 0.0)) - float(b.get(axis, 0.0))) > EPS:
			return false
	return true


func _test_placeholder_coverage(pack: Dictionary) -> void:
	var resolver := InsimulBindingResolver.new()
	var table := InsimulBindingTable.new()
	table.from_pack_dict(pack)
	resolver.add_tier(table)
	var archetypes := [
		"terrain", "road.street", "road",
		"building.downtown", "building.commercial", "building.residential",
		"interior.downtown", "prop.tree", "prop.lamp",
	]
	var all_covered := true
	var missing := ""
	for a in archetypes:
		var res := resolver.resolve(a)
		if not res.get("resolved", false) or String(res.get("key", "")) == "*":
			all_covered = false
			missing += (", " if not missing.is_empty() else "") + a
	_report("placeholder pack covers every golden archetype", all_covered, missing)


func _test_generator_pack_matches_fixture(pack: Dictionary) -> void:
	# The procedural generator's table must equal the committed coverage fixture.
	var built := InsimulPlaceholderPack.new().build_pack_dict()
	var a := JSON.stringify(built.get("entries", []))
	var b := JSON.stringify(pack.get("entries", []))
	_report("generator pack entries match fixture", a == b, "" if a == b else "generator diverged from fixture")


func _test_determinism(ir: Dictionary, resolver: InsimulBindingResolver, seed_value: String) -> void:
	var m1 := _build_manifest(ir, resolver, seed_value)
	var m2 := _build_manifest(ir, resolver, seed_value)
	_report("two runs produce identical manifest", JSON.stringify(m1) == JSON.stringify(m2), "")


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
	return "res://addons/insimul/editor/scene/fixtures"
