# save_system_test.gd — the Godot headless leg of the portable-save gate (US-GC2).
#
# When a `godot` binary is on PATH AND the InsimulSaveCodec GDExtension is built +
# loaded, this exercises InsimulSaveSystem end-to-end: new-game from the shared
# golden world snapshot, save to a slot as an export envelope, load it back with
# integrity verification, KB snapshot/restore round-trip, and tamper detection.
#
#   godot --headless -s addons/insimul/tests/save_system_test.gd
#   godot --headless -s addons/insimul/tests/save_system_test.gd -- --fixtures /abs/saves
#
# It SKIPS cleanly (exit 0) when the GDExtension is unavailable — the canonical
# JSON + SHA-256 save contract is proven regardless by the host C++ gate
# (gdextension/test/run_save_tests.sh) and the TS cross-check
# (packages/core/src/conformance/__tests__/save-integrity-crosscheck-godot.test.ts).
# This mirrors the host-vs-editor split used by world_source_test.gd.
extends SceneTree

var _pass := 0
var _fail := 0


func _initialize() -> void:
	if not InsimulSaveSystem.codec_available():
		print("[insimul-save] InsimulSaveCodec GDExtension not built — SKIP")
		print("[insimul-save] (host gate run_save_tests.sh covers the codec semantics)")
		quit(0)
		return

	var fixtures_dir := _resolve_fixtures_dir()
	print("[insimul-save] fixtures: %s" % fixtures_dir)

	_test_new_game_save_load(fixtures_dir)
	_test_tamper_detection(fixtures_dir)

	print("-----------------------------------------------------------")
	print("[insimul-save] %d passed, %d failed" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)


# ── AC: new-game -> save -> load round-trip with integrity ───────────────────
func _test_new_game_save_load(fixtures_dir: String) -> void:
	var snapshot := _load_snapshot(fixtures_dir)
	if snapshot.is_empty():
		_report("read v2-typical worldSnapshot", false, "empty snapshot")
		return

	var sys := InsimulSaveSystem.new()
	var codec := sys.new_game(snapshot, "save-1", "user-1", "fixture-world", "New Game", 0, "2026-07-17T00:00:00.000Z")
	_report("new_game builds a codec", codec != null, sys.last_error())
	if codec == null:
		return
	_expect_eq("fresh save is current version", codec.version(), 3)

	# Snapshot a couple of KB facts into the save, then persist.
	var facts := [
		{"predicate": "has_gold", "args": ["player", 42]},
		{"predicate": "at_location", "args": ["player", "lot-shop"]},
	]
	sys.snapshot_kb(codec, facts)

	var wrote := sys.save_to_slot(codec, 0, "insimul-godot-test", "2026-07-17T00:00:00.000Z")
	_report("save_to_slot writes an envelope", wrote, sys.last_error())

	# Load it back — integrity is recomputed and must verify.
	var loaded := sys.load_from_slot(0)
	_report("load_from_slot verifies + loads", loaded != null, sys.last_error())
	if loaded == null:
		return
	_expect_eq("loaded save is current version", loaded.version(), 3)

	# KB facts survive the full save cycle.
	var restored: Array = sys.restore_kb(loaded)
	_expect_eq("restored fact count", restored.size(), 2)

	sys.delete_save(0)


# ── AC: corruption is rejected, not silently loaded ──────────────────────────
func _test_tamper_detection(fixtures_dir: String) -> void:
	var snapshot := _load_snapshot(fixtures_dir)
	var sys := InsimulSaveSystem.new()
	var codec := sys.new_game(snapshot, "save-2", "user-1", "fixture-world", "Tamper", 1, "2026-07-17T00:00:00.000Z")
	if codec == null:
		_report("tamper: new_game", false, sys.last_error())
		return
	var envelope: String = codec.build_envelope("insimul-godot-test", "2026-07-17T00:00:00.000Z")

	# Flip a byte inside the saveFile payload — integrity must fail.
	var tampered := envelope.replace("\"status\":\"active\"", "\"status\":\"hacked\"")
	_report("tampering changed the bytes", tampered != envelope, "no substitution happened")
	var bad := sys.load_envelope(tampered)
	_report("tampered envelope rejected", bad == null, "unexpectedly loaded")
	_report("tamper reports an integrity error", not sys.last_error().is_empty(), "no error message")

	# The untouched envelope still verifies.
	var good := sys.load_envelope(envelope)
	_report("untouched envelope verifies", good != null, sys.last_error())


# ── Harness ──────────────────────────────────────────────────────────────────
func _load_snapshot(fixtures_dir: String) -> String:
	var path := fixtures_dir.path_join("v2-typical.json")
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return ""
	var json := JSON.new()
	if json.parse(text) != OK:
		return ""
	var save: Dictionary = json.data if json.data is Dictionary else {}
	if not (save.get("worldSnapshot") is Dictionary):
		return ""
	return JSON.stringify(save.get("worldSnapshot"))


func _report(label: String, ok: bool, detail: String) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		push_error("[insimul-save] FAIL: %s (%s)" % [label, detail])


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
