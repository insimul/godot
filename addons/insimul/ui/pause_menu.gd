class_name InsimulPauseMenu
extends Control
## Unified ESC / pause menu — a thin view over InsimulPauseMenuModel (US-GU3).
##
## Builds a tab bar from the model's VISIBLE tabs (module-bundle-gated), routes the
## active-tab selection through the model, and owns the engine-coupled bits the
## model can't: get_tree().paused, mouse mode, and the ESC toggle. Configure the
## enabled feature modules with configure() (from the active genre bundle).
##
## Model contract + shared cases: packages/core/conformance/ui/pause-menu-cases.json.

signal menu_opened
signal menu_closed
signal tab_selected(key: String)

var _model := InsimulPauseMenuModel.new()
var _tab_bar: HBoxContainer = null
var _title: Label = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = InsimulUiTokens.build_theme()
	_build_ui()
	visible = false


## Set the enabled feature-module ids (from the active genre bundle) — regates tabs.
func configure(enabled_modules: Array) -> void:
	_model = InsimulPauseMenuModel.new(enabled_modules)
	_rebuild_tabs()


func model() -> InsimulPauseMenuModel:
	return _model


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		toggle()


func toggle() -> void:
	_model.toggle()
	_apply_open_state()


func open_menu(tab: String = "") -> void:
	_model.open_menu(tab)
	_apply_open_state()


func close_menu() -> void:
	_model.close_menu()
	_apply_open_state()


func active_tab() -> String:
	return _model.active_tab()


func _apply_open_state() -> void:
	var open := _model.is_open()
	visible = open
	get_tree().paused = open
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED)
	if open:
		_rebuild_tabs()
		menu_opened.emit()
	else:
		menu_closed.emit()


func _select_tab(key: String) -> void:
	if _model.set_active(key):
		_update_title()
		tab_selected.emit(key)


func _update_title() -> void:
	if _title:
		_title.text = _model.active_tab()


func _rebuild_tabs() -> void:
	if _tab_bar == null:
		return
	for child in _tab_bar.get_children():
		child.queue_free()
	for tab in _model.visible_tabs():
		var key := String(tab["key"])
		var btn := Button.new()
		btn.text = String(tab.get("label", key))
		btn.pressed.connect(_select_tab.bind(key))
		_tab_bar.add_child(btn)
	_update_title()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = InsimulUiTokens.color("overlay")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.add_theme_constant_override("separation", int(InsimulUiTokens.SPACING["md"]))
	add_child(box)

	_tab_bar = HBoxContainer.new()
	_tab_bar.add_theme_constant_override("separation", int(InsimulUiTokens.SPACING["sm"]))
	box.add_child(_tab_bar)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", int(InsimulUiTokens.FONT_SIZE["title"]))
	box.add_child(_title)

	_rebuild_tabs()
