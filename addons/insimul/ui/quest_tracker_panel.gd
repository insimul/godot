class_name InsimulQuestTrackerPanel
extends Control
## Quest tracker HUD Control — a thin view over InsimulQuestJournalModel (US-GU2).
##
## Shows the bounded set of tracked ACTIVE quests (the model enforces max_tracked and
## auto-untracks on completion; shared cases: quest-journal-cases.json). Share the
## SAME model instance as the journal panel via set_model() so tracking a quest in
## the journal shows here immediately.

var _model: InsimulQuestJournalModel = null
var _list: VBoxContainer = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	theme = InsimulUiTokens.build_theme()
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", int(InsimulUiTokens.SPACING["sm"]))
	add_child(_list)
	_refresh()


## Bind the shared journal model (so the HUD reflects the journal's tracked set).
## The model's `changed` signal keeps the HUD live: a quest tracked in the journal
## or completed by the quest system redraws here with no polling.
func set_model(model: InsimulQuestJournalModel) -> void:
	if _model != null and _model.changed.is_connected(_refresh):
		_model.changed.disconnect(_refresh)
	_model = model
	if _model != null and not _model.changed.is_connected(_refresh):
		_model.changed.connect(_refresh)
	_refresh()


func model() -> InsimulQuestJournalModel:
	return _model


func refresh() -> void:
	_refresh()


func _refresh() -> void:
	if _list == null:
		return
	for child in _list.get_children():
		child.queue_free()
	if _model == null:
		return
	for quest in _model.tracked_quests():
		var row := Label.new()
		row.text = "◈ %s" % String(quest.get("title", "?"))
		_list.add_child(row)
