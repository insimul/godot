# quest_system_test.gd — the Godot headless leg of the portable quest gate (US-GC3).
#
# When a `godot` binary is on PATH AND the InsimulQuestCore GDExtension is built +
# loaded, this exercises InsimulQuestSystem end-to-end against the shared golden
# corpus: hydration parity (hydration-cases.json), radiant parity (radiant-cases.json),
# query-driven completion with fact-asserting transitions + preserved signals, and a
# save round-trip that preserves quest + radiant KB facts through InsimulSaveSystem.
#
#   godot --headless -s addons/insimul/tests/quest_system_test.gd
#   godot --headless -s addons/insimul/tests/quest_system_test.gd -- --quests /abs/quests --fixtures /abs/saves
#
# It SKIPS cleanly (exit 0) when the GDExtension is unavailable — the byte-parity
# quest contract is proven regardless by the host C++ gate
# (gdextension/test/run_quest_tests.sh). Mirrors save_system_test.gd.
extends SceneTree

var _pass := 0
var _fail := 0
var _signal_log: Array = []


func _initialize() -> void:
	if not InsimulQuestSystem.core_available():
		print("[insimul-quest] InsimulQuestCore GDExtension not built — SKIP")
		print("[insimul-quest] (host gate run_quest_tests.sh covers the quest semantics)")
		quit(0)
		return

	var quests_dir := _resolve_dir("--quests", "core/conformance/quests")
	var fixtures_dir := _resolve_dir("--fixtures", "core/conformance/saves")
	print("[insimul-quest] quests: %s" % quests_dir)

	_test_hydration_parity(quests_dir)
	_test_radiant_parity(quests_dir)
	_test_completion_transition()
	_test_save_round_trip(fixtures_dir)

	print("-----------------------------------------------------------")
	print("[insimul-quest] %d passed, %d failed" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)


# ── AC: golden hydration comparisons ─────────────────────────────────────────
func _test_hydration_parity(quests_dir: String) -> void:
	var corpus := _read_json(quests_dir.path_join("hydration-cases.json"))
	var cases: Array = corpus.get("cases", [])
	_report("hydration corpus has cases", cases.size() > 0, "empty corpus")
	var qs := InsimulQuestSystem.new()
	for c in cases:
		var name: String = str(c.get("name", "?"))
		var input: Dictionary = c.get("input", {})
		var expected: Dictionary = c.get("expected", {})
		var projection := qs.load_quest(name, str(input.get("content", "")), str(input.get("status", "")))
		_report("hydration %s matches golden projection" % name, _deep_eq(projection, expected),
			"got %s" % JSON.stringify(projection))


# ── AC: radiant conformance cases (byte-identical facts) ─────────────────────
func _test_radiant_parity(quests_dir: String) -> void:
	var corpus := _read_json(quests_dir.path_join("radiant-cases.json"))
	var cases: Array = corpus.get("cases", [])
	_report("radiant corpus has cases", cases.size() > 0, "empty corpus")
	var qs := InsimulQuestSystem.new()
	for c in cases:
		var name: String = str(c.get("name", "?"))
		var produced: Array = qs.run_radiant_tick(c.get("quests", []), int(c.get("maxOffering", 0)), int(c.get("ticks", 0)))
		var expected: Array = c.get("expected", [])
		_report("radiant %s facts match golden" % name,
			_fact_list_key(produced) == _fact_list_key(expected),
			"got %s" % _fact_list_key(produced))


# ── AC: query-driven completion + fact-asserting transitions (signals) ───────
func _test_completion_transition() -> void:
	var qs := InsimulQuestSystem.new()
	var content := "quest(q_c, 'Two Steps', errand, easy, active).\nquest_objective(q_c, 0, talk_to(npc_x)).\nquest_objective(q_c, 1, visit_location('Square'))."
	qs.load_quest("q_c", content)
	qs.accept_quest("q_c")

	_signal_log.clear()
	qs.objective_completed.connect(func(qid, oid): _signal_log.append(["obj", qid, oid]))
	qs.quest_completed.connect(func(qid): _signal_log.append(["quest", qid]))

	# Partial: only the talk objective is triggered.
	qs.assert_fact("talked_to", ["player", "npc_x"])
	var t1 := qs.evaluate_quest("q_c")
	_report("quest not complete with one objective outstanding", not t1.get("completed", false), "unexpectedly complete")
	_report("obj_0 completion signal fired", ["obj", "q_c", "obj_0"] in _signal_log, "no signal")
	_report("quest stays active while incomplete", qs.is_quest_active("q_c"), "not active")

	# Satisfy the second objective — the transition fires.
	qs.assert_fact("visited", ["player", "Square"])
	var t2 := qs.evaluate_quest("q_c")
	_report("quest completes when all objectives satisfied", t2.get("completed", false), "not complete")
	_report("quest_completed signal fired", ["quest", "q_c"] in _signal_log, "no signal")
	_report("quest moved to completed set", qs.is_quest_completed("q_c"), "not completed")


# ── AC: save round-trip preserves quest + radiant state ──────────────────────
func _test_save_round_trip(fixtures_dir: String) -> void:
	if not InsimulSaveSystem.codec_available():
		print("[insimul-quest] InsimulSaveCodec not built — skipping save round-trip")
		return
	var snapshot := _load_snapshot(fixtures_dir)
	if snapshot.is_empty():
		_report("read v2-typical worldSnapshot", false, "empty snapshot")
		return

	var save := InsimulSaveSystem.new()
	var codec := save.new_game(snapshot, "quest-save", "user-1", "fixture-world", "Quest", 0, "2026-07-17T00:00:00.000Z")
	if codec == null:
		_report("new_game builds a codec", false, save.last_error())
		return
	var hash_before: String = codec.compute_integrity()

	# Build quest + radiant KB state, then snapshot it into the save.
	var qs := InsimulQuestSystem.new()
	qs.assert_fact("quest_complete", ["quest-welcome"])
	qs.run_radiant_tick([
		{"id": "rq_1", "tags": ["radiant"], "status": "available"},
		{"id": "rq_2", "tags": ["radiant"], "status": "available"},
	], 1, 2)
	var facts := qs.kb_facts()
	_expect_eq("quest + 2 radiant facts", facts.size(), 3)

	save.snapshot_kb(codec, facts)
	var wrote := save.save_to_slot(codec, 0, "insimul-godot-quest", "2026-07-17T00:00:00.000Z")
	_report("save_to_slot writes an envelope", wrote, save.last_error())

	var loaded := save.load_from_slot(0)
	_report("load_from_slot verifies + loads", loaded != null, save.last_error())
	if loaded == null:
		return
	_expect_eq("worldSnapshot integrity stable across save/load", loaded.compute_integrity(), hash_before)

	var restored: Array = save.restore_kb(loaded)
	var qs2 := InsimulQuestSystem.new()
	qs2.restore_kb(restored)
	_report("quest + radiant facts round-trip", _fact_list_key(qs2.kb_facts()) == _fact_list_key(facts),
		"got %s" % _fact_list_key(qs2.kb_facts()))

	save.delete_save(0)


# ── Harness ──────────────────────────────────────────────────────────────────
func _fact_list_key(facts: Array) -> String:
	var lines: Array = []
	for f in facts:
		var parts: Array = []
		for a in f.get("args", []):
			parts.append(str(a))
		lines.append("%s(%s)" % [f.get("predicate", ""), ",".join(parts)])
	lines.sort()
	return "\n".join(lines)


func _deep_eq(a: Variant, b: Variant) -> bool:
	if typeof(a) != typeof(b):
		# Allow int/float numeric equivalence (JSON numbers).
		if (a is int or a is float) and (b is int or b is float):
			return float(a) == float(b)
		return false
	if a is Dictionary:
		if a.size() != b.size():
			return false
		for k in a.keys():
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


func _read_json(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return {}
	var json := JSON.new()
	if json.parse(text) != OK:
		return {}
	return json.data if json.data is Dictionary else {}


func _load_snapshot(fixtures_dir: String) -> String:
	var save := _read_json(fixtures_dir.path_join("v2-typical.json"))
	if not (save.get("worldSnapshot") is Dictionary):
		return ""
	return JSON.stringify(save.get("worldSnapshot"))


func _report(label: String, ok: bool, detail: String) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		push_error("[insimul-quest] FAIL: %s (%s)" % [label, detail])


func _expect_eq(label: String, actual: Variant, expected: Variant) -> void:
	_report(label, actual == expected, "expected %s, got %s" % [str(expected), str(actual)])


func _resolve_dir(flag: String, relative: String) -> String:
	var user_args := OS.get_cmdline_user_args()
	for i in user_args.size():
		if user_args[i] == flag and i + 1 < user_args.size():
			return user_args[i + 1]
	var script_path := (get_script() as Resource).resource_path
	# addons/insimul/tests -> addons/insimul -> addons -> insimul (package root)
	var pkg_dir := script_path.get_base_dir().get_base_dir().get_base_dir().get_base_dir()
	# packages/godot -> packages
	var packages_dir := pkg_dir.get_base_dir()
	return packages_dir.path_join(relative)
