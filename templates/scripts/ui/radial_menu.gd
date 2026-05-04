extends CanvasLayer
## Radial Action Menu — context-sensitive circular action wheel.
## Hold right-click to open, release to select.

signal action_selected(action_id: String)

const RADIUS := 120.0
const BUTTON_SIZE := 60.0
const CENTER_RADIUS := 30.0
const BG_COLOR := Color(0.1, 0.1, 0.12, 0.85)
const HIGHLIGHT_COLOR := Color(0.3, 0.5, 0.8, 0.9)
const TEXT_COLOR := Color(0.9, 0.88, 0.82)

var _is_open := false
var _actions: Array[Dictionary] = []  # [{id, name, icon, color}]
var _hovered_index := -1
var _center := Vector2.ZERO
var _draw_control: Control = null

func _ready() -> void:
	layer = 25
	_draw_control = Control.new()
	_draw_control.anchor_right = 1.0
	_draw_control.anchor_bottom = 1.0
	_draw_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_draw_control.draw.connect(_on_draw)
	add_child(_draw_control)
	visible = false

func open_menu(actions: Array[Dictionary]) -> void:
	if actions.is_empty():
		return
	_actions = actions
	_center = get_viewport().get_visible_rect().size / 2.0
	_hovered_index = -1
	_is_open = true
	visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_draw_control.queue_redraw()

func close_menu() -> void:
	if not _is_open:
		return
	_is_open = false
	visible = false
	if _hovered_index >= 0 and _hovered_index < _actions.size():
		action_selected.emit(_actions[_hovered_index].get("id", ""))
	_hovered_index = -1
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event is InputEventMouseMotion:
		_update_hover(event.position)
		_draw_control.queue_redraw()
	if event is InputEventMouseButton and not event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			close_menu()

func _update_hover(mouse_pos: Vector2) -> void:
	var diff := mouse_pos - _center
	var dist := diff.length()
	if dist < CENTER_RADIUS or _actions.is_empty():
		_hovered_index = -1
		return
	var angle := atan2(diff.y, diff.x)
	if angle < 0:
		angle += TAU
	var sector_size: float = TAU / float(_actions.size())
	_hovered_index = int(angle / sector_size) % _actions.size()

func _on_draw() -> void:
	if not _is_open or _actions.is_empty():
		return

	var count: int = _actions.size()
	var sector_size: float = TAU / float(count)

	# Draw background circle
	_draw_control.draw_circle(_center, RADIUS + BUTTON_SIZE / 2.0, BG_COLOR)

	# Draw action segments
	for i in range(count):
		var angle: float = sector_size * float(i) - PI / 2.0  # Start from top
		var btn_center := _center + Vector2(cos(angle), sin(angle)) * RADIUS
		var is_hovered: bool = (i == _hovered_index)

		# Segment highlight
		var color: Color = HIGHLIGHT_COLOR if is_hovered else Color(0.2, 0.2, 0.22, 0.8)
		_draw_control.draw_circle(btn_center, BUTTON_SIZE / 2.0, color)

		# Action name
		var action: Dictionary = _actions[i]
		var label: String = action.get("name", "?")
		# Truncate long names
		if label.length() > 10:
			label = label.substr(0, 9) + "."

		var font := ThemeDB.fallback_font
		var font_size: int = 12
		var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		var text_pos := btn_center - text_size / 2.0
		_draw_control.draw_string(font, text_pos, label, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, TEXT_COLOR)

	# Center cancel zone
	_draw_control.draw_circle(_center, CENTER_RADIUS, Color(0.15, 0.15, 0.18, 0.9))
	var cancel_font := ThemeDB.fallback_font
	var cancel_size := cancel_font.get_string_size("X", HORIZONTAL_ALIGNMENT_CENTER, -1, 16)
	_draw_control.draw_string(cancel_font, _center - cancel_size / 2.0, "X", HORIZONTAL_ALIGNMENT_CENTER, -1, 16, Color(0.6, 0.5, 0.5))
