extends Node3D
## Camera Manager — orbit and follow camera with SpringArm3D collision avoidance.
## Matches shared/game-engine/rendering/CameraManager.ts.

enum CameraMode { EXTERIOR, INTERIOR, DIALOGUE }

signal camera_mode_changed(mode: int)

@export var orbit_sensitivity := 0.003
@export var zoom_speed := 0.5
@export var min_spring_length := 2.0
@export var max_spring_length := 12.0
@export var exterior_spring_length := 8.0
@export var interior_spring_length := 3.5
@export var dialogue_spring_length := 4.0
@export var follow_smooth := 8.0
@export var rotation_smooth := 6.0

var current_mode: CameraMode = CameraMode.EXTERIOR
var _target: Node3D = null
var _spring_arm: SpringArm3D = null
var _camera: Camera3D = null
var _yaw := 0.0
var _pitch := -0.3
var _desired_spring_length: float = 8.0
var _dialogue_target: Node3D = null

func _ready() -> void:
	_build_rig()
	_find_player()

func _build_rig() -> void:
	_spring_arm = SpringArm3D.new()
	_spring_arm.spring_length = exterior_spring_length
	_spring_arm.collision_mask = 1
	_spring_arm.margin = 0.2
	add_child(_spring_arm)

	_camera = Camera3D.new()
	_camera.current = true
	_camera.fov = 65.0
	_spring_arm.add_child(_camera)

	_desired_spring_length = exterior_spring_length

func _find_player() -> void:
	await get_tree().process_frame
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		_target = players[0] as Node3D
		# Reparent existing camera pivot if player has one
		var existing_pivot = _target.get_node_or_null("CameraPivot")
		if existing_pivot:
			var existing_cam = existing_pivot.get_node_or_null("Camera3D")
			if existing_cam:
				existing_cam.current = false

func get_camera() -> Camera3D:
	return _camera

func get_camera_basis() -> Basis:
	return _spring_arm.global_transform.basis

func switch_mode(mode: CameraMode, target: Node3D = null) -> void:
	current_mode = mode
	match mode:
		CameraMode.EXTERIOR:
			_desired_spring_length = exterior_spring_length
			_dialogue_target = null
		CameraMode.INTERIOR:
			_desired_spring_length = interior_spring_length
			_dialogue_target = null
		CameraMode.DIALOGUE:
			_desired_spring_length = dialogue_spring_length
			_dialogue_target = target
	camera_mode_changed.emit(mode)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * orbit_sensitivity
		_pitch -= event.relative.y * orbit_sensitivity
		_pitch = clamp(_pitch, -1.2, 0.8)

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_desired_spring_length = max(min_spring_length, _desired_spring_length - zoom_speed)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_desired_spring_length = min(max_spring_length, _desired_spring_length + zoom_speed)

	# Gamepad right stick
	var right_x := Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
	var right_y := Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	if abs(right_x) > 0.1:
		_yaw -= right_x * orbit_sensitivity * 10.0
	if abs(right_y) > 0.1:
		_pitch -= right_y * orbit_sensitivity * 10.0
		_pitch = clamp(_pitch, -1.2, 0.8)

func _physics_process(delta: float) -> void:
	if _target == null:
		return

	# Smooth follow position
	var target_pos := _target.global_position + Vector3(0, 1.5, 0)
	global_position = global_position.lerp(target_pos, follow_smooth * delta)

	# Apply orbit rotation
	_spring_arm.rotation = Vector3(_pitch, _yaw, 0)

	# Smooth zoom
	_spring_arm.spring_length = lerp(_spring_arm.spring_length, _desired_spring_length, 5.0 * delta)

	# Dialogue mode: lerp to face NPC
	if current_mode == CameraMode.DIALOGUE and _dialogue_target:
		var dir_to_npc := (_dialogue_target.global_position - _target.global_position).normalized()
		var target_yaw := atan2(dir_to_npc.x, dir_to_npc.z)
		_yaw = lerp_angle(_yaw, target_yaw + PI, rotation_smooth * delta)
		_pitch = lerp(_pitch, -0.2, rotation_smooth * delta)
