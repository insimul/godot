class_name InsimulRadialMenuPanel
extends Control
## Radial action menu Control — the context wheel (US-GU2).
##
## Holds an ordered action list on a circle; the selection is a pure function of
## the pointer angle, so what the wheel would pick is testable without a mouse.
## Module-gated on `agentAi` for the same reason as the quick bar: the action set
## IS that module's IR section.

signal action_selected(action_id: String)

const RADIUS := 120.0
const WEDGE_RADIUS := 26.0

var _actions: Array = []
var _hovered := -1
var _centre := Vector2.ZERO


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = InsimulUiTokens.build_theme()
	visible = false
	queue_redraw()


## Bind the wheel's actions ({ id, name? }), in clockwise order from the top.
func set_actions(actions: Array) -> void:
	_actions = actions.duplicate(true)
	_hovered = -1
	queue_redraw()


func actions() -> Array:
	return _actions.duplicate(true)


func open_at(centre: Vector2) -> void:
	_centre = centre
	_hovered = -1
	visible = true
	queue_redraw()


func close() -> void:
	visible = false
	_hovered = -1


func is_open() -> bool:
	return visible


## The wedge centre for `index`, clockwise from straight up.
func point_for(index: int) -> Vector2:
	if _actions.is_empty():
		return _centre
	var angle := -PI * 0.5 + TAU * float(index) / float(_actions.size())
	return _centre + Vector2(cos(angle), sin(angle)) * RADIUS


## Which wedge a point picks — the whole selection rule, as arithmetic. Answers -1
## inside the dead zone at the centre (a release there cancels) and for an empty
## wheel.
func index_at(point: Vector2) -> int:
	if _actions.is_empty():
		return -1
	var offset := point - _centre
	if offset.length() < WEDGE_RADIUS:
		return -1
	var wedge := TAU / float(_actions.size())
	var angle := fposmod(offset.angle() + PI * 0.5 + wedge * 0.5, TAU)
	return int(angle / wedge) % _actions.size()


func hover(point: Vector2) -> int:
	_hovered = index_at(point)
	queue_redraw()
	return _hovered


func hovered_index() -> int:
	return _hovered


## Commit the wedge under `point`. Returns "" when the point cancels.
func select_at(point: Vector2) -> String:
	var index := index_at(point)
	close()
	if index < 0:
		return ""
	var id := String((_actions[index] as Dictionary).get("id", ""))
	if not id.is_empty():
		action_selected.emit(id)
	return id


func _draw() -> void:
	draw_circle(_centre, WEDGE_RADIUS, InsimulUiTokens.color("overlay"))
	for i in range(_actions.size()):
		var fill := InsimulUiTokens.color("accent") if i == _hovered else InsimulUiTokens.color("surface")
		draw_circle(point_for(i), WEDGE_RADIUS, fill)


func _gui_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseMotion:
		hover((event as InputEventMouseMotion).position)
	elif event is InputEventMouseButton and not (event as InputEventMouseButton).pressed:
		select_at((event as InputEventMouseButton).position)
