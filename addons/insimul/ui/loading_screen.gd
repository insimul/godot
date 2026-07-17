class_name InsimulLoadingScreen
extends Control
## Loading-screen Control — a thin view over InsimulLoadingScreenModel (US-GU1).
##
## Drive it from the boot loop with set_phase("world"), set_phase("kb"), … as each
## startup stage completes; the model computes the progress bar value, the phase
## label, and a rotating tip. Emits `finished` once the terminal phase is reached.
## All styling comes from the shared token Theme (InsimulUiTokens.build_theme()).

signal finished

var _model := InsimulLoadingScreenModel.new()
var _title: Label = null
var _bar: ProgressBar = null
var _tip: Label = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = InsimulUiTokens.build_theme()
	_build_ui()
	_refresh()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = InsimulUiTokens.color("background")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.add_theme_constant_override("separation", int(InsimulUiTokens.SPACING["md"]))
	add_child(box)

	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", int(InsimulUiTokens.FONT_SIZE["title"]))
	box.add_child(_title)

	_bar = ProgressBar.new()
	_bar.min_value = 0.0
	_bar.max_value = 1.0
	_bar.custom_minimum_size = Vector2(360, 18)
	_bar.show_percentage = false
	box.add_child(_bar)

	_tip = Label.new()
	_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip.add_theme_color_override("font_color", InsimulUiTokens.color("text_secondary"))
	_tip.add_theme_font_size_override("font_size", int(InsimulUiTokens.FONT_SIZE["caption"]))
	box.add_child(_tip)


## Advance the boot phase and repaint. Keys match loading-phases.json.
func set_phase(key: String) -> void:
	_model.advance(key)
	_refresh()
	if _model.is_complete():
		finished.emit()


func model() -> InsimulLoadingScreenModel:
	return _model


func _refresh() -> void:
	if _title == null:
		return
	_title.text = _model.label()
	_bar.value = _model.progress()
	_tip.text = _model.tip()
