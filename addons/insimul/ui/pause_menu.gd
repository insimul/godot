class_name InsimulPauseMenu
extends Control
## Unified ESC / pause menu — a thin view over InsimulPauseMenuModel (US-3).
##
## Builds a tab bar from the model's VISIBLE tabs (module-bundle-gated), routes the
## active-tab selection through the model, and owns the engine-coupled bits the
## model can't: get_tree().paused, mouse mode, and the ESC toggle. Configure the
## enabled feature modules with configure() (from the active genre bundle).
##
## ## Two gates stack, and they are different vocabularies
##
## A tab is offered when the pause-menu MODULE BUNDLE enables it
## (`knowledge-acquisition`, `proficiency`, `assessment`, … — the model's gate,
## pinned by the shared cases). Its BODY is a shipped panel resolved through
## [InsimulUiRegistry], so it additionally meets the band-111 panel gate
## (`skill`, `map`, `equipment`, …) on the way in. Neither vocabulary is spelled
## here: the tab set is the model's data and the tab -> panel map is the
## manifest's, exactly as a composite reads its children.
##
## A tab no shipped panel serves renders the reason rather than a blank pane; so
## does a tab whose panel this world's modules gate off. `panels.json` accounts for
## every one of the former in `pauseMenuTabNotes`, and check-ui.mjs holds that
## accounting to the shipped tab set in both directions.
##
## [codeblock]
## var ui := InsimulUiRegistry.shipped()
## ui.bind_activation(activation)
## var menu := ui.instantiate(key) as InsimulPauseMenu
## add_child(menu)
## menu.bind_registry(ui)              # tab bodies, gated
## menu.configure(bundle.module_ids()) # tab visibility
## [/codeblock]
##
## Model contract + shared cases: conformance/ui/pause-menu-cases.json.

signal menu_opened
signal menu_closed
signal tab_selected(key: String)

var _model := InsimulPauseMenuModel.new()
var _registry: InsimulUiRegistry = null
var _tab_bar: HBoxContainer = null
var _title: Label = null
var _body: MarginContainer = null
## Tab key -> the mounted panel, so switching away and back keeps its state.
var _bodies: Dictionary = {}
## Tab key -> whatever occupies its pane (a panel, or the note saying why not).
var _slots: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = InsimulUiTokens.build_theme()
	_build_ui()
	visible = false


## Set the enabled feature-module ids (from the active genre bundle) — regates tabs.
func configure(enabled_modules: Array) -> void:
	_model = InsimulPauseMenuModel.new(enabled_modules)
	_drop_bodies()
	_rebuild_tabs()


## Resolve tab BODIES through `registry`. Optional: an unbound menu is still a
## working tab bar, which is what the shared cases exercise.
func bind_registry(registry: InsimulUiRegistry) -> void:
	_registry = registry
	_drop_bodies()
	if _model.active_tab() != "":
		_show_body(_model.active_tab())


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


func is_open() -> bool:
	return _model.is_open()


func active_tab() -> String:
	return _model.active_tab()


## The mounted body for `tab_key`, or null when none is (or can be) shown.
func tab_body(tab_key: String) -> Node:
	return _bodies.get(tab_key, null)


func _apply_open_state() -> void:
	var open := _model.is_open()
	visible = open
	if is_inside_tree():
		get_tree().paused = open
	# A headless / dedicated-server build has no pointer to capture, and asking for
	# one there is an error rather than a no-op.
	if DisplayServer.has_feature(DisplayServer.FEATURE_MOUSE):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED)
	if open:
		_rebuild_tabs()
		_show_body(_model.active_tab())
		menu_opened.emit()
	else:
		menu_closed.emit()


## Switch to `key` exactly as pressing its tab button would — the close tab
## dismisses the menu, a hidden tab is refused by the model. Hosts bind keyboard
## shortcuts to this.
func select_tab(key: String) -> void:
	_select_tab(key)


func _select_tab(key: String) -> void:
	# One tab dismisses the menu instead of showing a body, and WHICH one is
	# manifest data — a shell that spelled it would stop answering the moment a
	# creator relabelled the tab set.
	if _registry != null and key == _registry.close_tab():
		close_menu()
		return
	if _model.set_active(key):
		_update_title()
		_show_body(key)
		tab_selected.emit(key)


func _update_title() -> void:
	if _title:
		_title.text = _model.active_tab()


## Mount (or re-show) the body for `tab_key`. Every branch renders something: a
## blank pane is indistinguishable from a broken install.
func _show_body(tab_key: String) -> void:
	if _body == null:
		return
	for child in _body.get_children():
		(child as CanvasItem).visible = false
	if tab_key == "":
		return
	if _slots.has(tab_key):
		(_slots[tab_key] as CanvasItem).visible = true
		return
	if _registry == null:
		return
	var slot := _resolve_body(tab_key)
	_body.add_child(slot)
	_slots[tab_key] = slot


## The Control that occupies `tab_key`'s pane: the shipped panel, or a note saying
## why there is none. Never null — a blank pane is indistinguishable from a broken
## install, which is the failure this whole registry exists to name.
func _resolve_body(tab_key: String) -> Control:
	var panel_key := _registry.tab_panel(tab_key)
	if panel_key == "":
		return _note("Nothing ships for this tab — the game supplies its body.")
	var panel := _registry.instantiate(panel_key)
	if panel == null:
		var missing := _registry.missing_modules(panel_key)
		if missing.is_empty():
			return _note("Unavailable — the panel could not be loaded.")
		return _note("Unavailable — this world does not activate %s." % ", ".join(missing))
	_bodies[tab_key] = panel
	return panel as Control


func _note(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", int(InsimulUiTokens.FONT_SIZE["caption"]))
	return label


## Drop every mounted body (a regate, a new world): the module set that let a body
## in may not be the one in force now.
func _drop_bodies() -> void:
	if _body != null:
		for child in _body.get_children():
			_body.remove_child(child)
			child.queue_free()
	_bodies.clear()
	_slots.clear()


func _rebuild_tabs() -> void:
	if _tab_bar == null:
		return
	for child in _tab_bar.get_children():
		_tab_bar.remove_child(child)
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
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.add_theme_constant_override("separation", int(InsimulUiTokens.SPACING["md"]))
	add_child(box)

	_tab_bar = HBoxContainer.new()
	_tab_bar.add_theme_constant_override("separation", int(InsimulUiTokens.SPACING["sm"]))
	box.add_child(_tab_bar)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", int(InsimulUiTokens.FONT_SIZE["title"]))
	box.add_child(_title)

	_body = MarginContainer.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("margin_left", int(InsimulUiTokens.SPACING["md"]))
	_body.add_theme_constant_override("margin_top", int(InsimulUiTokens.SPACING["md"]))
	box.add_child(_body)

	_rebuild_tabs()
