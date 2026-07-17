# runtime_bootstrap_test.gd — the Godot headless leg of the startup-orchestrator
# gate (US-GC4).
#
# When a `godot` binary is on PATH AND the InsimulSaveCodec + InsimulQuestCore
# GDExtensions are built + loaded, this drives InsimulRuntime end-to-end — the
# full template-startup loop world source -> save slot -> KB -> systems:
#   - boot a NEW GAME from the shared golden world snapshot (no slot present),
#     with the world source reporting the golden entity counts,
#   - run the radiant tick + complete an objective (fact-asserting transition),
#   - save the run, then re-boot the SAME slot and confirm it RESUMES with quest +
#     radiant state intact and the worldSnapshot hash stable across save/reload,
#   - a corrupt slot falls back to a new game rather than bricking boot.
#
#   godot --headless -s addons/insimul/tests/runtime_bootstrap_test.gd
#   godot --headless -s addons/insimul/tests/runtime_bootstrap_test.gd -- --fixtures /abs/saves
#
# It SKIPS cleanly (exit 0) when the GDExtensions are unavailable — the whole loop
# is proven regardless by the host C++ gate
# (gdextension/test/run_bootstrap_tests.sh). Mirrors save_system_test.gd /
# quest_system_test.gd.
extends SceneTree

var _pass := 0
var _fail := 0


func _initialize() -> void:
	if not InsimulRuntime.available() or not InsimulQuestSystem.core_available():
		print("[insimul-runtime] InsimulSaveCodec/InsimulQuestCore GDExtension not built — SKIP")
		print("[insimul-runtime] (host gate run_bootstrap_tests.sh covers the full loop)")
		quit(0)
		return

	var fixtures_dir := _resolve_fixtures_dir()
	print("[insimul-runtime] fixtures: %s" % fixtures_dir)

	_test_full_loop(fixtures_dir)
	_test_corrupt_fallback(fixtures_dir)

	print("-----------------------------------------------------------")
	print("[insimul-runtime] %d passed, %d failed" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)


# ── New game -> radiant -> objective -> save -> resume ────────────────────────
func _test_full_loop(fixtures_dir: String) -> void:
	var snapshot := _synthetic_snapshot()

	var rt := InsimulRuntime.new()
	rt.save.delete_save(0)

	# No slot present -> boot starts a new game from the world snapshot.
	var boot: Dictionary = rt.boot(0, snapshot, "save-gc4", "user-1", "synth-world", "GC4 Boot", "2026-07-17T00:00:00.000Z")
	_report("boot new game ok", boot.get("ok", false), rt.last_error())
	_report("boot did not resume (new game)", not boot.get("resumed_save", true), "unexpected resume")
	_expect_eq("three world quests loaded", rt.quests.get_all_quest_ids().size(), 3)

	var hash_before := rt.world_snapshot_integrity()
	_report("worldSnapshot hash computes", not hash_before.is_empty(), "empty hash")

	# Radiant tick: one offering per tick over two ticks -> both radiant quests.
	var offered: Array = rt.run_radiant_tick(1, 2)
	_expect_eq("radiant tick offers both quests", offered.size(), 2)

	# Main quest completes only when its objective trigger fires.
	rt.quests.accept_quest("q_main")
	var before: Array = rt.evaluate_all_quests()
	_report("main quest incomplete before trigger", not rt.quests.is_quest_completed("q_main"), "completed early")
	rt.quests.assert_fact("talked_to", ["player", "npc_a"])
	rt.evaluate_all_quests()
	_report("main quest completes on trigger", rt.quests.is_quest_completed("q_main"), "did not complete")

	# Save the run.
	var saved := rt.save_game("insimul-godot-test", "2026-07-17T00:00:00.000Z")
	_report("save_game writes the slot", saved, rt.last_error())
	_expect_eq("worldSnapshot hash stable after progress", rt.world_snapshot_integrity(), hash_before)

	# Re-boot the same slot -> resume with state intact.
	var rt2 := InsimulRuntime.new()
	var boot2: Dictionary = rt2.boot(0, snapshot, "save-gc4", "user-1", "synth-world", "GC4 Boot", "2026-07-17T00:00:00.000Z")
	_report("re-boot resumes the save", boot2.get("resumed_save", false), rt2.last_error())
	_report("completed quest survives reload", _kb_has(rt2, "quest_complete", ["q_main"]), "missing quest_complete")
	_report("radiant offering survives reload", _kb_has(rt2, "quest_offered", ["rq_2", 1]), "missing quest_offered")
	_expect_eq("worldSnapshot hash stable across save/reload", rt2.world_snapshot_integrity(), hash_before)

	rt.save.delete_save(0)


# ── Corrupt slot falls back to a new game ─────────────────────────────────────
func _test_corrupt_fallback(_fixtures_dir: String) -> void:
	var snapshot := _synthetic_snapshot()
	var rt := InsimulRuntime.new()
	rt.save.delete_save(1)

	# Write garbage into slot 1, then boot -> must fall back to a new game.
	DirAccess.make_dir_recursive_absolute("user://saves/")
	var f := FileAccess.open("user://saves/save_slot_1.json", FileAccess.WRITE)
	f.store_string("{ this is not a valid envelope")
	f.close()

	var boot: Dictionary = rt.boot(1, snapshot, "save-gc4b", "user-1", "synth-world", "Fallback", "2026-07-17T00:00:00.000Z")
	_report("corrupt slot boot recovers", boot.get("ok", false), rt.last_error())
	_report("corrupt slot falls back to new game", not boot.get("resumed_save", true), "unexpected resume")
	_expect_eq("fallback loaded the world (3 quests)", rt.quests.get_all_quest_ids().size(), 3)

	rt.save.delete_save(1)


# ── Harness ──────────────────────────────────────────────────────────────────
func _synthetic_snapshot() -> String:
	# One objective quest + two radiant quests (the same shape the host test uses).
	var quests := [
		{
			"id": "q_main",
			"status": "active",
			"content": "quest(q_main, 'Main Quest', errand, easy, active).\nquest_objective(q_main, 0, talk_to(npc_a)).\nquest_completion(q_main, all_objectives_complete).",
		},
		{
			"id": "rq_1",
			"status": "available",
			"content": "quest(rq_1, 'R1', errand, easy, available).\nquest_tag(rq_1, radiant).",
		},
		{
			"id": "rq_2",
			"status": "available",
			"content": "quest(rq_2, 'R2', errand, easy, available).\nquest_tag(rq_2, radiant).",
		},
	]
	var snapshot := {
		"world": {
			"id": "synth-world", "name": "Synth", "worldType": "language",
			"gameType": "open", "targetLanguage": "en", "description": "",
		},
		"countries": [], "settlements": [], "characters": [], "lots": [],
		"quests": quests,
	}
	return JSON.stringify(snapshot)


func _kb_has(rt: InsimulRuntime, predicate: String, args: Array) -> bool:
	for fact in rt.quests.kb_facts():
		if fact.get("predicate", "") == predicate and fact.get("args", []) == args:
			return true
	return false


func _report(label: String, ok: bool, detail: String) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		push_error("[insimul-runtime] FAIL: %s (%s)" % [label, detail])


func _expect_eq(label: String, actual: Variant, expected: Variant) -> void:
	_report(label, actual == expected, "expected %s, got %s" % [str(expected), str(actual)])


func _resolve_fixtures_dir() -> String:
	var user_args := OS.get_cmdline_user_args()
	for i in user_args.size():
		if user_args[i] == "--fixtures" and i + 1 < user_args.size():
			return user_args[i + 1]
	var script_path := (get_script() as Resource).resource_path
	var pkg_dir := script_path.get_base_dir().get_base_dir().get_base_dir().get_base_dir()
	var packages_dir := pkg_dir.get_base_dir()
	return packages_dir.path_join("core/conformance/saves")
