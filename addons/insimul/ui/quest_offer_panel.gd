class_name InsimulQuestOfferPanel
extends Control
## Quest offer dialog Control — a thin view over InsimulQuestJournalModel (US-GU2).
##
## Presents a single AVAILABLE quest (from an NPC giver or a radiant arrival) with
## Accept / Decline. The model owns the transitions (accept: available -> active,
## decline: removed); shared cases: quest-journal-cases.json. Share the SAME model
## instance as the journal via set_model() so an accepted offer shows up as active
## in the journal/tracker.

signal quest_accepted(quest_id: String)
signal quest_declined(quest_id: String)

var _model: InsimulQuestJournalModel = null
var _quest_id := ""
var _title: Label = null
var _desc: Label = null
var _accept_btn: Button = null
var _decline_btn: Button = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	theme = InsimulUiTokens.build_theme()
	_build_ui()
	visible = false


func _build_ui() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(InsimulUiTokens.SPACING["md"]))
	add_child(box)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", int(InsimulUiTokens.FONT_SIZE["title"]))
	box.add_child(_title)

	_desc = Label.new()
	_desc.add_theme_color_override("font_color", InsimulUiTokens.color("text_secondary"))
	box.add_child(_desc)

	var buttons := HBoxContainer.new()
	_accept_btn = Button.new()
	_accept_btn.text = "Accept"
	_accept_btn.pressed.connect(_on_accept)
	buttons.add_child(_accept_btn)
	_decline_btn = Button.new()
	_decline_btn.text = "Decline"
	_decline_btn.pressed.connect(_on_decline)
	buttons.add_child(_decline_btn)
	box.add_child(buttons)


func set_model(model: InsimulQuestJournalModel) -> void:
	_model = model


## Present an offer. `entry` is upserted (as available) into the shared model.
func present(entry: Dictionary) -> void:
	if _model != null:
		_model.upsert(entry)
	_quest_id = String(entry.get("id", ""))
	if _title != null:
		_title.text = String(entry.get("title", "?"))
		_desc.text = String(entry.get("description", ""))
	visible = true


func _on_accept() -> void:
	if _model != null and _model.accept(_quest_id):
		quest_accepted.emit(_quest_id)
	visible = false


func _on_decline() -> void:
	if _model != null and _model.decline(_quest_id):
		quest_declined.emit(_quest_id)
	visible = false
