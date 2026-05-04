extends Node
## Drives an AnimationPlayer based on character movement and state.
## Attach to any character (player or NPC) that has an AnimationPlayer child.
## Falls back gracefully when no AnimationPlayer is present.

signal animation_changed(anim_name: String)

@export var damp_time := 0.1
@export var run_speed_threshold := 4.0

var _anim_player: AnimationPlayer = null
var _has_animator := false
var _current_speed := 0.0
var _is_grounded := true
var _is_talking := false
var _current_anim := ""

func _ready() -> void:
	_anim_player = _find_animation_player(get_parent())
	_has_animator = _anim_player != null
	if not _has_animator:
		push_warning("[Insimul] No AnimationPlayer found on %s — animations disabled" % get_parent().name)

func _find_animation_player(node: Node) -> AnimationPlayer:
	for child in node.get_children():
		if child is AnimationPlayer:
			return child
		var found := _find_animation_player(child)
		if found:
			return found
	return null

func has_animator() -> bool:
	return _has_animator

func set_speed(speed: float) -> void:
	_current_speed = speed
	if not _has_animator:
		return
	if _is_talking:
		return
	if speed < 0.1:
		_play("idle")
	elif speed < run_speed_threshold:
		_play("walk")
	else:
		_play("run")

func set_grounded(grounded: bool) -> void:
	_is_grounded = grounded
	if not _has_animator:
		return
	if not grounded:
		_play("fall")

func set_talking(talking: bool) -> void:
	_is_talking = talking
	if not _has_animator:
		return
	if talking:
		_play("talk")
	else:
		set_speed(_current_speed)

func trigger_attack() -> void:
	if not _has_animator:
		return
	_play("attack")

func trigger_interact() -> void:
	if not _has_animator:
		return
	_play("interact")

func trigger_die() -> void:
	if not _has_animator:
		return
	_play("die")

func play_clip(clip_name: String) -> void:
	if not _has_animator:
		return
	_play(clip_name)

func _play(anim_name: String) -> void:
	if anim_name == _current_anim:
		return
	if _anim_player.has_animation(anim_name):
		_anim_player.play(anim_name)
		_current_anim = anim_name
		animation_changed.emit(anim_name)
