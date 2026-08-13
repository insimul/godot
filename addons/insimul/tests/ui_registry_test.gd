# ui_registry_test.gd — the Godot headless leg of the default-UI registry gate.
#
# Runs the shared, engine-neutral UI corpus (conformance/ui/{registry-cases,
# loading-phases,theme-tokens}.json) against the pure GDScript view-models —
# InsimulUiRegistry, InsimulLoadingScreenModel, InsimulNotifications — plus the
# SHIPPED manifest: every panel key resolves, every scene exists and
# instantiates, and every panel gates on the modules its world activates
# (conformance/modules/genre-activation.json — the band-111 table).
#
#   godot --headless -s addons/insimul/tests/ui_registry_test.gd -- --conformance /abs/conformance
#
# No GDExtension is needed (all pure GDScript), so this runs on any godot binary.
# The wrapper (run_ui_registry_headless.sh) SKIPS cleanly when no binary is
# available (the Ralph harness) — there, the structural lint plus
# tools/verify-ui/check-ui.mjs cover the same claims from the data side.
extends SceneTree

var _pass := 0
var _fail := 0


func _initialize() -> void:
	var root := _resolve_conformance_dir()
	var ui_dir := root.path_join("ui")
	print("[insimul-ui] corpus: %s" % root)

	_test_registry_cases(ui_dir)
	_test_loading_phase_cases(ui_dir)
	_test_registry_diagnostics_and_defaults()
	_test_shipped_manifest(ui_dir)
	_test_creator_override_without_engine_change()
	_test_module_gate(root)
	_test_notifications()
	_test_theme_tokens(ui_dir)

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


# ── Diagnostics sanity on a bare registry (no corpus needed) ──────────────────
func _test_registry_diagnostics_and_defaults() -> void:
	var reg := InsimulUiRegistry.new({"hud": "scene:hud"})
	_report("bare registry resolves its own default", reg.scene_ref("hud") == "scene:hud", "unresolved")
	_report("unknown key empty ref", reg.scene_ref("does_not_exist") == "", "unexpected ref")
	_report("unknown key diagnosed", reg.has_diagnostics(), "no diagnostic")
	reg.clear_diagnostics()
	_report("diagnostics clear", not reg.has_diagnostics(), "still diagnosed")


# ── AC: the SHIPPED manifest — every documented key, every scene, no gate ─────
func _test_shipped_manifest(ui_dir: String) -> void:
	var reg := InsimulUiRegistry.shipped()
	_report("shipped manifest parses", not reg.has_diagnostics(), _first_diagnostic(reg))
	var documented: Array = _load_json(ui_dir.path_join("registry-cases.json")).get("panel_keys", [])
	_report("corpus documents panel keys", documented.size() > 0, "panel_keys empty")
	for key in documented:
		var panel_key := String(key)
		_report("shipped panel '%s' registered" % panel_key, reg.has(panel_key), "not in the manifest")
		_report("shipped panel '%s' resolves" % panel_key, reg.scene_ref(panel_key) != "", "empty scene ref")
		var scene := reg.scene_ref(panel_key)
		_report("shipped panel '%s' scene exists" % panel_key, ResourceLoader.exists(scene), "no such scene: %s" % scene)
	# The registry declares nothing the corpus does not document.
	for key in reg.keys():
		_report("shipped key '%s' is documented" % key, documented.has(String(key)),
			"not in registry-cases.json -> panel_keys")
	# Ungated by default: a registry nobody told about the world shows everything.
	_report("no gate until an activation is bound", not reg.is_gated(), "gated on construction")
	_report("every panel available ungated", reg.available_keys().size() == reg.keys().size(), "some panel gated off")
	# instantiate() reaches a real Control through the PackedScene.
	var node := reg.instantiate("quest_journal")
	_report("instantiate('quest_journal') returns a Control", node is Control, _first_diagnostic(reg))
	if node != null:
		node.free()


# ── AC: an overridden key resolves to the override, with no engine code change ─
func _test_creator_override_without_engine_change() -> void:
	# The creator-facing path: a project setting, read by the shipped registry.
	# Nothing in addons/insimul/ui/ changes to make this happen.
	var custom := "res://creator/my_journal.tscn"
	ProjectSettings.set_setting(InsimulUiRegistry.OVERRIDES_SETTING, {"quest_journal": custom})
	var reg := InsimulUiRegistry.shipped()
	_report("project-setting override wins", reg.scene_ref("quest_journal") == custom,
		"got '%s'" % reg.scene_ref("quest_journal"))
	_report("override is reported as one", reg.is_overridden("quest_journal"), "not flagged as overridden")
	_report("other panels stay default",
		reg.scene_ref("inventory").begins_with("res://addons/insimul/ui/scenes/"),
		"got '%s'" % reg.scene_ref("inventory"))
	# A key the shipped manifest never declared can be added the same way.
	reg.register("creator_codex", "res://creator/codex.tscn")
	_report("creator key resolves", reg.scene_ref("creator_codex") == "res://creator/codex.tscn", "unresolved")
	ProjectSettings.set_setting(InsimulUiRegistry.OVERRIDES_SETTING, null)


# ── AC: every panel resolves through the band-111 module registry ─────────────
func _test_module_gate(root: String) -> void:
	var table := _load_json(root.path_join("modules/genre-activation.json"))
	var genres: Dictionary = table.get("genres", {})
	_report("activation table read", genres.size() > 0, "no genres in genre-activation.json")

	var probe := InsimulUiRegistry.shipped()
	var gated_keys := []
	var ungated_keys := []
	for key in probe.keys():
		if probe.requirements(String(key)).is_empty():
			ungated_keys.append(String(key))
		else:
			gated_keys.append(String(key))
	_report("the manifest gates at least one panel", gated_keys.size() > 0, "nothing is module-gated")

	for genre_id in genres.keys():
		var active := []
		for module in genres[genre_id].get("modules", []):
			active.append(String(module.get("id", "")))
		var reg := InsimulUiRegistry.shipped()
		reg.set_active_modules(active)
		_report("gate on for '%s'" % genre_id, reg.is_gated(), "gate not engaged")
		# An ungated panel is available under every bundle, including an empty one.
		for key in ungated_keys:
			_report("[%s] ungated '%s' available" % [genre_id, key], reg.is_available(key), "hidden")
		# A gated panel is available exactly when the bundle activates its modules.
		for key in gated_keys:
			var satisfied := true
			for module_id in reg.requirements(key):
				if not active.has(module_id):
					satisfied = false
			_report("[%s] gated '%s' availability" % [genre_id, key], reg.is_available(key) == satisfied,
				"expected available=%s" % str(satisfied))
			if satisfied:
				continue
			# Hidden means hidden: no scene ref, and the creator is TOLD why.
			reg.clear_diagnostics()
			_report("[%s] gated '%s' has no scene ref" % [genre_id, key], reg.scene_ref(key) == "", "resolved anyway")
			_report("[%s] gated '%s' instantiates to null" % [genre_id, key], reg.instantiate(key) == null, "instantiated anyway")
			var kinds := []
			for note in reg.diagnostics():
				kinds.append(String(note.get("kind", "")))
			_report("[%s] gated '%s' diagnosed" % [genre_id, key], kinds.has("module_inactive"),
				"diagnostics=%s" % str(kinds))
			_report("[%s] gated '%s' names the missing module" % [genre_id, key],
				not reg.missing_modules(key).is_empty(), "no missing module reported")
			_report("[%s] gated '%s' out of available_keys" % [genre_id, key],
				not reg.available_keys().has(key), "still listed")

	# bind_activation() takes the real InsimulModuleActivation — or anything that
	# answers the same two questions, which is what lets the default UI compile in
	# a project with no GDExtension. Here it is a stub, so this test needs neither.
	var bound := InsimulUiRegistry.shipped()
	var declared := StubActivation.new(String(genres.keys()[0]), _module_ids_of(genres, String(genres.keys()[0])))
	bound.bind_activation(declared)
	_report("bind_activation(activation) engages the gate", bound.is_gated(), "gate not engaged")
	for key in gated_keys:
		var satisfied := true
		for module_id in bound.requirements(key):
			if not declared.module_ids().has(module_id):
				satisfied = false
		_report("bound '%s' availability" % key, bound.is_available(key) == satisfied,
			"expected available=%s" % str(satisfied))

	# An UNDECLARED world is not a world with nothing active — it runs everything.
	var undeclared := InsimulUiRegistry.shipped()
	undeclared.set_active_modules([])
	undeclared.bind_activation(StubActivation.new("", []))
	_report("an undeclared activation clears the gate", not undeclared.is_gated(), "still gated")
	undeclared.set_active_modules([])
	undeclared.bind_activation(null)
	_report("bind_activation(null) clears the gate", not undeclared.is_gated(), "still gated")
	_report("ungated registry offers every panel",
		undeclared.available_keys().size() == undeclared.keys().size(), "some panel still hidden")


## The two questions InsimulUiRegistry.bind_activation() asks — no GDExtension,
## no libinsimul, no core call. Standing in for InsimulModuleActivation.
class StubActivation:
	extends RefCounted

	var _genre := ""
	var _ids := PackedStringArray()

	func _init(genre_id: String, module_ids_in: Array) -> void:
		_genre = genre_id
		for id in module_ids_in:
			_ids.append(String(id))

	func genre() -> String:
		return _genre

	func module_ids() -> PackedStringArray:
		return _ids


func _module_ids_of(genres: Dictionary, genre_id: String) -> Array:
	var out := []
	for module in genres.get(genre_id, {}).get("modules", []):
		out.append(String(module.get("id", "")))
	return out


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


# ── AC: the Theme resource carries the SHARED token set, token for token ──────
func _test_theme_tokens(ui_dir: String) -> void:
	var doc := _load_json(ui_dir.path_join("theme-tokens.json"))
	_report("read theme-tokens.json", not doc.is_empty(), "empty/parse error")
	var groups := {
		"colors": InsimulUiTokens.COLORS,
		"spacing": InsimulUiTokens.SPACING,
		"radius": InsimulUiTokens.RADIUS,
		"font_size": InsimulUiTokens.FONT_SIZE,
	}
	for group in groups.keys():
		var shared: Dictionary = doc.get(group, {})
		var mine: Dictionary = groups[group]
		_report("token group '%s' has the same size" % group, shared.size() == mine.size(),
			"shared=%d, godot=%d" % [shared.size(), mine.size()])
		for name in shared.keys():
			_report("token %s.%s mirrors the corpus" % [group, name],
				mine.has(name) and _same_token(mine[name], shared[name]),
				"expected '%s', got '%s'" % [str(shared[name]), str(mine.get(name, "<absent>"))])

	var theme := InsimulUiTokens.build_theme()
	_report("build_theme returns a Theme", theme != null, "null theme")
	_report("label font color == text_primary",
		theme.get_color("font_color", "Label") == InsimulUiTokens.color("text_primary"),
		"mismatch")
	_report("button font size == body token",
		theme.get_font_size("font_size", "Button") == int(InsimulUiTokens.FONT_SIZE["body"]),
		"mismatch")


# ── Harness ──────────────────────────────────────────────────────────────────


## A token matches whether the corpus spells it as a number (JSON gives Godot a
## float) or as a string — 12 and 12.0 are the same spacing token, "#12141c" is
## not the same colour as "#12141d".
func _same_token(mine: Variant, shared: Variant) -> bool:
	var numeric := [TYPE_INT, TYPE_FLOAT]
	if numeric.has(typeof(mine)) and numeric.has(typeof(shared)):
		return abs(float(mine) - float(shared)) < 0.0001
	return str(mine) == str(shared)


func _load_json(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return {}
	var json := JSON.new()
	if json.parse(text) != OK:
		return {}
	return json.data if json.data is Dictionary else {}


func _first_diagnostic(reg: InsimulUiRegistry) -> String:
	var notes := reg.diagnostics()
	return "" if notes.is_empty() else String(notes[0].get("message", ""))


func _report(label: String, ok: bool, detail: String) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		push_error("[insimul-ui] FAIL: %s (%s)" % [label, detail])


func _resolve_conformance_dir() -> String:
	var user_args := OS.get_cmdline_user_args()
	for i in user_args.size():
		if user_args[i] == "--conformance" and i + 1 < user_args.size():
			return user_args[i + 1]
	# Standalone layout: the corpus is vendored in this repo, beside addons/.
	return "res://conformance"
