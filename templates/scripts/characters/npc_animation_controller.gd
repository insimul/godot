extends Node
## NPC Animation Controller — AnimationTree state machine for NPC animations.
## Matches shared/game-engine/rendering/NPCAnimationController.ts and AnimationAssetManager.ts.

signal animation_state_changed(state: String)

enum AnimState { IDLE, WALK, RUN, TALK, SIT, WORK, EAT, SLEEP, INTERACT, COMBAT }

const STATE_NAMES := {
	AnimState.IDLE: "idle",
	AnimState.WALK: "walk",
	AnimState.RUN: "run",
	AnimState.TALK: "talk",
	AnimState.SIT: "sit",
	AnimState.WORK: "work",
	AnimState.EAT: "eat",
	AnimState.SLEEP: "sleep",
	AnimState.INTERACT: "interact",
	AnimState.COMBAT: "combat",
}

## Occupation-specific work animation overrides
const OCCUPATION_WORK_ANIMS := {
	"blacksmith": "work_hammering",
	"merchant": "work_gesturing",
	"guard": "work_patrolling",
	"innkeeper": "work_serving",
	"farmer": "work_farming",
	"baker": "work_kneading",
	"tailor": "work_sewing",
}

@export var crossfade_duration := 0.25
@export var idle_variation_interval := 8.0

var current_state: AnimState = AnimState.IDLE
var _occupation := ""
var _speed := 0.0
var _anim_tree: AnimationTree = null
var _anim_player: AnimationPlayer = null
var _idle_timer := 0.0

func _ready() -> void:
	_anim_tree = _find_child_of_type(get_parent(), "AnimationTree") as AnimationTree
	_anim_player = _find_child_of_type(get_parent(), "AnimationPlayer") as AnimationPlayer

func setup(occupation: String) -> void:
	_occupation = occupation

func set_speed(speed: float) -> void:
	_speed = speed
	if current_state == AnimState.TALK or current_state == AnimState.SIT:
		return
	if speed < 0.1:
		_transition_to(AnimState.IDLE)
	elif speed < 3.5:
		_transition_to(AnimState.WALK)
	else:
		_transition_to(AnimState.RUN)

	# Update blend space parameter for locomotion
	if _anim_tree:
		_anim_tree.set("parameters/locomotion/blend_position", speed)

func set_state(state: AnimState) -> void:
	_transition_to(state)

func set_talking(talking: bool) -> void:
	if talking:
		_transition_to(AnimState.TALK)
	else:
		set_speed(_speed)

func set_sitting(sitting: bool) -> void:
	if sitting:
		_transition_to(AnimState.SIT)
	else:
		_transition_to(AnimState.IDLE)

func set_working(working: bool) -> void:
	if working:
		_transition_to(AnimState.WORK)
	else:
		_transition_to(AnimState.IDLE)

func set_eating(eating: bool) -> void:
	if eating:
		_transition_to(AnimState.EAT)
	else:
		_transition_to(AnimState.IDLE)

func set_sleeping(sleeping: bool) -> void:
	if sleeping:
		_transition_to(AnimState.SLEEP)
	else:
		_transition_to(AnimState.IDLE)

func _transition_to(new_state: AnimState) -> void:
	if new_state == current_state:
		return

	var old_state := current_state
	current_state = new_state
	var anim_name := _resolve_animation_name(new_state)

	if _anim_tree:
		_anim_tree.set("parameters/state_machine/transition", anim_name)
	elif _anim_player:
		if _anim_player.has_animation(anim_name):
			_anim_player.play(anim_name, crossfade_duration)

	animation_state_changed.emit(STATE_NAMES.get(new_state, "idle"))

func _resolve_animation_name(state: AnimState) -> String:
	if state == AnimState.WORK and OCCUPATION_WORK_ANIMS.has(_occupation):
		return OCCUPATION_WORK_ANIMS[_occupation]
	return STATE_NAMES.get(state, "idle")

func _process(delta: float) -> void:
	if current_state == AnimState.IDLE:
		_idle_timer += delta
		if _idle_timer >= idle_variation_interval:
			_idle_timer = 0.0
			_play_idle_variation()

func _play_idle_variation() -> void:
	var variations := ["idle_look_around", "idle_scratch", "idle_shift_weight"]
	var pick: String = variations[randi() % variations.size()]
	if _anim_player and _anim_player.has_animation(pick):
		_anim_player.play(pick, crossfade_duration)

func _find_child_of_type(node: Node, type_name: String) -> Node:
	for child in node.get_children():
		if child.get_class() == type_name:
			return child
		var found := _find_child_of_type(child, type_name)
		if found:
			return found
	return null
