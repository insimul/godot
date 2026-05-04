extends Control
## Minimap — top-right overhead camera view with POI markers.
##
## Uses a SubViewport + Camera3D for a top-down render of the world.
## Tracks the player position and displays points of interest (quest markers,
## NPCs, buildings, settlements, discoveries) as colored dots overlaid on the viewport.
## Supports all 8 marker types, legend panel, fullscreen toggle,
## collapse/expand, right-click teleport with confirmation, pulsing exclamation
## markers, diamond/circle shape variants, and smart capture scheduling.

const MINIMAP_SIZE := 200
const MINIMAP_MARGIN := 8
const HEADER_HEIGHT := 20
const CAMERA_HEIGHT := 200.0
const POI_RADIUS := 3.0
const CAPTURE_THRESHOLD := 5.0   # world units before re-render
const CAPTURE_INTERVAL := 0.5    # seconds between captures
const PULSE_SPEED := 1.5

## Marker types matching Babylon source of truth
enum MarkerType {
	PLAYER,
	NPC,
	SETTLEMENT,
	BUILDING,
	WATER_FEATURES,
	QUEST,
	QUEST_OBJECTIVE,
	EXCLAMATION,
	DISCOVERY,
}

## Shape hint for quest_objective markers
enum MarkerShape {
	CIRCLE,
	DIAMOND,
}

signal teleport_requested(world_x: float, world_z: float)
signal fullscreen_toggled

var _player: CharacterBody3D
var _camera: Camera3D
var _viewport: SubViewport
var _viewport_container: SubViewportContainer
var _border: Panel
var _map_area: Control
var _header: Control
var _player_marker: ColorRect
var _legend_panel: Panel
var _toggle_label: Label
var _teleport_dialog: Panel

var _poi_markers: Dictionary = {}  # id -> { node: Control, world_pos: Vector3, type: int, pulse: bool, label_node: Label }
var _visible := true
var _expanded := true
var _legend_visible := false
var _is_fullscreen := false
var _normal_position := Vector2.ZERO
var _normal_size := Vector2.ZERO

# Smart capture scheduling
var _last_capture_pos := Vector3(INF, 0, INF)
var _last_capture_time := 0.0
var _terrain_size := 1024.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()
	await get_tree().process_frame
	_player = get_tree().get_first_node_in_group("player") as CharacterBody3D

func _build_ui() -> void:
	var screen_size := get_viewport().get_visible_rect().size
	var container_w := MINIMAP_SIZE + 14

	# Border panel (main container)
	_border = Panel.new()
	_border.custom_minimum_size = Vector2(container_w, MINIMAP_SIZE + HEADER_HEIGHT)
	_border.size = Vector2(container_w, MINIMAP_SIZE + HEADER_HEIGHT)
	_border.position = Vector2(
		screen_size.x - container_w - MINIMAP_MARGIN,
		MINIMAP_MARGIN
	)
	_border.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_border)

	# ── Header ──
	_header = Control.new()
	_header.size = Vector2(container_w, HEADER_HEIGHT)
	_header.position = Vector2.ZERO
	_header.mouse_filter = Control.MOUSE_FILTER_STOP
	_border.add_child(_header)

	# Toggle button (left)
	var toggle_btn := Button.new()
	toggle_btn.size = Vector2(20, 16)
	toggle_btn.position = Vector2(2, 2)
	toggle_btn.flat = true
	_border.add_child(toggle_btn)

	_toggle_label = Label.new()
	_toggle_label.text = "▼"
	_toggle_label.add_theme_font_size_override("font_size", 9)
	_toggle_label.position = Vector2(4, 0)
	toggle_btn.add_child(_toggle_label)
	toggle_btn.pressed.connect(_toggle_collapse)

	# Title
	var title := Label.new()
	title.text = "Map"
	title.add_theme_font_size_override("font_size", 10)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size = Vector2(container_w, HEADER_HEIGHT)
	title.position = Vector2.ZERO
	_header.add_child(title)

	# Legend button ("?")
	var legend_btn := Button.new()
	legend_btn.text = "?"
	legend_btn.size = Vector2(16, 14)
	legend_btn.position = Vector2(container_w - 38, 3)
	legend_btn.flat = true
	legend_btn.pressed.connect(_toggle_legend)
	_header.add_child(legend_btn)

	# Fullscreen button
	var fs_btn := Button.new()
	fs_btn.text = "⛶"
	fs_btn.size = Vector2(16, 14)
	fs_btn.position = Vector2(container_w - 18, 3)
	fs_btn.flat = true
	fs_btn.pressed.connect(func(): fullscreen_toggled.emit())
	_header.add_child(fs_btn)

	# Header click -> collapse
	_header.gui_input.connect(_on_header_input)

	# ── Map area ──
	_map_area = Control.new()
	_map_area.size = Vector2(MINIMAP_SIZE, MINIMAP_SIZE)
	_map_area.position = Vector2(7, HEADER_HEIGHT)
	_map_area.mouse_filter = Control.MOUSE_FILTER_STOP
	_map_area.gui_input.connect(_on_map_input)
	_border.add_child(_map_area)

	# SubViewportContainer
	_viewport_container = SubViewportContainer.new()
	_viewport_container.size = Vector2(MINIMAP_SIZE, MINIMAP_SIZE)
	_viewport_container.position = Vector2.ZERO
	_viewport_container.stretch = true
	_viewport_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_area.add_child(_viewport_container)

	# SubViewport with smart capture (not UPDATE_ALWAYS)
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(512, 512)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_viewport.transparent_bg = false
	_viewport_container.add_child(_viewport)

	# Top-down camera
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = _terrain_size / 2.0
	_camera.rotation_degrees = Vector3(-90, 0, 0)
	_camera.position = Vector3(0, CAMERA_HEIGHT, 0)
	_viewport.add_child(_camera)

	# Player marker (centered cyan dot)
	_player_marker = ColorRect.new()
	_player_marker.color = _get_default_color(MarkerType.PLAYER)
	_player_marker.size = Vector2(6, 6)
	_player_marker.position = Vector2(MINIMAP_SIZE / 2.0 - 3, MINIMAP_SIZE / 2.0 - 3)
	_player_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_area.add_child(_player_marker)

	# ── Legend panel ──
	_build_legend()

func _build_legend() -> void:
	var items := [
		{ "label": "You",        "color": _get_default_color(MarkerType.PLAYER) },
		{ "label": "NPC",        "color": _get_default_color(MarkerType.NPC) },
		{ "label": "Settlement", "color": _get_default_color(MarkerType.SETTLEMENT) },
		{ "label": "Quest",      "color": _get_default_color(MarkerType.QUEST) },
		{ "label": "Building",   "color": _get_default_color(MarkerType.BUILDING) },
	]

	var row_h := 14
	var legend_h := items.size() * row_h + 8
	var legend_w := MINIMAP_SIZE + 14
	var screen_size := get_viewport().get_visible_rect().size

	_legend_panel = Panel.new()
	_legend_panel.size = Vector2(legend_w, legend_h)
	_legend_panel.position = Vector2(
		screen_size.x - legend_w - MINIMAP_MARGIN,
		MINIMAP_MARGIN + MINIMAP_SIZE + HEADER_HEIGHT + 2
	)
	_legend_panel.visible = false
	_legend_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_legend_panel)

	for i in range(items.size()):
		var item: Dictionary = items[i]

		var dot := ColorRect.new()
		dot.color = item["color"]
		dot.size = Vector2(6, 6)
		dot.position = Vector2(4, 4 + i * row_h + 4)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_legend_panel.add_child(dot)

		var lbl := Label.new()
		lbl.text = item["label"]
		lbl.add_theme_font_size_override("font_size", 8)
		lbl.position = Vector2(14, 4 + i * row_h)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_legend_panel.add_child(lbl)

func _process(delta: float) -> void:
	if _player == null or _camera == null:
		return

	# Update POI marker screen positions
	_update_poi_positions()

	# Smart capture: re-render only when player moves enough
	var ppos := _player.global_position
	var dx := ppos.x - _last_capture_pos.x
	var dz := ppos.z - _last_capture_pos.z
	var dist_sq := dx * dx + dz * dz
	var now := Time.get_ticks_msec() / 1000.0

	if dist_sq > CAPTURE_THRESHOLD * CAPTURE_THRESHOLD and now - _last_capture_time > CAPTURE_INTERVAL:
		_camera.global_position = Vector3(ppos.x, CAMERA_HEIGHT, ppos.z)
		_last_capture_pos = ppos
		_last_capture_time = now
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

	# Pulse exclamation markers
	for id in _poi_markers:
		var entry: Dictionary = _poi_markers[id]
		if entry.get("pulse", false):
			var node: Control = entry["node"]
			var alpha := 0.7 + 0.3 * sin(now * PULSE_SPEED * PI)
			node.modulate.a = alpha

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_M:
		set_minimap_visible(not _visible)

# ── Marker management ──

func add_poi(id: String, world_pos: Vector3, type: int, label: String = "", shape: int = MarkerShape.CIRCLE, custom_color: Color = Color(-1, -1, -1)) -> void:
	if _poi_markers.has(id):
		remove_poi(id)

	var color: Color
	if custom_color.r >= 0:
		color = custom_color
	else:
		color = _get_default_color(type)

	var marker_size := _get_marker_size(type)
	var is_pulse := type == MarkerType.EXCLAMATION

	var node: Control

	if type == MarkerType.EXCLAMATION:
		# Exclamation: rounded rect with "!" text
		var rect := ColorRect.new()
		rect.size = Vector2(12, 12)
		rect.color = color
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var lbl := Label.new()
		lbl.text = "!"
		lbl.add_theme_font_size_override("font_size", 9)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.size = Vector2(12, 12)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rect.add_child(lbl)
		node = rect

	elif type == MarkerType.QUEST_OBJECTIVE and shape == MarkerShape.DIAMOND:
		# Diamond: rotated square
		var rect := ColorRect.new()
		rect.size = Vector2(6, 6)
		rect.color = color
		rect.rotation = PI / 4.0
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		node = rect

	else:
		# Default: colored rectangle (circle approximation)
		var rect := ColorRect.new()
		rect.size = Vector2(marker_size * 2, marker_size * 2)
		rect.color = color
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		node = rect

	_map_area.add_child(node)

	# Add label below marker if provided
	var label_node: Label = null
	if label != "":
		label_node = Label.new()
		label_node.text = label
		label_node.add_theme_font_size_override("font_size", 7)
		label_node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label_node.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
		label_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_map_area.add_child(label_node)

	_poi_markers[id] = { "node": node, "world_pos": world_pos, "type": type, "pulse": is_pulse, "label_node": label_node }

func remove_poi(id: String) -> void:
	if not _poi_markers.has(id):
		return
	var entry: Dictionary = _poi_markers[id]
	var node: Control = entry["node"]
	node.queue_free()
	var label_node = entry.get("label_node", null)
	if label_node != null:
		label_node.queue_free()
	_poi_markers.erase(id)

func clear_markers() -> void:
	for id in _poi_markers.keys():
		remove_poi(id)

func set_minimap_visible(show: bool) -> void:
	_visible = show
	_border.visible = show
	if not show:
		_legend_visible = false
		_legend_panel.visible = false

# ── Fullscreen toggle ──

## Toggle between normal minimap and fullscreen map view.
## In fullscreen, the minimap border fills the screen center area.
func toggle_fullscreen() -> void:
	_is_fullscreen = not _is_fullscreen
	var screen_size := get_viewport().get_visible_rect().size

	if _is_fullscreen:
		_normal_position = _border.position
		_normal_size = _border.size
		var margin := 40.0
		_border.position = Vector2(margin, margin)
		_border.size = Vector2(screen_size.x - margin * 2, screen_size.y - margin * 2)
		_map_area.size = _border.size - Vector2(14, HEADER_HEIGHT)
		_viewport_container.size = _map_area.size
	else:
		_border.position = _normal_position
		_border.size = _normal_size
		_map_area.size = Vector2(MINIMAP_SIZE, MINIMAP_SIZE)
		_viewport_container.size = Vector2(MINIMAP_SIZE, MINIMAP_SIZE)

	fullscreen_toggled.emit()

# ── Collapse / expand ──

func _toggle_collapse() -> void:
	_expanded = not _expanded
	if _expanded:
		_border.size.y = MINIMAP_SIZE + HEADER_HEIGHT
		_map_area.visible = true
		_toggle_label.text = "▼"
	else:
		_border.size.y = HEADER_HEIGHT
		_map_area.visible = false
		_toggle_label.text = "▲"
		_legend_visible = false
		_legend_panel.visible = false

func _on_header_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_toggle_collapse()

# ── Legend ──

func _toggle_legend() -> void:
	_legend_visible = not _legend_visible
	_legend_panel.visible = _legend_visible

# ── Teleport (right-click) ──

func _on_map_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT):
		return

	var local_pos: Vector2 = event.position - _map_area.global_position
	var half_map := MINIMAP_SIZE / 2.0
	var centered := local_pos - Vector2(half_map, half_map)

	if absf(centered.x) > half_map or absf(centered.y) > half_map:
		return

	var half_world := _terrain_size / 2.0
	var cam_size: float = _camera.size
	var world_x := (centered.x / half_map) * cam_size
	var world_z := (centered.y / half_map) * cam_size

	_show_teleport_dialog(world_x, world_z)

func _show_teleport_dialog(world_x: float, world_z: float) -> void:
	_dismiss_teleport_dialog()

	_teleport_dialog = Panel.new()
	_teleport_dialog.size = Vector2(220, 90)
	var screen_center := get_viewport().get_visible_rect().size / 2.0
	_teleport_dialog.position = screen_center - _teleport_dialog.size / 2.0
	_teleport_dialog.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_teleport_dialog)

	var question := Label.new()
	question.text = "Teleport here?"
	question.add_theme_font_size_override("font_size", 14)
	question.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	question.size = Vector2(220, 40)
	question.position = Vector2(0, 8)
	_teleport_dialog.add_child(question)

	var yes_btn := Button.new()
	yes_btn.text = "Yes"
	yes_btn.size = Vector2(70, 28)
	yes_btn.position = Vector2(30, 52)
	yes_btn.pressed.connect(func():
		teleport_requested.emit(world_x, world_z)
		_dismiss_teleport_dialog()
	)
	_teleport_dialog.add_child(yes_btn)

	var no_btn := Button.new()
	no_btn.text = "No"
	no_btn.size = Vector2(70, 28)
	no_btn.position = Vector2(120, 52)
	no_btn.pressed.connect(_dismiss_teleport_dialog)
	_teleport_dialog.add_child(no_btn)

func _dismiss_teleport_dialog() -> void:
	if _teleport_dialog != null:
		_teleport_dialog.queue_free()
		_teleport_dialog = null

# ── Position updates ──

func _update_poi_positions() -> void:
	if _player == null:
		return
	var half := MINIMAP_SIZE / 2.0
	var cam_size: float = _camera.size
	for id in _poi_markers:
		var entry: Dictionary = _poi_markers[id]
		var node: Control = entry["node"]
		var world_pos: Vector3 = entry["world_pos"]
		var dx: float = world_pos.x - _player.global_position.x
		var dz: float = world_pos.z - _player.global_position.z
		var node_half := node.size / 2.0
		var px: float = half + (dx / cam_size) * MINIMAP_SIZE - node_half.x
		var pz: float = half + (dz / cam_size) * MINIMAP_SIZE - node_half.y
		# Clamp to minimap bounds
		px = clampf(px, 0, MINIMAP_SIZE - node.size.x)
		pz = clampf(pz, 0, MINIMAP_SIZE - node.size.y)
		node.position = Vector2(px, pz)

		# Update label position (offset below marker)
		var label_node = entry.get("label_node", null)
		if label_node != null:
			label_node.position = Vector2(px - 20, pz + node.size.y + 1)

# ── Helpers ──

func _get_marker_size(type: int) -> float:
	match type:
		MarkerType.PLAYER: return 3.0
		MarkerType.SETTLEMENT: return 4.0
		MarkerType.QUEST: return 3.5
		MarkerType.QUEST_OBJECTIVE: return 2.5
		MarkerType.DISCOVERY: return 3.0
		MarkerType.BUILDING: return 1.5
		MarkerType.NPC: return 2.0
		MarkerType.WATER_FEATURES: return 2.0
		MarkerType.EXCLAMATION: return 6.0
		_: return 2.0

func _get_default_color(type: int) -> Color:
	match type:
		MarkerType.PLAYER: return Color(0.0, 1.0, 1.0)       # cyan
		MarkerType.NPC: return Color(1.0, 1.0, 0.0)           # yellow
		MarkerType.SETTLEMENT: return Color(1.0, 0.65, 0.0)   # orange
		MarkerType.QUEST: return Color(1.0, 0.0, 1.0)         # magenta
		MarkerType.BUILDING: return Color(0.5, 0.5, 0.5)      # gray
		MarkerType.WATER_FEATURES: return Color(0.2, 0.4, 0.8)
		MarkerType.QUEST_OBJECTIVE: return Color(0.0, 0.74, 0.83)  # #00BCD4
		MarkerType.EXCLAMATION: return Color(1.0, 0.8, 0.0)        # #ffcc00
		MarkerType.DISCOVERY: return Color(0.506, 0.78, 0.518)     # #81C784
		_: return Color(1.0, 1.0, 1.0)
