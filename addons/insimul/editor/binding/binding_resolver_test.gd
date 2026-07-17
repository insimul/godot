# binding_resolver_test.gd — the Godot headless leg of the Asset Binding Layer
# resolver gate (US-GB1).
#
# When a `godot` binary is on PATH this runs the GDScript resolver
# (InsimulBindingTable + InsimulBindingResolver) against the SHARED matrix
# (editor/binding/fixtures/resolver-matrix.json) end-to-end, plus the
# cross-engine pack round-trip (unity-fixture-pack.json) and sorted-serialization
# determinism — the exact cases the host C++ gate
# (gdextension/test/run_binding_tests.sh) proves on a bare box.
#
#   godot --headless -s addons/insimul/editor/binding/binding_resolver_test.gd
#   godot --headless -s .../binding_resolver_test.gd -- --fixtures /abs/fixtures
#
# The host C++ gate is the authority on the plain Ralph box; this SceneTree test
# is the editor-side twin that runs when a real Godot binary is available. This
# mirrors the host-vs-editor split used by world_source_test.gd.
extends SceneTree

var _pass := 0
var _fail := 0


func _initialize() -> void:
	var fixtures_dir := _resolve_fixtures_dir()
	print("[insimul-binding] fixtures: %s" % fixtures_dir)

	_test_matrix(fixtures_dir)
	_test_roundtrip(fixtures_dir)
	_test_determinism()

	print("-----------------------------------------------------------")
	print("[insimul-binding] %d passed, %d failed" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)


func _test_matrix(fixtures_dir: String) -> void:
	var doc := _read_json(fixtures_dir + "/resolver-matrix.json")
	if not (doc is Dictionary):
		_report("read resolver-matrix.json", false, "not a dict")
		return
	var resolver := InsimulBindingResolver.from_matrix_sources(doc.get("sources", []))
	_report("matrix sources parse", resolver.tiers.size() == 3, str(resolver.tiers.size()))

	for c in doc.get("cases", []):
		var query := String(c.get("query", ""))
		var got := resolver.resolve(query)
		var expect = c.get("expect", null)
		if expect == null:
			_report(String(c.get("name", query)), not got.get("resolved", false), "expected unresolved")
			continue
		var ok: bool = got.get("resolved", false) \
			and String(got.get("source", "")) == String(expect.get("source", "")) \
			and String(got.get("key", "")) == String(expect.get("key", ""))
		_report(String(c.get("name", query)), ok,
			"want %s/%s got %s/%s" % [expect.get("source"), expect.get("key"), got.get("source"), got.get("key")])


func _test_roundtrip(fixtures_dir: String) -> void:
	var text := _read_text(fixtures_dir + "/unity-fixture-pack.json")
	var table := InsimulBindingTable.import_pack_json(text)
	_report("unity pack imports", table.entries.size() == 3, str(table.entries.size()))

	var resolver := InsimulBindingResolver.new()
	resolver.add_tier(table)
	var house := resolver.resolve("building.residential.house")
	_report("resolve exact from unity pack",
		house.get("resolved", false) and String(house.get("entry", {}).get("scene", "")) == "Assets/Insimul/Buildings/House.prefab",
		String(house.get("entry", {}).get("scene", "")))
	var generic := resolver.resolve("building.commercial.tower")
	_report("resolve wildcard from unity pack",
		generic.get("resolved", false) and String(generic.get("key", "")) == "building.*",
		String(generic.get("key", "")))

	# Re-export -> re-import -> identical pack dict (stable round-trip).
	var s1 := table.export_pack_json()
	var table2 := InsimulBindingTable.import_pack_json(s1)
	var s2 := table2.export_pack_json()
	_report("round-trip stable", s1 == s2, "s1 != s2" if s1 != s2 else "")


func _test_determinism() -> void:
	var table := InsimulBindingTable.new()
	table.source_name = "z-order-test"
	table.priority = 10
	table.set_binding("prop.z", {"scene": "res://z.tscn"})
	table.set_binding("building.a", {"scene": "res://a.tscn"})
	table.set_binding("character.m", {"scene": "res://m.tscn"})
	var a := table.export_pack_json()
	var b := table.export_pack_json()
	_report("serialization deterministic", a == b, "a != b" if a != b else "")
	var ordered: bool = a.find("building.a") < a.find("character.m") and a.find("character.m") < a.find("prop.z")
	_report("declaration-order-independent sort", ordered, "")


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
	return "res://addons/insimul/editor/binding/fixtures"
