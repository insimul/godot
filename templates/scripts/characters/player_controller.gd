extends CharacterBody3D
## Third-person player controller.
## Attach to a CharacterBody3D with a CollisionShape3D child.

@export var move_speed := {{PLAYER_SPEED}}
@export var jump_height := {{PLAYER_JUMP_HEIGHT}}
@export var gravity_mult := {{PLAYER_GRAVITY}}
@export var rotation_speed := 10.0

@export var initial_health := {{PLAYER_INITIAL_HEALTH}}
@export var initial_energy := {{PLAYER_INITIAL_ENERGY}}
@export var initial_gold := {{PLAYER_INITIAL_GOLD}}

var health: float
var max_health: float
var energy: float
var gold: int

var _anim_controller: Node = null

@onready var camera_pivot: Node3D = $CameraPivot if has_node("CameraPivot") else null

func _ready() -> void:
	health = initial_health
	max_health = initial_health
	energy = initial_energy
	gold = initial_gold
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_anim_controller = _find_anim_controller()

func _find_anim_controller() -> Node:
	for child in get_children():
		if child.has_method("set_speed"):
			return child
	return null

func _physics_process(delta: float) -> void:
	# Gravity
	var was_on_floor := is_on_floor()
	if not is_on_floor():
		velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * gravity_mult * delta

	# Jump
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = sqrt(jump_height * 2.0 * ProjectSettings.get_setting("physics/3d/default_gravity") * gravity_mult)

	# Movement
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var cam_basis := camera_pivot.global_transform.basis if camera_pivot else global_transform.basis
	var direction := (cam_basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	direction.y = 0

	if direction.length() > 0.1:
		velocity.x = direction.x * move_speed
		velocity.z = direction.z * move_speed
		var target_rot := atan2(direction.x, direction.z)
		rotation.y = lerp_angle(rotation.y, target_rot, rotation_speed * delta)
	else:
		velocity.x = move_toward(velocity.x, 0, move_speed * delta * 5.0)
		velocity.z = move_toward(velocity.z, 0, move_speed * delta * 5.0)

	move_and_slide()

	# Animation
	if _anim_controller:
		var horizontal_speed := Vector2(velocity.x, velocity.z).length()
		_anim_controller.set_speed(horizontal_speed)
		_anim_controller.set_grounded(is_on_floor())

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("attack"):
		_on_attack()
	elif event.is_action_pressed("interact"):
		_on_interact()
	elif event.is_action_pressed("menu"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED)

func _on_attack() -> void:
	if _anim_controller:
		_anim_controller.trigger_attack()
	print("[Insimul] Player Attack")

func _on_interact() -> void:
	if _anim_controller:
		_anim_controller.trigger_interact()
	print("[Insimul] Player Interact")
