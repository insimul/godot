# dialogue_menu_save_test.gd — the Godot headless leg of the default-UI US-GU3 gate.
#
# Runs the shared, engine-neutral dialogue + pause-menu + save-slot matrices
# (packages/core/conformance/ui/{chat-cases,pause-menu-cases,save-slot-cases}.json)
# against the pure GDScript view-models — InsimulChatModel, InsimulPauseMenuModel,
# InsimulSaveSlotModel. No GDExtension is needed (all pure GDScript), so this runs on
# any godot binary:
#
#   godot --headless -s addons/insimul/tests/dialogue_menu_save_test.gd -- --ui /abs/ui
#
# It SKIPS cleanly (exit 0) only when no godot binary is available (the Ralph
# harness) — the structural lint covers the .gd files there. Mirrors quest_trade_test.gd.
extends SceneTree

var _pass := 0
var _fail := 0


func _initialize() -> void:
	var ui_dir := _resolve_ui_dir()
	print("[insimul-ui3] corpus: %s" % ui_dir)

	_test_chat_cases(ui_dir)
	_test_menu_cases(ui_dir)
	_test_slot_cases(ui_dir)

	print("-----------------------------------------------------------")
	print("[insimul-ui3] %d passed, %d failed" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)


# ── AC: dialogue / chat streaming shared cases ───────────────────────────────
func _test_chat_cases(ui_dir: String) -> void:
	var doc := _load_json(ui_dir.path_join("chat-cases.json"))
	if doc.is_empty():
		_report("read chat-cases.json", false, "empty/parse error")
		return
	for case in doc.get("cases", []):
		var name: String = case.get("name", "?")
		var character: Dictionary = case.get("character", {})
		var model := InsimulChatModel.new(String(character.get("id", "")), String(character.get("name", "")))
		for ev in case.get("events", []):
			var op := String(ev.get("op", ""))
			var ok := true
			var checked := false
			match op:
				"greeting":
					model.greeting(String(ev.get("text", "")))
				"begin":
					ok = model.begin_user_turn(String(ev.get("text", ""))); checked = true
				"chunk":
					model.append_chunk(String(ev.get("text", "")))
				"action":
					model.trigger_action({"name": String(ev.get("name", "")), "args": ev.get("args", []),
						"factToAssert": String(ev.get("fact", ""))})
				"complete":
					var full: Variant = ev.get("full_text", null)
					ok = model.complete_turn(full); checked = true
				"fail":
					ok = model.fail_turn(String(ev.get("error", ""))); checked = true
				_:
					_report("chat[%s] unknown op %s" % [name, op], false, "")
			if checked and ev.has("expected_ok"):
				_report("chat[%s].%s ok" % [name, op], ok == bool(ev.get("expected_ok")),
					"expected %s" % str(ev.get("expected_ok")))

		_report("chat[%s] messages" % name, _messages_match(model.message_list(), case.get("expected_messages", [])),
			"got %s" % str(model.message_list()))
		_report("chat[%s] streaming" % name, model.is_streaming() == bool(case.get("expected_streaming", false)), "")
		_report("chat[%s] actions" % name, _actions_match(model.action_list(), case.get("expected_actions", [])),
			"got %s" % str(model.action_list()))
		_report("chat[%s] turn_count" % name, model.completed_turn_count() == int(case.get("expected_turn_count", 0)),
			"got %d" % model.completed_turn_count())
		_report("chat[%s] last_npc_text" % name, model.last_npc_text() == String(case.get("expected_last_npc_text", "")),
			"got '%s'" % model.last_npc_text())
		var hist: Dictionary = model.history()
		_report("chat[%s] history_turns" % name,
			_history_match(hist.get("recentTurns", []), case.get("expected_history_turns", [])),
			"got %s" % str(hist.get("recentTurns", [])))


func _messages_match(actual: Array, expected: Array) -> bool:
	if actual.size() != expected.size():
		return false
	for i in actual.size():
		var a: Dictionary = actual[i]
		var e: Dictionary = expected[i]
		if String(a.get("role", "")) != String(e.get("role", "")):
			return false
		if String(a.get("text", "")) != String(e.get("text", "")):
			return false
		if bool(a.has("error")) != bool(e.get("error", false)):
			return false
	return true


func _actions_match(actual: Array, expected: Array) -> bool:
	if actual.size() != expected.size():
		return false
	for i in actual.size():
		var a: Dictionary = actual[i]
		var e: Dictionary = expected[i]
		if String(a.get("name", "")) != String(e.get("name", "")):
			return false
		if String(a.get("factToAssert", "")) != String(e.get("factToAssert", "")):
			return false
		if JSON.stringify(a.get("args", [])) != JSON.stringify(e.get("args", [])):
			return false
	return true


func _history_match(actual: Array, expected: Array) -> bool:
	if actual.size() != expected.size():
		return false
	for i in actual.size():
		var a: Dictionary = actual[i]
		var e: Dictionary = expected[i]
		if String(a.get("role", "")) != String(e.get("role", "")):
			return false
		if String(a.get("content", "")) != String(e.get("content", "")):
			return false
	return true


# ── AC: pause-menu tab-gating shared cases ───────────────────────────────────
func _test_menu_cases(ui_dir: String) -> void:
	var doc := _load_json(ui_dir.path_join("pause-menu-cases.json"))
	if doc.is_empty():
		_report("read pause-menu-cases.json", false, "empty/parse error")
		return
	for case in doc.get("cases", []):
		var name: String = case.get("name", "?")
		var model: InsimulPauseMenuModel
		if case.has("tabs"):
			model = InsimulPauseMenuModel.new(case.get("enabled_modules", []), case.get("tabs"))
		else:
			model = InsimulPauseMenuModel.new(case.get("enabled_modules", []))
		_report("menu[%s] visible_keys" % name,
			model.visible_keys() == _str_array(case.get("expected_visible_keys", [])),
			"got %s" % str(model.visible_keys()))
		for step in case.get("steps", []):
			var op := String(step.get("op", ""))
			match op:
				"open":
					model.open_menu(String(step.get("tab", "")))
				"close":
					model.close_menu()
				"toggle":
					model.toggle()
				"set_active":
					var ok := model.set_active(String(step.get("key", "")))
					if step.has("expected_ok"):
						_report("menu[%s] set_active ok" % name, ok == bool(step.get("expected_ok")),
							"expected %s" % str(step.get("expected_ok")))
				"expect_active":
					_report("menu[%s] active" % name, model.active_tab() == String(step.get("key", "")),
						"got '%s'" % model.active_tab())
				"expect_open":
					_report("menu[%s] open" % name, model.is_open() == bool(step.get("value", false)),
						"got %s" % str(model.is_open()))
				_:
					_report("menu[%s] unknown op %s" % [name, op], false, "")


# ── AC: save/load slot shared cases (incl. corrupted envelope messaging) ──────
func _test_slot_cases(ui_dir: String) -> void:
	var doc := _load_json(ui_dir.path_join("save-slot-cases.json"))
	if doc.is_empty():
		_report("read save-slot-cases.json", false, "empty/parse error")
		return
	for case in doc.get("cases", []):
		var name: String = case.get("name", "?")
		var model := InsimulSaveSlotModel.new(case.get("slots", []))
		var rows := model.slots()
		var expected: Array = case.get("expected", [])
		_report("slot[%s] row_count" % name, rows.size() == expected.size(),
			"got %d" % rows.size())
		for i in min(rows.size(), expected.size()):
			var r: Dictionary = rows[i]
			var e: Dictionary = expected[i]
			_report("slot[%s][%d] fields" % [name, i], _slot_match(r, e), "got %s" % str(r))
		_report("slot[%s] has_loadable" % name,
			model.has_any_loadable() == bool(case.get("expected_has_loadable", false)), "")


func _slot_match(r: Dictionary, e: Dictionary) -> bool:
	return int(r.get("index", -1)) == int(e.get("index", -1)) \
		and String(r.get("status", "")) == String(e.get("status", "")) \
		and String(r.get("title", "")) == String(e.get("title", "")) \
		and String(r.get("message", "")) == String(e.get("message", "")) \
		and bool(r.get("can_load", false)) == bool(e.get("can_load", false)) \
		and bool(r.get("can_save", false)) == bool(e.get("can_save", false))


# ── Harness ──────────────────────────────────────────────────────────────────
func _str_array(v: Variant) -> Array:
	var out: Array = []
	for x in (v if v is Array else []):
		out.append(String(x))
	return out


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
		push_error("[insimul-ui3] FAIL: %s (%s)" % [label, detail])


func _resolve_ui_dir() -> String:
	var user_args := OS.get_cmdline_user_args()
	for i in user_args.size():
		if user_args[i] == "--ui" and i + 1 < user_args.size():
			return user_args[i + 1]
	var script_path := (get_script() as Resource).resource_path
	# addons/insimul/tests -> addons/insimul -> addons -> insimul (package root)
	var pkg_dir := script_path.get_base_dir().get_base_dir().get_base_dir().get_base_dir()
	var packages_dir := pkg_dir.get_base_dir()
	return packages_dir.path_join("core/conformance/ui")
