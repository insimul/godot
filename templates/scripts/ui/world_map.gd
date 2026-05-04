extends CanvasLayer
## Full-screen world map — toggled with M key.
## Shows settlements, roads, water, quest markers, and player position.
## Supports pan (click-drag) and zoom (scroll wheel).

const MAP_BG_COLOR := Color(0.12, 0.15, 0.1, 0.95)
const GROUND_COLOR := Color({{GROUND_COLOR_R}}, {{GROUND_COLOR_G}}, {{GROUND_COLOR_B}})
const ROAD_COLOR := Color({{ROAD_COLOR_R}}, {{ROAD_COLOR_G}}, {{ROAD_COLOR_B}})
const WATER_COLOR := Color(0.2, 0.5, 0.8, 0.8)
const SETTLEMENT_COLOR := Color(0.9, 0.8, 0.6)
const PLAYER_COLOR := Color(0.2, 0.9, 0.3)
const QUEST_AVAILABLE_COLOR := Color(1.0, 0.85, 0.0)
const QUEST_TURNIN_COLOR := Color(0.3, 0.8, 1.0)
const LABEL_COLOR := Color(1.0, 1.0, 1.0, 0.9)
const ROAD_WIDTH_PX := 2.0
const SETTLEMENT_RADIUS_MIN := 6.0
const PLAYER_MARKER_SIZE := 8.0
const QUEST_MARKER_SIZE := 10.0
const ZOOM_MIN := 0.5
const ZOOM_MAX := 4.0
const ZOOM_STEP := 0.15
const PAN_SMOOTH := 8.0
const ZOOM_SMOOTH := 8.0

var _is_open := false
var _player: CharacterBody3D

# Map data
var _terrain_size := {{TERRAIN_SIZE}}
var _settlements: Array = []
var _roads: Array = []
var _water_features: Array = []
var _quests: Array = []

# Camera state
var _cam_offset := Vector2.ZERO
var _target_offset := Vector2.ZERO
var _zoom := 1.0
var _target_zoom := 1.0
var _is_dragging := false
var _drag_start := Vector2.ZERO
var _offset_at_drag_start := Vector2.ZERO

# Pulse animation for player marker
var _pulse_time := 0.0

# UI nodes
var _map_panel: Control
var _map_canvas: Control
var _title_label: Label
var _close_hint: Label

func _ready() -> void:
	layer = 10
	_build_ui()
	_load_map_data()
	visible = false
	await get_tree().process_frame
	_player = get_tree().get_first_node_in_group("player") as CharacterBody3D

func _build_ui() -> void:
	_map_panel = Control.new()
	_map_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_map_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_map_panel)

	_map_canvas = Control.new()
	_map_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_map_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_map_canvas.connect("draw", _on_canvas_draw)
	_map_panel.add_child(_map_canvas)

	_title_label = Label.new()
	_title_label.text = "World Map"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_title_label.offset_top = 16
	_title_label.offset_bottom = 48
	_title_label.add_theme_font_size_override("font_size", 24)
	_map_panel.add_child(_title_label)

	_close_hint = Label.new()
	_close_hint.text = "Press M to close  |  Scroll to zoom  |  Drag to pan"
	_close_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_close_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_close_hint.offset_top = -40
	_close_hint.add_theme_font_size_override("font_size", 14)
	_close_hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	_map_panel.add_child(_close_hint)

func _load_map_data() -> void:
	if not Engine.has_singleton("DataLoader"):
		var dl = get_node_or_null("/root/DataLoader")
		if dl == null:
			return
		_settlements = dl.load_settlements()
		_quests = dl.load_quests()
		_load_roads_and_water(dl)
		return
	var dl = Engine.get_singleton("DataLoader")
	_settlements = dl.load_settlements()
	_quests = dl.load_quests()
	_load_roads_and_water(dl)

func _load_roads_and_water(dl: Node) -> void:
	# Roads and water come from scene_descriptor or world IR
	var world_data: Dictionary = dl.load_world_data()
	var entities: Dictionary = world_data.get("entities", {})
	_roads = entities.get("roads", [])
	var geo: Dictionary = world_data.get("geography", {})
	_water_features = geo.get("waterFeatures", [])
	if _water_features.is_empty():
		_water_features = geo.get("water_features", [])

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_M:
		_toggle_map()
		get_viewport().set_input_as_handled()
		return
	if not _is_open:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_target_zoom = clampf(_target_zoom + ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_target_zoom = clampf(_target_zoom - ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_is_dragging = true
				_drag_start = mb.position
				_offset_at_drag_start = _target_offset
			else:
				_is_dragging = false
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _is_dragging:
		var mm := event as InputEventMouseMotion
		var delta: Vector2 = mm.position - _drag_start
		_target_offset = _offset_at_drag_start + delta / _zoom
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if not _is_open:
		return
	_pulse_time += delta
	_cam_offset = _cam_offset.lerp(_target_offset, clampf(PAN_SMOOTH * delta, 0.0, 1.0))
	_zoom = lerpf(_zoom, _target_zoom, clampf(ZOOM_SMOOTH * delta, 0.0, 1.0))
	_map_canvas.queue_redraw()

func _toggle_map() -> void:
	_is_open = not _is_open
	visible = _is_open
	get_tree().paused = _is_open
	if _is_open:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		# Center on player
		if _player:
			var pw := Vector2(_player.global_position.x, _player.global_position.z)
			var screen_center := get_viewport().get_visible_rect().size * 0.5
			var map_center := Vector2(_terrain_size * 0.5, _terrain_size * 0.5)
			_target_offset = (map_center - pw)
			_cam_offset = _target_offset
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

## Convert world XZ position to screen position.
func _world_to_screen(world_x: float, world_z: float) -> Vector2:
	var screen_size := get_viewport().get_visible_rect().size
	var center := screen_size * 0.5
	var half_terrain := _terrain_size * 0.5
	var nx := (world_x - half_terrain) / half_terrain
	var nz := (world_z - half_terrain) / half_terrain
	var scale_factor := minf(screen_size.x, screen_size.y) * 0.4 * _zoom
	return center + (Vector2(nx, nz) + _cam_offset / half_terrain) * scale_factor

func _on_canvas_draw() -> void:
	var canvas := _map_canvas
	var screen_size := get_viewport().get_visible_rect().size

	# Background
	canvas.draw_rect(Rect2(Vector2.ZERO, screen_size), MAP_BG_COLOR)

	# Terrain outline
	var tl := _world_to_screen(0, 0)
	var br := _world_to_screen(_terrain_size, _terrain_size)
	var terrain_rect := Rect2(tl, br - tl)
	canvas.draw_rect(terrain_rect, GROUND_COLOR * Color(1, 1, 1, 0.3))
	canvas.draw_rect(terrain_rect, GROUND_COLOR * Color(1, 1, 1, 0.5), false, 1.0)

	# Water features
	_draw_water(canvas)

	# Roads
	_draw_roads(canvas)

	# Settlements
	_draw_settlements(canvas)

	# Quest markers
	_draw_quest_markers(canvas)

	# Player
	_draw_player(canvas)

func _draw_water(canvas: Control) -> void:
	for wf in _water_features:
		var pos: Dictionary = wf.get("position", {})
		var bounds: Dictionary = wf.get("bounds", {})
		if bounds.is_empty():
			continue
		var tl := _world_to_screen(bounds.get("minX", 0), bounds.get("minZ", 0))
		var br := _world_to_screen(bounds.get("maxX", 0), bounds.get("maxZ", 0))
		canvas.draw_rect(Rect2(tl, br - tl), WATER_COLOR)

func _draw_roads(canvas: Control) -> void:
	for road in _roads:
		var wps: Array = road.get("waypoints", [])
		if wps.size() < 2:
			continue
		for i in range(wps.size() - 1):
			var a: Dictionary = wps[i]
			var b: Dictionary = wps[i + 1]
			var pa := _world_to_screen(a.get("x", 0), a.get("z", 0))
			var pb := _world_to_screen(b.get("x", 0), b.get("z", 0))
			canvas.draw_line(pa, pb, ROAD_COLOR, ROAD_WIDTH_PX)

func _draw_settlements(canvas: Control) -> void:
	var font := ThemeDB.fallback_font
	var font_size := 13
	for s in _settlements:
		var pos: Dictionary = s.get("position", {})
		var center := _world_to_screen(pos.get("x", 0), pos.get("z", 0))
		var r: float = maxf(SETTLEMENT_RADIUS_MIN, s.get("radius", 10) * _zoom * 0.15)

		# Settlement circle
		canvas.draw_circle(center, r, SETTLEMENT_COLOR * Color(1, 1, 1, 0.4))
		canvas.draw_arc(center, r, 0, TAU, 32, SETTLEMENT_COLOR, 1.5)

		# House icon (simple triangle roof + rectangle)
		var icon_size := r * 0.6
		var house_top := center + Vector2(0, -r - icon_size * 2)
		var house_bl := house_top + Vector2(-icon_size, icon_size)
		var house_br := house_top + Vector2(icon_size, icon_size)
		canvas.draw_polygon([house_top, house_bl, house_br], [SETTLEMENT_COLOR])
		var base_tl := house_bl
		var base_br := house_br + Vector2(0, icon_size * 0.8)
		canvas.draw_rect(Rect2(base_tl, base_br - base_tl), SETTLEMENT_COLOR)

		# Name label
		var name_str: String = s.get("name", "")
		var pop: int = s.get("population", 0)
		var label_text := "%s (%d)" % [name_str, pop] if pop > 0 else name_str
		var text_size := font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		var text_pos := center + Vector2(-text_size.x * 0.5, r + font_size + 4)
		canvas.draw_string(font, text_pos, label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, LABEL_COLOR)

func _draw_quest_markers(canvas: Control) -> void:
	var font := ThemeDB.fallback_font
	for q in _quests:
		var pos: Dictionary = q.get("locationPosition", {})
		if pos.is_empty():
			continue
		var center := _world_to_screen(pos.get("x", 0), pos.get("z", 0))
		var status: String = q.get("status", "available")
		var is_turnin := status == "ready_to_turn_in"
		var color := QUEST_TURNIN_COLOR if is_turnin else QUEST_AVAILABLE_COLOR
		var symbol := "?" if is_turnin else "!"

		# Diamond background
		var s := QUEST_MARKER_SIZE
		var points: PackedVector2Array = [
			center + Vector2(0, -s),
			center + Vector2(s * 0.7, 0),
			center + Vector2(0, s),
			center + Vector2(-s * 0.7, 0),
		]
		canvas.draw_polygon(points, [color * Color(1, 1, 1, 0.8)])

		# Symbol
		var text_size := font.get_string_size(symbol, HORIZONTAL_ALIGNMENT_CENTER, -1, 14)
		canvas.draw_string(font, center + Vector2(-text_size.x * 0.5, 5), symbol, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.BLACK)

func _draw_player(canvas: Control) -> void:
	if _player == null:
		return
	var px := _player.global_position.x
	var pz := _player.global_position.z
	var center := _world_to_screen(px, pz)

	# Pulsing glow
	var pulse := 0.5 + 0.5 * sin(_pulse_time * 3.0)
	var glow_radius := PLAYER_MARKER_SIZE * (1.2 + pulse * 0.5)
	canvas.draw_circle(center, glow_radius, PLAYER_COLOR * Color(1, 1, 1, 0.2 + pulse * 0.15))

	# Arrow pointing in facing direction
	var facing := -_player.global_transform.basis.z
	var angle := atan2(facing.x, facing.z)
	var s := PLAYER_MARKER_SIZE
	var forward := Vector2(sin(angle), cos(angle))
	var right := Vector2(forward.y, -forward.x)
	var tip := center + forward * s
	var bl := center - forward * s * 0.6 - right * s * 0.5
	var br := center - forward * s * 0.6 + right * s * 0.5
	canvas.draw_polygon([tip, bl, br], [PLAYER_COLOR])
