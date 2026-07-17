class_name InsimulQuestJournalPanel
extends Control
## Quest journal Control — a thin view over InsimulQuestJournalModel (US-GU2).
##
## Renders the tab-filtered quest list; the model owns all filtering / lifecycle /
## tracking logic (shared cases: quest-journal-cases.json). Drive it from the real
## InsimulQuestSystem: connect quest_offered -> offer(), quest_accepted /
## quest_completed -> refresh after accept()/complete(). All styling comes from the
## shared token Theme.

signal quest_tracked(quest_id: String)
signal quest_untracked(quest_id: String)

var _model := InsimulQuestJournalModel.new()
var _tabs: HBoxContainer = null
var _list: VBoxContainer = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = InsimulUiTokens.build_theme()
	_build_ui()
	_refresh()


func _build_ui() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.add_theme_constant_override("separation", int(InsimulUiTokens.SPACING["md"]))
	add_child(box)

	_tabs = HBoxContainer.new()
	for f in ["all", "active", "completed", "available"]:
		var btn := Button.new()
		btn.text = String(f).capitalize()
		btn.pressed.connect(_on_filter.bind(String(f)))
		_tabs.add_child(btn)
	box.add_child(_tabs)

	_list = VBoxContainer.new()
	box.add_child(_list)


## Bind a quest set (present-only projections { id, title, status, difficulty? }).
func set_quests(entries: Array) -> void:
	_model.set_quests(entries)
	_refresh()


## A radiant arrival (quest_offered) — appears under the Available tab.
func offer(entry: Dictionary) -> void:
	_model.upsert(entry)
	_refresh()


func accept(id: String) -> bool:
	var ok := _model.accept(id)
	if ok:
		_refresh()
	return ok


func complete(id: String) -> bool:
	var ok := _model.complete(id)
	if ok:
		_refresh()
	return ok


func track(id: String) -> bool:
	var ok := _model.track(id)
	if ok:
		quest_tracked.emit(id)
		_refresh()
	return ok


func untrack(id: String) -> bool:
	var ok := _model.untrack(id)
	if ok:
		quest_untracked.emit(id)
		_refresh()
	return ok


func model() -> InsimulQuestJournalModel:
	return _model


func _on_filter(filter: String) -> void:
	_model.set_filter(filter)
	_refresh()


func _refresh() -> void:
	if _list == null:
		return
	for child in _list.get_children():
		child.queue_free()
	for quest in _model.filtered():
		var row := Label.new()
		var marker := "★ " if _model.is_tracked(String(quest.get("id", ""))) else ""
		row.text = "%s%s  [%s]" % [marker, String(quest.get("title", "?")), String(quest.get("status", ""))]
		_list.add_child(row)
