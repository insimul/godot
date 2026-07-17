class_name InsimulSaveLoadPanel
extends Control
## Save / load slot UI — a thin view over InsimulSaveSlotModel (US-GU3).
##
## Renders one row per slot from the model (status/title/message + Load/Save
## affordances), showing the corrupted-envelope MESSAGING when the codec reports an
## integrity failure. Feed it codec-reported slot outcomes via set_slots(); the panel
## emits load_requested / save_requested for the host to act on.
##
## Model contract + shared cases: packages/core/conformance/ui/save-slot-cases.json.

signal load_requested(index: int)
signal save_requested(index: int)

var _model := InsimulSaveSlotModel.new()
var _list: VBoxContainer = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = InsimulUiTokens.build_theme()
	_build_ui()
	_refresh()


## Set the codec-reported slot outcomes: [{ index, outcome, summary? }].
func set_slots(results: Array) -> void:
	_model.set_slots(results)
	_refresh()


func model() -> InsimulSaveSlotModel:
	return _model


func _refresh() -> void:
	if _list == null:
		return
	for child in _list.get_children():
		child.queue_free()
	for row in _model.slots():
		_list.add_child(_build_row(row))


func _build_row(row: Dictionary) -> Control:
	var index := int(row.get("index", 0))
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", int(InsimulUiTokens.SPACING["sm"]))

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(info)

	var title := Label.new()
	title.text = String(row.get("title", ""))
	if String(row.get("status", "")) == "corrupted":
		title.add_theme_color_override("font_color", InsimulUiTokens.color("danger"))
	info.add_child(title)

	var message := String(row.get("message", ""))
	if message != "":
		var msg := Label.new()
		msg.text = message
		msg.add_theme_font_size_override("font_size", int(InsimulUiTokens.FONT_SIZE["caption"]))
		info.add_child(msg)

	var load_btn := Button.new()
	load_btn.text = "Load"
	load_btn.disabled = not bool(row.get("can_load", false))
	load_btn.pressed.connect(func(): load_requested.emit(index))
	hbox.add_child(load_btn)

	var save_btn := Button.new()
	save_btn.text = "Save"
	save_btn.disabled = not bool(row.get("can_save", false))
	save_btn.pressed.connect(func(): save_requested.emit(index))
	hbox.add_child(save_btn)

	return hbox


func _build_ui() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.add_theme_constant_override("separation", int(InsimulUiTokens.SPACING["sm"]))
	add_child(box)

	var heading := Label.new()
	heading.text = "Save / Load"
	heading.add_theme_font_size_override("font_size", int(InsimulUiTokens.FONT_SIZE["title"]))
	box.add_child(heading)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", int(InsimulUiTokens.SPACING["xs"]))
	box.add_child(_list)
