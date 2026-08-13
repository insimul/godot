# dialogue_menu_save_test.gd — the Godot headless leg of the default-UI US-3 gate.
#
# Two halves:
#
#   * THE SHARED MATRICES. conformance/ui/{chat-cases,pause-menu-cases,
#     save-slot-cases}.json against the pure GDScript view-models —
#     InsimulChatModel, InsimulPauseMenuModel, InsimulSaveSlotModel. Same JSON the
#     Babylon reference and the Unreal/Unity ports run; divergence is a bug.
#   * THE NODE-LEVEL LEGS. The Controls, in a real tree: the dialogue panel driven
#     by a stub streaming service (chunks, TTS, lip-sync, KB actions, the history
#     projection landing in save.conversations), the ESC menu resolving its tab
#     BODIES through the registry (including a body the module gate takes away),
#     the menu shell, the save/load rows and the main-menu gate.
#
# No GDExtension is needed (all pure GDScript), so this runs on any godot binary:
#
#   godot --headless -s addons/insimul/tests/dialogue_menu_save_test.gd -- --ui /abs/ui
#
# The wrapper (run_dialogue_menu_save_headless.sh) is what makes the run mean
# something: it imports the project first (without it nothing parses and `godot -s`
# still exits 0) and greps the log for parse errors afterwards.
#
# This file names panel keys on purpose — it tests the SHIPPED default UI, and
# check-ui.mjs holds those keys to the shared corpus. The rule about spelling a
# panel key is about addons/insimul/ui/, whose job is to resolve whatever the
# manifest says.
extends SceneTree

var _pass := 0
var _fail := 0
var _ui_dir := ""


func _initialize() -> void:
	_ui_dir = _resolve_ui_dir()
	print("[insimul-ui3] corpus: %s" % _ui_dir)

	_test_chat_cases(_ui_dir)
	_test_menu_cases(_ui_dir)
	_test_slot_cases(_ui_dir)
	_test_tab_map()
	# The node-level legs run on the first frame — see _process().


## The tree's ROOT IS NOT IN THE TREE during _initialize(), so a panel added there
## never gets its _ready() and every "does this panel build itself?" check would
## pass vacuously. The node-level legs therefore run on the first real frame, and
## the summary + exit code move with them.
func _process(_delta: float) -> bool:
	_test_dialogue_panel_streaming()
	_test_dialogue_history_persists()
	_test_pause_menu_control()
	_test_pause_menu_bodies()
	_test_game_menu_shell()
	_test_save_load_panel()
	_test_main_menu_gate()

	print("-----------------------------------------------------------")
	print("[insimul-ui3] %d passed, %d failed" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
	return true


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
		if not _deep_eq(a.get("args", []), e.get("args", [])):
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
		for i in mini(rows.size(), expected.size()):
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


# ── AC: the ESC menu's tab bodies are DATA, and the accounting is total ───────
func _test_tab_map() -> void:
	var reg := InsimulUiRegistry.shipped()
	var manifest := _load_json(InsimulUiRegistry.MANIFEST_PATH)
	var notes: Dictionary = manifest.get("pauseMenuTabNotes", {})
	var map := reg.tab_panels()
	_report("the registry answers the tab map", not map.is_empty(), "no tab mounts a panel")
	for tab in map.keys():
		_report("tab '%s' mounts a registered panel" % tab, reg.has(String(map[tab])),
			"no panel '%s'" % str(map[tab]))
	for tab_def in InsimulPauseMenuModel.DEFAULT_TABS:
		var key := String((tab_def as Dictionary)["key"])
		_report("tab '%s' has a body or a note" % key, map.has(key) or notes.has(key),
			"a tab in neither would render blank with nothing to read")
	_report("the close tab is a shipped tab", _tab_keys().has(reg.close_tab()),
		"close_tab() = '%s'" % reg.close_tab())


func _tab_keys() -> Array:
	var out: Array = []
	for tab_def in InsimulPauseMenuModel.DEFAULT_TABS:
		out.append(String((tab_def as Dictionary)["key"]))
	return out


# ── AC: the panel runs on the streaming SDK (chunks, TTS, lip-sync, KB) ──────

## The streaming conversation SDK's contract, as the dialogue panel sees it: the
## three signals with AIService's exact signatures plus send_message. The binding is
## duck-typed on purpose — the default UI must compile in a project with no game
## code in it — so this stub IS the interface under test.
class StubConversationService extends RefCounted:
	signal chunk_received(npc_id: String, text: String)
	signal response_complete(npc_id: String, full_text: String)
	signal response_error(npc_id: String, error: String)

	var sent: Array = []

	func send_message(character_id: String, user_message: String, _appearance: String = "") -> void:
		sent.append([character_id, user_message])


func _test_dialogue_panel_streaming() -> void:
	var reg := InsimulUiRegistry.shipped()
	var panel := reg.instantiate("dialogue") as InsimulDialoguePanel
	if not _report("the dialogue panel instantiates", panel != null, _first_diagnostic(reg)):
		return
	root.add_child(panel)

	var service := StubConversationService.new()
	_report("a duck-typed service binds", panel.bind_conversation_service(service), "bind refused")
	_report("a service-less panel says so", not panel.bind_conversation_service(null), "bound to nothing")
	panel.bind_conversation_service(service)

	var spoken: Array = []
	var visemes: Array = []
	var facts: Array = []
	panel.set_tts_provider(func(text: String, char_id: String): spoken.append([char_id, text]))
	panel.set_lip_sync_hook(func(char_id: String, text: String): visemes.append([char_id, text]))
	panel.set_kb_assert(func(fact: String): facts.append(fact))

	panel.open_chat("npc1", "Aldric", "Well met, traveler.")
	_report("the greeting seeds the transcript", panel.model().message_list().size() == 1,
		"got %d messages" % panel.model().message_list().size())

	_report("a line sends", panel.send_line("Hello"), "send_line refused")
	_report("the service received the line", _deep_eq(service.sent, [["npc1", "Hello"]]),
		"got %s" % str(service.sent))
	_report("the turn is in flight", panel.model().is_streaming(), "not streaming")
	_report("a second line is refused while streaming", not panel.send_line("Again"), "accepted two turns")

	service.chunk_received.emit("npc1", "Good ")
	service.chunk_received.emit("npc1", "day.")
	service.chunk_received.emit("npc2", " (from someone else)")
	_report("chunks accumulate into the in-flight bubble", panel.model().streaming_text() == "Good day.",
		"got '%s'" % panel.model().streaming_text())

	panel.on_action("give_item", ["sword"], "has_item(player,sword)")
	panel.on_action("smile", [], "")
	_report("a triggered action reaches the KB exactly once", _deep_eq(facts, ["has_item(player,sword)"]),
		"got %s" % str(facts))

	service.response_complete.emit("npc1", "Good day to you.")
	_report("complete settles the turn", panel.model().completed_turn_count() == 1,
		"got %d" % panel.model().completed_turn_count())
	_report("TTS speaks the settled line", _deep_eq(spoken, [["npc1", "Good day to you."]]),
		"got %s" % str(spoken))
	_report("lip-sync drives the same line", _deep_eq(visemes, [["npc1", "Good day to you."]]),
		"got %s" % str(visemes))
	_report("the input unlocks", not panel.model().is_streaming(), "still streaming")

	# A failed stream renders an error bubble and speaks nothing.
	panel.send_line("Hello?")
	service.response_error.emit("npc1", "connection timed out")
	var last: Dictionary = panel.model().message_list().back()
	_report("a stream error renders an error bubble", last.has("error"), "got %s" % str(last))
	_report("a failed turn is not spoken", spoken.size() == 1, "got %s" % str(spoken))
	_report("a failed turn does not count", panel.model().completed_turn_count() == 1,
		"got %d" % panel.model().completed_turn_count())

	root.remove_child(panel)
	panel.free()


# ── AC: the transcript lands in save.conversations, and nowhere else ─────────
func _test_dialogue_history_persists() -> void:
	var reg := InsimulUiRegistry.shipped()
	var panel := reg.instantiate("dialogue") as InsimulDialoguePanel
	if panel == null:
		return
	root.add_child(panel)
	var service := StubConversationService.new()
	panel.bind_conversation_service(service)

	_report("with no save bound, persisting is a no-op", not panel.persist_history(), "wrote somewhere")

	var save := {"conversations": []}
	panel.bind_save(save)
	panel.open_chat("npc1", "Aldric", "Well met, traveler.")
	panel.send_line("Hello")
	service.response_complete.emit("npc1", "Good day to you.")
	panel.close_chat("2026-08-13T00:00:00.000Z")

	var conversations: Array = save["conversations"]
	_report("closing writes one ConversationSummary", conversations.size() == 1,
		"got %d" % conversations.size())
	if conversations.size() == 1:
		var summary: Dictionary = conversations[0]
		_report("the summary names the character", String(summary.get("npcCharacterId", "")) == "npc1"
			and String(summary.get("npcCharacterName", "")) == "Aldric", "got %s" % str(summary))
		_report("recentTurns carries the settled transcript",
			(summary.get("recentTurns", []) as Array).size() == 3, "got %s" % str(summary.get("recentTurns", [])))
		_report("totalTurnCount is the settled count", int(summary.get("totalTurnCount", -1)) == 1,
			"got %s" % str(summary.get("totalTurnCount", null)))
		_report("every turn carries the caller's timestamp",
			String(((summary.get("recentTurns", []) as Array)[0] as Dictionary).get("timestamp", ""))
				== "2026-08-13T00:00:00.000Z", "got %s" % str(summary.get("recentTurns", [])))

	# A second conversation with the same NPC UPDATES the entry rather than
	# appending a second one — the save is the store, so there is one row per NPC.
	panel.send_line("Anything else?")
	service.response_complete.emit("npc1", "Not today.")
	panel.close_chat("2026-08-13T00:05:00.000Z")
	_report("a later close updates the same entry", (save["conversations"] as Array).size() == 1,
		"got %d rows" % (save["conversations"] as Array).size())
	_report("the updated entry counts both turns",
		int(((save["conversations"] as Array)[0] as Dictionary).get("totalTurnCount", -1)) == 2,
		"got %s" % str((save["conversations"] as Array)[0]))

	# An errored turn never reaches the save.
	panel.send_line("Still there?")
	service.response_error.emit("npc1", "connection timed out")
	panel.close_chat("2026-08-13T00:10:00.000Z")
	var turns: Array = ((save["conversations"] as Array)[0] as Dictionary).get("recentTurns", [])
	_report("an errored turn is excluded from the save", turns.size() == 6,
		"got %d turns: %s" % [turns.size(), str(turns)])

	# A different NPC gets its own row.
	panel.open_chat("npc2", "Bram")
	panel.send_line("Hi")
	service.response_complete.emit("npc2", "Hello.")
	panel.close_chat("2026-08-13T00:15:00.000Z")
	_report("a second NPC appends a second row", (save["conversations"] as Array).size() == 2,
		"got %d rows" % (save["conversations"] as Array).size())

	root.remove_child(panel)
	panel.free()


# ── AC: the ESC menu, module-bundle-gated, in a real tree ────────────────────
func _test_pause_menu_control() -> void:
	var reg := InsimulUiRegistry.shipped()
	var menu := reg.instantiate("pause_menu") as InsimulPauseMenu
	if not _report("the pause menu instantiates", menu != null, _first_diagnostic(reg)):
		return
	root.add_child(menu)
	menu.bind_registry(reg)

	# The strategy bundle keeps only `character` among the gated tabs.
	menu.configure(["proficiency", "gamification", "adaptive-difficulty", "world-lore", "onboarding"])
	var visible := menu.model().visible_keys()
	_report("the tab bar draws one button per visible tab",
		_button_labels(menu).size() == visible.size(),
		"%d buttons for %s" % [_button_labels(menu).size(), str(visible)])
	_report("the strategy bundle hides the assessment tab", not visible.has("assessment"),
		"got %s" % str(visible))

	# The language-learning bundle brings every gated tab back — and the tab bar
	# with it, without anything else being touched.
	menu.configure(["knowledge-acquisition", "proficiency", "pattern-recognition", "performance-scoring",
		"voice", "gamification", "skill-tree", "adaptive-difficulty", "world-lore",
		"conversation-analytics", "assessment", "npc-exams", "onboarding"])
	_report("a regate redraws the tab bar",
		_button_labels(menu).size() == menu.model().visible_keys().size(),
		"%d buttons for %s" % [_button_labels(menu).size(), str(menu.model().visible_keys())])
	_report("the language-learning bundle shows the assessment tab",
		menu.model().visible_keys().has("assessment"), "got %s" % str(menu.model().visible_keys()))

	menu.open_menu()
	_report("opening shows the menu", menu.visible, "not visible")
	_report("opening pauses the tree", paused, "the tree kept running")
	_report("opening lands on the first visible tab", menu.active_tab() == "resume",
		"got '%s'" % menu.active_tab())

	menu.select_tab("journal")
	_report("selecting a visible tab switches to it", menu.active_tab() == "journal",
		"got '%s'" % menu.active_tab())

	# The close tab dismisses the menu instead of showing a body, and WHICH tab
	# that is came from the manifest.
	menu.select_tab(reg.close_tab())
	_report("the close tab dismisses the menu", not menu.is_open(), "still open")
	_report("closing unpauses the tree", not paused, "the tree stayed paused")
	_report("the close tab is not the active tab", menu.active_tab() == "journal",
		"got '%s'" % menu.active_tab())

	menu.toggle()
	_report("toggle reopens", menu.is_open(), "stayed closed")
	menu.toggle()
	_report("toggle closes again", not menu.is_open(), "stayed open")

	paused = false
	root.remove_child(menu)
	menu.free()


# ── AC: a tab BODY is a registry panel, so the module gate reaches it ────────
func _test_pause_menu_bodies() -> void:
	# Ungated (no activation bound): every mapped tab mounts its panel.
	var reg := InsimulUiRegistry.shipped()
	var menu := reg.instantiate("pause_menu") as InsimulPauseMenu
	if menu == null:
		return
	root.add_child(menu)
	menu.configure([])
	menu.bind_registry(reg)
	for tab in reg.tab_panels().keys():
		var tab_key := String(tab)
		if not menu.model().is_visible(tab_key):
			continue
		menu.select_tab(tab_key)
		_report("tab '%s' mounts its body through the registry" % tab_key,
			menu.tab_body(tab_key) is Control, _first_diagnostic(reg))
	# Switching away and back keeps the same body — a panel that rebuilt itself on
	# every tab press would drop whatever the player had scrolled to.
	var first := String(reg.tab_panels().keys()[0])
	if menu.model().is_visible(first):
		var body := menu.tab_body(first)
		menu.select_tab("map")
		menu.select_tab(first)
		_report("switching away and back keeps the same body", menu.tab_body(first) == body,
			"the body was rebuilt")
	root.remove_child(menu)
	menu.free()

	# Gated on a world that activates NOTHING: the tab is still offered (its gate is
	# the module BUNDLE, a different vocabulary) but the body is not, and the
	# registry says which band-111 module took it away.
	var gated := InsimulUiRegistry.shipped()
	gated.set_active_modules([])
	var bare := gated.instantiate("pause_menu") as InsimulPauseMenu
	root.add_child(bare)
	bare.configure([])
	bare.bind_registry(gated)
	gated.clear_diagnostics()
	bare.select_tab("map")
	_report("a tab whose panel the world gates off is still offered", bare.model().is_visible("map"),
		"the module bundle gate and the panel gate are different vocabularies")
	_report("the gated body is absent", bare.tab_body("map") == null, "mounted a gated panel")
	_report("the gate records why the body is absent", gated.has_diagnostics(),
		"a blank pane with nothing to read")
	var told := false
	for note in gated.diagnostics():
		if String((note as Dictionary).get("kind", "")) == "module_inactive":
			told = true
	_report("the diagnostic names the module gate", told, "got %s" % str(gated.diagnostics()))
	root.remove_child(bare)
	bare.free()


# ── AC: the in-game menu SHELL is a composite, mounted through the registry ───
func _test_game_menu_shell() -> void:
	var reg := InsimulUiRegistry.shipped()
	var shell := reg.instantiate("game_menu") as InsimulGameMenu
	if not _report("the menu shell instantiates", shell != null, _first_diagnostic(reg)):
		return
	root.add_child(shell)
	var declared := reg.children("game_menu")
	_report("the shell declares children in the manifest", declared.size() > 0, "no children")
	var mounted := shell.mount(reg, "game_menu")
	_report("the shell mounts every child the gate allows", mounted.size() == declared.size(),
		"mounted %s of %s" % [str(mounted), str(declared)])
	_report("the shell finds its menu by duck-typing", shell.menu_panel() != null,
		"no mounted child behaves like a menu")

	shell.configure(["proficiency"])
	shell.open_menu()
	_report("the shell forwards open to the menu", shell.is_open(), "did not open")
	shell.close_menu()
	_report("the shell forwards close to the menu", not shell.is_open(), "did not close")

	shell.unmount()
	_report("unmounting drops every child", shell.mounted_keys().is_empty(), "children survived")
	paused = false
	root.remove_child(shell)
	shell.free()


# ── AC: save/load rows, incl. the corrupted-envelope messaging ───────────────
func _test_save_load_panel() -> void:
	var reg := InsimulUiRegistry.shipped()
	var panel := reg.instantiate("save_load") as InsimulSaveLoadPanel
	if not _report("the save/load panel instantiates", panel != null, _first_diagnostic(reg)):
		return
	root.add_child(panel)
	panel.set_slots([
		{"index": 0, "outcome": "ok", "summary": {"playerName": "Mara", "level": 7, "locationName": "Rivertown"}},
		{"index": 1, "outcome": "integrity_mismatch"},
		{"index": 2, "outcome": "empty"},
	])
	var texts := _label_texts(panel)
	_report("a healthy slot renders its summary title", texts.has("Mara · Lv 7 · Rivertown"),
		"got %s" % str(texts))
	_report("a corrupted slot renders the integrity message",
		texts.has(InsimulSaveSlotModel.MESSAGES["integrity_mismatch"]), "got %s" % str(texts))
	_report("a corrupted slot is titled as such", texts.has("Corrupted Save"), "got %s" % str(texts))
	_report("an empty slot renders as empty", texts.has("Empty Slot"), "got %s" % str(texts))

	var loads := _buttons_named(panel, "Load")
	_report("one Load affordance per slot", loads.size() == 3, "got %d" % loads.size())
	_report("only the healthy slot can be loaded",
		not loads[0].disabled and loads[1].disabled and loads[2].disabled,
		"disabled = %s" % str([loads[0].disabled, loads[1].disabled, loads[2].disabled]))
	var saves := _buttons_named(panel, "Save")
	_report("a corrupted slot can still be overwritten", not saves[1].disabled, "Save was disabled")

	var requested: Array = []
	panel.load_requested.connect(func(index: int): requested.append(index))
	loads[0].pressed.emit()
	_report("pressing Load asks the host for that slot", _deep_eq(requested, [0]), "got %s" % str(requested))

	root.remove_child(panel)
	panel.free()


# ── AC: the main menu gates Continue/Load on a loadable slot ─────────────────
func _test_main_menu_gate() -> void:
	var reg := InsimulUiRegistry.shipped()
	var menu := reg.instantiate("main_menu") as InsimulMainMenu
	if not _report("the main menu instantiates", menu != null, _first_diagnostic(reg)):
		return
	root.add_child(menu)

	menu.set_slots([{"index": 0, "outcome": "empty"}, {"index": 1, "outcome": "integrity_mismatch"}])
	_report("a fresh install has no save", not menu.has_save(), "claimed a save")
	var cont := _buttons_named(menu, "Continue")
	var load_btn := _buttons_named(menu, "Load Game")
	_report("Continue is disabled with nothing loadable", cont.size() == 1 and cont[0].disabled, "enabled")
	_report("Load is disabled with nothing loadable", load_btn.size() == 1 and load_btn[0].disabled, "enabled")
	_report("a corrupted slot is not a save", not menu.has_save(), "a corrupted slot counted")

	menu.set_slots([{"index": 0, "outcome": "ok", "summary": {"playerName": "Kip", "level": 3}}])
	_report("Continue enables once a slot is loadable", not cont[0].disabled, "still disabled")
	_report("Load enables once a slot is loadable", not load_btn[0].disabled, "still disabled")

	var started := []
	menu.new_game_requested.connect(func(): started.append(true))
	_buttons_named(menu, "New Game")[0].pressed.emit()
	_report("New Game asks the host to start one", started.size() == 1, "got %d" % started.size())

	root.remove_child(menu)
	menu.free()


# ── Harness ──────────────────────────────────────────────────────────────────

## Every Label text under `node`, depth-first — how a node-level leg asks what a
## panel actually RENDERED rather than what its model would have said.
func _label_texts(node: Node) -> Array:
	var out: Array = []
	for child in node.get_children():
		if child is Label:
			out.append((child as Label).text)
		out.append_array(_label_texts(child))
	return out


func _buttons_named(node: Node, label: String) -> Array:
	var out: Array = []
	for child in node.get_children():
		if child is Button and (child as Button).text == label:
			out.append(child)
		out.append_array(_buttons_named(child, label))
	return out


func _button_labels(node: Node) -> Array:
	var out: Array = []
	for child in node.get_children():
		if child is Button:
			out.append((child as Button).text)
		out.append_array(_button_labels(child))
	return out


func _first_diagnostic(reg: InsimulUiRegistry) -> String:
	var notes := reg.diagnostics()
	if notes.is_empty():
		return "no diagnostic"
	return String((notes[0] as Dictionary).get("message", ""))


func _str_array(v: Variant) -> Array:
	var out: Array = []
	for x in (v if v is Array else []):
		out.append(String(x))
	return out


func _deep_eq(a: Variant, b: Variant) -> bool:
	return _norm(a) == _norm(b)


## A structural, JSON-number-tolerant rendering of `v`. JSON.parse() hands back
## every number as a FLOAT, so a corpus `4` arrives as `4.0` while a model counter
## is an `int`; comparing str() or JSON.stringify() of the two says they differ.
## Whole floats are therefore rendered as integers.
func _norm(v: Variant) -> String:
	if v is Dictionary:
		var keys := (v as Dictionary).keys()
		keys.sort()
		var parts: Array = []
		for k in keys:
			parts.append("%s=%s" % [str(k), _norm(v[k])])
		return "{%s}" % ",".join(parts)
	if v is Array:
		var items: Array = []
		for item in (v as Array):
			items.append(_norm(item))
		return "[%s]" % ",".join(items)
	if v is float:
		var f := float(v)
		return str(int(f)) if is_equal_approx(f, floor(f)) else str(f)
	return str(v)


func _load_json(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return {}
	var json := JSON.new()
	if json.parse(text) != OK:
		return {}
	return json.data if json.data is Dictionary else {}


func _report(label: String, ok: bool, detail: String) -> bool:
	if ok:
		_pass += 1
	else:
		_fail += 1
		push_error("[insimul-ui3] FAIL: %s (%s)" % [label, detail])
	return ok


func _resolve_ui_dir() -> String:
	var user_args := OS.get_cmdline_user_args()
	for i in user_args.size():
		if user_args[i] == "--ui" and i + 1 < user_args.size():
			return user_args[i + 1]
	var script_path := (get_script() as Resource).resource_path
	# addons/insimul/tests -> addons/insimul -> addons -> repo root
	var repo := script_path.get_base_dir().get_base_dir().get_base_dir().get_base_dir()
	return repo.path_join("conformance/ui")
