class_name InsimulLipSync
extends Node
## InsimulLipSync — Applies viseme data to blend shapes on a MeshInstance3D.
##
## Attach as a child of a MeshInstance3D with blend shapes (morph targets).
## Viseme data from the conversation service is smoothly interpolated onto
## the mesh's blend shape weights.

# ── Export Variables ──────────────────────────────────────────────────────────

## The MeshInstance3D whose blend shapes will be driven.
@export var target_mesh: MeshInstance3D = null
## Interpolation speed for smooth blending between viseme poses.
@export var blend_speed: float = 12.0

# ── Oculus OVR Viseme Mapping ────────────────────────────────────────────────
# Maps phoneme names to blend shape names. Override in Inspector or code
# to match your character's blend shape naming convention.

## Mapping from Insimul phoneme names to blend shape names on the mesh.
@export var phoneme_blend_map: Dictionary = {
	"sil": "viseme_sil",
	"PP": "viseme_PP",
	"FF": "viseme_FF",
	"TH": "viseme_TH",
	"DD": "viseme_DD",
	"kk": "viseme_kk",
	"CH": "viseme_CH",
	"SS": "viseme_SS",
	"nn": "viseme_nn",
	"RR": "viseme_RR",
	"aa": "viseme_aa",
	"E": "viseme_E",
	"ih": "viseme_ih",
	"oh": "viseme_oh",
	"ou": "viseme_ou",
}

# ── State ────────────────────────────────────────────────────────────────────

var _target_weights: Dictionary = {}  # blend_shape_name -> target weight
var _current_weights: Dictionary = {}  # blend_shape_name -> current weight
var _blend_shape_indices: Dictionary = {}  # blend_shape_name -> index
var _active: bool = false
var _viseme_queue: Array[InsimulTypes.FacialData] = []
var _current_viseme_time: float = 0.0
var _current_visemes: Array[InsimulTypes.Viseme] = []
var _current_viseme_index: int = 0


func _ready() -> void:
	_cache_blend_shape_indices()


func _process(delta: float) -> void:
	if not _active and _viseme_queue.is_empty():
		return
	_advance_viseme_timeline(delta)
	_interpolate_weights(delta)
	_apply_weights()


# ── Public API ───────────────────────────────────────────────────────────────

## Queue facial data for playback.
func queue_facial_data(data: InsimulTypes.FacialData) -> void:
	_viseme_queue.append(data)
	if not _active:
		_start_next_facial_data()


## Stop lip sync and reset all blend shapes to zero.
func stop() -> void:
	_active = false
	_viseme_queue.clear()
	_current_visemes.clear()
	_current_viseme_index = 0
	_current_viseme_time = 0.0
	# Reset all weights to zero
	for key in _target_weights:
		_target_weights[key] = 0.0


## Reset for a new conversation.
func reset() -> void:
	stop()


# ── Internal ─────────────────────────────────────────────────────────────────

func _cache_blend_shape_indices() -> void:
	if target_mesh == null:
		# Try parent as fallback
		var parent := get_parent()
		if parent is MeshInstance3D:
			target_mesh = parent as MeshInstance3D
	if target_mesh == null or target_mesh.mesh == null:
		return
	var blend_count: int = target_mesh.mesh.get_blend_shape_count()
	for i in range(blend_count):
		var blend_name: String = target_mesh.mesh.get_blend_shape_name(i)
		_blend_shape_indices[blend_name] = i
		_current_weights[blend_name] = 0.0
		_target_weights[blend_name] = 0.0


func _start_next_facial_data() -> void:
	if _viseme_queue.is_empty():
		_active = false
		# Reset to silence
		for key in _target_weights:
			_target_weights[key] = 0.0
		return
	var data := _viseme_queue.pop_front() as InsimulTypes.FacialData
	_current_visemes.clear()
	for v in data.visemes:
		_current_visemes.append(v)
	_current_viseme_index = 0
	_current_viseme_time = 0.0
	_active = true
	_apply_current_viseme()


func _advance_viseme_timeline(delta: float) -> void:
	if not _active or _current_visemes.is_empty():
		return
	_current_viseme_time += delta * 1000.0  # convert to ms
	if _current_viseme_index < _current_visemes.size():
		var current: Dictionary = _current_visemes[_current_viseme_index]
		if _current_viseme_time >= current.duration_ms:
			_current_viseme_time -= current.duration_ms
			_current_viseme_index += 1
			if _current_viseme_index < _current_visemes.size():
				_apply_current_viseme()
			else:
				_start_next_facial_data()


func _apply_current_viseme() -> void:
	# Zero all targets first
	for key in _target_weights:
		_target_weights[key] = 0.0
	if _current_viseme_index >= _current_visemes.size():
		return
	var viseme: Dictionary = _current_visemes[_current_viseme_index]
	var blend_name: String = phoneme_blend_map.get(viseme.phoneme, "")
	if blend_name != "" and blend_name in _blend_shape_indices:
		_target_weights[blend_name] = viseme.weight


func _interpolate_weights(delta: float) -> void:
	for key in _target_weights:
		var target: float = _target_weights[key]
		var current: float = _current_weights.get(key, 0.0)
		_current_weights[key] = lerpf(current, target, clampf(blend_speed * delta, 0.0, 1.0))


func _apply_weights() -> void:
	if target_mesh == null:
		return
	for blend_name in _blend_shape_indices:
		var idx: int = _blend_shape_indices[blend_name]
		var weight: float = _current_weights.get(blend_name, 0.0)
		target_mesh.set_blend_shape_value(idx, weight)
