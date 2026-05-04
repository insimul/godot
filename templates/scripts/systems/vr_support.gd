extends Node3D
## VR Support Scaffolding — XR rig with hand tracking and VR UI.
## Matches VRManager.ts, VRHandTrackingManager.ts, VRInteractionManager.ts, etc.

signal vr_entered
signal vr_exited
signal teleport_requested(position: Vector3)

@export var snap_turn_angle := 45.0
@export var vignette_enabled := true
@export var seated_mode := false

var _xr_interface: XRInterface = null
var _xr_origin: XROrigin3D = null
var _xr_camera: XRCamera3D = null
var _left_controller: XRController3D = null
var _right_controller: XRController3D = null
var _teleport_ray: RayCast3D = null
var _is_vr_active := false

func _ready() -> void:
	_xr_interface = XRServer.find_interface("OpenXR")
	if _xr_interface == null:
		print("[VR] OpenXR interface not available")
		return
	_setup_xr_rig()

func _setup_xr_rig() -> void:
	_xr_origin = XROrigin3D.new()
	_xr_origin.name = "XROrigin"
	add_child(_xr_origin)

	_xr_camera = XRCamera3D.new()
	_xr_camera.name = "XRCamera"
	_xr_origin.add_child(_xr_camera)

	# Left controller
	_left_controller = XRController3D.new()
	_left_controller.name = "LeftController"
	_left_controller.tracker = &"left_hand"
	_xr_origin.add_child(_left_controller)

	# Right controller
	_right_controller = XRController3D.new()
	_right_controller.name = "RightController"
	_right_controller.tracker = &"right_hand"
	_xr_origin.add_child(_right_controller)

	# Teleport ray on right controller
	_teleport_ray = RayCast3D.new()
	_teleport_ray.target_position = Vector3(0, -1, -10)
	_teleport_ray.collision_mask = 1
	_right_controller.add_child(_teleport_ray)

	# Teleport visual arc
	var arc := MeshInstance3D.new()
	var arc_mesh := CylinderMesh.new()
	arc_mesh.top_radius = 0.005
	arc_mesh.bottom_radius = 0.005
	arc_mesh.height = 5.0
	arc.mesh = arc_mesh
	arc.rotation.x = -PI / 4
	arc.position.z = -2.5
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.5, 1.0, 0.5)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	arc.material_override = mat
	_teleport_ray.add_child(arc)

	# Button signals
	_right_controller.button_pressed.connect(_on_right_button)
	_left_controller.button_pressed.connect(_on_left_button)

func enter_vr() -> void:
	if _xr_interface == null:
		push_error("[VR] No XR interface available")
		return
	if not _xr_interface.is_initialized():
		if not _xr_interface.initialize():
			push_error("[VR] Failed to initialize OpenXR")
			return
	get_viewport().use_xr = true
	_is_vr_active = true
	_xr_camera.current = true
	vr_entered.emit()

func exit_vr() -> void:
	get_viewport().use_xr = false
	_is_vr_active = false
	vr_exited.emit()

func is_vr_active() -> bool:
	return _is_vr_active

func _on_right_button(button: String) -> void:
	match button:
		"trigger_click":
			_attempt_teleport()
		"primary_click":
			# Snap turn right
			_xr_origin.rotate_y(deg_to_rad(-snap_turn_angle))

func _on_left_button(button: String) -> void:
	match button:
		"primary_click":
			# Snap turn left
			_xr_origin.rotate_y(deg_to_rad(snap_turn_angle))

func _attempt_teleport() -> void:
	if _teleport_ray and _teleport_ray.is_colliding():
		var point := _teleport_ray.get_collision_point()
		_xr_origin.global_position = point
		teleport_requested.emit(point)

func create_vr_ui_panel(content: Control) -> MeshInstance3D:
	## Render a Control node onto a world-space panel via SubViewport.
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1024, 768)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.add_child(content)
	add_child(viewport)

	var panel_mesh := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 0.75)
	panel_mesh.mesh = quad

	var mat := StandardMaterial3D.new()
	mat.albedo_texture = viewport.get_texture()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	panel_mesh.material_override = mat

	return panel_mesh
