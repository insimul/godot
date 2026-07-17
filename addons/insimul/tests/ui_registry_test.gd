# ui_registry_test.gd — the Godot headless leg of the default-UI US-GU1 gate.
#
# Runs the shared, engine-neutral UI corpus
# (packages/core/conformance/ui/{registry-cases,loading-phases}.json) against the
# pure GDScript view-models — InsimulUiRegistry, InsimulLoadingScreenModel, and
# InsimulNotifications — plus a smoke check that InsimulUiTokens.build_theme()
# realizes the shared token set. No GDExtension is needed (all pure GDScript), so
# this runs on any godot binary:
#
#   godot --headless -s addons/insimul/tests/ui_registry_test.gd -- --ui /abs/ui
#
# It SKIPS cleanly (exit 0) only when no godot binary is available (the Ralph
# harness) — the structural lint covers the .gd files there. Mirrors the
# host-vs-editor split used by save_system_test.gd / quest_system_test.gd.
extends SceneTree

var _pass := 0
var _fail := 0


func _initialize() -> void:
	var ui_dir := _resolve_ui_dir()
	print("[insimul-ui] corpus: %s" % ui_dir)

	_test_registry_cases(ui_dir)
	_test_loading_phase_cases(ui_dir)
	_test_registry_diagnostics_and_defaults()
	_test_notifications()
	_test_theme_tokens()

	print("-----------------------------------------------------------")
	print("[insimul-ui] %d passed, %d failed" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)


# ── AC: registry shared cases (default lookup, override precedence, missing) ──
func _test_registry_cases(ui_dir: String) -> void:
	var doc := _load_json(ui_dir.path_join("registry-cases.json"))
	if doc.is_empty():
		_report("read registry-cases.json", false, "empty/parse error")
		return
	for case in doc.get("cases", []):
		var name: String = case.get("name", "?")
		var reg := InsimulUiRegistry.new(case.get("defaults", {}))
		reg.apply_overrides(case.get("overrides", {}))
		var key: String = case.get("resolve", "")
		var scene := reg.scene_ref(key)
		_report("registry[%s] scene_ref" % name, scene == String(case.get("expected_scene", "")),
			"expected '%s', got '%s'" % [case.get("expected_scene", ""), scene])
		var missing := not reg.has(key)
		_report("registry[%s] missing" % name, missing == bool(case.get("expected_missing", false)),
			"expected missing=%s" % str(case.get("expected_missing", false)))
		_report("registry[%s] overridden" % name, reg.is_overridden(key) == bool(case.get("expected_overridden", false)),
			"expected overridden=%s" % str(case.get("expected_overridden", false)))
		# A missing key must have produced a diagnostic; a hit must not.
		if bool(case.get("expected_missing", false)):
			_report("registry[%s] diagnosed" % name, reg.has_diagnostics(), "no diagnostic recorded")
		else:
			_report("registry[%s] clean" % name, not reg.has_diagnostics(), "unexpected diagnostic")


# ── AC: loading-phase view-model shared cases ────────────────────────────────
func _test_loading_phase_cases(ui_dir: String) -> void:
	var doc := _load_json(ui_dir.path_join("loading-phases.json"))
	if doc.is_empty():
		_report("read loading-phases.json", false, "empty/parse error")
		return
	var phases: Array = doc.get("phases", [])
	var tips: Array = doc.get("tips", [])
	for case in doc.get("cases", []):
		var name: String = case.get("name", "?")
		var model := InsimulLoadingScreenModel.new(phases, tips)
		for step in case.get("steps", []):
			model.advance(String(step.get("advance", "")))
			var exp_p := float(step.get("expected_progress", -1.0))
			_report("loading[%s@%s] progress" % [name, step.get("advance", "")],
				abs(model.progress() - exp_p) < 0.0001,
				"expected %f, got %f" % [exp_p, model.progress()])
			_report("loading[%s@%s] label" % [name, step.get("advance", "")],
				model.label() == String(step.get("expected_label", "")),
				"expected '%s', got '%s'" % [step.get("expected_label", ""), model.label()])
			_report("loading[%s@%s] complete" % [name, step.get("advance", "")],
				model.is_complete() == bool(step.get("expected_complete", false)),
				"expected complete=%s" % str(step.get("expected_complete", false)))


# ── Default panel map + diagnostics sanity (no corpus needed) ─────────────────
func _test_registry_diagnostics_and_defaults() -> void:
	var reg := InsimulUiRegistry.new()
	# Every documented panel key resolves out of the box.
	for key in ["loading_screen", "notifications", "quest_journal", "inventory", "dialogue"]:
		_report("default panel '%s' resolves" % key, reg.has(key) and reg.scene_ref(key) != "", "unresolved")
	# An unknown key is missing + diagnosed.
	reg.clear_diagnostics()
	_report("unknown key empty ref", reg.scene_ref("does_not_exist") == "", "unexpected ref")
	_report("unknown key diagnosed", reg.has_diagnostics(), "no diagnostic")


# ── Notifications view-model (the pattern-proof pair) ─────────────────────────
func _test_notifications() -> void:
	var notes := InsimulNotifications.new()
	var a := notes.push("hello", InsimulNotifications.Kind.INFO, 3.0)
	notes.push("saved", InsimulNotifications.Kind.SUCCESS, 1.0)
	_report("two notifications visible", notes.count() == 2, "count=%d" % notes.count())
	# tick past the shorter lifetime — one expires.
	var changed := notes.tick(1.5)
	_report("tick expired the short one", changed and notes.count() == 1, "count=%d" % notes.count())
	# dismiss the remaining by id.
	_report("dismiss by id", notes.dismiss(a) and notes.count() == 0, "count=%d" % notes.count())


# ── Theme builder realizes the shared tokens ─────────────────────────────────
func _test_theme_tokens() -> void:
	var theme := InsimulUiTokens.build_theme()
	_report("build_theme returns a Theme", theme != null, "null theme")
	_report("label font color == text_primary",
		theme.get_color("font_color", "Label") == InsimulUiTokens.color("text_primary"),
		"mismatch")
	_report("button font size == body token",
		theme.get_font_size("font_size", "Button") == int(InsimulUiTokens.FONT_SIZE["body"]),
		"mismatch")


# ── Harness ──────────────────────────────────────────────────────────────────
func _load_json(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return {}
	var json := JSON.new()
	if json.parse(text) != OK:
		return {}
	return json.data if json.data is Dictionary else {}


func _report(label: String, ok: bool, detail: String) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		push_error("[insimul-ui] FAIL: %s (%s)" % [label, detail])


func _resolve_ui_dir() -> String:
	var user_args := OS.get_cmdline_user_args()
	for i in user_args.size():
		if user_args[i] == "--ui" and i + 1 < user_args.size():
			return user_args[i + 1]
	var script_path := (get_script() as Resource).resource_path
	# addons/insimul/tests -> addons/insimul -> addons -> insimul (package root)
	var pkg_dir := script_path.get_base_dir().get_base_dir().get_base_dir().get_base_dir()
	# packages/godot -> packages; corpus lives at packages/core/conformance/ui
	var packages_dir := pkg_dir.get_base_dir()
	return packages_dir.path_join("core/conformance/ui")
