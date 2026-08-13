class_name InsimulFullMapPanel
extends Control
## Full-map Control — the whole-world view over InsimulMapModel (US-GU2).
##
## The same marker set the minimap draws, projected over the WHOLE world bounds
## with pan + zoom. Module-gated on `map`. Share the model with
## [InsimulMinimapPanel] via [method set_model] and the two views agree by
## construction.

signal marker_clicked(marker_id: String)
signal world_point_picked(world_x: float, world_z: float)

const ZOOM_MIN := 0.5
const ZOOM_MAX := 4.0
const ZOOM_STEP := 0.25
const MARKER_RADIUS := 5.0
const PLAYER_RADIUS := 6.0

var _model := InsimulMapModel.new()
var _zoom := 1.0
var _pan := Vector2.ZERO


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = InsimulUiTokens.build_theme()
	visible = false
	queue_redraw()


func set_model(model: InsimulMapModel) -> void:
	_model = model
	queue_redraw()


func model() -> InsimulMapModel:
	return _model


func open() -> void:
	visible = true
	queue_redraw()


func close() -> void:
	visible = false


func zoom() -> float:
	return _zoom


## Clamped so the map can never be zoomed out of existence or into one pixel.
func set_zoom(value: float) -> void:
	_zoom = clampf(value, ZOOM_MIN, ZOOM_MAX)
	queue_redraw()


func pan() -> Vector2:
	return _pan


func set_pan(offset: Vector2) -> void:
	_pan = offset
	queue_redraw()


## World (x, z) -> a point in this Control, through the shared normalized
## projection, then zoom and pan.
func point_for(world_x: float, world_z: float) -> Vector2:
	return _model.to_map(world_x, world_z) * size * _zoom + _pan


## The inverse of [method point_for] — what a click on the map means in the world.
func world_for(point: Vector2) -> Vector2:
	var normalized := (point - _pan) / maxf(_zoom, 0.001) / Vector2(maxf(size.x, 1.0), maxf(size.y, 1.0))
	return _model.to_world(normalized)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), InsimulUiTokens.color("background"))
	for marker in _model.markers():
		draw_circle(
			point_for(float(marker.get("x", 0.0)), float(marker.get("z", 0.0))),
			MARKER_RADIUS,
			InsimulUiTokens.color("quest")
		)
	var player := _model.player_position()
	draw_circle(point_for(player.x, player.y), PLAYER_RADIUS, InsimulUiTokens.color("accent"))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if not button.pressed:
			return
		if button.button_index == MOUSE_BUTTON_WHEEL_UP:
			set_zoom(_zoom + ZOOM_STEP)
			return
		if button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			set_zoom(_zoom - ZOOM_STEP)
			return
		for marker in _model.markers():
			var p := point_for(float(marker.get("x", 0.0)), float(marker.get("z", 0.0)))
			if p.distance_to(button.position) <= MARKER_RADIUS * 2.0:
				marker_clicked.emit(String(marker.get("id", "")))
				return
		var world := world_for(button.position)
		world_point_picked.emit(world.x, world.y)
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if motion.button_mask & MOUSE_BUTTON_MASK_LEFT:
			set_pan(_pan + motion.relative)
