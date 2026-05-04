extends Node
## Ambient Conversation System — NPC-NPC chat with speech bubbles.
## Matches shared/game-engine/rendering/AmbientConversationSystem.ts.

signal conversation_started(npc_a: String, npc_b: String)
signal conversation_ended(npc_a: String, npc_b: String)
signal relationship_changed(npc_a: String, npc_b: String, delta: float)

@export var conversation_radius := 5.0
@export var line_display_time := 3.5
@export var max_concurrent_conversations := 4

const AMBIENT_LINES := [
	"Nice weather today, isn't it?",
	"Have you heard the latest news?",
	"Business has been good lately.",
	"I saw something strange by the road.",
	"The harvest looks promising this year.",
	"I could use a drink at the tavern.",
	"Did you see the new merchant in town?",
	"My back has been aching all week.",
	"The guard patrols seem lighter recently.",
	"I need to visit the market soon.",
]

var _active_conversations: Array[Dictionary] = []
var _conversation_timer := 0.0
var _check_interval := 5.0
var _npc_nodes: Dictionary = {}  # npc_id -> CharacterBody3D

func register_npc(npc_id: String, npc: CharacterBody3D) -> void:
	_npc_nodes[npc_id] = npc

func unregister_npc(npc_id: String) -> void:
	_npc_nodes.erase(npc_id)

func _process(delta: float) -> void:
	_conversation_timer += delta
	if _conversation_timer >= _check_interval:
		_conversation_timer = 0.0
		_check_proximity_conversations()

	# Update active conversations
	var to_remove: Array[int] = []
	for i in range(_active_conversations.size()):
		_active_conversations[i]["timer"] -= delta
		if _active_conversations[i]["timer"] <= 0:
			_advance_conversation(i)
			if _active_conversations[i].get("finished", false):
				to_remove.append(i)

	# Remove finished (in reverse order)
	for i in range(to_remove.size() - 1, -1, -1):
		var conv: Dictionary = _active_conversations[to_remove[i]]
		_cleanup_conversation(conv)
		_active_conversations.remove_at(to_remove[i])

func _check_proximity_conversations() -> void:
	if _active_conversations.size() >= max_concurrent_conversations:
		return

	var npc_ids: Array = _npc_nodes.keys()
	for i in range(npc_ids.size()):
		for j in range(i + 1, npc_ids.size()):
			if _active_conversations.size() >= max_concurrent_conversations:
				return
			var id_a: String = npc_ids[i]
			var id_b: String = npc_ids[j]

			# Skip if already in conversation
			if _is_in_conversation(id_a) or _is_in_conversation(id_b):
				continue

			var npc_a: CharacterBody3D = _npc_nodes[id_a]
			var npc_b: CharacterBody3D = _npc_nodes[id_b]
			if not is_instance_valid(npc_a) or not is_instance_valid(npc_b):
				continue

			var dist := npc_a.global_position.distance_to(npc_b.global_position)
			if dist <= conversation_radius and randf() < 0.3:
				_start_conversation(id_a, id_b)

func _is_in_conversation(npc_id: String) -> bool:
	for conv in _active_conversations:
		if conv.get("npc_a") == npc_id or conv.get("npc_b") == npc_id:
			return true
	return false

func _start_conversation(npc_a: String, npc_b: String) -> void:
	var conv := {
		"npc_a": npc_a,
		"npc_b": npc_b,
		"line_index": 0,
		"max_lines": randi_range(2, 4),
		"timer": line_display_time,
		"current_speaker": npc_a,
		"bubble": null,
		"finished": false,
	}
	_active_conversations.append(conv)
	_show_line(conv)
	conversation_started.emit(npc_a, npc_b)

func _advance_conversation(index: int) -> void:
	var conv: Dictionary = _active_conversations[index]
	# Remove old bubble
	if conv.get("bubble") and is_instance_valid(conv["bubble"]):
		conv["bubble"].queue_free()

	conv["line_index"] += 1
	if conv["line_index"] >= conv["max_lines"]:
		conv["finished"] = true
		return

	# Switch speaker
	conv["current_speaker"] = conv["npc_b"] if conv["current_speaker"] == conv["npc_a"] else conv["npc_a"]
	conv["timer"] = line_display_time
	_show_line(conv)

func _show_line(conv: Dictionary) -> void:
	var speaker_id: String = conv["current_speaker"]
	var npc: CharacterBody3D = _npc_nodes.get(speaker_id)
	if not is_instance_valid(npc):
		conv["finished"] = true
		return

	var line: String = AMBIENT_LINES[randi() % AMBIENT_LINES.size()]
	var bubble := Label3D.new()
	bubble.text = line
	bubble.position.y = 2.5
	bubble.font_size = 14
	bubble.outline_size = 3
	bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bubble.modulate = Color(1, 1, 0.95, 0.9)
	npc.add_child(bubble)
	conv["bubble"] = bubble

func _cleanup_conversation(conv: Dictionary) -> void:
	if conv.get("bubble") and is_instance_valid(conv["bubble"]):
		conv["bubble"].queue_free()
	# Emit relationship change
	relationship_changed.emit(conv["npc_a"], conv["npc_b"], 0.5)
	conversation_ended.emit(conv["npc_a"], conv["npc_b"])
