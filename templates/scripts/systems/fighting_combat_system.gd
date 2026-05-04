extends Node
## Fighting Combat System — frame-based combo combat with special meter.
## Used when combat_style is "fighting".

signal combo_hit(combo_count: int, total_damage: float)
signal combo_ended(total_hits: int, total_damage: float)
signal special_meter_changed(value: float)
signal fighter_state_changed(fighter_id: String, state: String)

## Attack frame data
const ATTACKS := {
	"light_punch": {"damage": 8, "startup": 3, "active": 3, "recovery": 8, "hitstun": 12, "blockstun": 6, "knockback": 1.0, "meter_gain": 5, "meter_cost": 0},
	"light_kick": {"damage": 10, "startup": 4, "active": 3, "recovery": 10, "hitstun": 14, "blockstun": 7, "knockback": 1.5, "meter_gain": 5, "meter_cost": 0},
	"medium_punch": {"damage": 18, "startup": 6, "active": 4, "recovery": 14, "hitstun": 18, "blockstun": 10, "knockback": 2.0, "meter_gain": 8, "meter_cost": 0},
	"medium_kick": {"damage": 20, "startup": 7, "active": 4, "recovery": 16, "hitstun": 20, "blockstun": 10, "knockback": 2.5, "meter_gain": 8, "meter_cost": 0},
	"heavy_punch": {"damage": 30, "startup": 10, "active": 5, "recovery": 20, "hitstun": 24, "blockstun": 14, "knockback": 4.0, "meter_gain": 12, "meter_cost": 0},
	"heavy_kick": {"damage": 35, "startup": 12, "active": 5, "recovery": 22, "hitstun": 26, "blockstun": 14, "knockback": 5.0, "meter_gain": 12, "meter_cost": 0},
	"fireball": {"damage": 25, "startup": 15, "active": 30, "recovery": 12, "hitstun": 20, "blockstun": 12, "knockback": 3.0, "meter_gain": 0, "meter_cost": 25},
	"grab": {"damage": 20, "startup": 5, "active": 3, "recovery": 25, "hitstun": 35, "blockstun": 0, "knockback": 2.0, "meter_gain": 10, "meter_cost": 0},
}

## Fighter states
enum FighterState { IDLE, ATTACKING, BLOCKING, HITSTUN, KNOCKDOWN, JUMPING, DASHING }

## Combo scaling: 10% reduction per hit, minimum 30%
const COMBO_SCALING_DECAY := 0.1
const COMBO_SCALING_MIN := 0.3

## Input buffer
const INPUT_BUFFER_SIZE := 3

var _fighters: Dictionary = {}  # fighter_id → FighterData

func initialize_fighter(fighter_id: String) -> void:
	_fighters[fighter_id] = {
		"state": FighterState.IDLE,
		"special_meter": 0.0,
		"frame_counter": 0,
		"current_attack": "",
		"combo_hits": 0,
		"combo_damage": 0.0,
		"combo_scaling": 1.0,
		"input_buffer": [],
		"is_blocking": false,
		"hitstun_frames": 0,
	}

func input_attack(fighter_id: String, attack_id: String) -> void:
	if not _fighters.has(fighter_id):
		return
	var fighter: Dictionary = _fighters[fighter_id]

	# Buffer input
	if fighter["input_buffer"].size() < INPUT_BUFFER_SIZE:
		fighter["input_buffer"].append(attack_id)

	# Execute if idle
	if fighter["state"] == FighterState.IDLE:
		_execute_buffered(fighter_id)

func set_blocking(fighter_id: String, blocking: bool) -> void:
	if not _fighters.has(fighter_id):
		return
	var fighter: Dictionary = _fighters[fighter_id]
	fighter["is_blocking"] = blocking
	if blocking and fighter["state"] == FighterState.IDLE:
		fighter["state"] = FighterState.BLOCKING
		fighter_state_changed.emit(fighter_id, "blocking")
	elif not blocking and fighter["state"] == FighterState.BLOCKING:
		fighter["state"] = FighterState.IDLE
		fighter_state_changed.emit(fighter_id, "idle")

func update(delta: float) -> void:
	for fighter_id in _fighters:
		_update_fighter(fighter_id, delta)

func _update_fighter(fighter_id: String, _delta: float) -> void:
	var fighter: Dictionary = _fighters[fighter_id]
	var state: int = fighter["state"]

	if state == FighterState.ATTACKING:
		fighter["frame_counter"] += 1
		var attack: Dictionary = ATTACKS.get(fighter["current_attack"], {})
		var total_frames: int = attack.get("startup", 0) + attack.get("active", 0) + attack.get("recovery", 0)

		# Check if in active frames (hit window)
		var startup: int = attack.get("startup", 0)
		var active: int = attack.get("active", 0)
		var frame: int = fighter["frame_counter"]
		if frame == startup + 1:
			# First active frame — trigger hit check
			_process_hit(fighter_id, attack)

		if frame >= total_frames:
			# Attack finished — check buffer
			fighter["state"] = FighterState.IDLE
			fighter["frame_counter"] = 0
			fighter["current_attack"] = ""
			if not fighter["input_buffer"].is_empty():
				_execute_buffered(fighter_id)
			elif fighter["combo_hits"] > 0:
				combo_ended.emit(fighter["combo_hits"], fighter["combo_damage"])
				fighter["combo_hits"] = 0
				fighter["combo_damage"] = 0.0
				fighter["combo_scaling"] = 1.0

	elif state == FighterState.HITSTUN:
		fighter["hitstun_frames"] -= 1
		if fighter["hitstun_frames"] <= 0:
			fighter["state"] = FighterState.IDLE
			fighter_state_changed.emit(fighter_id, "idle")

func _execute_buffered(fighter_id: String) -> void:
	var fighter: Dictionary = _fighters[fighter_id]
	if fighter["input_buffer"].is_empty():
		return
	var attack_id: String = fighter["input_buffer"].pop_front()
	var attack: Dictionary = ATTACKS.get(attack_id, {})
	if attack.is_empty():
		return

	# Check meter cost
	var meter_cost: float = attack.get("meter_cost", 0)
	if meter_cost > 0 and fighter["special_meter"] < meter_cost:
		return

	fighter["special_meter"] -= meter_cost
	fighter["state"] = FighterState.ATTACKING
	fighter["current_attack"] = attack_id
	fighter["frame_counter"] = 0
	fighter_state_changed.emit(fighter_id, "attacking_%s" % attack_id)

func _process_hit(attacker_id: String, attack: Dictionary) -> void:
	var attacker: Dictionary = _fighters[attacker_id]
	var base_damage: float = attack.get("damage", 10)
	var scaled_damage: float = base_damage * attacker["combo_scaling"]

	# Update combo
	attacker["combo_hits"] += 1
	attacker["combo_damage"] += scaled_damage
	attacker["combo_scaling"] = maxf(COMBO_SCALING_MIN, attacker["combo_scaling"] - COMBO_SCALING_DECAY)

	# Gain meter
	attacker["special_meter"] = minf(100.0, attacker["special_meter"] + attack.get("meter_gain", 0))
	special_meter_changed.emit(attacker["special_meter"])

	combo_hit.emit(attacker["combo_hits"], attacker["combo_damage"])

	EventBus.emit_event({
		"type": "combat_action",
		"action_type": attacker["current_attack"],
		"damage": int(scaled_damage),
		"is_critical": attacker["combo_hits"] >= 5,
		"combo_count": attacker["combo_hits"],
	})

func get_special_meter(fighter_id: String) -> float:
	if _fighters.has(fighter_id):
		return _fighters[fighter_id]["special_meter"]
	return 0.0

func get_combo_count(fighter_id: String) -> int:
	if _fighters.has(fighter_id):
		return _fighters[fighter_id]["combo_hits"]
	return 0
