# world_source_test.gd — the Godot headless leg of the world-source parity gate.
#
# Godot is scriptable and free, so when a `godot` binary is on PATH this loads
# the SHARED golden save fixture (packages/core/conformance/saves/v2-typical.json
# — the same JSON the Unreal/Unity/Babylon runtimes assert against) through the
# real InsimulWorldSource + generated DTOs and checks the golden entity counts,
# the schema-version compatibility gate, and malformed-input handling.
#
#   godot --headless -s addons/insimul/tests/world_source_test.gd
#   godot --headless -s addons/insimul/tests/world_source_test.gd -- --fixtures /abs/saves
#
# Exit 0 iff every check passes; non-zero (with a per-check FAIL line) otherwise —
# CI-consumable. When godot is absent (the Ralph harness), the GDScript
# structural lint (gdextension/tests/gdscript_structural_lint.py) covers the
# addon `.gd` files and the human toolchain review (autoMerge: false) covers the
# rest; see VERIFICATION.md for the host-vs-editor split.
extends SceneTree

var _pass := 0
var _fail := 0


func _initialize() -> void:
	var fixtures_dir := _resolve_fixtures_dir()
	print("[insimul-world-source] fixtures: %s" % fixtures_dir)

	_test_golden_counts(fixtures_dir)
	_test_version_gate()
	_test_malformed()

	print("-----------------------------------------------------------")
	print("[insimul-world-source] %d passed, %d failed" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)


# ── AC: golden v2-typical fixture loads with matching entity counts ──────────
func _test_golden_counts(fixtures_dir: String) -> void:
	var path := fixtures_dir.path_join("v2-typical.json")
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		_report("read v2-typical.json", false, "cannot read %s" % path)
		return

	var source := InsimulWorldSource.new()
	var ok := source.load_from_save_file_json(text)
	_report("v2-typical loads", ok, source.last_error())
	if not ok:
		return

	# Cross-runtime parity: these counts MUST match every other runtime's
	# assertions against packages/core/conformance/saves/v2-typical.json.
	_expect_eq("loaded save version", source.loaded_version(), 2)
	_expect_eq("world id", source.world().world.id, "fixture-world")
	_expect_eq("country count", source.country_count(), 1)
	_expect_eq("settlement count", source.settlement_count(), 1)
	_expect_eq("character count", source.character_count(), 1)
	_expect_eq("lot count", source.lot_count(), 1)
	_expect_eq("quest count", source.quest_count(), 1)
	_expect_eq("rule count", source.rule_count(), 0)
	_expect_eq("action count", source.action_count(), 0)
	_expect_eq("grammar count", source.grammar_count(), 0)

	# Typed accessors.
	var marie := source.find_character("npc-shopkeeper")
	_report("find_character(npc-shopkeeper)", not marie.is_empty(), "not found")
	_expect_eq("character first name", str(marie.get("firstName", "")), "Marie")
	_expect_eq("character occupation", str(marie.get("occupation", "")), "Shopkeeper")
	_expect_eq("character location", str(marie.get("currentLocation", "")), "lot-shop")

	var quest := source.find_quest("quest-welcome")
	_report("find_quest(quest-welcome)", not quest.is_empty(), "not found")
	_expect_eq("quest status", str(quest.get("status", "")), "active")
	_report("quest has Prolog content", not str(quest.get("content", "")).is_empty(), "empty content")

	var village := source.find_settlement("settlement-1")
	_report("find_settlement(settlement-1)", not village.is_empty(), "not found")
	_expect_eq("settlement population", int(village.get("population", -1)), 50)


# ── AC: incompatible version rejected ────────────────────────────────────────
func _test_version_gate() -> void:
	_report("version 2 compatible", InsimulWorldSource.check_version(2).compatible, "")
	_report("version 3 (current) compatible", InsimulWorldSource.check_version(3).compatible, "")
	_report("version 0 incompatible", not InsimulWorldSource.check_version(0).compatible, "")
	_report("version 999 (future) incompatible", not InsimulWorldSource.check_version(999).compatible, "")

	# A whole save stamped with a future version must be refused at load.
	var future_save := '{ "version": 999, "worldSnapshot": { "world": { "id": "x", "name": "y" } } }'
	var source := InsimulWorldSource.new()
	var loaded := source.load_from_save_file_json(future_save)
	_report("future-version save rejected at load", not loaded, "unexpectedly loaded")
	_report("source not marked loaded after rejection", not source.is_loaded(), "still loaded")


# ── Malformed JSON is a clean failure, not a crash ───────────────────────────
func _test_malformed() -> void:
	var source := InsimulWorldSource.new()
	var loaded := source.load_from_save_file_json("{ not valid json ")
	_report("malformed JSON rejected", not loaded, "unexpectedly loaded")
	_report("malformed JSON reports an error", not source.last_error().is_empty(), "no error message")


# ── Harness ──────────────────────────────────────────────────────────────────
func _report(label: String, ok: bool, detail: String) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		push_error("[insimul-world-source] FAIL: %s (%s)" % [label, detail])


func _expect_eq(label: String, actual: Variant, expected: Variant) -> void:
	_report(label, actual == expected, "expected %s, got %s" % [str(expected), str(actual)])


func _resolve_fixtures_dir() -> String:
	var user_args := OS.get_cmdline_user_args()
	for i in user_args.size():
		if user_args[i] == "--fixtures" and i + 1 < user_args.size():
			return user_args[i + 1]
	var script_path := (get_script() as Resource).resource_path
	# addons/insimul/tests -> addons/insimul -> addons -> insimul (package root)
	var pkg_dir := script_path.get_base_dir().get_base_dir().get_base_dir().get_base_dir()
	# packages/godot -> packages; saves live at packages/core/conformance/saves
	var packages_dir := pkg_dir.get_base_dir()
	return packages_dir.path_join("core/conformance/saves")
