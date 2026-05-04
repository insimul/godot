extends Node
## Lip Sync Controller — animates NPC mouth blend shapes during dialogue.
## Matches shared/game-engine/rendering/LipSyncController.ts.

@export var blend_speed := 8.0
@export var mouth_open_amount := 0.6
@export var oscillation_speed := 12.0

var _mesh: MeshInstance3D = null
var _is_speaking := false
var _speak_timer := 0.0
var _current_blend := 0.0
var _mouth_blend_index := -1

func setup(mesh: MeshInstance3D) -> void:
	_mesh = mesh
	if _mesh:
		# Find mouth-related blend shape
		var blend_count := _mesh.get_blend_shape_count()
		for i in range(blend_count):
			var name := _mesh.mesh.get_blend_shape_name(i) if _mesh.mesh else ""
			if "mouth" in name.to_lower() or "jaw" in name.to_lower() or "open" in name.to_lower():
				_mouth_blend_index = i
				break

func start_speaking() -> void:
	_is_speaking = true
	_speak_timer = 0.0

func stop_speaking() -> void:
	_is_speaking = false
	_current_blend = 0.0
	_apply_blend(0.0)

func _process(delta: float) -> void:
	if not _is_speaking or not _mesh:
		return

	_speak_timer += delta

	# Oscillate mouth open/closed to simulate speech
	var target := sin(_speak_timer * oscillation_speed) * 0.5 + 0.5
	target *= mouth_open_amount
	_current_blend = lerp(_current_blend, target, blend_speed * delta)
	_apply_blend(_current_blend)

func _apply_blend(value: float) -> void:
	if not _mesh:
		return
	if _mouth_blend_index >= 0:
		_mesh.set_blend_shape_value(_mouth_blend_index, value)
