# content_import_test.gd — the Godot headless leg of the content-library import
# parity gate (content-portability, US-IM1).
#
# When a `godot` binary is on PATH this loads the SHARED content-library fixture
# (conformance/content/library.json — the same JSON the Unity/Unreal importers
# assert against) through InsimulContentLibrary and checks that importing produces
# the expected native Godot entities, and that invalid libraries are rejected with
# a clear error (schema-validated).
#
#   godot --headless -s addons/insimul/tests/content_import_test.gd
#   godot --headless -s addons/insimul/tests/content_import_test.gd -- --fixtures /abs/content
#
# Exit 0 iff every check passes; non-zero (with a per-check FAIL line) otherwise.
# When godot is absent (the Ralph harness), the GDScript structural lint
# (tools/verify-godot/check.mjs) covers the addon `.gd` files; see VERIFICATION.md
# for the host-vs-editor split. Mirrors world_source_test.gd.
extends SceneTree

var _pass := 0
var _fail := 0


func _initialize() -> void:
	var fixtures_dir := _resolve_fixtures_dir()
	print("[insimul-content-import] fixtures: %s" % fixtures_dir)

	_test_golden_import(fixtures_dir)
	_test_native_scene(fixtures_dir)
	_test_schema_gate()
	_test_invalid_rejected()

	print("-----------------------------------------------------------")
	print("[insimul-content-import] %d passed, %d failed" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)


# ── AC: importing the shared fixture produces the expected native entities ────
func _test_golden_import(fixtures_dir: String) -> void:
	var path := fixtures_dir.path_join("library.json")
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		_report("read library.json", false, "cannot read %s" % path)
		return

	var lib := InsimulContentLibrary.new()
	var ok := lib.load_from_json(text)
	_report("library imports", ok, lib.last_error())
	if not ok:
		return

	_expect_eq("schema version", lib.loaded_schema_version(), 1)
	_expect_eq("library id", lib.library_id(), "conformance-content-library")

	# Cross-engine parity: these counts MUST match every other importer.
	_expect_eq("item count", lib.item_count(), 2)
	_expect_eq("character count", lib.character_count(), 2)
	_expect_eq("town count", lib.town_count(), 1)
	_expect_eq("quest count", lib.quest_count(), 1)
	_expect_eq("narrative count", lib.narrative_count(), 1)
	_expect_eq("total entity count", lib.entity_count(), 7)

	# Typed accessors read the engine-neutral payload.
	var bread := lib.find_item("item-bread")
	_report("find_item(item-bread)", not bread.is_empty(), "not found")
	_expect_eq("item name", str(bread.get("name", "")), "Bread")
	_expect_eq("item type", str(bread.get("itemType", "")), "food")

	var marie := lib.find_character("npc-shopkeeper")
	_report("find_character(npc-shopkeeper)", not marie.is_empty(), "not found")
	_expect_eq("character occupation", str(marie.get("occupation", "")), "Shopkeeper")

	var quest := lib.find_quest("quest-welcome")
	_report("find_quest(quest-welcome)", not quest.is_empty(), "not found")
	_report("quest has Prolog content", not str(quest.get("content", "")).is_empty(), "empty content")

	# materialize() yields native Entity objects with kind + assembled name.
	var entities := lib.materialize()
	_expect_eq("materialized entity count", entities.size(), 7)
	var shopkeeper: InsimulContentLibrary.Entity = null
	for e in entities:
		if e.id == "npc-shopkeeper":
			shopkeeper = e
	_report("materialized shopkeeper present", shopkeeper != null, "missing")
	if shopkeeper != null:
		_expect_eq("materialized kind", shopkeeper.kind, "character")
		_expect_eq("materialized composed name", shopkeeper.name, "Marie Fixture")


# ── AC: materialization builds native Godot Nodes with insimul_* metadata ─────
func _test_native_scene(fixtures_dir: String) -> void:
	var path := fixtures_dir.path_join("library.json")
	var text := FileAccess.get_file_as_string(path)
	var lib := InsimulContentLibrary.new()
	if not lib.load_from_json(text):
		_report("scene: library imports", false, lib.last_error())
		return

	var root := Node.new()
	var count := lib.build_scene(root)
	_expect_eq("built node count", count, 7)
	_expect_eq("root child count", root.get_child_count(), 7)

	var found := false
	for child in root.get_children():
		if String(child.get_meta("insimul_entity_id", "")) == "quest-welcome":
			found = true
			_expect_eq("node kind meta", String(child.get_meta("insimul_kind", "")), "quest")
			_report("node generated meta", bool(child.get_meta("insimul_generated", false)), "not generated")
	_report("quest node present with metadata", found, "quest-welcome node missing")
	root.free()


# ── AC: unsupported schema version rejected ───────────────────────────────────
func _test_schema_gate() -> void:
	_report("schema v1 compatible", InsimulContentLibrary.check_schema_version(1).compatible, "")
	_report("schema v0 incompatible", not InsimulContentLibrary.check_schema_version(0).compatible, "")
	_report("schema v999 (future) incompatible", not InsimulContentLibrary.check_schema_version(999).compatible, "")

	var future := '{ "schemaVersion": 999, "id": "x", "name": "y", "items": [], "characters": [], "towns": [], "quests": [], "narratives": [] }'
	var lib := InsimulContentLibrary.new()
	var loaded := lib.load_from_json(future)
	_report("future-schema library rejected", not loaded, "unexpectedly loaded")
	_report("future-schema not marked loaded", not lib.is_loaded(), "still loaded")


# ── AC: invalid libraries rejected with a clear error ─────────────────────────
func _test_invalid_rejected() -> void:
	# Malformed JSON.
	var lib := InsimulContentLibrary.new()
	_report("malformed JSON rejected", not lib.load_from_json("{ not valid json "), "unexpectedly loaded")
	_report("malformed JSON reports an error", not lib.last_error().is_empty(), "no error message")

	# Missing a required collection.
	var missing := '{ "schemaVersion": 1, "id": "x", "name": "y", "items": [], "characters": [], "towns": [], "quests": [] }'
	var lib2 := InsimulContentLibrary.new()
	_report("missing collection rejected", not lib2.load_from_json(missing), "unexpectedly loaded")
	_report("missing collection error mentions narratives", lib2.last_error().contains("narratives"), lib2.last_error())

	# A collection that is not an array.
	var not_array := '{ "schemaVersion": 1, "id": "x", "name": "y", "items": {}, "characters": [], "towns": [], "quests": [], "narratives": [] }'
	var lib3 := InsimulContentLibrary.new()
	_report("non-array collection rejected", not lib3.load_from_json(not_array), "unexpectedly loaded")

	# An entity with no id.
	var no_id := '{ "schemaVersion": 1, "id": "x", "name": "y", "items": [ { "name": "no id" } ], "characters": [], "towns": [], "quests": [], "narratives": [] }'
	var lib4 := InsimulContentLibrary.new()
	_report("entity without id rejected", not lib4.load_from_json(no_id), "unexpectedly loaded")
	_report("missing-id error is clear", lib4.last_error().contains("id"), lib4.last_error())


# ── Harness ──────────────────────────────────────────────────────────────────
func _report(label: String, ok: bool, detail: String) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		push_error("[insimul-content-import] FAIL: %s (%s)" % [label, detail])


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
