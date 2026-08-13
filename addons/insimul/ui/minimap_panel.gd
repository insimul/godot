class_name InsimulMinimapPanel
extends Control
## Minimap Control — the near-field view over InsimulMapModel (US-GU2).
##
## Draws the markers within [member view_radius] world units of the player onto a
## fixed square, with the player at the centre. Module-gated on `map`.
##
## This panel draws MARKERS, not the world: the overhead render (a SubViewport +
## Camera3D) is engine-specific and lives in `templates/scripts/ui/minimap.gd`. The
## addon owns the projection and the marker set, so the minimap and the full map
## can never disagree about where a thing is — they share one model.

signal marker_clicked(marker_id: String)

const DEFAULT_SIZE := 200.0
const MARKER_RADIUS := 3.0
const PLAYER_RADIUS := 4.0

## World units from the player that fit on the minimap edge-to-centre.
var view_radius := 60.0

var _model := InsimulMapModel.new()


func _ready() -> void:
	custom_minimum_size = Vector2(DEFAULT_SIZE, DEFAULT_SIZE)
	size = custom_minimum_size
	theme = InsimulUiTokens.build_theme()
	queue_redraw()


## Share the map model with the full map so both show the same markers.
func set_model(model: InsimulMapModel) -> void:
	_model = model
	queue_redraw()


func model() -> InsimulMapModel:
	return _model


func refresh() -> void:
	queue_redraw()


## Markers currently on the minimap — the near-field slice of the shared set.
func visible_markers() -> Array:
	var player := _model.player_position()
	return _model.markers_near(player.x, player.y, view_radius)


## World (x, z) -> a point in this Control, player-centred. Callers that need the
## whole-world projection ask the model for [method InsimulMapModel.to_map].
func point_for(world_x: float, world_z: float) -> Vector2:
	var player := _model.player_position()
	var centre := size * 0.5
	var scale_px := (minf(size.x, size.y) * 0.5) / maxf(view_radius, 0.001)
	return centre + Vector2(world_x - player.x, world_z - player.y) * scale_px


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), InsimulUiTokens.color("surface"))
	draw_rect(Rect2(Vector2.ZERO, size), InsimulUiTokens.color("border"), false, 1.0)
	for marker in visible_markers():
		draw_circle(
			point_for(float(marker.get("x", 0.0)), float(marker.get("z", 0.0))),
			MARKER_RADIUS,
			InsimulUiTokens.color("quest")
		)
	draw_circle(size * 0.5, PLAYER_RADIUS, InsimulUiTokens.color("accent"))


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton) or not (event as InputEventMouseButton).pressed:
		return
	var at: Vector2 = (event as InputEventMouseButton).position
	for marker in visible_markers():
		var p := point_for(float(marker.get("x", 0.0)), float(marker.get("z", 0.0)))
		if p.distance_to(at) <= MARKER_RADIUS * 2.0:
			marker_clicked.emit(String(marker.get("id", "")))
			return
