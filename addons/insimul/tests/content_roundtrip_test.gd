# content_roundtrip_test.gd — the Godot leg of the content-library ROUND-TRIP
# parity gate (content-portability, US-IM2).
#
# US-IM1 proved the shared content library imports into the expected native Godot
# entities. This proves the imported content carries the SAME semantics as the
# source library: it re-exports the materialized entities back into an
# engine-neutral library, re-imports that through a fresh InsimulContentLibrary,
# and asserts the re-import matches the shared golden (conformance/content/
# library.json) collection-for-collection and field-for-field. That is the
# per-engine leg of the author-once / use-anywhere proof — the same golden every
# other engine's importer round-trips against, so no engine can silently diverge.
#
#   godot --headless -s addons/insimul/tests/content_roundtrip_test.gd
#   godot --headless -s addons/insimul/tests/content_roundtrip_test.gd -- --fixtures /abs/content
#
# Exit 0 iff every check passes; non-zero (with a per-check FAIL line) otherwise.
# When godot is absent (the Ralph harness), the GDScript structural lint
# (tools/verify-godot/check.mjs) covers the addon `.gd` files; see VERIFICATION.md
# for the host-vs-editor split. Mirrors content_import_test.gd.
extends SceneTree

var _pass := 0
var _fail := 0


func _initialize() -> void:
	var fixtures_dir := _resolve_fixtures_dir()
	print("[insimul-content-roundtrip] fixtures: %s" % fixtures_dir)

	_test_roundtrip_matches_golden(fixtures_dir)

	print("-----------------------------------------------------------")
	print("[insimul-content-roundtrip] %d passed, %d failed" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)


# ── AC: the imported content round-trips back to the shared golden ────────────
func _test_roundtrip_matches_golden(fixtures_dir: String) -> void:
	var path := fixtures_dir.path_join("library.json")
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		_report("read library.json", false, "cannot read %s" % path)
		return

	# Leg 1 — import the shared golden.
	var golden := InsimulContentLibrary.new()
	var ok := golden.load_from_json(text)
	_report("golden imports", ok, golden.last_error())
	if not ok:
		return

	# Leg 2 — re-export the materialized entities and re-import them fresh.
	var exported_json := golden.export_json()
	_report("export produces JSON", not exported_json.is_empty(), "empty export")
	var reimport := InsimulContentLibrary.new()
	var reloaded := reimport.load_from_json(exported_json)
	_report("re-export re-imports", reloaded, reimport.last_error())
	if not reloaded:
		return

	# Library identity survives the round-trip.
	_expect_eq("schema version", reimport.loaded_schema_version(), golden.loaded_schema_version())
	_expect_eq("library id", reimport.library_id(), golden.library_id())
	_expect_eq("library name", reimport.library_name(), golden.library_name())
	_expect_eq("total entity count", reimport.entity_count(), golden.entity_count())

	# Every collection matches the golden count-for-count and field-for-field.
	for spec in InsimulContentLibrary.COLLECTIONS:
		var key: String = spec["key"]
		var g: Array = golden.source().get(key, [])
		var r: Array = reimport.source().get(key, [])
		_expect_eq("%s count" % key, r.size(), g.size())
		for i in g.size():
			var eid := str((g[i] as Dictionary).get("id", ""))
			var g_entity: Dictionary = g[i]
			var r_entity := _find_by_id(r, eid)
			_report("%s '%s' present after round-trip" % [key, eid], not r_entity.is_empty(), "missing")
			_report("%s '%s' payload identical" % [key, eid], _deep_eq(g_entity, r_entity),
				"golden=%s reimport=%s" % [str(g_entity), str(r_entity)])

	# Materialized native entities carry identical semantics (kind + composed name),
	# e.g. the character's firstName/lastName still assemble to the same name.
	var g_named := _materialized_names(golden)
	var r_named := _materialized_names(reimport)
	_report("materialized entity set identical", _deep_eq(g_named, r_named),
		"golden=%s reimport=%s" % [str(g_named), str(r_named)])


# ── Helpers ──────────────────────────────────────────────────────────────────

# id -> "kind|name" for every materialized entity, so a single deep-eq compares
# the full native-entity set (kind and composed name) across the round-trip.
func _materialized_names(lib: InsimulContentLibrary) -> Dictionary:
	var out := {}
	for e in lib.materialize():
		out[e.id] = "%s|%s" % [e.kind, e.name]
	return out


func _find_by_id(arr: Array, id: String) -> Dictionary:
	for item in arr:
		if item is Dictionary and str(item.get("id", "")) == id:
			return item
	return {}


# Recursive structural equality for the JSON-shaped values a library holds
# (Dictionaries, Arrays, and scalars). Godot's `==` already deep-compares nested
# Dictionaries/Arrays, but this stays explicit so a payload mismatch reports the
# offending values.
func _deep_eq(a: Variant, b: Variant) -> bool:
	if typeof(a) != typeof(b):
		return false
	if a is Dictionary:
		if a.size() != b.size():
			return false
		for k in a:
			if not b.has(k) or not _deep_eq(a[k], b[k]):
				return false
		return true
	if a is Array:
		if a.size() != b.size():
			return false
		for i in a.size():
			if not _deep_eq(a[i], b[i]):
				return false
		return true
	return a == b


# ── Harness ──────────────────────────────────────────────────────────────────
func _report(label: String, ok: bool, detail: String) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		push_error("[insimul-content-roundtrip] FAIL: %s (%s)" % [label, detail])


func _expect_eq(label: String, actual: Variant, expected: Variant) -> void:
	_report(label, actual == expected, "expected %s, got %s" % [str(expected), str(actual)])


func _resolve_fixtures_dir() -> String:
	var user_args := OS.get_cmdline_user_args()
	for i in user_args.size():
		if user_args[i] == "--fixtures" and i + 1 < user_args.size():
			return user_args[i + 1]
	var script_path := (get_script() as Resource).resource_path
	# addons/insimul/tests -> addons/insimul -> addons -> <pkg root>
	var pkg_dir := script_path.get_base_dir().get_base_dir().get_base_dir().get_base_dir()
	return pkg_dir.path_join("conformance/content")
