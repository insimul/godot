extends CanvasLayer
## Action Quick Bar — HUD hotbar and radial menu.
## Matches shared/game-engine/rendering/ActionQuickBar.ts, BabylonRadialMenu.ts.

signal action_triggered(slot: int, action_id: String)

const SLOT_COUNT := 9

var _slots: Array[Dictionary] = []  # { id, name, icon_path }
var _slot_buttons: Array[TextureRect] = []
var _slot_labels: Array[Label] = []
var _hotbar: HBoxContainer = null

func _ready() -> void:
	layer = 3
	_build_hotbar()
	_slots.resize(SLOT_COUNT)
	for i in range(SLOT_COUNT):
		_slots[i] = {}

func assign_slot(slot: int, action_id: String, action_name: String) -> void:
	if slot < 0 or slot >= SLOT_COUNT:
		return
	_slots[slot] = {"id": action_id, "name": action_name}
	if slot < _slot_labels.size():
		_slot_labels[slot].text = action_name.substr(0, 4)

func clear_slot(slot: int) -> void:
	if slot < 0 or slot >= SLOT_COUNT:
		return
	_slots[slot] = {}
	if slot < _slot_labels.size():
		_slot_labels[slot].text = str(slot + 1)

func _unhandled_input(event: InputEvent) -> void:
	# Number keys 1-9
	for i in range(SLOT_COUNT):
		var action_name := "hotbar_%d" % (i + 1)
		if InputMap.has_action(action_name) and event.is_action_pressed(action_name):
			_activate_slot(i)
			return

	# Also check raw key events for 1-9
	if event is InputEventKey and event.pressed and not event.echo:
		var key: int = event.keycode
		if key >= KEY_1 and key <= KEY_9:
			_activate_slot(key - KEY_1)

func _activate_slot(slot: int) -> void:
	var data: Dictionary = _slots[slot]
	if data.is_empty():
		return
	action_triggered.emit(slot, data.get("id", ""))

	# Visual feedback
	if slot < _slot_buttons.size():
		var rect: TextureRect = _slot_buttons[slot]
		var tween := create_tween()
		tween.tween_property(rect, "modulate", Color(1.5, 1.5, 0.5, 1), 0.1)
		tween.tween_property(rect, "modulate", Color.WHITE, 0.2)

func _build_hotbar() -> void:
	_hotbar = HBoxContainer.new()
	_hotbar.anchors_preset = Control.PRESET_CENTER_BOTTOM
	_hotbar.anchor_left = 0.25
	_hotbar.anchor_right = 0.75
	_hotbar.anchor_top = 0.92
	_hotbar.anchor_bottom = 0.99
	_hotbar.alignment = BoxContainer.ALIGNMENT_CENTER
	_hotbar.add_theme_constant_override("separation", 4)
	add_child(_hotbar)

	for i in range(SLOT_COUNT):
		var slot_panel := PanelContainer.new()
		slot_panel.custom_minimum_size = Vector2(50, 50)
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.15, 0.15, 0.2, 0.8)
		style.set_corner_radius_all(4)
		style.border_color = Color(0.4, 0.4, 0.5, 0.8)
		style.set_border_width_all(1)
		slot_panel.add_theme_stylebox_override("panel", style)
		_hotbar.add_child(slot_panel)

		var tex_rect := TextureRect.new()
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		slot_panel.add_child(tex_rect)
		_slot_buttons.append(tex_rect)

		var label := Label.new()
		label.text = str(i + 1)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		slot_panel.add_child(label)
		_slot_labels.append(label)
