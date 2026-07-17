@tool
class_name InsimulWorldBrowserDock
extends Control
## World Browser dock — UI (US-GE2).
##
## The @tool Control the EditorPlugin docks into the editor. It is a THIN view over
## the logic layer (InsimulWorldBrowserModel): the model owns list/detail parsing,
## the selection reducer, the compatibility badge, and the open-in-web URL; this
## file only wires Godot Controls (ItemList, labels, buttons) to those calls and
## dispatches API operations through the shared InsimulEditorSession. Per the
## story's "logic layer tested; UI structurally checked" split, the model is
## exercised headless (browser_test.gd) and this file is covered by the GDScript
## structural lint + the human end-to-end pass (VERIFICATION.md).

const _LEVEL_COLORS := {
	"compatible": Color(0.55, 0.85, 0.55),
	"warning": Color(0.9, 0.8, 0.45),
	"incompatible": Color(0.9, 0.55, 0.5),
}

var model: InsimulWorldBrowserModel
var session: InsimulEditorSession

var _list: ItemList
var _detail: Label
var _badge: Label
var _status: Label


func _init(editor_session: InsimulEditorSession = null) -> void:
	model = InsimulWorldBrowserModel.new()
	session = editor_session
	name = "Insimul Worlds"


func _ready() -> void:
	_build_ui()
	refresh()


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var toolbar := HBoxContainer.new()
	root.add_child(toolbar)

	var refresh_btn := Button.new()
	refresh_btn.text = "Refresh"
	refresh_btn.pressed.connect(refresh)
	toolbar.add_child(refresh_btn)

	var import_btn := Button.new()
	import_btn.text = "Import (dry run)…"
	import_btn.pressed.connect(_on_import_pressed.bind(true))
	toolbar.add_child(import_btn)

	var sync_btn := Button.new()
	sync_btn.text = "Sync into pipeline"
	sync_btn.pressed.connect(_on_import_pressed.bind(false))
	toolbar.add_child(sync_btn)

	var web_btn := Button.new()
	web_btn.text = "Open in Web"
	web_btn.pressed.connect(_on_open_web_pressed)
	toolbar.add_child(web_btn)

	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(_on_item_selected)
	root.add_child(_list)

	_detail = Label.new()
	root.add_child(_detail)

	_badge = Label.new()
	root.add_child(_badge)

	_status = Label.new()
	root.add_child(_status)


## Fetch the worlds list via the session and repopulate the dock.
func refresh() -> void:
	model.load_start()
	_render()
	if session == null:
		return
	session.call_operation("listWorlds", "", func(res: Dictionary):
		var code := int(res.get("code", 0))
		if code >= 200 and code < 300:
			model.load_success(InsimulWorldBrowserModel.parse_world_list(String(res.get("body", ""))))
		else:
			model.load_error("listWorlds failed (%d)" % code)
		_render()
	)


func _render() -> void:
	if _list == null:
		return
	_list.clear()
	for w in model.state.get("worlds", []):
		_list.add_item(String(w.get("name", "")))
	_status.text = "%d world(s) — %s" % [model.state.get("worlds", []).size(), String(model.state.get("status", ""))]
	_render_detail()


func _on_item_selected(index: int) -> void:
	var worlds: Array = model.state.get("worlds", [])
	if index >= 0 and index < worlds.size():
		model.select(String(worlds[index].get("id", "")))
		_render_detail()


func _render_detail() -> void:
	var world := model.selected_world()
	if world.is_empty():
		_detail.text = "Select a world."
		_badge.text = ""
		return
	_detail.text = "%s — v%d, %d NPCs, %d settlements, %d quests" % [
		String(world.get("name", "")), int(world.get("world_version", 0)),
		int(world.get("npc_count", 0)), int(world.get("settlement_count", 0)),
		int(world.get("quest_count", 0)),
	]
	var badge := InsimulWorldBrowserModel.world_compatibility(world)
	_badge.text = String(badge.get("message", ""))
	_badge.add_theme_color_override("font_color", _LEVEL_COLORS.get(String(badge.get("level", "")), Color.WHITE))


func _on_import_pressed(dry_run: bool) -> void:
	var world := model.selected_world()
	if world.is_empty() or session == null:
		return
	var body := JSON.stringify({"worldId": String(world.get("id", "")), "dryRun": dry_run})
	session.call_operation("importWorld", body, func(res: Dictionary):
		var report := InsimulWorldBrowserModel.parse_import_report(String(res.get("body", "")))
		if not report.is_empty():
			_status.text = InsimulWorldBrowserModel.summarize_import_report(report)
	)


func _on_open_web_pressed() -> void:
	var world := model.selected_world()
	if world.is_empty() or session == null:
		return
	OS.shell_open(InsimulWorldBrowserModel.open_in_web_url(session.base_url, String(world.get("id", ""))))
