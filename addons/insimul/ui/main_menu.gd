class_name InsimulMainMenu
extends Control
## Main menu (US-GU3).
##
## The title-screen entry point: New Game / Continue / Load / Settings / Quit. The
## Continue + Load affordances gate on whether any slot is loadable, reusing the
## InsimulSaveSlotModel contract (has_any_loadable) so the main menu and the in-game
## save/load panel agree on what "has a save" means. Feed codec-reported slot
## outcomes via set_slots().

signal new_game_requested
signal continue_requested
signal load_requested
signal settings_requested
signal quit_requested

var _slots := InsimulSaveSlotModel.new()
var _continue_btn: Button = null
var _load_btn: Button = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = InsimulUiTokens.build_theme()
	_build_ui()
	_refresh_gates()


## Set the codec-reported slot outcomes (gates Continue/Load).
func set_slots(results: Array) -> void:
	_slots.set_slots(results)
	_refresh_gates()


func has_save() -> bool:
	return _slots.has_any_loadable()


func _refresh_gates() -> void:
	var has := _slots.has_any_loadable()
	if _continue_btn:
		_continue_btn.disabled = not has
	if _load_btn:
		_load_btn.disabled = not has


func _build_ui() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.add_theme_constant_override("separation", int(InsimulUiTokens.SPACING["md"]))
	add_child(box)

	var title := Label.new()
	title.text = "insimul"
	title.add_theme_font_size_override("font_size", int(InsimulUiTokens.FONT_SIZE["display"]))
	box.add_child(title)

	_continue_btn = _menu_button(box, "Continue", func(): continue_requested.emit())
	var new_btn := _menu_button(box, "New Game", func(): new_game_requested.emit())
	new_btn.grab_focus()
	_load_btn = _menu_button(box, "Load Game", func(): load_requested.emit())
	_menu_button(box, "Settings", func(): settings_requested.emit())
	_menu_button(box, "Quit", func(): quit_requested.emit())


func _menu_button(parent: Control, label: String, cb: Callable) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(220, 0)
	btn.pressed.connect(cb)
	parent.add_child(btn)
	return btn
