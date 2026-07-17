# browser_test.gd — the Godot headless leg of the World Browser gate (US-GE2),
# exercising the LOGIC LAYER (InsimulWorldBrowserModel + InsimulWorldCompat) over
# mocked API bodies.
#
# The dock UI (insimul_world_browser_dock.gd) needs a running editor and is only
# structurally checked; the model is pure and fully testable here. The
# machine-runnable source of truth is packages/core/src/editor/world-browser.ts +
# world-browser.test.ts (they run on a bare box under `npm test`); this file is the
# end-to-end Godot confirmation for the merge gate. When NO `godot` binary is
# present the runner SKIPs.
#
#   godot --headless -s addons/insimul/editor/browser/browser_test.gd
extends SceneTree

var _pass := 0
var _fail := 0


func _initialize() -> void:
	_test_compat_badge()
	_test_parse_world_list()
	_test_import_report()
	_test_reducer_selection()
	_test_open_in_web()
	_finish()


func _finish() -> void:
	print("-----------------------------------------------------------")
	print("[insimul-browser] %d passed, %d failed" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)


func _test_compat_badge() -> void:
	_report("equal -> compatible", String(InsimulWorldCompat.compatibility(3, 3).get("level", "")) == "compatible", "")
	_report("older -> warning", String(InsimulWorldCompat.compatibility(2, 3).get("level", "")) == "warning", "")
	_report("newer -> incompatible", String(InsimulWorldCompat.compatibility(4, 3).get("level", "")) == "incompatible", "")


func _test_parse_world_list() -> void:
	var body := '{"worlds":[{"id":"w1","name":"Riverbend","saveFormatVersion":3,"npcCount":42},{"name":"no id"}]}'
	var worlds := InsimulWorldBrowserModel.parse_world_list(body)
	_report("parse drops malformed, keeps valid", worlds.size() == 1 and String(worlds[0].get("id", "")) == "w1", "%s" % worlds)
	_report("parse tolerates a bad body", InsimulWorldBrowserModel.parse_world_list("nope").is_empty(), "")


func _test_import_report() -> void:
	var report := InsimulWorldBrowserModel.parse_import_report('{"worldId":"w1","dryRun":true,"added":2,"updated":1,"unchanged":10}')
	_report("import report parsed", String(report.get("world_id", "")) == "w1" and bool(report.get("dry_run", false)), "%s" % report)
	_report("import summary", InsimulWorldBrowserModel.summarize_import_report(report) == "Dry run: +2 / ~1 / -0 (10 unchanged).", InsimulWorldBrowserModel.summarize_import_report(report))


func _test_reducer_selection() -> void:
	var model := InsimulWorldBrowserModel.new()
	model.load_start()
	_report("load_start -> loading", String(model.state.get("status", "")) == "loading", "")
	var worlds := [{"id": "w1", "name": "A"}, {"id": "w2", "name": "B"}]
	model.load_success(worlds)
	model.select("w2")
	_report("select in-list world", String(model.selected_world().get("name", "")) == "B", "")
	model.select("ghost")
	_report("select ignores unknown id", String(model.state.get("selected_id", "")) == "w2", "")
	model.load_success([{"id": "w1", "name": "A"}])
	_report("re-fetch clears dangling selection", String(model.state.get("selected_id", "")) == "", "")


func _test_open_in_web() -> void:
	_report("open-in-web URL", InsimulWorldBrowserModel.open_in_web_url("http://x/", "a b") == "http://x/worlds/a%20b", InsimulWorldBrowserModel.open_in_web_url("http://x/", "a b"))


func _report(name: String, ok: bool, detail: String) -> void:
	print("  %s  %s%s" % ["PASS" if ok else "FAIL", name, ("" if detail.is_empty() else "  " + detail)])
	if ok:
		_pass += 1
	else:
		_fail += 1
