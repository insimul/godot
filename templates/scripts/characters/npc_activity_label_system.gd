extends Node
## NPC Activity Label System — shows activity labels and talking indicators.
## Matches shared/game-engine/rendering/NPCActivityLabelSystem.ts, NPCTalkingIndicator.ts.

const ACTIVITY_LABELS := {
	"work": "Working",
	"eat": "Eating",
	"socialize": "Socializing",
	"sleep": "Resting",
	"shop": "Shopping",
	"idle_at_home": "",
	"wander": "",
	"visit_friend": "Visiting",
}

var _labels: Dictionary = {}  # npc_id -> Label3D
var _talking_indicators: Dictionary = {}  # npc_id -> Sprite3D
var _player: Node3D = null
var _fade_distance := 30.0

func _ready() -> void:
	await get_tree().process_frame
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		_player = players[0] as Node3D

func register_npc(npc: CharacterBody3D, npc_id: String) -> void:
	# Activity label
	var label := Label3D.new()
	label.text = ""
	label.position.y = 2.4
	label.font_size = 14
	label.outline_size = 3
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color(0.9, 0.9, 0.7, 0.8)
	npc.add_child(label)
	_labels[npc_id] = label

	# Talking indicator (speech bubble sprite)
	var indicator := Sprite3D.new()
	indicator.position.y = 2.6
	indicator.pixel_size = 0.01
	indicator.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	indicator.visible = false
	# Create speech bubble texture procedurally
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0.9))
	indicator.texture = ImageTexture.create_from_image(img)
	indicator.modulate = Color(1, 1, 1, 0.8)
	npc.add_child(indicator)
	_talking_indicators[npc_id] = indicator

func set_activity(npc_id: String, activity: String) -> void:
	var label: Label3D = _labels.get(npc_id)
	if label:
		label.text = ACTIVITY_LABELS.get(activity, "")

func set_talking(npc_id: String, is_talking: bool) -> void:
	var indicator: Sprite3D = _talking_indicators.get(npc_id)
	if indicator:
		indicator.visible = is_talking

func _process(_delta: float) -> void:
	if not _player:
		return

	var player_pos := _player.global_position
	# Fade labels based on distance
	for npc_id in _labels:
		var label: Label3D = _labels[npc_id]
		if not is_instance_valid(label):
			continue
		var dist := player_pos.distance_to(label.global_position)
		var alpha := clampf(1.0 - (dist / _fade_distance), 0.0, 0.8)
		label.modulate.a = alpha

	for npc_id in _talking_indicators:
		var indicator: Sprite3D = _talking_indicators[npc_id]
		if not is_instance_valid(indicator) or not indicator.visible:
			continue
		var dist := player_pos.distance_to(indicator.global_position)
		var alpha := clampf(1.0 - (dist / _fade_distance), 0.0, 0.8)
		indicator.modulate.a = alpha

func unregister_npc(npc_id: String) -> void:
	_labels.erase(npc_id)
	_talking_indicators.erase(npc_id)
